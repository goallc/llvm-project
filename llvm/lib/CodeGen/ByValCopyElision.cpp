//===- ByValCopyElision.cpp - Private byval initialization ------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Analysis/ValueTracking.h"
#include "llvm/CodeGen/Analysis.h"
#include "llvm/IR/CFG.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/Statepoint.h"
#include "llvm/Support/MathExtras.h"

using namespace llvm;

namespace {

// Bound analysis and expansion work, rather than matching an aggregate size.
// Large objects with only a few explicit writes need no special treatment.
constexpr unsigned MaxInitWork = 128;

using ByteRange = std::pair<uint64_t, uint64_t>;

struct ByValCarrier {
  const CallBase *Call = nullptr;
  unsigned ArgNo = 0;
  SmallVector<const Instruction *, 8> Writes;
  SmallVector<const Instruction *, 8> Addresses;
  SmallVector<const IntrinsicInst *, 2> Lifetimes;
};

// Both preparation and GC/codegen qualification use this ownership proof.
// Memsets are accepted only while preparing: the final carrier must contain
// stores that SelectionDAG can forward without introducing a runtime call.
static bool collectCarrier(const AllocaInst &AI, const DataLayout &DL,
                           ByValCarrier &C, bool Preparing,
                           bool AllowGCLiveUses = false) {
  auto *Count = dyn_cast<ConstantInt>(AI.getArraySize());
  auto Size = AI.getAllocationSize(DL);
  if (!AI.isStaticAlloca() || !Count || !Count->isOne() || !Size ||
      Size->isScalable() || AI.isUsedWithInAlloca() || AI.isSwiftError())
    return false;
  uint64_t Bytes = Size->getFixedValue();
  if (Preparing && (!Bytes || AI.getAddressSpace() != 0))
    return false;

  auto InBounds = [&](const Value *Ptr, uint64_t Length) {
    int64_t Offset = 0;
    return GetPointerBaseWithConstantOffset(Ptr, Offset, DL) == &AI &&
           Offset >= 0 && uint64_t(Offset) <= Bytes &&
           Length <= Bytes - uint64_t(Offset);
  };

  SmallVector<const Value *, 8> Worklist{&AI};
  SmallPtrSet<const Value *, 16> Seen;
  while (!Worklist.empty()) {
    const Value *V = Worklist.pop_back_val();
    if (!Seen.insert(V).second)
      continue;
    if (Preparing && Seen.size() > MaxInitWork)
      return false;
    if (V != &AI)
      C.Addresses.push_back(cast<Instruction>(V));
    for (const Use &U : V->uses()) {
      if (Preparing &&
          (C.Writes.size() > MaxInitWork || Worklist.size() > MaxInitWork))
        return false;
      auto *I = dyn_cast<Instruction>(U.getUser());
      if (!I)
        return false;
      if (isa<GetElementPtrInst, BitCastInst, AddrSpaceCastInst>(I)) {
        if (U.getOperandNo() != 0 || !InBounds(I, 0) ||
            (Preparing && isa<AddrSpaceCastInst>(I)))
          return false;
        Worklist.push_back(I);
        continue;
      }
      if (auto *SI = dyn_cast<StoreInst>(I)) {
        Type *Ty = SI->getValueOperand()->getType();
        TypeSize StoreSize = DL.getTypeStoreSize(Ty);
        if (U.getOperandNo() != StoreInst::getPointerOperandIndex() ||
            !SI->isSimple() || StoreSize.isScalable() ||
            !InBounds(V, StoreSize.getFixedValue()))
          return false;
        // An aggregate store need not write its padding. Do not use it as a
        // byte-covering definition when eliminating earlier initializers.
        if (Preparing && (Ty->isAggregateType() ||
                          DL.getTypeSizeInBits(Ty) != StoreSize * 8))
          return false;
        C.Writes.push_back(SI);
        continue;
      }
      if (Preparing)
        if (auto *MS = dyn_cast<MemSetInst>(I)) {
          auto *Length = dyn_cast<ConstantInt>(MS->getLength());
          if (&U != &MS->getRawDestUse() || MS->isVolatile() || !Length ||
              Length->getValue().getActiveBits() > 64 ||
              !InBounds(V, Length->getZExtValue()))
            return false;
          C.Writes.push_back(MS);
          continue;
        }
      if (auto *II = dyn_cast<IntrinsicInst>(I);
          II && II->isLifetimeStartOrEnd()) {
        if (Preparing && V != &AI)
          return false;
        C.Lifetimes.push_back(II);
        continue;
      }
      if (auto *CB = dyn_cast<CallBase>(I)) {
        if (AllowGCLiveUses && V == &AI && isa<GCStatepointInst>(CB) &&
            CB->isOperandBundleOfType(LLVMContext::OB_gc_live,
                                      U.getOperandNo()))
          continue;
        auto *CI = dyn_cast<CallInst>(CB);
        if (C.Call || !CB->isArgOperand(&U) ||
            (Preparing &&
             (!CI || CI->isMustTailCall() || isa<GCStatepointInst>(CI))))
          return false;
        unsigned Arg = CB->getArgOperandNo(&U);
        int64_t Offset = 0;
        if (!CB->paramHasAttr(Arg, Attribute::ByVal) ||
            GetPointerBaseWithConstantOffset(V, Offset, DL) != &AI || Offset ||
            CB->getParamByValType(Arg) != AI.getAllocatedType())
          return false;
        auto Align = CB->getParamAlign(Arg);
        if (!Align || AI.getAlign() < *Align ||
            (Preparing && AI.getAlign() != *Align))
          return false;
        C.Call = CB;
        C.ArgNo = Arg;
        continue;
      }
      // No loads, address observations, captures, or other calls.
      return false;
    }
    if (Preparing && C.Writes.size() + C.Lifetimes.size() > MaxInitWork)
      return false;
  }
  return C.Call && !C.Writes.empty();
}

static ByteRange writeRange(const Instruction *I, const DataLayout &DL) {
  const Value *Ptr;
  uint64_t Bytes;
  if (auto *SI = dyn_cast<StoreInst>(I)) {
    Ptr = SI->getPointerOperand();
    Bytes = DL.getTypeStoreSize(SI->getValueOperand()->getType());
  } else {
    auto *MS = cast<MemSetInst>(I);
    Ptr = MS->getDest();
    Bytes = cast<ConstantInt>(MS->getLength())->getZExtValue();
  }
  int64_t Offset = 0;
  GetPointerBaseWithConstantOffset(Ptr, Offset, DL);
  return {uint64_t(Offset), uint64_t(Offset) + Bytes};
}

// Return the parts of R not covered by later definitions. The range list is
// proportional to the number of writes, not to the size of the alloca.
static SmallVector<ByteRange, 4> uncovered(ByteRange R,
                                           ArrayRef<ByteRange> Covered) {
  SmallVector<ByteRange, 4> Result;
  for (auto [Begin, End] : Covered) {
    if (End <= R.first)
      continue;
    if (Begin >= R.second)
      break;
    if (Begin > R.first)
      Result.emplace_back(R.first, Begin);
    R.first = std::max(R.first, End);
  }
  if (R.first < R.second)
    Result.push_back(R);
  return Result;
}

static void cover(ByteRange R, SmallVectorImpl<ByteRange> &Covered) {
  Covered.push_back(R);
  llvm::sort(Covered);
  unsigned N = 0;
  for (ByteRange Next : Covered) {
    if (N && Next.first <= Covered[N - 1].second)
      Covered[N - 1].second = std::max(Covered[N - 1].second, Next.second);
    else
      Covered[N++] = Next;
  }
  Covered.resize(N);
}

// Every initializer must dominate the call. A diamond without conditional
// writes is allowed, but cycles and calls on any path to the use are not.
static bool orderInitializers(ByValCarrier &C, const DominatorTree &DT) {
  if (!DT.isReachableFromEntry(C.Call->getParent()))
    return false;
  for (const Instruction *I : C.Writes)
    if (!DT.dominates(I, C.Call))
      return false;
  llvm::sort(C.Writes, [&](const Instruction *A, const Instruction *B) {
    return A != B && DT.dominates(A, B);
  });
  const Instruction *First = C.Writes.front();
  for (const IntrinsicInst *II : C.Lifetimes)
    if (II->getIntrinsicID() != Intrinsic::lifetime_start ||
        !DT.dominates(II, First))
      return false;
  if (C.Lifetimes.size() > 1)
    return false;

  const BasicBlock *FirstBB = First->getParent();
  const BasicBlock *CallBB = C.Call->getParent();
  SmallPtrSet<const BasicBlock *, 16> Region;
  SmallVector<const BasicBlock *, 16> Worklist{CallBB};
  while (!Worklist.empty()) {
    const BasicBlock *BB = Worklist.pop_back_val();
    if (!Region.insert(BB).second)
      continue;
    if (Region.size() > MaxInitWork || !DT.dominates(FirstBB, BB))
      return false;
    if (BB != FirstBB)
      llvm::append_range(Worklist, predecessors(BB));
  }

  SmallPtrSet<const BasicBlock *, 16> Active, Done;
  SmallVector<std::pair<const BasicBlock *, bool>, 16> DFS{{FirstBB, false}};
  while (!DFS.empty()) {
    auto [BB, Finished] = DFS.pop_back_val();
    if (Finished) {
      Active.erase(BB);
      Done.insert(BB);
      continue;
    }
    if (Done.contains(BB))
      continue;
    if (!Active.insert(BB).second)
      return false;
    DFS.emplace_back(BB, true);
    if (BB != CallBB)
      for (const BasicBlock *Succ : successors(BB))
        if (Region.contains(Succ))
          DFS.emplace_back(Succ, false);
  }

  for (const BasicBlock *BB : Region) {
    auto Begin = BB == FirstBB ? First->getIterator() : BB->begin();
    auto End = BB == CallBB ? C.Call->getIterator() : BB->end();
    for (const Instruction &I : make_range(Begin, End))
      if (isa<CallBase>(I) && !llvm::is_contained(C.Writes, &I) &&
          !(isa<IntrinsicInst>(I) &&
            cast<IntrinsicInst>(I).isLifetimeStartOrEnd()))
        return false;
  }
  return true;
}

} // namespace

