//===- GoObjDebug.cpp - Go object debug metadata handler -----------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "GoObjDebug.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/CodeGen/AsmPrinter.h"
#include "llvm/CodeGen/DebugHandlerBase.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/CodeGen/TargetRegisterInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DebugInfoMetadata.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/MCSymbol.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/LEB128.h"
#include "llvm/Support/Path.h"
#include <algorithm>
#include <cstdint>
#include <iterator>
#include <limits>
#include <string>
#include <utility>
#include <vector>

using namespace llvm;

namespace {

class GoObjDebugHandler final : public DebugHandlerBase {
  AsmPrinter &Asm;
  Module *M = nullptr;
  const MCSymbol *CurrentFunction = nullptr;
  DebugLoc PreviousLocation;
  MapVector<const DISubprogram *, const MCSymbol *> SubprogramSymbols;
  DenseMap<std::pair<const DILocation *, const DISubprogram *>, uint64_t>
      InlineSiteIDs;
  uint64_t NextInlineSiteID = 1;
  DenseMap<const DILocalVariable *, MCContext::GoObjDebugVariable> VariableInfo;

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
      const DISubprogram *Callee = Loc->getScope()->getSubprogram();
      if (!Callee)
        report_fatal_error("GoObj inline location has no callee subprogram");
      MCContext::GoObjDebugInlineFrame Frame;
      Frame.Callee = getSubprogramSymbol(Callee);
      Frame.CallFile = filePath(Call->getFile());
      Frame.CallLine = Call->getLine();
      // A callsite DILocation describes the caller position, but not the
      // inlinee. LLVM may therefore share it between different callees. Keep
      // the complete edge identity instead of rewriting otherwise valid debug
      // locations into distinct nodes in a late machine pass.
      auto [It, Inserted] =
          InlineSiteIDs.try_emplace(std::make_pair(Call, Callee), 0);
      if (Inserted)
        It->second = NextInlineSiteID++;
      Frame.SiteID = It->second;
      Reversed.push_back(std::move(Frame));
      Loc = Call;
    }
    return std::vector<MCContext::GoObjDebugInlineFrame>(Reversed.rbegin(),
                                                         Reversed.rend());
  }

  static void uleb(std::vector<uint8_t> &Bytes, uint64_t Value) {
    uint8_t Buffer[10];
    unsigned Size = encodeULEB128(Value, Buffer);
    Bytes.insert(Bytes.end(), Buffer, Buffer + Size);
  }

  static void sleb(std::vector<uint8_t> &Bytes, int64_t Value) {
    uint8_t Buffer[10];
    unsigned Size = encodeSLEB128(Value, Buffer);
    Bytes.insert(Bytes.end(), Buffer, Buffer + Size);
  }

  std::optional<unsigned> variableIndex(const DILocalVariable *Var) const {
    auto It = VariableInfo.find(Var);
    if (It == VariableInfo.end())
      return std::nullopt;
    const auto *Info =
        Asm.OutContext.getGoObjFunctionDebugInfo(CurrentFunction);
    if (!Info)
      return std::nullopt;
    const auto &Key = It->second;
    for (auto [Index, Candidate] : enumerate(Info->Variables))
      if (Candidate.Name == Key.Name && Candidate.TypeName == Key.TypeName &&
          Candidate.File == Key.File && Candidate.DeclLine == Key.DeclLine &&
          Candidate.ArgNo == Key.ArgNo && Candidate.DictIndex == Key.DictIndex)
        return Index;
    return std::nullopt;
  }

  // Only serialize operations whose operands and location semantics we support.
  // LLVM-only operations must never escape into Go's DWARF carriers.
  static bool appendExpression(std::vector<uint8_t> &Bytes,
                               ArrayRef<uint64_t> Ops) {
    DIExpressionCursor Cursor(Ops);
    while (auto Op = Cursor.take()) {
      switch (Op->getOp()) {
      case dwarf::DW_OP_plus_uconst:
      case dwarf::DW_OP_constu:
        Bytes.push_back(Op->getOp());
        uleb(Bytes, Op->getArg(0));
        break;
      case dwarf::DW_OP_consts:
        Bytes.push_back(Op->getOp());
        sleb(Bytes, Op->getArg(0));
        break;
      case dwarf::DW_OP_deref:
      case dwarf::DW_OP_plus:
      case dwarf::DW_OP_minus:
      case dwarf::DW_OP_stack_value:
        Bytes.push_back(Op->getOp());
        break;
      default:
        return false;
      }
    }
    return true;
  }

  static uint64_t lastOpcode(ArrayRef<uint64_t> Ops) {
    uint64_t Last = 0;
    DIExpressionCursor Cursor(Ops);
    while (auto Op = Cursor.take())
      Last = Op->getOp();
    return Last;
  }

  std::vector<uint8_t> debugValueExpression(const MachineInstr &MI,
                                            const MachineFunction &MF) {
    if (!MI.isDebugValue() || MI.getNumDebugOperands() != 1 ||
        MI.isUndefDebugValue())
      return {};
    auto SingleExpr =
        DIExpression::convertToNonVariadicExpression(MI.getDebugExpression());
    if (!SingleExpr)
      return {};
    const DIExpression *Expr = *SingleExpr;
    ArrayRef<uint64_t> Ops = Expr->getElements();
    if (Expr->isFragment())
      Ops = Ops.drop_back(3);
    const MachineOperand &MO = MI.getDebugOperand(0);
    std::vector<uint8_t> Bytes;
    if (MO.isReg()) {
      const auto *TRI = MF.getSubtarget().getRegisterInfo();
      int Reg = TRI->getDwarfRegNum(MO.getReg(), false);
      if (Reg < 0)
        return {};
      if (Ops.empty() && !MI.isIndirectDebugValue()) {
        if (Reg < 32)
          Bytes.push_back(dwarf::DW_OP_reg0 + Reg);
        else {
          Bytes.push_back(dwarf::DW_OP_regx);
          uleb(Bytes, Reg);
        }
        return Bytes;
      }
      if (Reg < 32)
        Bytes.push_back(dwarf::DW_OP_breg0 + Reg);
      else {
        Bytes.push_back(dwarf::DW_OP_bregx);
        uleb(Bytes, Reg);
      }
      sleb(Bytes, MI.isIndirectDebugValue() ? MI.getDebugOffset().getImm() : 0);
      // A final dereference describes the value at the computed address.
      // DWARF memory locations already have that dereference implicitly.
      bool IsMemory = MI.isIndirectDebugValue();
      if (!IsMemory && !Ops.empty() && lastOpcode(Ops) == dwarf::DW_OP_deref) {
        Ops = Ops.drop_back();
        IsMemory = true;
      }
      if (!appendExpression(Bytes, Ops))
        return {};
      if (!IsMemory &&
          (Ops.empty() || lastOpcode(Ops) != dwarf::DW_OP_stack_value))
        Bytes.push_back(dwarf::DW_OP_stack_value);
    } else if (MO.isImm() && !MI.isIndirectDebugValue()) {
      Bytes.push_back(dwarf::DW_OP_consts);
      sleb(Bytes, MO.getImm());
      if (!appendExpression(Bytes, Ops))
        return {};
      if (Ops.empty() || lastOpcode(Ops) != dwarf::DW_OP_stack_value)
        Bytes.push_back(dwarf::DW_OP_stack_value);
    }
    return Bytes;
  }

  struct Piece {
    const DIExpression *Expr;
    std::vector<uint8_t> Bytes;
  };

  static std::vector<uint8_t> joinPieces(SmallVector<Piece, 4> Pieces) {
    if (Pieces.size() == 1 && !Pieces[0].Expr->isFragment())
      return std::move(Pieces[0].Bytes);
    if (any_of(Pieces, [](const Piece &P) { return !P.Expr->isFragment(); }))
      return {};
    llvm::sort(Pieces, [](const Piece &L, const Piece &R) {
      return L.Expr->getFragmentInfo()->OffsetInBits <
             R.Expr->getFragmentInfo()->OffsetInBits;
    });
    std::vector<uint8_t> Bytes;
    uint64_t End = 0;
    bool HasLocation = false;
    for (const Piece &P : Pieces) {
      auto Fragment = *P.Expr->getFragmentInfo();
      if (Fragment.OffsetInBits < End || Fragment.OffsetInBits % 8 ||
          Fragment.SizeInBits % 8)
        return {};
      if (Fragment.OffsetInBits != End) {
        Bytes.push_back(dwarf::DW_OP_piece);
        uleb(Bytes, (Fragment.OffsetInBits - End) / 8);
      }
      HasLocation |= !P.Bytes.empty();
      Bytes.insert(Bytes.end(), P.Bytes.begin(), P.Bytes.end());
      Bytes.push_back(dwarf::DW_OP_piece);
      uleb(Bytes, Fragment.SizeInBits / 8);
      End = Fragment.OffsetInBits + Fragment.SizeInBits;
    }
    return HasLocation ? Bytes : std::vector<uint8_t>();
  }

  void collectVariableLocations(const MachineFunction &MF) {
    if (!CurrentFunction || Asm.OutContext.getGoObjDwarfVersion() == 0)
      return;
    auto Add = [&](unsigned Index, const MCSymbol *Begin, const MCSymbol *End,
                   std::vector<uint8_t> Bytes) {
      if (Begin && End && Begin != End && !Bytes.empty())
        Asm.OutContext.addGoObjVariableLocation(CurrentFunction, Index,
                                                {Begin, End, std::move(Bytes)});
    };

    // Stack slots in the MF side table use final frame offsets. For the two
    // supported Go targets these are relative to the entry CFA, including the
    // return-address bias on X86. CFA addressing also survives the prologue
    // and epilogue, unlike an unqualified SP-relative expression.
    DenseMap<unsigned, SmallVector<Piece, 4>> StackVariables;
    DenseMap<unsigned, LexicalScope *> StackScopes;
    const auto &MFI = MF.getFrameInfo();
    const auto *TRI = MF.getSubtarget().getRegisterInfo();
    auto Arch = Asm.OutContext.getTargetTriple().getArch();
    if ((Arch == Triple::x86_64 || Arch == Triple::aarch64) &&
        !MFI.hasVarSizedObjects() && !TRI->hasStackRealignment(MF)) {
      for (const auto &VI : MF.getVariableDbgInfo()) {
        if (!VI.Var || !VI.inStackSlot() || VI.Loc->getInlinedAt())
          continue;
        auto Index = variableIndex(VI.Var);
        LexicalScope *Scope = LScopes.findLexicalScope(VI.Loc);
        if (!Scope)
          continue;
        int FI = VI.getStackSlot();
        if (!Index || MFI.isDeadObjectIndex(FI) || MFI.getStackID(FI) != 0)
          continue;
        std::vector<uint8_t> Bytes = {dwarf::DW_OP_fbreg};
        sleb(Bytes, MFI.getObjectOffset(FI));
        ArrayRef<uint64_t> Ops = VI.Expr->getElements();
        if (VI.Expr->isFragment())
          Ops = Ops.drop_back(3);
        if (!appendExpression(Bytes, Ops))
          Bytes.clear();
        StackVariables[*Index].push_back({VI.Expr, std::move(Bytes)});
        StackScopes[*Index] = Scope;
      }
    }
    for (auto &[Index, Pieces] : StackVariables)
      for (const auto &Range : StackScopes[Index]->getRanges())
        Add(Index, getLabelBeforeInsn(Range.first),
            getLabelAfterInsn(Range.second), joinPieces(Pieces));

    // Reuse LLVM's final-machine history: it closes ranges on register
    // clobbers, undef values, overlapping fragments, and CFG boundaries.
    for (const auto &[Entity, Entries] : DbgValues) {
      if (Entity.second)
        continue;
      auto Index = variableIndex(cast<DILocalVariable>(Entity.first));
      if (!Index || StackVariables.contains(*Index))
        continue;
      SmallVector<const DbgValueHistoryMap::Entry *, 4> Active;
      for (auto [N, Entry] : enumerate(Entries)) {
        erase_if(Active, [&](const auto *E) { return E->getEndIndex() <= N; });
        if (Entry.isDbgValue() && !Entry.getInstr()->isUndefDebugValue())
          Active.push_back(&Entry);
        auto Label = [&](const auto &E) {
          return E.isClobber() ? getLabelAfterInsn(E.getInstr())
                               : getLabelBeforeInsn(E.getInstr());
        };
        const MCSymbol *Begin = Label(Entry);
        const MCSymbol *End = N + 1 == Entries.size() ? Asm.getFunctionEnd()
                                                      : Label(Entries[N + 1]);
        SmallVector<Piece, 4> Pieces;
        for (const auto *E : Active)
          Pieces.push_back({E->getInstr()->getDebugExpression(),
                            debugValueExpression(*E->getInstr(), MF)});
        Add(*Index, Begin, End, joinPieces(std::move(Pieces)));
      }
    }
  }

