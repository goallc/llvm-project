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
#include <limits>

using namespace llvm;

namespace {

template <typename ArgT>
static void setByValLocation(unsigned ArgIndex, ArrayRef<ArgT> Pieces,
                             ArrayRef<CCValAssign> ArgLocs,
                             goabi::ValueLayout &Layout, const DataLayout &DL) {
  assert(ArgLocs.size() == Pieces.size() &&
         "argument assignments must match argument pieces");

  const ArgT *ByValPiece = nullptr;
  const CCValAssign *ByValLoc = nullptr;
  for (auto [PieceIndex, Piece] : llvm::enumerate(Pieces)) {
    if (Piece.OrigArgIndex != ArgIndex)
      continue;
    if (ByValPiece)
      report_fatal_error("invalid Go byval argument piece count");
    ByValPiece = &Piece;
    ByValLoc = &ArgLocs[PieceIndex];
  }

  if (!ByValPiece || !ByValPiece->Flags.isByVal() ||
      ByValPiece->PartOffset != 0 || !ByValLoc->isMemLoc() ||
      ByValPiece->Flags.getByValSize() != DL.getTypeAllocSize(Layout.Ty))
    report_fatal_error("invalid Go byval argument");

  Layout.StackOffset = ByValLoc->getLocMemOffset();
  Layout.Alignment = ByValPiece->Flags.getNonZeroByValAlign();
}

} // namespace

goabi::CallLayout
goabi::computeFormalArgLayout(const Function &F, ArrayRef<ISD::InputArg> Ins,
                              ArrayRef<CCValAssign> ArgLocs,
                              uint64_t StackArgsSize, uint64_t StackResultsEnd,
                              const DataLayout &DL, const ABIConfig &Config) {
  SmallVector<ResultCarrier, 4> MemoryResults;
  for (const Argument &Arg : F.args()) {
    if (!Arg.hasGoRetAttr())
      continue;
    uint64_t Index;
    Attribute IndexAttr = F.getAttributes()
                              .getParamAttrs(Arg.getArgNo())
                              .getAttribute("goretindex");
    if (!IndexAttr.isStringAttribute() ||
        IndexAttr.getValueAsString().getAsInteger(10, Index) ||
        Index > std::numeric_limits<unsigned>::max())
      report_fatal_error("invalid goretindex function attribute");
    MemoryResults.push_back(
        {static_cast<unsigned>(Index), Arg.getParamGoRetType()});
  }
  validateResultCarriers(F.getReturnType(), hasTupleResultsAttr(F),
                         MemoryResults, F.getCallingConv(), DL, Config);

  SmallVector<ValueLayout, 8> ArgLayouts;
  for (const Argument &Arg : F.args()) {
    if (Arg.hasNestAttr() || Arg.hasGoRetAttr())
      continue;
    ValueLayout &Layout = ArgLayouts.emplace_back();
    Layout.Ty =
        Arg.hasByValAttr() ? Arg.getPointeeInMemoryValueType() : Arg.getType();
    Layout.InRegs = !Arg.hasByValAttr();
    if (Arg.hasByValAttr())
      setByValLocation(Arg.getArgNo(), Ins, ArgLocs, Layout, DL);
  }

  return goabi::computeCallLayout(ArgLayouts, StackArgsSize, StackResultsEnd,
                                  DL, Config);
}

goabi::CallLayout
goabi::computeCallLayout(TargetLowering::CallLoweringInfo &CLI,
                         ArrayRef<CCValAssign> ArgLocs, uint64_t StackArgsSize,
                         uint64_t StackResultsEnd, const ABIConfig &Config) {
  const TargetLowering::ArgListTy &Args = CLI.getArgs();
  SmallVector<ResultCarrier, 4> MemoryResults;
  for (const TargetLowering::ArgListEntry &Arg : Args)
    if (Arg.IsGoRet)
      MemoryResults.push_back({Arg.GoRetIndex, Arg.IndirectType});
  bool TupleResults = CLI.CB && hasTupleResultsAttr(*CLI.CB);
  validateResultCarriers(CLI.OrigRetTy, TupleResults, MemoryResults,
                         CLI.CallConv, CLI.DAG.getDataLayout(), Config);

  SmallVector<ValueLayout, 8> ArgLayouts;
  for (auto [I, Arg] : llvm::enumerate(Args)) {
    if (Arg.IsNest || Arg.IsGoRet)
      continue;
    Type *Ty = Arg.IsByVal ? Arg.IndirectType : Arg.OrigTy;
    if (!Ty)
      report_fatal_error("Go call argument has no logical type");
    ValueLayout &Layout = ArgLayouts.emplace_back();
    Layout.Ty = Ty;
    Layout.InRegs = !Arg.IsByVal;
    if (Arg.IsByVal)
      setByValLocation(I, ArrayRef(CLI.Outs), ArgLocs, Layout,
                       CLI.DAG.getDataLayout());
  }

  return goabi::computeCallLayout(ArgLayouts, StackArgsSize, StackResultsEnd,
                                  CLI.DAG.getDataLayout(), Config);
}
