//===- GoObjAsyncPreemption.h - GoObj unsafe-point callbacks -*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CODEGEN_GOOBJASYNCPREEMPTION_H
#define LLVM_CODEGEN_GOOBJASYNCPREEMPTION_H

#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/Support/Compiler.h"

#include <functional>

namespace llvm {

class MachineFunction;
class MachineInstr;

enum class GoObjAsyncPreemptionMode {
  /// No callback recognized the function. Preserve the frontend-provided
  /// whole-function fallback, if any.
  Unhandled,
  /// The callback handled the function. Unmarked instructions are safe and
  /// every marked MachineInstr contributes its complete emitted half-open PC
  /// span, including any target AsmPrinter expansion, as unsafe.
  InstructionRanges,
  /// The callback handled the function but could not describe it precisely.
  WholeFunctionUnsafe,
};

using GoObjUnsafeInstructionMarker = function_ref<void(const MachineInstr &)>;
using GoObjAsyncPreemptionCallback = std::function<GoObjAsyncPreemptionMode(
    const MachineFunction &, GoObjUnsafeInstructionMarker)>;

/// Register a callback that describes asynchronous-preemption safety after
/// machine code generation is complete. The callback owns language-specific
/// policy; LLVM only converts marked final MachineInstr spans into GoObj PC
/// data. Returning InstructionRanges overrides a frontend whole-function
/// fallback without mutating IR or the MachineFunction.
class RegisterGoObjAsyncPreemptionCallback {
public:
  GoObjAsyncPreemptionCallback Callback;

  LLVM_ABI explicit RegisterGoObjAsyncPreemptionCallback(
      GoObjAsyncPreemptionCallback &&C);
  LLVM_ABI ~RegisterGoObjAsyncPreemptionCallback();
  RegisterGoObjAsyncPreemptionCallback(
      const RegisterGoObjAsyncPreemptionCallback &) = delete;
  RegisterGoObjAsyncPreemptionCallback &
  operator=(const RegisterGoObjAsyncPreemptionCallback &) = delete;
};

LLVM_ABI GoObjAsyncPreemptionMode invokeGoObjAsyncPreemptionCallbacks(
    const MachineFunction &MF, GoObjUnsafeInstructionMarker MarkUnsafe);

} // namespace llvm

#endif // LLVM_CODEGEN_GOOBJASYNCPREEMPTION_H
