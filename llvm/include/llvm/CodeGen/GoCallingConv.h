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
#include "llvm/ADT/SmallBitVector.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/BinaryFormat/GoObj.h"
#include "llvm/IR/Attributes.h"
#include "llvm/IR/CallingConv.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Function.h"
#include "llvm/Support/Alignment.h"
#include <cstdint>
#include <string>

namespace llvm {

class CallBase;
class MachineFunction;
class MachineInstrBuilder;
class Type;

namespace goabi {

inline constexpr StringLiteral TupleResultsAttr = "go_results_tuple";
inline constexpr StringLiteral PadTypeName = "go.abi.pad";
// Target frame lowering must not synthesize a morestack edge for such a
// function. GoObj Go functions otherwise use the native Go default: emit a
// stack check and call the ABI0 runtime.morestack helper on the slow path.
inline constexpr StringLiteral NoSplitAttr = "go-nosplit";
// A //go:systemstack function checks g.stackguard1 and traps through
// runtime.morestackc if it is entered on an ordinary goroutine stack.
inline constexpr StringLiteral SystemStackAttr = "go-systemstack";
// Every GoObj Go function carries its entry argument pointer map in a
// zero-byte STACKMAP. It is function metadata, not a stack-growth callsite.
inline constexpr uint64_t EntryArgsStackMapID = GoObj::EntryArgsStackMapID;

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
// Mirrors ComputeValueTypes and marks leaves originating in %go.abi.pad.
SmallBitVector getPaddingPieces(Type *Ty);

void getReturnTypes(Type *ReturnType, bool TupleResults,
                    SmallVectorImpl<Type *> &ResultTys);

/// Complete the Go ABI frame layout after the target calling-convention rules
/// have assigned every input to either registers or a stack offset and
/// computed the input stack extent. This helper does not classify inputs.
/// Result classification remains here until stack results have an explicit IR
/// carrier of their own.
CallLayout computeCallLayout(ArrayRef<ValueLayout> Args, uint64_t StackArgsSize,
                             ArrayRef<Type *> ResultTys, const DataLayout &DL,
                             const ABIConfig &Config);

/// Collect the logical Go input type represented by each non-context IR
/// argument. A typed byval pointer represents its pointee value; all other
/// arguments represent their IR type directly. Physical register and stack
/// locations come exclusively from the target calling-convention analysis.
void getArgumentTypes(const Function &F, SmallVectorImpl<Type *> &ArgTys,
                      SmallVectorImpl<int> &ArgToLayout);

EntryArgsInfo computeEntryArgsInfo(ArrayRef<Type *> ArgTys,
                                   const CallLayout &Layout,
                                   const DataLayout &DL,
                                   const ABIConfig &Config);

bool isIntegerPiece(Type *Ty);
bool isFloatingPiece(Type *Ty);

/// Add a late target-inserted call operand for the ABI0 form of \p SymbolName.
/// ABI0 identity is encoded directly in the MC symbol name; the GoObj writer
/// strips the reserved suffix and records ABI0 in the object symbol.
void addGoObjABI0Callee(MachineInstrBuilder &MIB, MachineFunction &MF,
                        StringRef SymbolName);

/// Resolve a compiler-provided Go builtin declaration by its logical linker
/// name and calling convention. The declaration name carries its GoObj builtin
/// index, so target late passes never need a duplicate builtin table.
std::string getGoObjBuiltinCalleeName(MachineFunction &MF, StringRef SymbolName,
                                      CallingConv::ID CC);

} // namespace goabi
} // namespace llvm

#endif // LLVM_CODEGEN_GOCALLINGCONV_H
