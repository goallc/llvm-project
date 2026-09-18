//===- GoObjBuiltinNameTest.cpp
//--------------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/CodeGen/CodeGenTargetMachineImpl.h"
#include "llvm/CodeGen/GoCallingConv.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/TargetFrameLowering.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetLowering.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/TargetRegistry.h"
#include "gtest/gtest.h"

using namespace llvm;

namespace {
#include "MFCommon.inc"

class GoObjBuiltinNameTest : public testing::Test {
protected:
  LLVMContext Ctx;
  Module M{"test", Ctx};
  BogusTargetMachine TM;
  MachineModuleInfo MMI{&TM};
  std::unique_ptr<MachineFunction> MF;

  void SetUp() override {
    Function *Caller = add("caller", CallingConv::GoABIInternal);
    MF = std::make_unique<MachineFunction>(
        *Caller, TM, *TM.getSubtargetImpl(*Caller), MMI.getContext(), 0);
  }

  Function *add(StringRef Name, CallingConv::ID CC) {
    auto *F = Function::Create(FunctionType::get(Type::getVoidTy(Ctx), false),
                               GlobalValue::ExternalLinkage, Name, M);
    F->setCallingConv(CC);
    return F;
  }

  std::string lookup(StringRef Name, CallingConv::ID CC = CallingConv::GoABI0) {
    return goabi::getGoObjBuiltinCalleeName(*MF, Name, CC);
  }
};

TEST_F(GoObjBuiltinNameTest, ABIAndOrdinaryFunctionMutations) {
  auto *F = add("runtime.helper<builtin.10><ABI0>", CallingConv::GoABI0);
  add("runtime.helper<builtin.11>", CallingConv::GoABIInternal);
  EXPECT_EQ(lookup("runtime.helper"), F->getName());
  EXPECT_EQ(lookup("runtime.helper", CallingConv::GoABIInternal),
            "runtime.helper<builtin.11>");
  // Ordinary function mutations during emission do not affect builtin bindings.
  auto *Other = add("ordinary", CallingConv::C);
  Other->setName("renamed");
  Other->eraseFromParent();
  EXPECT_EQ(lookup("runtime.helper"), F->getName());
}

TEST_F(GoObjBuiltinNameTest, NewPMEmissionResetsIndexForSameModule) {
  auto *F = add("runtime.helper<builtin.10><ABI0>", CallingConv::GoABI0);
  EXPECT_EQ(lookup("runtime.helper"), F->getName());
  // IR preparation between emissions may replace builtin declarations.
  F->eraseFromParent();
  F = add("runtime.helper<builtin.12><ABI0>", CallingConv::GoABI0);
  ModuleAnalysisManager MAM;
  MachineModuleAnalysis Analysis(MMI);
  (void)Analysis.run(M, MAM);
  EXPECT_EQ(lookup("runtime.helper"), F->getName());
}

TEST_F(GoObjBuiltinNameTest, LegacyEmissionResetsIndexForSameModule) {
  MachineModuleInfoWrapperPass Wrapper(&TM, &MMI.getContext());
  Wrapper.doInitialization(M);
  auto *F = add("runtime.helper<builtin.10><ABI0>", CallingConv::GoABI0);
  EXPECT_EQ(lookup("runtime.helper"), F->getName());
  Wrapper.doFinalization(M);
  F->eraseFromParent();
  F = add("runtime.helper<builtin.12><ABI0>", CallingConv::GoABI0);
  Wrapper.doInitialization(M);
  EXPECT_EQ(lookup("runtime.helper"), F->getName());
  Wrapper.doFinalization(M);
}

TEST_F(GoObjBuiltinNameTest, IgnoresMalformedAndUnqueriedNames) {
  add("runtime.helper<builtin.4294967296><ABI0>", CallingConv::GoABI0);
  add("runtime.helper<builtin.><ABI0>", CallingConv::GoABI0);
  add("runtime.helper<builtin.x><ABI0>", CallingConv::GoABI0);
  add("runtime.unused<builtin.1><ABI0>", CallingConv::C);
  add("runtime.unused<builtin.2><ABI0>", CallingConv::GoABI0);
  EXPECT_EQ(lookup("runtime.helper"), "runtime.helper<ABI0>");
}

TEST_F(GoObjBuiltinNameTest, DuplicateDeclarations) {
  add("runtime.helper<builtin.1><ABI0>", CallingConv::GoABI0);
  add("runtime.helper<builtin.2><ABI0>", CallingConv::GoABI0);
  EXPECT_DEATH(lookup("runtime.helper"), "duplicate Go builtin declaration");
}

TEST_F(GoObjBuiltinNameTest, CallingConventionChangesWithoutRename) {
  auto *F = add("runtime.helper<builtin.1><ABI0>", CallingConv::GoABI0);
  EXPECT_EQ(lookup("runtime.helper"), F->getName());
  F->setCallingConv(CallingConv::C);
  EXPECT_DEATH(lookup("runtime.helper"),
               "Go builtin declaration has invalid calling convention");
}

TEST_F(GoObjBuiltinNameTest, MissingProductionDeclaration) {
  M.getOrInsertNamedMetadata("goobj.config");
  EXPECT_DEATH(lookup("runtime.helper"), "missing Go builtin declaration");
}

TEST_F(GoObjBuiltinNameTest, DifferentModuleInSameContext) {
  add("runtime.helper<builtin.1><ABI0>", CallingConv::GoABI0);
  EXPECT_EQ(lookup("runtime.helper"), "runtime.helper<builtin.1><ABI0>");
  Module Other("other", Ctx);
  auto *F = Function::Create(FunctionType::get(Type::getVoidTy(Ctx), false),
                             GlobalValue::ExternalLinkage, "caller", Other);
  MachineFunction OtherMF(*F, TM, *TM.getSubtargetImpl(*F), MMI.getContext(),
                          1);
  EXPECT_EQ(goabi::getGoObjBuiltinCalleeName(OtherMF, "runtime.helper",
                                             CallingConv::GoABI0),
            "runtime.helper<ABI0>");
  EXPECT_EQ(lookup("runtime.helper"), "runtime.helper<builtin.1><ABI0>");
}
} // namespace
