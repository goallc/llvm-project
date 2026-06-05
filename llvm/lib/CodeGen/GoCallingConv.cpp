//===- GoCallingConv.cpp - Go ABI helper implementation -------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/CodeGen/GoCallingConv.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Instructions.h"

using namespace llvm;

namespace llvm::goabi {

static bool classifyType(Type *Ty, const DataLayout &DL, const ABIConfig &Config,
                         unsigned &IntRegs, unsigned &FPRegs) {
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

CallLayout computeCallLayout(ArrayRef<Type *> ArgTys, ArrayRef<Type *> ResultTys,
                             const DataLayout &DL, const ABIConfig &Config) {
  CallLayout Layout;
  Layout.Args.reserve(ArgTys.size());
  Layout.Results.reserve(ResultTys.size());

  unsigned NextInt = 0;
  unsigned NextFP = 0;
  uint64_t StackArgsEnd = 0;
  for (Type *ArgTy : ArgTys) {
    ValueLayout ArgLayout = computeValueLayout(ArgTy, DL, Config, NextInt, NextFP);
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
  Layout.TotalStackSize =
      alignToValue(alignToValue(SpillEnd, Config.PtrAlign), Config.StackAlign);
  return Layout;
}

bool isIntegerPiece(Type *Ty) {
  return Ty->isPointerTy() || Ty->isIntegerTy();
}

bool isFloatingPiece(Type *Ty) {
  return Ty->isHalfTy() || Ty->isBFloatTy() || Ty->isFloatTy() ||
         Ty->isDoubleTy();
}

} // namespace llvm::goabi