bool llvm::isSingleByValCallCarrier(const AllocaInst &AI, const DataLayout &DL,
                                    bool AllowGCLiveUses) {
  ByValCarrier C;
  if (!collectCarrier(AI, DL, C, /*Preparing=*/false, AllowGCLiveUses))
    return false;
  const BasicBlock *CallBB = C.Call->getParent();
  const Instruction *First = C.Writes.front();
  for (const Instruction *I : C.Writes) {
    if (I->getParent() != CallBB || !I->comesBefore(C.Call))
      return false;
    if (I->comesBefore(First))
      First = I;
  }
  for (const Instruction *I : C.Addresses)
    if (I->getParent() != CallBB || !I->comesBefore(C.Call))
      return false;
  for (const IntrinsicInst *II : C.Lifetimes)
    if (II->getParent() != CallBB || !II->comesBefore(C.Call))
      return false;

  // An intervening call can reuse the outgoing area. Its stack map does not
  // describe partially initialized arguments belonging to a later call.
  for (const Instruction *I = First->getNextNode(); I != C.Call;
       I = I->getNextNode())
    if (isa<CallBase>(I) && !(isa<IntrinsicInst>(I) &&
                              cast<IntrinsicInst>(I)->isLifetimeStartOrEnd()))
      return false;
  return true;
}

