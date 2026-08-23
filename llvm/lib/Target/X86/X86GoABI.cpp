//===- X86GoABI.cpp - Repair reserved Go ABI state ------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// R14 and XMM15 are reserved in every x86-64 Go function. ABIInternal requires
// them to contain g and zero respectively, while ABI0 does not establish or
// preserve those values. Call lowering marks ABI0 calls as explicit clobbers
// before register allocation. This late pass repairs the reserved state at ABI
// boundaries after register allocation, frame lowering, and scheduling.
//
//===----------------------------------------------------------------------===//

#include "MCTargetDesc/X86BaseInfo.h"
#include "X86.h"
#include "X86InstrInfo.h"
#include "X86RegisterInfo.h"
#include "X86Subtarget.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/CodeGen/GoCallingConv.h"
#include "llvm/CodeGen/MachineBasicBlock.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachinePassManager.h"
#include "llvm/CodeGen/StackMaps.h"
#include "llvm/IR/CallingConv.h"
#include "llvm/Pass.h"

#include <iterator>

using namespace llvm;

#define DEBUG_TYPE "x86-go-abi"

namespace {

class X86GoABILegacy : public MachineFunctionPass {
public:
  static char ID;

  X86GoABILegacy() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override { return "X86 Go ABI state repair"; }

  bool runOnMachineFunction(MachineFunction &MF) override;

  MachineFunctionProperties getRequiredProperties() const override {
    return MachineFunctionProperties().setNoVRegs();
  }

  void getAnalysisUsage(AnalysisUsage &AU) const override {
    AU.setPreservesCFG();
    MachineFunctionPass::getAnalysisUsage(AU);
  }
};

} // end anonymous namespace

char X86GoABILegacy::ID = 0;

INITIALIZE_PASS(X86GoABILegacy, DEBUG_TYPE, "X86 Go ABI state repair", false,
                false)

FunctionPass *llvm::createX86GoABILegacyPass() { return new X86GoABILegacy(); }

static bool isOrdinaryGoCall(const MachineInstr &MI,
                             const MachineFunction &MF) {
  if (MI.getOpcode() == TargetOpcode::STATEPOINT)
    return goabi::isGoCallingConv(StatepointOpers(&MI).getCallingConv());

  const X86RegisterInfo &TRI =
      *MF.getSubtarget<X86Subtarget>().getRegisterInfo();
  const uint32_t *GoABIInternalMask =
      TRI.getCallPreservedMask(MF, CallingConv::GoABIInternal);
  const uint32_t *GoABI0Mask =
      TRI.getCallPreservedMask(MF, CallingConv::GoABI0);
  return llvm::any_of(MI.operands(), [&](const MachineOperand &MO) {
    return MO.isRegMask() &&
           (MO.getRegMask() == GoABIInternalMask ||
            MO.getRegMask() == GoABI0Mask);
  });
}

static bool isGoABI0Call(const MachineInstr &MI, const MachineFunction &MF) {
  if (MI.getOpcode() == TargetOpcode::STATEPOINT)
    return goabi::isGoABI0CallingConv(
        StatepointOpers(&MI).getCallingConv());

  const X86RegisterInfo &TRI =
      *MF.getSubtarget<X86Subtarget>().getRegisterInfo();
  const uint32_t *GoABI0Mask =
      TRI.getCallPreservedMask(MF, CallingConv::GoABI0);
  return llvm::any_of(MI.operands(), [&](const MachineOperand &MO) {
    return MO.isRegMask() && MO.getRegMask() == GoABI0Mask;
  });
}

static void emitABIInternalState(MachineBasicBlock &MBB,
                                 MachineBasicBlock::iterator Pos,
                                 const DebugLoc &DL, const X86InstrInfo &TII) {
  BuildMI(MBB, Pos, DL, TII.get(X86::XORPSrr), X86::XMM15)
      .addReg(X86::XMM15, RegState::Undef)
      .addReg(X86::XMM15, RegState::Undef);
  BuildMI(MBB, Pos, DL, TII.get(X86::MOV64rm), X86::R14)
      .addReg(X86::NoRegister)
      .addImm(1)
      .addReg(X86::NoRegister)
      .addExternalSymbol("runtime.tlsg", X86II::MO_TPOFF)
      .addReg(X86::FS);
}

static bool repairGoABIState(MachineFunction &MF) {
  CallingConv::ID CallerCC = MF.getFunction().getCallingConv();
  if (!goabi::isGoCallingConv(CallerCC))
    return false;

  const X86Subtarget &ST = MF.getSubtarget<X86Subtarget>();
  if (!ST.is64Bit())
    return false;

  assert(MF.getRegInfo().isReserved(X86::R14) &&
         MF.getRegInfo().isReserved(X86::XMM15) &&
         "Go ABI state registers must be reserved");

  const X86InstrInfo &TII = *ST.getInstrInfo();
  bool Changed = false;
  for (MachineBasicBlock &MBB : MF) {
    for (auto I = MBB.begin(); I != MBB.end(); ++I) {
      MachineInstr &MI = *I;
      if (!MI.isCall() && !TII.isTailCall(MI))
        continue;
      if (!isOrdinaryGoCall(MI, MF))
        continue;

      bool CalleeIsABI0 = isGoABI0Call(MI, MF);
      bool RepairBefore = goabi::isGoABI0CallingConv(CallerCC) && !CalleeIsABI0;
      bool RepairAfter =
          goabi::isGoABIInternalCallingConv(CallerCC) && CalleeIsABI0;
      if (RepairBefore) {
        emitABIInternalState(MBB, I, MI.getDebugLoc(), TII);
        Changed = true;
      } else if (RepairAfter) {
        emitABIInternalState(MBB, std::next(I), MI.getDebugLoc(), TII);
        Changed = true;
      }
    }
  }
  return Changed;
}

bool X86GoABILegacy::runOnMachineFunction(MachineFunction &MF) {
  return repairGoABIState(MF);
}

PreservedAnalyses X86GoABIPass::run(MachineFunction &MF,
                                    MachineFunctionAnalysisManager &MFAM) {
  return repairGoABIState(MF) ? getMachineFunctionPassPreservedAnalyses()
                                    .preserveSet<CFGAnalyses>()
                              : PreservedAnalyses::all();
}
