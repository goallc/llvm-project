//===- GoISelLowering.cpp - Go SelectionDAG lowering helpers -------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/CodeGen/GoISelLowering.h"
#include "llvm/CodeGen/CallingConvLower.h"
#include "llvm/CodeGen/TargetCallingConv.h"
#include "llvm/IR/Argument.h"
#include "llvm/Support/ErrorHandling.h"

using namespace llvm;

namespace {

template <typename ArgT, typename GetLogicalArg>
static void
applyArgumentAssignments(ArrayRef<ArgT> Pieces, ArrayRef<CCValAssign> ArgLocs,
                         MutableArrayRef<goabi::ValueLayout> ArgLayouts,
                         MutableArrayRef<int> ArgToLayout, GetLogicalArg GetArg,
                         const DataLayout &DL) {
  if (ArgLocs.size() != Pieces.size())
    report_fatal_error("Go argument assignment count mismatch");

  SmallVector<unsigned, 8> PieceCounts(ArgToLayout.size(), 0);
  for (auto [PieceIndex, VA] : llvm::enumerate(ArgLocs)) {
    if (VA.getValNo() != PieceIndex)
      report_fatal_error("Go argument assignments are not ordered");

    const ArgT &Piece = Pieces[PieceIndex];
    unsigned ArgIndex = Piece.OrigArgIndex;
    if (ArgIndex == ISD::InputArg::NoArgIndex || ArgIndex >= ArgToLayout.size())
      report_fatal_error("Go argument piece has no logical argument");

    const auto &Arg = GetArg(ArgIndex);
    ++PieceCounts[ArgIndex];
    if (Arg.IsNest) {
      if (!VA.isRegLoc())
        report_fatal_error("Go closure context is not in a register");
      continue;
    }

    int LayoutIndex = ArgToLayout[ArgIndex];
    if (LayoutIndex < 0 || unsigned(LayoutIndex) >= ArgLayouts.size())
      report_fatal_error("Go argument has no logical layout");
    goabi::ValueLayout &Layout = ArgLayouts[LayoutIndex];
    bool IsByVal = Arg.IsByVal;
    if (Piece.Flags.isByVal() != IsByVal)
      report_fatal_error(
          "Go argument carrier disagrees with calling convention");
    if (IsByVal ? !VA.isMemLoc() : !VA.isRegLoc())
      report_fatal_error("invalid Go argument location");
    if (!IsByVal)
      continue;

    if (PieceCounts[ArgIndex] != 1 || Piece.PartOffset != 0 ||
        Piece.Flags.getByValSize() != DL.getTypeAllocSize(Layout.Ty))
      report_fatal_error("invalid Go byval argument");
    Layout.StackOffset = VA.getLocMemOffset();
    Layout.Alignment = Piece.Flags.getNonZeroByValAlign();
  }

  for (unsigned I = 0; I != ArgToLayout.size(); ++I) {
    const auto &Arg = GetArg(I);
    if (Arg.IsNest && PieceCounts[I] != 1)
      report_fatal_error("invalid Go closure context");
    if (!Arg.IsNest && Arg.IsByVal && PieceCounts[I] != 1)
      report_fatal_error("invalid Go byval argument piece count");
  }
}

struct LogicalArgView {
  bool IsNest;
  bool IsByVal;
};

} // namespace

goabi::FormalArgLayout
goabi::computeFormalArgLayout(const Function &F, ArrayRef<ISD::InputArg> Ins,
                              ArrayRef<CCValAssign> ArgLocs,
                              uint64_t StackArgsSize, const DataLayout &DL,
                              const ABIConfig &Config) {
  FormalArgLayout Info;
  getArgumentTypes(F, Info.ArgTypes, Info.ArgToLayout);

  SmallVector<ValueLayout, 8> ArgLayouts(Info.ArgTypes.size());
  for (const Argument &Arg : F.args()) {
    if (Arg.hasNestAttr())
      continue;
    int LayoutIndex = Info.ArgToLayout[Arg.getArgNo()];
    ArgLayouts[LayoutIndex].Ty = Info.ArgTypes[LayoutIndex];
    ArgLayouts[LayoutIndex].InRegs = !Arg.hasByValAttr();
  }

  auto GetArg = [&](unsigned I) {
    const Argument &Arg = *F.getArg(I);
    return LogicalArgView{Arg.hasNestAttr(), Arg.hasByValAttr()};
  };
  applyArgumentAssignments(Ins, ArgLocs, ArgLayouts, Info.ArgToLayout, GetArg,
                           DL);

  SmallVector<Type *, 8> ResultTys;
  getReturnTypes(F.getReturnType(), hasTupleResultsAttr(F), ResultTys);
  Info.Layout = goabi::computeCallLayout(ArgLayouts, StackArgsSize, ResultTys,
                                         DL, Config);
  return Info;
}

goabi::CallLayout
goabi::computeCallLayout(TargetLowering::CallLoweringInfo &CLI,
                         ArrayRef<CCValAssign> ArgLocs, uint64_t StackArgsSize,
                         const ABIConfig &Config) {
  const TargetLowering::ArgListTy &Args = CLI.getArgs();
  SmallVector<int, 8> ArgToLayout(Args.size(), -1);
  SmallVector<ValueLayout, 8> ArgLayouts;
  for (auto [I, Arg] : llvm::enumerate(Args)) {
    if (Arg.IsNest)
      continue;
    ArgToLayout[I] = ArgLayouts.size();
    Type *Ty = Arg.IsByVal ? Arg.IndirectType : Arg.OrigTy;
    if (!Ty)
      report_fatal_error("Go call argument has no logical type");
    ValueLayout &Layout = ArgLayouts.emplace_back();
    Layout.Ty = Ty;
    Layout.InRegs = !Arg.IsByVal;
  }

  auto GetArg = [&](unsigned I) {
    const TargetLowering::ArgListEntry &Arg = Args[I];
    return LogicalArgView{Arg.IsNest, Arg.IsByVal};
  };
  applyArgumentAssignments(ArrayRef(CLI.Outs), ArgLocs, ArgLayouts, ArgToLayout,
                           GetArg, CLI.DAG.getDataLayout());

  SmallVector<Type *, 8> ResultTys;
  getReturnTypes(CLI.RetTy, CLI.CB && goabi::hasTupleResultsAttr(*CLI.CB),
                 ResultTys);
  return goabi::computeCallLayout(ArgLayouts, StackArgsSize, ResultTys,
                                  CLI.DAG.getDataLayout(), Config);
}
