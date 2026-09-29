//===- GoObjAsmParser.cpp - Go object assembly parser ---------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/MC/MCParser/MCAsmParserExtension.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCParser/AsmLexer.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/SectionKind.h"

using namespace llvm;

namespace {

class GoObjAsmParser : public MCAsmParserExtension {
  template <bool (GoObjAsmParser::*HandlerMethod)(StringRef, SMLoc)>
  void addDirectiveHandler(StringRef Directive) {
    MCAsmParser::ExtensionDirectiveHandler Handler =
        std::make_pair(this, HandleDirective<GoObjAsmParser, HandlerMethod>);
    getParser().addDirectiveHandler(Directive, Handler);
  }

  bool parseSectionName(StringRef &SectionName) {
    SMLoc FirstLoc = getLexer().getLoc();
    unsigned Size = 0;

    if (getLexer().is(AsmToken::String)) {
      SectionName = getTok().getIdentifier();
      Lex();
      return false;
    }

    while (!getParser().hasPendingError()) {
      SMLoc PrevLoc = getLexer().getLoc();
      if (getLexer().is(AsmToken::Comma) ||
          getLexer().is(AsmToken::EndOfStatement))
        break;

      unsigned CurSize;
      if (getLexer().is(AsmToken::String)) {
        CurSize = getTok().getIdentifier().size() + 2;
        Lex();
      } else if (getLexer().is(AsmToken::Identifier)) {
        CurSize = getTok().getIdentifier().size();
        Lex();
      } else {
        CurSize = getTok().getString().size();
        Lex();
      }
      Size += CurSize;
      SectionName = StringRef(FirstLoc.getPointer(), Size);

      if (PrevLoc.getPointer() + CurSize != getTok().getLoc().getPointer())
        break;
    }

    return Size == 0;
  }

  SectionKind getSectionKind(StringRef Section) {
    return StringSwitch<SectionKind>(Section)
        .Case(".text", SectionKind::getText())
        .Case(".data", SectionKind::getData())
        .Case(".noptrdata", SectionKind::getData())
        .Case(".bss", SectionKind::getBSS())
        .Case(".noptrbss", SectionKind::getBSS())
        .Case(".rodata", SectionKind::getReadOnly())
        .Case(".tdata", SectionKind::getThreadData())
        .Case(".tbss", SectionKind::getThreadBSS())
        .Default(Section.starts_with(".debug_") ? SectionKind::getMetadata()
                                                : SectionKind::getData());
  }

  bool switchSection(StringRef Section, SectionKind Kind) {
    if (parseEOL())
      return true;
    getStreamer().switchSection(getContext().getGoObjSection(Section, Kind));
    return false;
  }

  bool parseSectionDirectiveText(StringRef, SMLoc) {
    return switchSection(".text", SectionKind::getText());
  }

  bool parseSectionDirectiveData(StringRef, SMLoc) {
    return switchSection(".data", SectionKind::getData());
  }

  bool parseSectionDirectiveBSS(StringRef, SMLoc) {
    return switchSection(".bss", SectionKind::getBSS());
  }

  bool parseSectionDirectiveRoData(StringRef, SMLoc) {
    return switchSection(".rodata", SectionKind::getReadOnly());
  }

  bool parseDirectiveSection(StringRef, SMLoc) {
    StringRef SectionName;
    if (parseSectionName(SectionName))
      return TokError("expected section name");

    while (getLexer().isNot(AsmToken::EndOfStatement))
      Lex();
    Lex();

    getStreamer().switchSection(
        getContext().getGoObjSection(SectionName, getSectionKind(SectionName)));
    return false;
  }

  bool parseDirectiveCgo(StringRef, SMLoc) {
    std::string Pragmas;
    if (getParser().parseEscapedString(Pragmas))
      return true;
    if (Pragmas.empty())
      return TokError("expected non-empty cgo pragmas");
    if (parseEOL())
      return true;
    if (!getContext().getGoObjCgoPragmas().empty())
      return TokError("duplicate .goobj.cgo directive");

    getContext().setGoObjCgoPragmas(Pragmas);
    return false;
  }

  bool parseSymbol(const MCSymbol *&Sym) {
    StringRef Name;
    if (getParser().parseIdentifier(Name))
      return TokError("expected GoObj symbol");
    Sym = getContext().getOrCreateSymbol(Name);
    return false;
  }

  bool parseInteger(int64_t &Value) {
    return getParser().parseToken(AsmToken::Comma) ||
           getParser().parseAbsoluteExpression(Value);
  }

