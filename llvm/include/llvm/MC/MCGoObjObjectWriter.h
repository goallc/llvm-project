//===-- MCGoObjObjectWriter.h - Go object writer interface ------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_MC_MCGOOBJOBJECTWRITER_H
#define LLVM_MC_MCGOOBJOBJECTWRITER_H

#include "llvm/BinaryFormat/GoObj.h"
#include "llvm/MC/MCObjectWriter.h"
#include <array>
#include <memory>
#include <string>
#include <vector>

namespace llvm {

class MCFixup;
class MCSection;
class MCValue;
class raw_pwrite_stream;

struct MCGoObjObjectWriterConfig {
  GoObj::SourceKind SourceKind = GoObj::SourceKind::Assembly;
  GoObj::DefinedSymbolBlock DefaultDefinedSymbolBlock =
      GoObj::DefinedSymbolBlock::Symdef;
  std::string Version = "go1.26.3";
  std::vector<std::string> Experiments = {
      "regabiwrappers", "regabiargs", "dwarf5", "greenteagc",
      "randomizedheapbase64"};
  std::string PackagePath;
  std::array<uint8_t, GoObj::FingerprintSize> Fingerprint = {};
  bool IsShared = false;
  bool IsStd = false;
  bool IsUnlinkable = false;
};

class MCGoObjObjectTargetWriter : public MCObjectTargetWriter {
protected:
  MCGoObjObjectTargetWriter() = default;

public:
  ~MCGoObjObjectTargetWriter() override = default;

  Triple::ObjectFormatType getFormat() const override { return Triple::GoObj; }

  static bool classof(const MCObjectTargetWriter *W) {
    return W->getFormat() == Triple::GoObj;
  }

  virtual unsigned getRelocType(const MCValue &Target,
                                const MCFixup &Fixup) const = 0;
};

struct GoObjRelocationEntry {
  const MCSymbol *Symbol;
  const MCSymbol *Subtractor;
  const MCSection *Section;
  uint64_t Offset;
  int64_t Addend;
  unsigned Type;
  uint8_t Size;
  bool IsPCRel;
};

class GoObjObjectWriter final : public MCObjectWriter {
  std::unique_ptr<MCGoObjObjectTargetWriter> TargetObjectWriter;
  raw_pwrite_stream &OS;
  MCGoObjObjectWriterConfig Config;

  std::vector<GoObjRelocationEntry> Relocations;

public:
  GoObjObjectWriter(std::unique_ptr<MCGoObjObjectTargetWriter> MOTW,
                    raw_pwrite_stream &OS,
                    MCGoObjObjectWriterConfig Config = {});
  ~GoObjObjectWriter() override;

  void setAssembler(MCAssembler *Asm) override;
  void reset() override;

  bool isSymbolRefDifferenceFullyResolvedImpl(const MCSymbol &SymA,
                                              const MCFragment &FB, bool InSet,
                                              bool IsPCRel) const override;

  void recordRelocation(const MCFragment &F, const MCFixup &Fixup,
                        MCValue Target, uint64_t &FixedValue) override;

  uint64_t writeObject() override;
};

std::unique_ptr<MCObjectWriter>
createGoObjObjectWriter(std::unique_ptr<MCGoObjObjectTargetWriter> MOTW,
                        raw_pwrite_stream &OS);

std::unique_ptr<MCObjectWriter>
createGoObjObjectWriter(std::unique_ptr<MCGoObjObjectTargetWriter> MOTW,
                        raw_pwrite_stream &OS,
                        MCGoObjObjectWriterConfig Config);

} // end namespace llvm

#endif // LLVM_MC_MCGOOBJOBJECTWRITER_H
