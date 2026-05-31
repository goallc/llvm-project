//===-- X86GoObjObjectWriter.cpp - X86 Go object writer -------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "MCTargetDesc/X86FixupKinds.h"
#include "MCTargetDesc/X86MCAsmInfo.h"
#include "MCTargetDesc/X86MCTargetDesc.h"
#include "llvm/BinaryFormat/GoObj.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCGoObjObjectWriter.h"
#include "llvm/MC/MCObjectWriter.h"
#include "llvm/MC/MCValue.h"
#include <memory>

using namespace llvm;

namespace {

class X86GoObjObjectWriter : public MCGoObjObjectTargetWriter {
public:
  X86GoObjObjectWriter(bool) {}
  ~X86GoObjObjectWriter() override = default;

  unsigned getRelocType(const MCValue &Target,
                        const MCFixup &Fixup) const override;
};

} // end anonymous namespace

unsigned X86GoObjObjectWriter::getRelocType(const MCValue &Target,
                                            const MCFixup &Fixup) const {
  switch (Target.getSpecifier()) {
  case X86::S_None:
    break;
  case X86::S_GOTPCREL:
  case X86::S_GOTPCREL_NORELAX:
    return GoObj::R_GOTPCREL;
  case X86::S_GOTTPOFF:
  case X86::S_INDNTPOFF:
    return GoObj::R_TLS_IE;
  case X86::S_NTPOFF:
  case X86::S_TPOFF:
    return GoObj::R_TLS_LE;
  default:
    reportError(Fixup.getLoc(), "unsupported X86 goobj relocation specifier");
    return GoObj::R_ADDR;
  }

  switch (unsigned(Fixup.getKind())) {
  case FK_Data_1:
  case FK_Data_2:
  case FK_Data_4:
  case FK_Data_8:
  case X86::reloc_signed_4byte:
  case X86::reloc_signed_4byte_relax:
    return Fixup.isPCRel() ? GoObj::R_PCREL : GoObj::R_ADDR;
  case X86::reloc_riprel_4byte:
  case X86::reloc_riprel_4byte_movq_load:
  case X86::reloc_riprel_4byte_movq_load_rex2:
  case X86::reloc_riprel_4byte_relax:
  case X86::reloc_riprel_4byte_relax_rex:
  case X86::reloc_riprel_4byte_relax_rex2:
  case X86::reloc_riprel_4byte_relax_evex:
    return GoObj::R_PCREL;
  case X86::reloc_branch_4byte_pcrel:
    return GoObj::R_CALL;
  default:
    reportError(Fixup.getLoc(), "unsupported X86 goobj relocation type");
    return GoObj::R_ADDR;
  }
}

std::unique_ptr<MCObjectTargetWriter>
llvm::createX86GoObjObjectWriter(bool Is64Bit) {
  return std::make_unique<X86GoObjObjectWriter>(Is64Bit);
}
