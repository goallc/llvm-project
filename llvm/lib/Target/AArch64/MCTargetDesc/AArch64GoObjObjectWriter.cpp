//===-- AArch64GoObjObjectWriter.cpp - AArch64 Go object writer ----------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "MCTargetDesc/AArch64FixupKinds.h"
#include "MCTargetDesc/AArch64MCAsmInfo.h"
#include "MCTargetDesc/AArch64MCTargetDesc.h"
#include "llvm/ADT/Twine.h"
#include "llvm/BinaryFormat/GoObj.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCGoObjObjectWriter.h"
#include "llvm/MC/MCObjectWriter.h"
#include "llvm/MC/MCValue.h"
#include <memory>

using namespace llvm;

namespace {

class AArch64GoObjObjectWriter : public MCGoObjObjectTargetWriter {
public:
  unsigned getRelocType(const MCValue &Target,
                        const MCFixup &Fixup) const override;
  uint8_t getRelocSize(const MCFixup &Fixup) const override;
  int64_t getRelocAddend(const MCValue &Target,
                         const MCFixup &Fixup) const override;
  bool mergeRelocations(GoObjRelocationEntry &Previous,
                        const GoObjRelocationEntry &Current) const override;
};

} // end anonymous namespace

uint8_t AArch64GoObjObjectWriter::getRelocSize(const MCFixup &Fixup) const {
  switch (unsigned(Fixup.getKind())) {
  case FK_Data_1:
    return 1;
  case FK_Data_2:
    return 2;
  case FK_Data_4:
    return 4;
  case FK_Data_8:
    return 8;
  default:
    return 4;
  }
}

int64_t AArch64GoObjObjectWriter::getRelocAddend(const MCValue &Target,
                                                 const MCFixup &Fixup) const {
  return Target.getConstant() - (Fixup.isPCRel() ? 4 : 0);
}

unsigned AArch64GoObjObjectWriter::getRelocType(const MCValue &Target,
                                                const MCFixup &Fixup) const {
  switch (static_cast<AArch64::Specifier>(Target.getSpecifier())) {
  case AArch64::S_None:
  case AArch64::S_CALL:
  case AArch64::S_ABS_PAGE:
  case AArch64::S_LO12:
    break;
  case AArch64::S_GOT:
  case AArch64::S_GOT_PAGE:
  case AArch64::S_GOT_LO12:
  case AArch64::S_GOTPCREL:
    return GoObj::R_ARM64_GOTPCREL;
  case AArch64::S_GOTTPREL:
  case AArch64::S_GOTTPREL_PAGE:
  case AArch64::S_GOTTPREL_LO12_NC:
    return GoObj::R_ARM64_TLS_IE;
  case AArch64::S_TPREL_G2:
  case AArch64::S_TPREL_G1:
  case AArch64::S_TPREL_G1_NC:
  case AArch64::S_TPREL_G0:
  case AArch64::S_TPREL_G0_NC:
  case AArch64::S_TPREL_HI12:
  case AArch64::S_TPREL_LO12:
  case AArch64::S_TPREL_LO12_NC:
    return GoObj::R_ARM64_TLS_LE;
  default:
    reportError(Fixup.getLoc(),
                "unsupported AArch64 goobj relocation specifier");
    return GoObj::R_ADDR;
  }

  switch (unsigned(Fixup.getKind())) {
  case FK_Data_1:
  case FK_Data_2:
  case FK_Data_4:
  case FK_Data_8:
    return Fixup.isPCRel() ? GoObj::R_PCREL : GoObj::R_ADDR;
  case AArch64::fixup_aarch64_pcrel_call26:
  case AArch64::fixup_aarch64_pcrel_branch26:
    return GoObj::R_CALLARM64;
  case AArch64::fixup_aarch64_pcrel_adr_imm21:
  case AArch64::fixup_aarch64_pcrel_adrp_imm21:
  case AArch64::fixup_aarch64_add_imm12:
  case AArch64::fixup_aarch64_ldst_imm12_scale1:
  case AArch64::fixup_aarch64_ldst_imm12_scale2:
  case AArch64::fixup_aarch64_ldst_imm12_scale4:
  case AArch64::fixup_aarch64_ldst_imm12_scale8:
  case AArch64::fixup_aarch64_ldst_imm12_scale16:
    return GoObj::R_ARM64_PCREL;
  default:
    reportError(Fixup.getLoc(), "unsupported AArch64 goobj relocation type");
    return GoObj::R_ADDR;
  }
}

bool AArch64GoObjObjectWriter::mergeRelocations(
    GoObjRelocationEntry &Previous,
    const GoObjRelocationEntry &Current) const {
  // getRelocAddend subtracts one instruction from the PC-relative ADRP,
  // while the low-12 fixup is not itself PC-relative. Thus matching source
  // expressions differ internally by the original four-byte relocation size.
  if (Previous.Section != Current.Section ||
      Previous.Offset + 4 != Current.Offset ||
      Previous.Symbol != Current.Symbol ||
      Previous.Subtractor != Current.Subtractor ||
      Previous.Addend + Previous.Size != Current.Addend ||
      Previous.FixupKind != AArch64::fixup_aarch64_pcrel_adrp_imm21)
    return false;

  unsigned Type;
  switch (Current.FixupKind) {
  case AArch64::fixup_aarch64_add_imm12:
    Type = GoObj::R_ADDRARM64;
    break;
  case AArch64::fixup_aarch64_ldst_imm12_scale1:
    Type = GoObj::R_ARM64_PCREL_LDST8;
    break;
  case AArch64::fixup_aarch64_ldst_imm12_scale2:
    Type = GoObj::R_ARM64_PCREL_LDST16;
    break;
  case AArch64::fixup_aarch64_ldst_imm12_scale4:
    Type = GoObj::R_ARM64_PCREL_LDST32;
    break;
  case AArch64::fixup_aarch64_ldst_imm12_scale8:
    Type = GoObj::R_ARM64_PCREL_LDST64;
    break;
  default:
    return false;
  }

  Previous.Type = Type;
  Previous.Size = 8;
  // getGoObjRelocAddend adds the composite relocation size back for a
  // PC-relative entry. Normalize the pair so its serialized addend remains
  // the expression's source addend, just like the two individual fixups.
  Previous.Addend = Current.Addend - Previous.Size;
  return true;
}

std::unique_ptr<MCObjectTargetWriter> llvm::createAArch64GoObjObjectWriter() {
  return std::make_unique<AArch64GoObjObjectWriter>();
}
