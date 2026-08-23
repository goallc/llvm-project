//===- GoObjAsyncPreemption.cpp - GoObj unsafe-point callbacks -----------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/CodeGen/GoObjAsyncPreemption.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/STLExtras.h"

using namespace llvm;

static SmallVector<RegisterGoObjAsyncPreemptionCallback *, 1>
    GoObjAsyncPreemptionCallbacks;

RegisterGoObjAsyncPreemptionCallback::RegisterGoObjAsyncPreemptionCallback(
    GoObjAsyncPreemptionCallback &&C)
    : Callback(std::move(C)) {
  GoObjAsyncPreemptionCallbacks.push_back(this);
}

RegisterGoObjAsyncPreemptionCallback::~RegisterGoObjAsyncPreemptionCallback() {
  auto It = llvm::find(GoObjAsyncPreemptionCallbacks, this);
  if (It != GoObjAsyncPreemptionCallbacks.end())
    GoObjAsyncPreemptionCallbacks.erase(It);
}

GoObjAsyncPreemptionMode llvm::invokeGoObjAsyncPreemptionCallbacks(
    const MachineFunction &MF, GoObjUnsafeInstructionMarker MarkUnsafe) {
  GoObjAsyncPreemptionMode Result = GoObjAsyncPreemptionMode::Unhandled;
  for (const RegisterGoObjAsyncPreemptionCallback *Registration :
       GoObjAsyncPreemptionCallbacks) {
    GoObjAsyncPreemptionMode Mode = Registration->Callback(MF, MarkUnsafe);
    if (Mode == GoObjAsyncPreemptionMode::WholeFunctionUnsafe)
      return Mode;
    if (Mode == GoObjAsyncPreemptionMode::InstructionRanges)
      Result = Mode;
  }
  return Result;
}
