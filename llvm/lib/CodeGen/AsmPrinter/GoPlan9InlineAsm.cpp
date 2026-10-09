//===- GoPlan9InlineAsm.cpp - Deferred Go assembler bridge
//------------------===//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include "GoPlan9InlineAsm.h"
#include "llvm-c/GoPlan9.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/CodeGen/AsmPrinter.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/InlineAsm.h"
#include "llvm/MC/MCAssembler.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCGoObjObjectWriter.h"
#include "llvm/MC/MCObjectStreamer.h"
#include "llvm/Support/JSON.h"
#include <map>

using namespace llvm;

// The embedding Go driver registers a callback on the codegen thread. The
// callback returns JSON allocated by it; Release owns deallocation. A bitcode
// consumer without a registered assembler fails explicitly, never parses Plan 9
// with a target's GNU parser.
static thread_local LLVMGoPlan9AssembleCallback Assemble;
static thread_local LLVMGoPlan9ReleaseCallback Release;
extern "C" LLVM_C_ABI void
LLVMGoSetPlan9Assembler(LLVMGoPlan9AssembleCallback A,
                        LLVMGoPlan9ReleaseCallback R) {
  Assemble = A;
  Release = R;
}

namespace {
struct Event {
  int64_t PC, Kind, Value;
  std::string File;
};
struct AssemblyReloc {
  int64_t Offset, Size, Type, Addend, Target;
};
struct Funcdata {
  int64_t Index, Target;
};
bool fromJSON(const json::Value &V, Event &E, json::Path P) {
  json::ObjectMapper O(V, P);
  return O && O.map("pc", E.PC) && O.map("kind", E.Kind) &&
         O.map("value", E.Value) && O.map("file", E.File);
}
bool fromJSON(const json::Value &V, AssemblyReloc &R, json::Path P) {
  json::ObjectMapper O(V, P);
  return O && O.map("offset", R.Offset) && O.map("size", R.Size) &&
         O.map("type", R.Type) && O.map("addend", R.Addend) &&
         O.map("target", R.Target);
}
bool fromJSON(const json::Value &V, Funcdata &F, json::Path P) {
  json::ObjectMapper O(V, P);
  return O && O.map("index", F.Index) && O.map("target", F.Target);
}
} // namespace

