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
  }
};

} // namespace

MCAsmParserExtension *llvm::createGoObjAsmParser() {
  return new GoObjAsmParser;
}
