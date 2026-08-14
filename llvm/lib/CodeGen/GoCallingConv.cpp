//===- GoCallingConv.cpp - Go ABI helper implementation -------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/CodeGen/GoCallingConv.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/CodeGen/CommandFlags.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/ErrorHandling.h"
#include <limits>
#include <string>

using namespace llvm;

namespace llvm::goabi {

std::string getGoObjBuiltinCalleeName(MachineFunction &MF, StringRef SymbolName,
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

static bool classifyType(Type *Ty, const DataLayout &DL,
                         const ABIConfig &Config, unsigned &IntRegs,
                         unsigned &FPRegs) {
  if (isPaddingType(Ty))
    return true;

  if (Ty->isVoidTy())
    return true;

  if (DL.getTypeAllocSize(Ty) == 0)
    return true;

  if (auto *AT = dyn_cast<ArrayType>(Ty)) {
    uint64_t Len = AT->getNumElements();
    if (Len == 0)
      return true;
    if (Len == 1)
      return classifyType(AT->getElementType(), DL, Config, IntRegs, FPRegs);
    return false;
  }

  if (auto *ST = dyn_cast<StructType>(Ty)) {
    for (Type *EltTy : ST->elements())
      if (!classifyType(EltTy, DL, Config, IntRegs, FPRegs))
        return false;
    return true;
  }

  if (Ty->isPointerTy()) {
    ++IntRegs;
    return IntRegs <= Config.IntRegs.size();
  }

  if (Ty->isIntegerTy()) {
    unsigned Bits = Ty->getIntegerBitWidth();
    unsigned PtrBits = Config.PtrSize * 8;
    if (Bits <= PtrBits) {
      ++IntRegs;
      return IntRegs <= Config.IntRegs.size();
    }
    if (Bits <= PtrBits * 2) {
      IntRegs += 2;
      return IntRegs <= Config.IntRegs.size();
    }
    return false;
  }

  if (Ty->isHalfTy() || Ty->isBFloatTy() || Ty->isFloatTy() ||
      Ty->isDoubleTy()) {
    if (Config.SoftFloat)
      return false;
    ++FPRegs;
    return FPRegs <= Config.FPRegs.size();
  }

  return false;
}

static uint64_t alignToValue(uint64_t Value, Align Alignment) {
  return alignTo(Value, Alignment.value());
}

static ValueLayout computeValueLayout(Type *Ty, const DataLayout &DL,
                                      const ABIConfig &Config, unsigned &IntReg,
                                      unsigned &FPReg) {
  ValueLayout Layout;
  Layout.Ty = Ty;
  Layout.Size = DL.getTypeAllocSize(Ty);
  Layout.Alignment = DL.getABITypeAlign(Ty);
  Layout.IntRegStart = IntReg;
  Layout.FPRegStart = FPReg;

  SmallBitVector PaddingPieces = getPaddingPieces(Ty);
  if (PaddingPieces.any() && PaddingPieces.count() == PaddingPieces.size()) {
    Layout.Size = 0;
    return Layout;
  }

  unsigned IntAfter = IntReg;
  unsigned FPAfter = FPReg;
  if (classifyType(Ty, DL, Config, IntAfter, FPAfter)) {
    Layout.InRegs = true;
    Layout.IntRegCount = IntAfter - IntReg;
    Layout.FPRegCount = FPAfter - FPReg;
    IntReg = IntAfter;
    FPReg = FPAfter;
  }

  return Layout;
}

static uint64_t layoutStackValue(uint64_t Offset, ValueLayout &Layout) {
  Offset = alignToValue(Offset, Layout.Alignment);
  Layout.StackOffset = Offset;
  return Offset + Layout.Size;
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

CallLayout computeCallLayout(ArrayRef<Type *> ArgTys,
                             ArrayRef<Type *> ResultTys, const DataLayout &DL,
                             const ABIConfig &Config) {
  CallLayout Layout;
  Layout.Args.reserve(ArgTys.size());
  Layout.Results.reserve(ResultTys.size());

  unsigned NextInt = 0;
  unsigned NextFP = 0;
  uint64_t StackArgsEnd = 0;
  for (Type *ArgTy : ArgTys) {
    ValueLayout ArgLayout =
        computeValueLayout(ArgTy, DL, Config, NextInt, NextFP);
    if (!ArgLayout.InRegs)
      StackArgsEnd = layoutStackValue(StackArgsEnd, ArgLayout);
    Layout.Args.push_back(ArgLayout);
  }
  Layout.StackArgsSize = StackArgsEnd;

  NextInt = 0;
  NextFP = 0;
  uint64_t StackResultsEnd = alignToValue(StackArgsEnd, Config.PtrAlign);
  uint64_t StackResultsStart = StackResultsEnd;
  for (Type *ResultTy : ResultTys) {
    ValueLayout ResultLayout =
        computeValueLayout(ResultTy, DL, Config, NextInt, NextFP);
    if (!ResultLayout.InRegs)
      StackResultsEnd = layoutStackValue(StackResultsEnd, ResultLayout);
    Layout.Results.push_back(ResultLayout);
  }
  Layout.StackResultsSize = StackResultsEnd - StackResultsStart;

  uint64_t SpillEnd = alignToValue(StackResultsEnd, Config.PtrAlign);
  Layout.SpillAreaOffset = SpillEnd;
  for (const ValueLayout &ArgLayout : Layout.Args)
    if (ArgLayout.InRegs)
      SpillEnd = alignToValue(SpillEnd, ArgLayout.Alignment) + ArgLayout.Size;
  Layout.SpillAreaSize = SpillEnd - Layout.SpillAreaOffset;
  Layout.ArgSize = alignToValue(SpillEnd, Config.PtrAlign);
  Layout.TotalStackSize = alignToValue(Layout.ArgSize, Config.StackAlign);
  return Layout;
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

EntryArgsInfo computeEntryArgsInfo(ArrayRef<Type *> ArgTys,
                                   const CallLayout &Layout,
                                   const DataLayout &DL,
                                   const ABIConfig &Config) {
  if (!Config.PtrSize || Layout.ArgSize % Config.PtrSize != 0 ||
      Layout.ArgSize / Config.PtrSize > std::numeric_limits<uint32_t>::max())
    report_fatal_error("invalid Go entry argument map dimensions");
  if (ArgTys.size() != Layout.Args.size())
    report_fatal_error("Go entry argument types do not match ABI layout");

  EntryArgsInfo Info;
  Info.PointerSize = Config.PtrSize;
  Info.ArgSize = Layout.ArgSize;
  Info.NumBits = static_cast<uint32_t>(Layout.ArgSize / Config.PtrSize);

  SmallVector<uint64_t, 8> HomeOffsets(ArgTys.size());
  uint64_t SpillOffset = Layout.SpillAreaOffset;
  for (auto [Index, ArgLayout] : llvm::enumerate(Layout.Args)) {
    if (ArgLayout.InRegs) {
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
  for (auto [Index, ArgTy] : llvm::enumerate(ArgTys))
    collectPointerOffsets(ArgTy, HomeOffsets[Index], DL, PointerOffsets);
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

bool isIntegerPiece(Type *Ty) { return Ty->isPointerTy() || Ty->isIntegerTy(); }

bool isFloatingPiece(Type *Ty) {
  return Ty->isHalfTy() || Ty->isBFloatTy() || Ty->isFloatTy() ||
         Ty->isDoubleTy();
}

} // namespace llvm::goabi