bool llvm::prepareSingleByValCallCarrier(AllocaInst &AI,
                                         const DominatorTree &DT) {
  Function &F = *AI.getFunction();
  if (F.hasOptNone() || F.hasOptSize())
    return false;
  const DataLayout &DL = F.getDataLayout();
  ByValCarrier C;
  if (!collectCarrier(AI, DL, C, /*Preparing=*/true) ||
      !orderInitializers(C, DT))
    return false;

  struct FinalWrite {
    const Instruction *Original;
    SmallVector<ByteRange, 4> Ranges;
  };
  SmallVector<FinalWrite, 8> Final;
  SmallVector<ByteRange, 8> Covered;
  uint64_t Work = 0;
  for (const Instruction *I : llvm::reverse(C.Writes)) {
    ByteRange R = writeRange(I, DL);
    auto Remaining = uncovered(R, Covered);
    if (!Remaining.empty()) {
      if (isa<StoreInst>(I)) {
        // Do not reconstruct pointer values or extract bytes from a partially
        // overwritten scalar. Forward its typed store before the later writes.
        Remaining.assign(1, R);
        ++Work;
      } else {
        for (auto [Begin, End] : Remaining) {
          uint64_t Bytes = End - Begin;
          if (Bytes > MaxInitWork * 16)
            return false;
          Work += Bytes / 16 + llvm::popcount(Bytes % 16);
        }
      }
      if (Work > MaxInitWork)
        return false;
      Final.push_back({I, std::move(Remaining)});
    }
    cover(R, Covered);
  }
  if (Final.empty())
    return false;

  // Avoid rebuilding an already prepared object on subsequent invocations.
  if (Final.size() == C.Writes.size() &&
      llvm::none_of(C.Writes,
                    [](const Instruction *I) { return isa<MemSetInst>(I); }) &&
      isSingleByValCallCarrier(AI, DL))
    return false;

  auto *Call = cast<CallInst>(const_cast<CallBase *>(C.Call));
  IRBuilder<> B(Call);
  for (const IntrinsicInst *II : C.Lifetimes)
    const_cast<IntrinsicInst *>(II)->moveBefore(Call->getIterator());
  SmallPtrSet<const Instruction *, 16> Kept;
  for (const FinalWrite &W : llvm::reverse(Final)) {
    B.SetCurrentDebugLocation(W.Original->getDebugLoc());
    if (auto *SI = dyn_cast<StoreInst>(W.Original)) {
      auto *Store = const_cast<StoreInst *>(SI);
      Value *Ptr = B.CreateConstGEP1_64(B.getInt8Ty(), &AI, W.Ranges[0].first);
      Store->setOperand(StoreInst::getPointerOperandIndex(), Ptr);
      Store->moveBefore(Call->getIterator());
      Kept.insert(Store);
      continue;
    }
    auto *MS = cast<MemSetInst>(W.Original);
    for (auto [Begin, End] : W.Ranges) {
      while (Begin != End) {
        unsigned Bytes = llvm::bit_floor(std::min(uint64_t(16), End - Begin));
        Value *Fill = MS->getValue();
        if (Bytes != 1)
          Fill = B.CreateVectorSplat(Bytes, Fill);
        Value *Ptr = B.CreateConstGEP1_64(B.getInt8Ty(), &AI, Begin);
        B.CreateAlignedStore(Fill, Ptr, commonAlignment(AI.getAlign(), Begin));
        Begin += Bytes;
      }
    }
  }
  Call->setArgOperand(C.ArgNo, &AI);
  for (const Instruction *I : C.Writes)
    if (!Kept.contains(I))
      const_cast<Instruction *>(I)->eraseFromParent();
  for (const Instruction *I : llvm::reverse(C.Addresses))
    if (I->use_empty())
      const_cast<Instruction *>(I)->eraseFromParent();
  assert(isSingleByValCallCarrier(AI, DL) &&
         "preparation must produce a carrier");
  return true;
}
