//===- lib/MC/MCGoObjStreamer.cpp - Go object output ---------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/MC/MCGoObjStreamer.h"
#include "llvm/MC/MCAssembler.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCSymbol.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/SMLoc.h"

using namespace llvm;

bool MCGoObjStreamer::emitSymbolAttribute(MCSymbol *Symbol,
                                          MCSymbolAttr Attribute) {
  switch (Attribute) {
  case MCSA_Global:
  case MCSA_NoDeadStrip:
    getAssembler().registerSymbol(*Symbol);
    return true;
  default:
    return false;
  }
}

void MCGoObjStreamer::emitCommonSymbol(MCSymbol *Symbol, uint64_t Size,
                                       Align ByteAlignment) {
  if (Symbol->declareCommon(Size, ByteAlignment))
    getContext().reportError(SMLoc(), "goobj common symbol changed binding");
  getAssembler().registerSymbol(*Symbol);
}

MCStreamer *llvm::createGoObjStreamer(MCContext &Context,
                                      std::unique_ptr<MCAsmBackend> &&MAB,
                                      std::unique_ptr<MCObjectWriter> &&OW,
                                      std::unique_ptr<MCCodeEmitter> &&CE) {
  return new MCGoObjStreamer(Context, std::move(MAB), std::move(OW),
                             std::move(CE));
}
