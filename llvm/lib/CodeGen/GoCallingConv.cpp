//===- GoCallingConv.cpp - Go ABI helper implementation -------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/CodeGen/GoCallingConv.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/CodeGen/CommandFlags.h"
#include "llvm/CodeGen/MachineBasicBlock.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineMemOperand.h"
#include "llvm/CodeGen/PseudoSourceValue.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/MCContext.h"
#include "llvm/Support/ErrorHandling.h"
#include <limits>
#include <string>

using namespace llvm;

namespace llvm::goabi {

namespace {

constexpr uint8_t TraceArgsSpecial = 0xf0;
constexpr uint8_t TraceArgsOffsetTooLarge = 0xfb;
constexpr uint8_t TraceArgsDotdotdot = 0xfc;
constexpr uint8_t TraceArgsEndAgg = 0xfd;
constexpr uint8_t TraceArgsStartAgg = 0xfe;
constexpr uint8_t TraceArgsEndSeq = 0xff;

static void appendGoObjConstantBytes(const Constant *C,
                                     SmallVectorImpl<uint8_t> &Bytes) {
  if (const auto *CI = dyn_cast<ConstantInt>(C)) {
    if (!CI->getType()->isIntegerTy(8))
      report_fatal_error("GoObj arginfo contains a non-byte integer");
    Bytes.push_back(static_cast<uint8_t>(CI->getZExtValue()));
    return;
  }
  if (const auto *CDS = dyn_cast<ConstantDataSequential>(C)) {
    if (!CDS->getElementType()->isIntegerTy(8))
      report_fatal_error("GoObj arginfo contains non-byte sequential data");
    for (unsigned I = 0, E = CDS->getNumElements(); I != E; ++I)
      Bytes.push_back(
          static_cast<uint8_t>(CDS->getElementAsInteger(I)));
    return;
  }
  if (isa<ConstantAggregateZero>(C)) {
    Type *Ty = C->getType();
    if (const auto *AT = dyn_cast<ArrayType>(Ty)) {
      if (!AT->getElementType()->isIntegerTy(8))
        report_fatal_error("GoObj arginfo contains non-byte zero data");
      Bytes.append(AT->getNumElements(), 0);
      return;
    }
  }
  if (const auto *CA = dyn_cast<ConstantAggregate>(C)) {
    for (const Use &Op : CA->operands())
      appendGoObjConstantBytes(cast<Constant>(Op.get()), Bytes);
    return;
  }
  report_fatal_error("GoObj arginfo is not constant byte data");
}

static SmallVector<std::pair<uint8_t, uint8_t>, 10>
decodeGoObjTracebackSlots(const GlobalValue &Data, uint64_t ArgSize,
                          uint64_t SpillAreaOffset) {
  const auto *GV = dyn_cast<GlobalVariable>(&Data);
  if (!GV || !GV->hasInitializer())
    report_fatal_error("GoObj arginfo does not have a constant definition");

  SmallVector<uint8_t, 32> Bytes;
  appendGoObjConstantBytes(GV->getInitializer(), Bytes);
  SmallVector<std::pair<uint8_t, uint8_t>, 10> Slots;
  bool SawEnd = false;
  for (size_t I = 0; I < Bytes.size();) {
    uint8_t Op = Bytes[I++];
    if (Op == TraceArgsEndSeq) {
      SawEnd = true;
      break;
    }
    if (Op == TraceArgsStartAgg || Op == TraceArgsEndAgg ||
        Op == TraceArgsDotdotdot || Op == TraceArgsOffsetTooLarge)
      continue;
    if (Op >= TraceArgsSpecial || I == Bytes.size())
      report_fatal_error("malformed GoObj traceback argument bytecode");
    uint8_t Size = Bytes[I++];
    if (uint64_t(Op) > ArgSize || uint64_t(Size) > ArgSize - uint64_t(Op))
      report_fatal_error("GoObj traceback argument is outside its frame");
    if (uint64_t(Op) >= SpillAreaOffset)
      Slots.emplace_back(Op, Size);
  }
  if (!SawEnd)
    report_fatal_error("unterminated GoObj traceback argument bytecode");
  if (Slots.size() > 10)
    report_fatal_error("GoObj traceback argument bitmap exceeds ten slots");
  return Slots;
}

} // namespace

bool isSupportedMustTailCall(const Function &Caller, const CallBase &CB) {
  CallingConv::ID CallerCC = Caller.getCallingConv();
  CallingConv::ID CalleeCC = CB.getCallingConv();
  if (!CB.isMustTailCall() || !isGoCallingConv(CallerCC) ||
      !isGoCallingConv(CalleeCC) || Caller.isVarArg() ||
      CB.getFunctionType()->isVarArg())
    return false;

  // An exact-signature transfer within one Go calling convention reuses the
  // caller's register and stack argument/result layout. This includes an
  // indirect transfer: the IR function type and ABI-impacting call attributes
  // still provide the complete mechanical contract.
  if (CallerCC == CalleeCC)
    return Caller.getFunctionType() == CB.getFunctionType() &&
           hasTupleResultsAttr(Caller) == hasTupleResultsAttr(CB);

  // Keep the ABI0-to-ABIInternal transition deliberately narrow. Unlike a
  // same-ABI transfer, its argument and result layouts are not interchangeable.
  const Function *Callee = CB.getCalledFunction();
  return CallerCC == CallingConv::GoABI0 &&
         CalleeCC == CallingConv::GoABIInternal && Callee &&
         Caller.arg_empty() && CB.arg_empty() &&
         Caller.getReturnType()->isVoidTy() &&
         CB.getFunctionType()->getReturnType()->isVoidTy();
}

std::string getGoObjBuiltinCalleeName(const MachineFunction &MF,
                                      StringRef SymbolName,
                                      CallingConv::ID CC) {
  if (SymbolName.empty() ||
      (CC != CallingConv::GoABIInternal && CC != CallingConv::GoABI0))
    report_fatal_error("invalid logical Go builtin symbol");

  const Module &M = *MF.getFunction().getParent();
  const Function *Match = nullptr;
  for (const Function &F : M) {
    StringRef Candidate = F.getName();
    bool IsABI0 = Candidate.consume_back(GoObj::ABI0SymbolSuffix);
    if (IsABI0 != (CC == CallingConv::GoABI0) ||
        !Candidate.consume_front(SymbolName) ||
        !Candidate.consume_front(GoObj::BuiltinSymbolSuffixPrefix) ||
        !Candidate.consume_back(">") || Candidate.empty())
      continue;
    uint32_t Index;
    if (Candidate.getAsInteger(10, Index))
      continue;
    if (F.getCallingConv() != CC)
      report_fatal_error(
          "Go builtin declaration has invalid calling convention");
    if (Match)
      report_fatal_error("duplicate Go builtin declaration");
    Match = &F;
  }
  if (Match)
    return Match->getName().str();

  // Native Go disables builtin-index references for -linkshared.
  if (std::optional<codegen::GoObjConfig> Config = codegen::getGoObjConfig();
      Config && Config->IsShared) {
    std::string StorageName = SymbolName.str();
    if (CC == CallingConv::GoABI0)
      StorageName += GoObj::ABI0SymbolSuffix;
    return StorageName;
  }

  // Hand-written backend fixtures predate the compiler declaration contract.
  // Production Go IR is self-describing and must fail closed if its late
  // helper declaration is missing.
  if (M.getNamedMetadata("goobj.config"))
    report_fatal_error("missing Go builtin declaration for " + SymbolName);

  std::string StorageName = SymbolName.str();
  if (CC == CallingConv::GoABI0)
    StorageName += GoObj::ABI0SymbolSuffix;
  return StorageName;
}

void addGoObjABI0Callee(MachineInstrBuilder &MIB, MachineFunction &MF,
                        StringRef SymbolName) {
  std::string StorageName =
      getGoObjBuiltinCalleeName(MF, SymbolName, CallingConv::GoABI0);
  MIB.addExternalSymbol(MF.createExternalSymbolName(StorageName));
}

static bool isPaddingType(Type *Ty) {
  auto *ST = dyn_cast<StructType>(Ty);
  if (!ST || !ST->hasName() || ST->getName() != PadTypeName)
    return false;
  if (ST->isOpaque() || ST->getNumElements() != 1 ||
      !ST->getElementType(0)->isIntegerTy(8))
    report_fatal_error("invalid Go ABI pad type");
  return true;
}

static void collectPaddingPieces(Type *Ty, SmallBitVector &Pieces) {
  if (isPaddingType(Ty)) {
    Pieces.push_back(true);
    return;
  }

  if (auto *AT = dyn_cast<ArrayType>(Ty)) {
    for (uint64_t I = 0; I != AT->getNumElements(); ++I)
      collectPaddingPieces(AT->getElementType(), Pieces);
    return;
  }

  if (auto *ST = dyn_cast<StructType>(Ty)) {
    for (Type *EltTy : ST->elements())
      collectPaddingPieces(EltTy, Pieces);
    return;
  }

  if (!Ty->isVoidTy())
    Pieces.push_back(false);
}

SmallBitVector getPaddingPieces(Type *Ty) {
  SmallBitVector Pieces;
  collectPaddingPieces(Ty, Pieces);
  return Pieces;
}

static uint64_t alignToValue(uint64_t Value, Align Alignment) {
  return alignTo(Value, Alignment.value());
}

bool hasTupleResultsAttr(const AttributeList &Attrs) {
  return Attrs.hasFnAttr(TupleResultsAttr);
}

bool hasTupleResultsAttr(const Function &F) {
  return F.hasFnAttribute(TupleResultsAttr);
}

bool hasTupleResultsAttr(const CallBase &CB) {
  if (CB.hasFnAttr(TupleResultsAttr))
    return true;
  if (const Function *Callee = CB.getCalledFunction())
    return Callee->hasFnAttribute(TupleResultsAttr);
  return false;
}

void getReturnTypes(Type *ReturnType, bool TupleResults,
                    SmallVectorImpl<Type *> &ResultTys) {
  if (ReturnType->isVoidTy())
    return;

  if (TupleResults) {
    if (auto *ST = dyn_cast<StructType>(ReturnType)) {
      ResultTys.append(ST->element_begin(), ST->element_end());
      return;
    }
  }

  ResultTys.push_back(ReturnType);
}

static bool classifyRegisterResult(Type *Ty, const DataLayout &DL,
                                   const ABIConfig &Config, unsigned &IntRegs,
                                   unsigned &FPRegs) {
  if (isPaddingType(Ty) || Ty->isVoidTy())
    return true;

  // Go assigns arrays longer than one element to memory even when their
  // elements, and therefore the array itself, have zero size.
  if (auto *AT = dyn_cast<ArrayType>(Ty)) {
    if (AT->getNumElements() == 0)
      return true;
    if (AT->getNumElements() == 1)
      return classifyRegisterResult(AT->getElementType(), DL, Config, IntRegs,
                                    FPRegs);
    return false;
  }

  if (auto *ST = dyn_cast<StructType>(Ty)) {
    for (Type *EltTy : ST->elements())
      if (!classifyRegisterResult(EltTy, DL, Config, IntRegs, FPRegs))
        return false;
    return true;
  }

  if (DL.getTypeAllocSize(Ty) == 0)
    return true;

  if (Ty->isPointerTy()) {
    ++IntRegs;
    return IntRegs <= Config.IntRegs.size();
  }

  if (Ty->isIntegerTy()) {
    unsigned Bits = Ty->getIntegerBitWidth();
    unsigned PtrBits = Config.PtrSize * 8;
    if (Bits <= PtrBits)
      ++IntRegs;
    else if (Bits <= PtrBits * 2)
      IntRegs += 2;
    else
      return false;
    return IntRegs <= Config.IntRegs.size();
  }

  if (Ty->isHalfTy() || Ty->isBFloatTy() || Ty->isFloatTy() ||
      Ty->isDoubleTy()) {
    if (Config.SoftFloat)
      return false;
    ++FPRegs;
    return FPRegs <= Config.FPRegs.size();
  }

  if (isa<FixedVectorType>(Ty)) {
    if (Config.SoftFloat)
      return false;
    ++FPRegs;
    return FPRegs <= Config.FPRegs.size();
  }

  return false;
}

void validateResultCarriers(Type *DirectReturnType, bool TupleResults,
                            ArrayRef<ResultCarrier> MemoryResults,
                            CallingConv::ID CC, const DataLayout &DL,
                            const ABIConfig &Config) {
  if (!isGoCallingConv(CC))
    report_fatal_error("Go result validation requires a Go calling convention");

  SmallVector<Type *, 8> DirectResults;
  getReturnTypes(DirectReturnType, TupleResults, DirectResults);
  unsigned ResultCount = DirectResults.size() + MemoryResults.size();
  SmallVector<Type *, 8> LogicalResults(ResultCount, nullptr);
  SmallBitVector IsMemory(ResultCount);
  for (const ResultCarrier &Carrier : MemoryResults) {
    if (!Carrier.Ty || Carrier.Index >= ResultCount ||
        LogicalResults[Carrier.Index])
      report_fatal_error("invalid goret logical result mapping");
    LogicalResults[Carrier.Index] = Carrier.Ty;
    IsMemory.set(Carrier.Index);
  }

  auto DirectIt = DirectResults.begin();
  for (Type *&Ty : LogicalResults)
    if (!Ty) {
      if (DirectIt == DirectResults.end())
        report_fatal_error("invalid direct Go result mapping");
      Ty = *DirectIt++;
    }
  if (DirectIt != DirectResults.end())
    report_fatal_error("invalid direct Go result count");

  unsigned IntRegs = 0;
  unsigned FPRegs = 0;
  for (auto [Index, Ty] : llvm::enumerate(LogicalResults)) {
    unsigned IntAfter = IntRegs;
    unsigned FPAfter = FPRegs;
    bool InRegs =
        classifyRegisterResult(Ty, DL, Config, IntAfter, FPAfter);
    if (InRegs) {
      IntRegs = IntAfter;
      FPRegs = FPAfter;
    }
    if (InRegs == IsMemory.test(Index))
      report_fatal_error("Go result " + Twine(Index) +
                         (InRegs ? " is register-assigned but uses goret"
                                 : " is memory-assigned but uses a direct "
                                   "LLVM return; use goret"));
  }
}

static uint64_t getDirectValueSize(Type *Ty, const DataLayout &DL) {
  SmallBitVector PaddingPieces = getPaddingPieces(Ty);
  if (PaddingPieces.any() && PaddingPieces.count() == PaddingPieces.size())
    return 0;
  return DL.getTypeAllocSize(Ty);
}

CallLayout computeCallLayout(ArrayRef<ValueLayout> Args, uint64_t StackArgsSize,
                             uint64_t StackResultsEnd, const DataLayout &DL,
                             const ABIConfig &Config) {
  CallLayout Layout;
  Layout.Args.append(Args.begin(), Args.end());
  Layout.StackArgsSize = StackArgsSize;

  for (ValueLayout &Arg : Layout.Args) {
    if (!Arg.Ty)
      report_fatal_error("Go ABI argument layout has no logical type");
    uint64_t ExpectedSize = Arg.InRegs ? getDirectValueSize(Arg.Ty, DL)
                                       : DL.getTypeAllocSize(Arg.Ty);
    Arg.Size = ExpectedSize;
    Align ABIAlignment = DL.getABITypeAlign(Arg.Ty);
    if (Arg.InRegs) {
      Arg.Alignment = ABIAlignment;
      continue;
    }
    if (Arg.Alignment < ABIAlignment)
      report_fatal_error("invalid preassigned Go ABI argument layout");
    if (Arg.StackOffset % Arg.Alignment.value() != 0 ||
        Arg.StackOffset > StackArgsSize ||
        Arg.Size > StackArgsSize - Arg.StackOffset)
      report_fatal_error(
          "Go ABI stack argument is outside its assigned input area");
  }

  uint64_t StackResultsStart = alignToValue(StackArgsSize, Config.PtrAlign);
  if (StackResultsEnd == StackArgsSize)
    StackResultsEnd = StackResultsStart;
  else if (StackResultsEnd < StackResultsStart)
    report_fatal_error("Go ABI result area overlaps the input stack area");
  Layout.StackResultsSize = StackResultsEnd - StackResultsStart;

  uint64_t SpillEnd = alignToValue(StackResultsEnd, Config.PtrAlign);
  Layout.SpillAreaOffset = SpillEnd;
  for (const ValueLayout &ArgLayout : Layout.Args)
    if (ArgLayout.InRegs && ArgLayout.Size != 0)
      SpillEnd = alignToValue(SpillEnd, ArgLayout.Alignment) + ArgLayout.Size;
  Layout.SpillAreaSize = SpillEnd - Layout.SpillAreaOffset;
  Layout.ArgSize = alignToValue(SpillEnd, Config.PtrAlign);
  Layout.TotalStackSize = alignToValue(Layout.ArgSize, Config.StackAlign);
  return Layout;
}

std::optional<GoObjArgInfo> getGoObjArgInfo(const Function &F) {
  const MDNode *MD = F.getMetadata(FunctionArgInfoMD);
  if (!MD)
    return std::nullopt;
  if (MD->getNumOperands() < 3 || (MD->getNumOperands() - 3) % 2 != 0)
    report_fatal_error(
        "expected !goobj.func.arginfo to contain data, frame sizes, and "
        "argument offset/size pairs");

  auto ReadConstant = [&](unsigned Index) -> uint64_t {
    const auto *CAM =
        dyn_cast_or_null<ConstantAsMetadata>(MD->getOperand(Index).get());
    const auto *CI = CAM ? dyn_cast<ConstantInt>(CAM->getValue()) : nullptr;
    if (!CI || !CI->getType()->isIntegerTy(64))
      report_fatal_error(
          "expected !goobj.func.arginfo layout operand to be i64");
    return CI->getZExtValue();
  };

  const auto *CAM =
      dyn_cast_or_null<ConstantAsMetadata>(MD->getOperand(0).get());
  const auto *Data = CAM ? dyn_cast<GlobalValue>(CAM->getValue()) : nullptr;
  if (!Data)
    report_fatal_error(
        "expected !goobj.func.arginfo data operand to be an LLVM global "
        "reference");

  GoObjArgInfo Info;
  Info.Data = Data;
  Info.ArgSize = ReadConstant(1);
  Info.SpillAreaOffset = ReadConstant(2);
  if (Info.SpillAreaOffset > Info.ArgSize)
    report_fatal_error("invalid !goobj.func.arginfo spill area offset");
  for (unsigned I = 3, E = MD->getNumOperands(); I != E; I += 2) {
    uint64_t Offset = ReadConstant(I);
    uint64_t Size = ReadConstant(I + 1);
    if (Offset > Info.ArgSize || Size > Info.ArgSize - Offset)
      report_fatal_error("!goobj.func.arginfo argument is outside its frame");
    Info.Args.emplace_back(Offset, Size);
  }
  Info.TracebackSlots = decodeGoObjTracebackSlots(
      *Info.Data, Info.ArgSize, Info.SpillAreaOffset);
  return Info;
}

static uint16_t
getGoObjArgLiveStoreMask(const MachineInstr &MI,
                         ArrayRef<MachineFrameInfo::GoObjArgLiveSlot> Slots) {
  if (!MI.mayStore())
    return 0;

  uint16_t Mask = 0;
  for (const MachineMemOperand *MMO : MI.memoperands()) {
    if (!MMO->isStore())
      continue;
    const auto *Fixed =
        dyn_cast_or_null<FixedStackPseudoSourceValue>(MMO->getPseudoValue());
    if (!Fixed)
      continue;
    LocationSize StoreSize = MMO->getSize();
    if (!StoreSize.hasValue() || !StoreSize.isPrecise() ||
        StoreSize.isScalable() || MMO->getOffset() < 0)
      continue;
    uint64_t StoreBegin = static_cast<uint64_t>(MMO->getOffset());
    uint64_t StoreBytes = StoreSize.getValue().getFixedValue();
    if (StoreBegin > UINT64_MAX - StoreBytes)
      continue;
    uint64_t StoreEnd = StoreBegin + StoreBytes;
    for (const MachineFrameInfo::GoObjArgLiveSlot &Slot : Slots) {
      if (Slot.FrameIndex != Fixed->getFrameIndex())
        continue;
      uint64_t SlotBegin = Slot.Offset;
      uint64_t SlotEnd = SlotBegin + Slot.Size;
      if (StoreBegin <= SlotBegin && SlotEnd <= StoreEnd)
        Mask |= Slot.Mask;
    }
  }
  return Mask;
}

void recordGoObjArgLiveStores(MachineFunction &MF) {
  MachineFrameInfo &MFI = MF.getFrameInfo();
  ArrayRef<MachineFrameInfo::GoObjArgLiveSlot> Slots =
      MFI.getGoObjArgLiveSlots();
  if (Slots.empty())
    return;

  uint16_t AllMask = 0;
  for (const MachineFrameInfo::GoObjArgLiveSlot &Slot : Slots)
    AllMask |= Slot.Mask;

  SmallPtrSet<const MachineBasicBlock *, 32> Reachable;
  SmallVector<const MachineBasicBlock *, 32> Worklist(1, &MF.front());
  while (!Worklist.empty()) {
    const MachineBasicBlock *MBB = Worklist.pop_back_val();
    if (!Reachable.insert(MBB).second)
      continue;
    Worklist.append(MBB->successors().begin(), MBB->successors().end());
  }

  struct BlockState {
    uint16_t LiveIn;
    uint16_t LiveOut;
    uint16_t Stores;
  };
  DenseMap<const MachineBasicBlock *, BlockState> States;
  for (const MachineBasicBlock &MBB : MF) {
    uint16_t Stores = 0;
    for (const MachineInstr &MI : MBB)
      Stores |= getGoObjArgLiveStoreMask(MI, Slots);
    uint16_t Initial = Reachable.contains(&MBB) ? AllMask : 0;
    States[&MBB] = {Initial, Initial, Stores};
  }

  bool Changed;
  do {
    Changed = false;
    for (const MachineBasicBlock &MBB : MF) {
      BlockState &State = States[&MBB];
      uint16_t LiveIn = 0;
      if (Reachable.contains(&MBB) && &MBB != &MF.front()) {
        LiveIn = AllMask;
        if (MBB.pred_empty())
          LiveIn = 0;
        else
          for (const MachineBasicBlock *Pred : MBB.predecessors())
            LiveIn &= States[Pred].LiveOut;
      }
      uint16_t LiveOut = LiveIn | State.Stores;
      if (State.LiveIn != LiveIn || State.LiveOut != LiveOut) {
        State.LiveIn = LiveIn;
        State.LiveOut = LiveOut;
        Changed = true;
      }
    }
  } while (Changed);

  // At this point block layout and machine instructions are final. Record a
  // block-entry reset when layout order does not carry the CFG live-in state,
  // then record each existing home store at its actual post-instruction PC.
  uint16_t LayoutMask = 0;
  for (MachineBasicBlock &MBB : MF) {
    uint16_t Live = States[&MBB].LiveIn;
    if (&MBB != &MF.front() && Live != LayoutMask) {
      MBB.setLabelMustBeEmitted();
      MFI.addGoObjArgLiveEvent(MBB.getSymbol(), Live);
    }
    for (MachineInstr &MI : MBB) {
      uint16_t NewLive = Live | getGoObjArgLiveStoreMask(MI, Slots);
      if (NewLive == Live)
        continue;
      MCSymbol *Label = MI.getPostInstrSymbol();
      if (!Label) {
        Label = MF.getContext().createTempSymbol("goobj_arglive");
        MI.setPostInstrSymbol(MF, Label);
      }
      Live = NewLive;
      MFI.addGoObjArgLiveEvent(Label, Live);
    }
    LayoutMask = Live;
  }
}

void validateGoObjArgInfo(const Function &F, const CallLayout &Layout) {
  std::optional<GoObjArgInfo> Info = getGoObjArgInfo(F);
  if (!Info)
    return;
  if (Info->ArgSize != Layout.ArgSize)
    report_fatal_error(Twine("!goobj.func.arginfo argument size does not "
                             "match lowered Go ABI layout for ") +
                       F.getName() + ": frontend=" + Twine(Info->ArgSize) +
                       ", backend=" + Twine(Layout.ArgSize));
  if (Info->SpillAreaOffset != Layout.SpillAreaOffset)
    report_fatal_error("!goobj.func.arginfo spill area does not match lowered "
                       "Go ABI layout");
  if (Info->Args.size() != Layout.Args.size())
    report_fatal_error("!goobj.func.arginfo argument count does not match "
                       "lowered Go ABI layout");

  uint64_t SpillOffset = Layout.SpillAreaOffset;
  for (auto [Index, Arg] : llvm::enumerate(Layout.Args)) {
    uint64_t Offset = Arg.StackOffset;
    if (Arg.InRegs && Arg.Size != 0) {
      SpillOffset = alignToValue(SpillOffset, Arg.Alignment);
      Offset = SpillOffset;
      SpillOffset += Arg.Size;
    }
    auto [FrontendOffset, FrontendSize] = Info->Args[Index];
    if (FrontendSize != Arg.Size)
      report_fatal_error("!goobj.func.arginfo argument size does not match "
                         "lowered Go ABI home");
    // Zero-sized arguments have an alignment carrier but occupy no ABI home.
    if (Arg.Size != 0 && FrontendOffset != Offset)
      report_fatal_error("!goobj.func.arginfo argument offset does not match "
                         "lowered Go ABI home");
  }
  if (SpillOffset - Layout.SpillAreaOffset != Layout.SpillAreaSize)
    report_fatal_error("inconsistent lowered Go ABI spill area");
}

static void collectPointerOffsets(Type *Ty, uint64_t BaseOffset,
                                  const DataLayout &DL,
                                  SmallVectorImpl<uint64_t> &Offsets) {
  if (Ty->isPointerTy()) {
    Offsets.push_back(BaseOffset);
    return;
  }

  if (auto *AT = dyn_cast<ArrayType>(Ty)) {
    uint64_t Stride = DL.getTypeAllocSize(AT->getElementType());
    for (uint64_t I = 0; I != AT->getNumElements(); ++I)
      collectPointerOffsets(AT->getElementType(), BaseOffset + I * Stride, DL,
                            Offsets);
    return;
  }

  if (auto *ST = dyn_cast<StructType>(Ty)) {
    const StructLayout *Layout = DL.getStructLayout(ST);
    for (auto [Index, ElementTy] : llvm::enumerate(ST->elements()))
      collectPointerOffsets(
          ElementTy, BaseOffset + Layout->getElementOffset(Index), DL, Offsets);
    return;
  }

  if (Ty->isVectorTy() && Ty->getScalarType()->isPointerTy())
    report_fatal_error("Go entry argument maps do not support pointer vectors");
}

EntryArgsInfo computeEntryArgsInfo(const CallLayout &Layout,
                                   const DataLayout &DL,
                                   const ABIConfig &Config) {
  if (!Config.PtrSize || Layout.ArgSize % Config.PtrSize != 0 ||
      Layout.ArgSize / Config.PtrSize > std::numeric_limits<uint32_t>::max())
    report_fatal_error("invalid Go entry argument map dimensions");
  EntryArgsInfo Info;
  Info.PointerSize = Config.PtrSize;
  Info.ArgSize = Layout.ArgSize;
  Info.NumBits = static_cast<uint32_t>(Layout.ArgSize / Config.PtrSize);

  SmallVector<uint64_t, 8> HomeOffsets(Layout.Args.size());
  uint64_t SpillOffset = Layout.SpillAreaOffset;
  for (auto [Index, ArgLayout] : llvm::enumerate(Layout.Args)) {
    if (ArgLayout.InRegs) {
      if (ArgLayout.Size != 0)
        SpillOffset = alignToValue(SpillOffset, ArgLayout.Alignment);
      HomeOffsets[Index] = SpillOffset;
      SpillOffset += ArgLayout.Size;
    } else {
      HomeOffsets[Index] = ArgLayout.StackOffset;
    }
  }
  if (SpillOffset != Layout.SpillAreaOffset + Layout.SpillAreaSize)
    report_fatal_error("Go entry argument homes do not match spill area");

  SmallVector<uint64_t, 16> PointerOffsets;
  for (auto [Index, ArgLayout] : llvm::enumerate(Layout.Args))
    collectPointerOffsets(ArgLayout.Ty, HomeOffsets[Index], DL, PointerOffsets);
  llvm::sort(PointerOffsets);

  for (uint64_t Offset : PointerOffsets) {
    if (Offset % Config.PtrSize != 0 ||
        Offset + Config.PtrSize > Layout.ArgSize)
      report_fatal_error(
          "Go entry argument pointer is outside an aligned ABI home");
    uint32_t Word = static_cast<uint32_t>(Offset / Config.PtrSize);
    if (!Info.PointerWords.empty() && Info.PointerWords.back() >= Word)
      report_fatal_error(
          "Go entry argument pointer words are not strictly ordered");
    Info.PointerWords.push_back(Word);
  }

  // TODO(goallc): LLVM opaque pointer types currently conflate the non-GC
  // itab/type word of a Go interface and pointers to NotInHeap types with
  // ordinary Go GC pointers. Treat them conservatively until the frontend
  // gives those words a distinct IR type or signature attribute.
  return Info;
}

} // namespace llvm::goabi
