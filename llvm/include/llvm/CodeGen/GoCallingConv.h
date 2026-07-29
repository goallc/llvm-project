//===- GoCallingConv.h - Go ABI helper declarations -------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CODEGEN_GOCALLINGCONV_H
#define LLVM_CODEGEN_GOCALLINGCONV_H

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/BinaryFormat/GoObj.h"
#include "llvm/IR/Attributes.h"
#include "llvm/IR/CallingConv.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Function.h"
#include "llvm/Support/Alignment.h"
#include <cstdint>

namespace llvm {

class CallBase;
class Type;

namespace goabi {

inline constexpr StringLiteral TupleResultsAttr = "go_results_tuple";
// The Go statepoint pass uses this attribute to request that target frame
// lowering represent the late morestack call with a root-free STATEPOINT.
inline constexpr StringLiteral StackGrowthStatepointAttr =
    "go-stack-growth-statepoint";
inline constexpr uint64_t StackGrowthStatepointID =
    GoObj::StackGrowthStatepointID;

inline bool isGoABIInternalCallingConv(CallingConv::ID CC) {
  return CC == CallingConv::GoABIInternal;
}

inline bool isGoABI0CallingConv(CallingConv::ID CC) {
  return CC == CallingConv::GoABI0;
}

inline bool isGoCallingConv(CallingConv::ID CC) {
  return isGoABIInternalCallingConv(CC) || isGoABI0CallingConv(CC);
}

struct ABIConfig {
  ArrayRef<unsigned> IntRegs;
  ArrayRef<unsigned> FPRegs;
  unsigned PtrSize = 0;
  Align PtrAlign = Align(1);
  Align StackAlign = Align(1);
  bool SoftFloat = false;
};

struct ValueLayout {
  Type *Ty = nullptr;
  bool InRegs = false;
  unsigned IntRegStart = 0;
  unsigned IntRegCount = 0;
  unsigned FPRegStart = 0;
  unsigned FPRegCount = 0;
  uint64_t StackOffset = 0;
  uint64_t Size = 0;
  Align Alignment = Align(1);
};

struct CallLayout {
  SmallVector<ValueLayout, 8> Args;
  SmallVector<ValueLayout, 8> Results;
  uint64_t StackArgsSize = 0;
  uint64_t StackResultsSize = 0;
  uint64_t SpillAreaOffset = 0;
  uint64_t SpillAreaSize = 0;
  /// Semantic Go argument/result/home area size, excluding target call-frame
  /// tail padding.
  uint64_t ArgSize = 0;
  uint64_t TotalStackSize = 0;
};

struct EntryArgsInfo {
  uint32_t PointerSize = 0;
  uint64_t ArgSize = 0;
  uint32_t NumBits = 0;
  SmallVector<uint32_t, 8> PointerWords;
};

bool hasTupleResultsAttr(const AttributeList &Attrs);
bool hasTupleResultsAttr(const Function &F);
bool hasTupleResultsAttr(const CallBase &CB);

void getReturnTypes(Type *ReturnType, bool TupleResults,
                    SmallVectorImpl<Type *> &ResultTys);

CallLayout computeCallLayout(ArrayRef<Type *> ArgTys,
                             ArrayRef<Type *> ResultTys, const DataLayout &DL,
                             const ABIConfig &Config);

EntryArgsInfo computeEntryArgsInfo(ArrayRef<Type *> ArgTys,
                                   const CallLayout &Layout,
                                   const DataLayout &DL,
                                   const ABIConfig &Config);

bool isIntegerPiece(Type *Ty);
bool isFloatingPiece(Type *Ty);

} // namespace goabi
} // namespace llvm

#endif // LLVM_CODEGEN_GOCALLINGCONV_H
