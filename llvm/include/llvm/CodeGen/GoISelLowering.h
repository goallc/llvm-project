//===- GoISelLowering.h - Go SelectionDAG lowering helpers -----*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CODEGEN_GOISELLOWERING_H
#define LLVM_CODEGEN_GOISELLOWERING_H

#include "llvm/CodeGen/GoCallingConv.h"
#include "llvm/CodeGen/TargetLowering.h"

namespace llvm {

class CCValAssign;

namespace goabi {

struct FormalArgLayout {
  CallLayout Layout;
  SmallVector<Type *, 8> ArgTypes;
  SmallVector<int, 8> ArgToLayout;
};

/// Derive the logical Go function layout from LLVM formal arguments and the
/// physical locations assigned by the target calling convention.
FormalArgLayout
computeFormalArgLayout(const Function &F, ArrayRef<ISD::InputArg> Ins,
                       ArrayRef<CCValAssign> ArgLocs, uint64_t StackArgsSize,
                       const DataLayout &DL, const ABIConfig &Config);

/// Derive the logical Go call layout from the original LLVM call operands and
/// the physical locations assigned by the target calling convention.
CallLayout computeCallLayout(TargetLowering::CallLoweringInfo &CLI,
                             ArrayRef<CCValAssign> ArgLocs,
                             uint64_t StackArgsSize, const ABIConfig &Config);

} // namespace goabi
} // namespace llvm

#endif // LLVM_CODEGEN_GOISELLOWERING_H