bool llvm::emitGoPlan9InlineAsm(AsmPrinter &AP, const MachineInstr &MI,
                                const Function &F, MCSymbol *Fn, MCContext &Ctx,
                                MCStreamer &Out) {
  if (!F.hasFnAttribute("go-plan9-context"))
    return false;
  auto Fail = [&](const Twine &Message) {
    Ctx.reportError(SMLoc(), "Plan 9 inline assembly: " + Message);
    return true;
  };
  if (!F.hasFnAttribute(Attribute::Naked) ||
      !Ctx.getTargetTriple().isOSBinFormatGoObj())
    return Fail("requires a naked function and GoObj output");
  if (!Assemble || !Release)
    return Fail("no Go assembler registered by the codegen driver");
  auto *Assembler = Out.getAssemblerPtr();
  if (!Assembler)
    return Fail("requires object output");
  auto *Writer = static_cast<GoObjObjectWriter *>(&Assembler->getWriter());

  SmallVector<const MCSymbol *> Refs;
  for (unsigned I = InlineAsm::MIOp_FirstOperand; I < MI.getNumOperands();
       ++I) {
    const auto &MO = MI.getOperand(I);
    if (!MO.isImm())
      continue;
    InlineAsm::Flag Flag(MO.getImm());
    if (!Flag.isClobberKind()) {
      if (Flag.getNumOperandRegisters() != 1 ||
          !MI.getOperand(I + 1).isGlobal() ||
          MI.getOperand(I + 1).getOffset() != 0)
        return Fail("symbol operand is not an unmodified LLVM global");
      Refs.push_back(AP.getSymbol(MI.getOperand(I + 1).getGlobal()));
    }
    I += Flag.getNumOperandRegisters();
  }
  std::string Request;
  raw_string_ostream RequestOS(Request);
  RequestOS << json::Value(json::Object{
      {"body", MI.getOperand(0).getSymbolName()},
      {"context", F.getFnAttribute("go-plan9-context").getValueAsString()}});
  const char *Result = Assemble(Request.data(), Request.size());
  if (!Result)
    return Fail("assembler returned no result");
  auto Parsed = json::parse(Result);
  Release(Result);
  if (!Parsed)
    return Fail(toString(Parsed.takeError()));
  const auto *Object = Parsed->getAsObject();
  if (!Object)
    return Fail("invalid assembler response");
  if (auto Error = Object->getString("error"))
    return Fail(*Error);
  json::Path::Root Root;
  json::ObjectMapper M(*Parsed, Root);
  std::string Hex;
  int64_t Args, Locals, ID, Flags, Line;
  std::vector<Event> Events;
  std::vector<AssemblyReloc> Relocs;
  std::vector<Funcdata> Data;
  if (!M.map("code", Hex) || !M.map("args", Args) || !M.map("locals", Locals) ||
      !M.map("id", ID) || !M.map("flags", Flags) || !M.map("line", Line) ||
      !M.map("events", Events) || !M.map("relocs", Relocs) ||
      !M.map("funcdata", Data))
    return Fail("incomplete assembler response");
  if (Hex.size() % 2 ||
      !llvm::all_of(Hex, [](char C) { return isHexDigit(C); }))
    return Fail("invalid encoded bytes");
  std::string Code = fromHex(Hex);
  if (Args < INT32_MIN || Args > UINT32_MAX || Locals < INT32_MIN ||
      Locals > UINT32_MAX || ID < 0 || ID > UINT8_MAX || Flags < 0 ||
      Flags > UINT8_MAX || Line < 0 || Line > INT32_MAX)
    return Fail("invalid function information");
  auto ValidTarget = [&](int64_t T) {
    return T >= 0 && uint64_t(T) < Refs.size();
  };
  std::map<uint64_t, MCSymbol *> Labels;
  for (const auto &E : Events) {
    if (E.PC < 0 || uint64_t(E.PC) > Code.size() || E.Kind < -3 ||
        E.Kind == -1 || E.Kind > 65535 || E.Value < INT32_MIN ||
        E.Value > INT32_MAX)
      return Fail("invalid PC event");
    Labels[E.PC] = nullptr;
  }
  for (const auto &R : Relocs) {
    if (R.Offset < 0 || R.Size < 0 || R.Size > UINT8_MAX ||
        uint64_t(R.Offset) + R.Size > Code.size() || R.Type < 0 ||
        R.Type > UINT16_MAX || (R.Target != -1 && !ValidTarget(R.Target)))
      return Fail("invalid relocation");
  }
  for (const auto &D : Data)
    if (D.Index < 0 || D.Index > 255 || !ValidTarget(D.Target))
      return Fail("invalid FUNCDATA");

  size_t Position = 0;
  for (auto &[PC, Label] : Labels) {
    Out.emitBytes(StringRef(Code).slice(Position, PC));
    Label = Ctx.createTempSymbol("go_plan9_pc");
    Out.emitLabel(Label);
    Position = PC;
  }
  Out.emitBytes(StringRef(Code).drop_front(Position));
  auto &Info = Ctx.getOrCreateGoObjAsmFunction(Fn);
  Info.Args = Args;
  Info.Locals = Locals;
  Info.FuncID = ID;
  Info.FuncFlag = Flags;
  Info.StartLine = Line;
  for (const auto &E : Events)
    Info.Events.push_back(
        {Labels[E.PC], int32_t(E.Kind), int32_t(E.Value), E.File});
  for (const auto &D : Data) {
    Info.Funcdata.resize(std::max(Info.Funcdata.size(), size_t(D.Index + 1)));
    Info.Funcdata[D.Index] = Refs[D.Target];
  }
  for (const auto &R : Relocs)
    Writer->recordAssemblyRelocation(Fn,
                                     R.Target == -1 ? nullptr : Refs[R.Target],
                                     R.Offset, R.Size, R.Type, R.Addend);
  return true;
}
