//===- GoObjDebug.cpp - Go object debug metadata handler -----------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "GoObjDebug.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/CodeGen/AsmPrinter.h"
#include "llvm/CodeGen/AsmPrinterHandler.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DebugInfoMetadata.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/MCSymbol.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/Path.h"
#include <algorithm>
#include <cstdint>
#include <iterator>
#include <string>
#include <utility>
#include <vector>

using namespace llvm;

namespace {

class GoObjDebugHandler final : public AsmPrinterHandler {
  AsmPrinter &Asm;
  Module *M = nullptr;
  const MCSymbol *CurrentFunction = nullptr;
  DebugLoc PreviousLocation;
  DenseMap<const DISubprogram *, const MCSymbol *> SubprogramSymbols;
  DenseMap<const DILocation *, uint64_t> InlineSiteIDs;
  uint64_t NextInlineSiteID = 1;

  static std::string filePath(const DIFile *File) {
    if (!File)
      return "llvm-ir";
    SmallString<256> Path(File->getFilename());
    if (!sys::path::is_absolute(Path) && !File->getDirectory().empty()) {
      Path = File->getDirectory();
      sys::path::append(Path, File->getFilename());
    }
    return Path.empty() ? std::string("llvm-ir") : Path.str().str();
  }

  const MCSymbol *getSubprogramSymbol(const DISubprogram *SP) {
    if (auto It = SubprogramSymbols.find(SP); It != SubprogramSymbols.end())
      return It->second;
    StringRef LinkageName = SP->getLinkageName();
    if (LinkageName.empty())
      LinkageName = SP->getName();
    if (const auto *GV =
            dyn_cast_or_null<GlobalValue>(M->getNamedValue(LinkageName)))
      return Asm.getSymbol(GV);
    report_fatal_error(Twine("GoObj inline subprogram has no exact symbol: ") +
                       LinkageName);
  }

  std::vector<MCContext::GoObjDebugInlineFrame>
  getInlineFrames(const DILocation *Loc) {
    SmallVector<MCContext::GoObjDebugInlineFrame, 4> Reversed;
    while (const DILocation *Call = Loc->getInlinedAt()) {
      MCContext::GoObjDebugInlineFrame Frame;
      Frame.Callee = getSubprogramSymbol(Loc->getScope()->getSubprogram());
      Frame.CallFile = filePath(Call->getFile());
      Frame.CallLine = Call->getLine();
      auto [It, Inserted] = InlineSiteIDs.try_emplace(Call, 0);
      if (Inserted)
        It->second = NextInlineSiteID++;
      Frame.SiteID = It->second;
      Reversed.push_back(std::move(Frame));
      Loc = Call;
    }
    return std::vector<MCContext::GoObjDebugInlineFrame>(Reversed.rbegin(),
                                                         Reversed.rend());
  }

public:
  explicit GoObjDebugHandler(AsmPrinter &Asm) : Asm(Asm) {}

  void beginModule(Module *Module) override {
    M = Module;
    if (const NamedMDNode *Funcs = M->getNamedMetadata("goobj.debug.funcs")) {
      for (const MDNode *Entry : Funcs->operands()) {
        if (Entry->getNumOperands() != 2)
          report_fatal_error(
              "expected !goobj.debug.funcs entries to have two operands");
        const auto *SP = dyn_cast_or_null<DISubprogram>(Entry->getOperand(0));
        const auto *CAM =
            dyn_cast_or_null<ConstantAsMetadata>(Entry->getOperand(1));
        const auto *GV = CAM ? dyn_cast<GlobalValue>(CAM->getValue()) : nullptr;
        if (!SP || !GV)
          report_fatal_error("invalid !goobj.debug.funcs entry");
        if (!SubprogramSymbols.try_emplace(SP, Asm.getSymbol(GV)).second)
          report_fatal_error("duplicate !goobj.debug.funcs subprogram");
      }
    }
  }

  void endModule() override {}

  void beginFunction(const MachineFunction *MF) override {
    PreviousLocation = DebugLoc();
    CurrentFunction = nullptr;
    const DISubprogram *SP = MF->getFunction().getSubprogram();
    if (!SP || SP->getUnit()->getEmissionKind() == DICompileUnit::NoDebug)
      return;

    CurrentFunction = Asm.getSymbol(&MF->getFunction());
    Asm.OutStreamer->getContext().setGoObjFunctionSource(
        CurrentFunction, filePath(SP->getFile()), SP->getLine());
  }

  void endFunction(const MachineFunction *) override {
    CurrentFunction = nullptr;
    PreviousLocation = DebugLoc();
  }

  void beginInstruction(const MachineInstr *MI) override {
    if (!CurrentFunction || MI->isMetaInstruction() ||
        MI->getFlag(MachineInstr::FrameSetup))
      return;

    const DebugLoc &DL = MI->getDebugLoc();
    if (!DL || DL.getLine() == 0)
      return;

    MCContext &Context = Asm.OutStreamer->getContext();
    const MCSymbol *Label = MI->getPreInstrSymbol();
    bool IsAnchor = Label && Context.isGoObjInlineAnchor(Label);
    if (!IsAnchor && DL.isSameSourceLocation(PreviousLocation))
      return;

    if (!IsAnchor) {
      MCSymbol *LocationLabel = Context.createTempSymbol("goobj_debug");
      Asm.OutStreamer->emitLabel(LocationLabel);
      Label = LocationLabel;
    }

    MCContext::GoObjDebugLocation Location;
    Location.Label = Label;
    Location.File = filePath(DL->getFile());
    Location.Line = DL.getLine();
    Location.InlineFrames = getInlineFrames(DL.get());
    if (IsAnchor) {
      auto It = std::next(MI->getIterator());
      while (It != MI->getParent()->end() && It->isMetaInstruction())
        ++It;
      if (It == MI->getParent()->end() || !It->getDebugLoc())
        report_fatal_error(
            "GoObj inline anchor has no following source instruction");
      Location.AnchorChildFrames = getInlineFrames(It->getDebugLoc().get());
      if (Location.AnchorChildFrames.size() !=
              Location.InlineFrames.size() + 1 ||
          !std::equal(Location.InlineFrames.begin(),
                      Location.InlineFrames.end(),
                      Location.AnchorChildFrames.begin(),
                      [](const auto &LHS, const auto &RHS) {
                        return LHS.Callee == RHS.Callee &&
                               LHS.CallFile == RHS.CallFile &&
                               LHS.CallLine == RHS.CallLine &&
                               LHS.SiteID == RHS.SiteID;
                      }))
        report_fatal_error(
            "GoObj inline anchor does not precede its child frame");
    }
    Context.addGoObjDebugLocation(CurrentFunction, std::move(Location));
    PreviousLocation = DL;
  }
};

} // end anonymous namespace

std::unique_ptr<AsmPrinterHandler>
llvm::createGoObjDebugHandler(AsmPrinter &Asm) {
  return std::make_unique<GoObjDebugHandler>(Asm);
}