  bool parseDirectiveAssembly(StringRef, SMLoc) {
    if (parseEOL())
      return true;
    getContext().setGoObjFromAssembly();
    return false;
  }

  bool parseDirectiveAsmFunction(StringRef, SMLoc) {
    const MCSymbol *Sym;
    int64_t Args, Locals, ID, Flags, Line;
    if (parseSymbol(Sym) || parseInteger(Args) || parseInteger(Locals) ||
        parseInteger(ID) || parseInteger(Flags) || parseInteger(Line) ||
        parseEOL())
      return true;
    if (Args < INT32_MIN || Args > UINT32_MAX || Locals < 0 ||
        Locals > INT32_MAX || ID < 0 || ID > UINT8_MAX || Flags < 0 ||
        Flags > UINT8_MAX || Line < 0 || Line > INT32_MAX)
      return TokError("invalid GoObj assembly function metadata");
    auto &Info = getContext().getOrCreateGoObjAsmFunction(Sym);
    Info.Args = Args;
    Info.Locals = Locals;
    Info.FuncID = ID;
    Info.FuncFlag = Flags;
    Info.StartLine = Line;
    return false;
  }

  bool parseDirectiveAsmPC(StringRef, SMLoc) {
    const MCSymbol *Sym, *Label;
    int64_t Kind, Value;
    std::string File;
    if (parseSymbol(Sym) || getParser().parseToken(AsmToken::Comma) ||
        parseSymbol(Label) || parseInteger(Kind) || parseInteger(Value))
      return true;
    if (Kind < -5 || Kind == -4 || Kind == -1 || Kind > 65535 ||
        Value < INT32_MIN || Value > INT32_MAX)
      return TokError("invalid GoObj assembly PC event");
    if (Kind == -2 && (getParser().parseToken(AsmToken::Comma) ||
                       getParser().parseEscapedString(File)))
      return true;
    if (parseEOL())
      return true;
    if (Kind == -5) {
      getContext().addGoObjSymbolIndirectCallLabel(Sym, Label);
      return false;
    }
    getContext().getOrCreateGoObjAsmFunction(Sym).Events.push_back(
        {Label, static_cast<int32_t>(Kind), static_cast<int32_t>(Value),
         std::move(File)});
    return false;
  }

  bool parseDirectiveAsmFuncdata(StringRef, SMLoc) {
    const MCSymbol *Sym, *Target;
    int64_t Index;
    if (parseSymbol(Sym) || parseInteger(Index) ||
        getParser().parseToken(AsmToken::Comma) || parseSymbol(Target) ||
        parseEOL())
      return true;
    if (Index < 0 || Index > 255)
      return TokError("invalid GoObj assembly FUNCDATA index");
    auto &Data = getContext().getOrCreateGoObjAsmFunction(Sym).Funcdata;
    if (Data.size() <= static_cast<size_t>(Index))
      Data.resize(Index + 1);
    if (Data[Index])
      return TokError("duplicate GoObj assembly FUNCDATA index");
    Data[Index] = Target;
    return false;
  }

public:
  GoObjAsmParser() = default;

  void Initialize(MCAsmParser &Parser) override {
    MCAsmParserExtension::Initialize(Parser);

    addDirectiveHandler<&GoObjAsmParser::parseSectionDirectiveText>(".text");
    addDirectiveHandler<&GoObjAsmParser::parseSectionDirectiveData>(".data");
    addDirectiveHandler<&GoObjAsmParser::parseSectionDirectiveBSS>(".bss");
    addDirectiveHandler<&GoObjAsmParser::parseSectionDirectiveRoData>(
        ".rodata");
    addDirectiveHandler<&GoObjAsmParser::parseDirectiveSection>(".section");
    addDirectiveHandler<&GoObjAsmParser::parseDirectiveCgo>(".goobj.cgo");
    addDirectiveHandler<&GoObjAsmParser::parseDirectiveAssembly>(
        ".goobj.assembly");
    addDirectiveHandler<&GoObjAsmParser::parseDirectiveAsmFunction>(
        ".goobj.asmfunc");
    addDirectiveHandler<&GoObjAsmParser::parseDirectiveAsmPC>(".goobj.asmpc");
    addDirectiveHandler<&GoObjAsmParser::parseDirectiveAsmFuncdata>(
        ".goobj.asmfuncdata");
  }
};

} // namespace

MCAsmParserExtension *llvm::createGoObjAsmParser() {
  return new GoObjAsmParser;
}
