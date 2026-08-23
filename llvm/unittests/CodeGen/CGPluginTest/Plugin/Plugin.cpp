//===----------------------------------------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "CodeGenTestPass.h"

#include <llvm/ADT/StringRef.h>
#include <llvm/CodeGen/GoObjAsyncPreemption.h>
#include <llvm/CodeGen/MachineBasicBlock.h>
#include <llvm/CodeGen/MachineFunction.h>
#include <llvm/CodeGen/MachineInstr.h>
#include <llvm/CodeGen/Passes.h>
#include <llvm/CodeGen/TargetInstrInfo.h>
#include <llvm/CodeGen/TargetPassConfig.h>
#include <llvm/Target/RegisterTargetPassConfigCallback.h>

using namespace llvm;

namespace {
[[maybe_unused]] RegisterTargetPassConfigCallback X{
    [](auto &TM, auto &PM, auto *TPC) {
      TPC->insertPass(&GCLoweringID, &CodeGenTest::ID);
    }};

[[maybe_unused]] RegisterGoObjAsyncPreemptionCallback Y{
    [](const MachineFunction &MF, GoObjUnsafeInstructionMarker MarkUnsafe) {
      if (MF.getName() != "goobj_async_preemption_ranges")
        return GoObjAsyncPreemptionMode::Unhandled;
      const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();
      for (const MachineBasicBlock &MBB : MF)
        for (const MachineInstr &MI : MBB)
          if (StringRef(TII.getName(MI.getOpcode())).starts_with("ADD64ri")) {
            MarkUnsafe(MI);
            return GoObjAsyncPreemptionMode::InstructionRanges;
          }
      return GoObjAsyncPreemptionMode::InstructionRanges;
    }};
} // namespace

__attribute__((constructor)) static void initCodeGenPlugin() {
  initializeCodeGenTestPass(*PassRegistry::getPassRegistry());
}
