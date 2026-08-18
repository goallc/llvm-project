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
  uint64_t StackOffset = 0;
  uint64_t Size = 0;
  Align Alignment = Align(1);
};

struct CallLayout {
  SmallVector<ValueLayout, 8> Args;
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

struct ResultCarrier {
  unsigned Index = 0;
  Type *Ty = nullptr;
};

bool hasTupleResultsAttr(const AttributeList &Attrs);
bool hasTupleResultsAttr(const Function &F);
bool hasTupleResultsAttr(const CallBase &CB);
// Mirrors ComputeValueTypes and marks leaves originating in %go.abi.pad.
SmallBitVector getPaddingPieces(Type *Ty);

void getReturnTypes(Type *ReturnType, bool TupleResults,
                    SmallVectorImpl<Type *> &ResultTys);

/// Check that the IR-level direct/goret split matches Go's whole-value result
/// allocation. This validates the frontend decision; target TD rules remain
/// the authority for the physical register and stack locations.
void validateResultCarriers(Type *DirectReturnType, bool TupleResults,
                            ArrayRef<ResultCarrier> MemoryResults,
                            CallingConv::ID CC, const DataLayout &DL,
                            const ABIConfig &Config);

/// Complete the Go ABI frame layout after the target calling-convention rules
/// have assigned every input and goret carrier. This helper does not classify
/// values or choose physical locations.
CallLayout computeCallLayout(ArrayRef<ValueLayout> Args, uint64_t StackArgsSize,
                             uint64_t StackResultsEnd, const DataLayout &DL,
                             const ABIConfig &Config);

EntryArgsInfo computeEntryArgsInfo(const CallLayout &Layout,
                                   const DataLayout &DL,
                                   const ABIConfig &Config);

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