public:
  explicit GoObjDebugHandler(AsmPrinter &Asm)
      : DebugHandlerBase(&Asm), Asm(Asm) {}

  void beginModule(Module *Module) override {
    DebugHandlerBase::beginModule(Module);
    M = Module;

    unsigned DwarfVersion = 0;
    StringRef PackageName;
    if (const NamedMDNode *Config = M->getNamedMetadata("goobj.debug.config")) {
      if (Config->getNumOperands() != 1)
        report_fatal_error("expected one !goobj.debug.config entry");
      const MDNode *Entry = Config->getOperand(0);
      if (Entry->getNumOperands() == 0 ||
          !isa_and_nonnull<MDString>(Entry->getOperand(0)) ||
          cast<MDString>(Entry->getOperand(0))->getString() != "pcln-v1")
        report_fatal_error("unsupported GoObj debug configuration");
      if (Entry->getNumOperands() != 1) {
        if ((Entry->getNumOperands() != 3 && Entry->getNumOperands() != 4) ||
            !isa_and_nonnull<MDString>(Entry->getOperand(1)) ||
            cast<MDString>(Entry->getOperand(1))->getString() != "dwarf-v1" ||
            !isa_and_nonnull<MDString>(Entry->getOperand(2)))
          report_fatal_error("unsupported GoObj DWARF configuration");
        StringRef Version = cast<MDString>(Entry->getOperand(2))->getString();
        if (Version == "dwarf4")
          DwarfVersion = 4;
        else if (Version == "dwarf5")
          DwarfVersion = 5;
        else
          report_fatal_error("unsupported GoObj DWARF version");
        if (Entry->getNumOperands() == 4) {
          const auto *Name = dyn_cast_or_null<MDString>(Entry->getOperand(3));
          if (!Name)
            report_fatal_error("invalid GoObj DWARF package name");
          PackageName = Name->getString();
        }
      }
    }
    MCContext &Context = Asm.OutStreamer->getContext();
    Context.setGoObjDwarfVersion(DwarfVersion);
    Context.setGoObjDwarfPackageName(PackageName);

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

    // The frontend list also describes abstract inline functions, but it is
    // not an inventory of the functions remaining after optimization. Cloning
    // and specialization can add definitions with their own DISubprograms.
    // Bind those to the actual function symbol: a clone's linkage name can
    // still name its source function.
    for (const Function &F : *M) {
      if (F.isDeclarationForLinker())
        continue;
      const DISubprogram *SP = F.getSubprogram();
      if (!SP || !SP->getUnit() ||
          SP->getUnit()->getEmissionKind() == DICompileUnit::NoDebug)
        continue;
      SubprogramSymbols.try_emplace(SP, Asm.getSymbol(&F));
    }

    DenseMap<const DISubprogram *, std::vector<MCContext::GoObjDebugVariable>>
        Variables;
    if (const NamedMDNode *Vars = M->getNamedMetadata("goobj.debug.vars")) {
      if (DwarfVersion == 0)
        report_fatal_error(
            "GoObj debug variables require a DWARF configuration");
      for (const MDNode *Entry : Vars->operands()) {
        if (Entry->getNumOperands() != 3 && Entry->getNumOperands() != 4)
          report_fatal_error("expected !goobj.debug.vars entries to have three "
                             "or four operands");
        const auto *Var =
            dyn_cast_or_null<DILocalVariable>(Entry->getOperand(0));
        const auto *TypeName = dyn_cast_or_null<MDString>(Entry->getOperand(1));
        const auto *FlagsMD =
            dyn_cast_or_null<ConstantAsMetadata>(Entry->getOperand(2));
        const auto *Flags =
            FlagsMD ? dyn_cast<ConstantInt>(FlagsMD->getValue()) : nullptr;
        const ConstantInt *DictIndex = nullptr;
        if (Entry->getNumOperands() == 4) {
          const auto *DictIndexMD =
              dyn_cast_or_null<ConstantAsMetadata>(Entry->getOperand(3));
          DictIndex = DictIndexMD
                          ? dyn_cast<ConstantInt>(DictIndexMD->getValue())
                          : nullptr;
        }
        if (!Var || !TypeName || !Flags ||
            (Entry->getNumOperands() == 4 && !DictIndex))
          report_fatal_error("invalid !goobj.debug.vars entry");
        const DISubprogram *SP = Var->getScope()->getSubprogram();
        if (!SP || !SubprogramSymbols.contains(SP))
          report_fatal_error(
              "GoObj debug variable has no exact subprogram symbol");

        MCContext::GoObjDebugVariable Result;
        Result.Name = Var->getName().str();
        Result.TypeName = TypeName->getString().str();
        Result.File = filePath(Var->getFile());
        Result.DeclLine = Var->getLine();
        Result.ArgNo = Var->getArg();
        if (DictIndex) {
          uint64_t Value = DictIndex->getZExtValue();
          if (Value > std::numeric_limits<uint16_t>::max())
            report_fatal_error(
                "GoObj debug variable dictionary index overflow");
          Result.DictIndex = static_cast<uint16_t>(Value);
        }
        Result.IsReturn = (Flags->getZExtValue() & 1) != 0;
        VariableInfo.try_emplace(Var, Result);
        Variables[SP].push_back(std::move(Result));
      }
    }

    if (DwarfVersion != 0) {
      // Multiple inline instances can describe the same emitted function.
      // Merge their variable manifests instead of overwriting one another in
      // pointer-hash order, which loses variables and makes DWARF unstable.
      MapVector<const MCSymbol *,
                std::pair<const DISubprogram *,
                          std::vector<MCContext::GoObjDebugVariable>>>
          SymbolDebugInfo;
      for (const auto &[SP, Symbol] : SubprogramSymbols) {
        auto &Info = SymbolDebugInfo[Symbol];
        if (!Info.first)
          Info.first = SP;
        auto &Vars = Variables[SP];
        Info.second.insert(Info.second.end(),
                           std::make_move_iterator(Vars.begin()),
                           std::make_move_iterator(Vars.end()));
      }
      for (auto &[Symbol, Info] : SymbolDebugInfo) {
        const DISubprogram *SP = Info.first;
        auto &SPVariables = Info.second;
        llvm::sort(SPVariables, [](const auto &LHS, const auto &RHS) {
          if ((LHS.ArgNo == 0) != (RHS.ArgNo == 0))
            return LHS.ArgNo != 0;
          if (LHS.ArgNo != RHS.ArgNo)
            return LHS.ArgNo < RHS.ArgNo;
          if (LHS.DictIndex != RHS.DictIndex)
            return LHS.DictIndex < RHS.DictIndex;
          if (LHS.DeclLine != RHS.DeclLine)
            return LHS.DeclLine < RHS.DeclLine;
          if (LHS.Name != RHS.Name)
            return LHS.Name < RHS.Name;
          if (LHS.TypeName != RHS.TypeName)
            return LHS.TypeName < RHS.TypeName;
          if (LHS.File != RHS.File)
            return LHS.File < RHS.File;
          return LHS.IsReturn > RHS.IsReturn;
        });
        SPVariables.erase(llvm::unique(SPVariables,
                                       [](const auto &LHS, const auto &RHS) {
                                         return LHS.Name == RHS.Name &&
                                                LHS.TypeName == RHS.TypeName &&
                                                LHS.File == RHS.File &&
                                                LHS.DeclLine == RHS.DeclLine &&
                                                LHS.ArgNo == RHS.ArgNo &&
                                                LHS.DictIndex == RHS.DictIndex;
                                       }),
                          SPVariables.end());
        Asm.OutStreamer->getContext().setGoObjSubprogramDebugInfo(
            Symbol, SP->getName(), filePath(SP->getFile()), SP->getLine(),
            std::move(SPVariables));
      }
    }

    if (DwarfVersion != 0) {
      SmallVector<MCContext::GoObjDebugGlobal, 8> Globals;
      for (const GlobalVariable &GV : M->globals()) {
        SmallVector<DIGlobalVariableExpression *, 1> Expressions;
        GV.getDebugInfo(Expressions);
        for (const DIGlobalVariableExpression *Expression : Expressions) {
          const DIGlobalVariable *Variable = Expression->getVariable();
          if (!Variable)
            report_fatal_error("GoObj global debug attachment has no variable");
          MCContext::GoObjDebugGlobal Result;
          Result.Symbol = Asm.getSymbol(&GV);
          Result.Name = Variable->getName().str();
          Globals.push_back(std::move(Result));
        }
      }
      llvm::sort(Globals, [](const auto &LHS, const auto &RHS) {
        if (LHS.Symbol->getName() != RHS.Symbol->getName())
          return LHS.Symbol->getName() < RHS.Symbol->getName();
        return LHS.Name < RHS.Name;
      });
      Globals.erase(llvm::unique(Globals,
                                 [](const auto &LHS, const auto &RHS) {
                                   return LHS.Symbol == RHS.Symbol &&
                                          LHS.Name == RHS.Name;
                                 }),
                    Globals.end());
      for (MCContext::GoObjDebugGlobal &Global : Globals)
        Context.addGoObjDebugGlobal(std::move(Global));
    }
  }

  void endModule() override {}

  void beginFunctionImpl(const MachineFunction *MF) override {
    PreviousLocation = DebugLoc();
    CurrentFunction = nullptr;
    const DISubprogram *SP = MF->getFunction().getSubprogram();
    if (!SP || SP->getUnit()->getEmissionKind() == DICompileUnit::NoDebug)
      return;

    CurrentFunction = Asm.getSymbol(&MF->getFunction());
    Asm.OutStreamer->getContext().setGoObjFunctionSource(
        CurrentFunction, filePath(SP->getFile()), SP->getLine());
  }

  void endFunctionImpl(const MachineFunction *MF) override {
    collectVariableLocations(*MF);
    CurrentFunction = nullptr;
    PreviousLocation = DebugLoc();
  }

  void beginInstruction(const MachineInstr *MI) override {
    DebugHandlerBase::beginInstruction(MI);
    if (!CurrentFunction || MI->isMetaInstruction() ||
        MI->getFlag(MachineInstr::FrameSetup))
      return;

    const DebugLoc &DL = MI->getDebugLoc();
    // A merged location can have no source line while still describing an
    // exact inline scope. Record it so the previous instruction's inline
    // frames do not leak into this instruction's traceback.
    if (!DL)
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
    // Go trace consumers require a source line. For an ambiguous merged
    // location, use the containing function's declaration rather than a line
    // inherited from an unrelated inline frame. Keep the original scope.
    if (Location.Line == 0)
      if (const DISubprogram *SP = DL->getScope()->getSubprogram()) {
        Location.File = filePath(SP->getFile());
        Location.Line = SP->getLine();
      }
    Location.InlineFrames = getInlineFrames(DL.get());
    if (IsAnchor) {
      auto It = std::next(MI->getIterator());
      while (It != MI->getParent()->end() && It->isMetaInstruction())
        ++It;
      if (It == MI->getParent()->end() || !It->getDebugLoc())
        report_fatal_error(
            "GoObj inline anchor has no following source instruction");
      Location.AnchorChildFrames = getInlineFrames(It->getDebugLoc().get());
      if (Location.AnchorChildFrames.size() <=
              Location.InlineFrames.size() ||
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
      // Scheduling can move a non-faulting instruction from a deeper inline
      // frame ahead of that frame's preserved debug label. The anchor still
      // belongs to the first direct child after the parent prefix; descendants
      // get their own anchors at their final label or instruction boundary.
      Location.AnchorChildFrames.resize(Location.InlineFrames.size() + 1);
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
