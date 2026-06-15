//===- lib/MC/GoObjObjectWriter.cpp - Go object writer -------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/MC/MCGoObjObjectWriter.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/BinaryFormat/GoObj.h"
#include "llvm/MC/MCAsmBackend.h"
#include "llvm/MC/MCAssembler.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCSection.h"
#include "llvm/MC/MCValue.h"
#include "llvm/Support/Alignment.h"
#include "llvm/Support/EndianStream.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/TargetParser/Triple.h"
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <limits>
#include <optional>
#include <string>
#include <vector>

using namespace llvm;

namespace {

struct GoObjSymbol {
  struct Relocation {
    uint32_t Offset = 0;
    uint8_t Size = 0;
    uint16_t Type = 0;
    int64_t Addend = 0;
    uint32_t PkgIdx = GoObj::PkgIdxInvalid;
    uint32_t SymIdx = 0;
  };

  struct Auxiliary {
    uint8_t Type = 0;
    uint32_t TargetSymbolIndex = 0;
  };

  std::string Name;
  const MCSymbol *Symbol = nullptr;
  const MCSection *Section = nullptr;
  uint64_t SectionBegin = 0;
  uint64_t SectionEnd = 0;
  GoObj::DefinedSymbolBlock DefinedBlock = GoObj::DefinedSymbolBlock::Symdef;
  uint8_t Type = GoObj::Sxxx;
  uint16_t ABI = 0;
  uint64_t Size = 0;
  uint32_t Align = 0;
  SmallString<0> Data;
  std::vector<Relocation> Relocations;
  std::vector<Auxiliary> Auxiliaries;
};

struct GoObjSymRef {
  uint32_t PkgIdx = GoObj::PkgIdxInvalid;
  uint32_t SymIdx = 0;
};

uint32_t checkedUint32(uint64_t Value, const Twine &What) {
  if (Value > std::numeric_limits<uint32_t>::max())
    report_fatal_error(What + " exceeds GoObj uint32 limit");
  return static_cast<uint32_t>(Value);
}

uint16_t checkedUint16(uint64_t Value, const Twine &What) {
  if (Value > std::numeric_limits<uint16_t>::max())
    report_fatal_error(What + " exceeds GoObj uint16 limit");
  return static_cast<uint16_t>(Value);
}

uint32_t getGoObjPCQuantum(const Triple &TT) {
  switch (TT.getArch()) {
  case Triple::x86:
  case Triple::x86_64:
    return 1;
  default:
    return 4;
  }
}

uint8_t getGoObjSymbolType(const MCSection *Section) {
  if (!Section)
    return GoObj::SBSS;

  if (Section->isText())
    return GoObj::STEXT;
  if (Section->isBssSection())
    return GoObj::SBSS;

  StringRef Name = Section->getName();
  if (Name.starts_with(".rodata") || Name.starts_with("__TEXT,__const"))
    return GoObj::SRODATA;
  if (Name.starts_with(".debug_") || Name.starts_with("__DWARF,"))
    return GoObj::SDWARFCONST;

  return GoObj::SDATA;
}

void appendSectionContents(SmallVectorImpl<char> &Contents,
                           const MCAssembler &Asm, const MCSection &Section) {
  raw_svector_ostream ContentsOS(Contents);
  Asm.writeSectionData(ContentsOS, &Section);
}

void addDefinedSymbol(std::vector<GoObjSymbol> &Symbols,
                      const MCSymbol *MCSym, const MCSection *Section,
                      uint64_t SectionBegin, uint64_t SectionEnd,
                      GoObj::DefinedSymbolBlock DefinedBlock,
                      StringRef Name, uint8_t Type, uint16_t ABI,
                      uint64_t Size, ArrayRef<char> Data) {
  GoObjSymbol Sym;
  Sym.Name = Name.str();
  Sym.Symbol = MCSym;
  Sym.Section = Section;
  Sym.SectionBegin = SectionBegin;
  Sym.SectionEnd = SectionEnd;
  Sym.DefinedBlock = DefinedBlock;
  Sym.Type = Type;
  Sym.ABI = ABI;
  Sym.Size = Size;
  Sym.Data.append(Data.begin(), Data.end());
  Symbols.push_back(std::move(Sym));
}

void appendUvarint(SmallVectorImpl<char> &Data, uint64_t Value) {
  while (Value >= 0x80) {
    Data.push_back(static_cast<char>((Value & 0x7f) | 0x80));
    Value >>= 7;
  }
  Data.push_back(static_cast<char>(Value));
}

void appendVarint(SmallVectorImpl<char> &Data, int64_t Value) {
  uint64_t UValue = static_cast<uint64_t>(Value) << 1;
  if (Value < 0)
    UValue = ~UValue;
  appendUvarint(Data, UValue);
}

uint64_t getPCDeltaUnits(uint64_t Delta, uint32_t PCQuantum) {
  return (Delta + PCQuantum - 1) / PCQuantum;
}

SmallString<0> makeConstantPCTab(int32_t Value, uint64_t CodeSize,
                                 uint32_t PCQuantum) {
  SmallString<0> Data;
  appendVarint(Data, static_cast<int64_t>(Value) + 1);
  appendUvarint(Data, getPCDeltaUnits(CodeSize, PCQuantum));
  appendUvarint(Data, 0);
  return Data;
}

SmallString<0> makePCSPTab(ArrayRef<std::pair<uint64_t, int32_t>> Entries,
                           uint64_t CodeSize, uint32_t PCQuantum) {
  SmallString<0> Data;
  int32_t OldValue = -1;
  uint64_t PC = 0;
  bool Started = false;

  auto Emit = [&](uint64_t EventPC, int32_t Value) {
    if (EventPC > CodeSize)
      report_fatal_error("GoObj pcsp event exceeds function size");
    if (Started)
      appendUvarint(Data, getPCDeltaUnits(EventPC - PC, PCQuantum));
    appendVarint(Data, static_cast<int64_t>(Value) - OldValue);
    OldValue = Value;
    PC = EventPC;
    Started = true;
  };

  Emit(0, 0);
  for (const auto &[EventPC, Value] : Entries) {
    if (Value == OldValue)
      continue;
    Emit(EventPC, Value);
  }

  appendUvarint(Data, getPCDeltaUnits(CodeSize - PC, PCQuantum));
  appendUvarint(Data, 0);
  return Data;
}

SmallString<0> makeFuncInfoData(uint32_t StackSize) {
  SmallString<0> Data;
  raw_svector_ostream OS(Data);
  support::endian::Writer W(OS, llvm::endianness::little);
  W.write<uint32_t>(0);         // Args.
  W.write<uint32_t>(StackSize); // Locals.
  W.write<uint8_t>(0);          // FuncIDNormal.
  W.write<uint8_t>(0);          // No FuncFlag bits.
  W.write<uint8_t>(0);
  W.write<uint8_t>(0);
  W.write<uint32_t>(1); // StartLine.
  W.write<uint32_t>(1); // File count.
  W.write<uint32_t>(0); // File index in the object file table.
  W.write<uint32_t>(0); // Inline tree count.
  return Data;
}

uint32_t addAuxCarrierSymbol(std::vector<GoObjSymbol> &Symbols,
                             GoObj::DefinedSymbolBlock Block,
                             ArrayRef<char> Data) {
  GoObjSymbol Sym;
  Sym.DefinedBlock = Block;
  Sym.ABI = GoObj::SymABIstatic;
  Sym.Type = GoObj::SRODATA;
  Sym.Align = 1;
  Sym.Size = Data.size();
  Sym.Data.append(Data.begin(), Data.end());
  uint32_t Index = checkedUint32(Symbols.size(), "symbol count");
  Symbols.push_back(std::move(Sym));
  return Index;
}

int64_t getGoObjRelocAddend(const GoObjRelocationEntry &Reloc) {
  int64_t Addend = Reloc.Addend;
  if (Reloc.IsPCRel)
    Addend += Reloc.Size;
  return Addend;
}

uint32_t getGoObjFlags(const MCGoObjObjectWriterConfig &Config) {
  uint32_t Flags = 0;
  if (Config.IsShared)
    Flags |= GoObj::ObjFlagShared;
  if (Config.SourceKind == GoObj::SourceKind::Assembly)
    Flags |= GoObj::ObjFlagFromAssembly;
  if (Config.IsUnlinkable ||
      (Config.SourceKind == GoObj::SourceKind::Compiler &&
       Config.PackagePath.empty()))
    Flags |= GoObj::ObjFlagUnlinkable;
  if (Config.IsStd)
    Flags |= GoObj::ObjFlagStd;
  return Flags;
}

StringRef getGoOS(const Triple &TT) {
  switch (TT.getOS()) {
  case Triple::Linux:
    return "linux";
  case Triple::Darwin:
  case Triple::MacOSX:
    return "darwin";
  case Triple::FreeBSD:
    return "freebsd";
  case Triple::NetBSD:
    return "netbsd";
  case Triple::OpenBSD:
    return "openbsd";
  case Triple::Win32:
    return "windows";
  default:
    report_fatal_error("unsupported GoObj target OS");
  }
}

StringRef getGoArch(const Triple &TT) {
  switch (TT.getArch()) {
  case Triple::x86:
    return "386";
  case Triple::x86_64:
    return "amd64";
  case Triple::arm:
  case Triple::armeb:
    return "arm";
  case Triple::aarch64:
  case Triple::aarch64_be:
    return "arm64";
  case Triple::ppc64:
    return "ppc64";
  case Triple::ppc64le:
    return "ppc64le";
  case Triple::riscv64:
    return "riscv64";
  default:
    report_fatal_error("unsupported GoObj target architecture");
  }
}

void writeGoObjectTextHeader(raw_ostream &OS, const Triple &TT,
                             const MCGoObjObjectWriterConfig &Config) {
  OS << "go object " << getGoOS(TT) << ' ' << getGoArch(TT) << ' '
     << Config.Version;

  switch (TT.getArch()) {
  case Triple::x86:
    OS << " GO386=sse2";
    break;
  case Triple::x86_64:
    OS << " GOAMD64=v1";
    break;
  case Triple::arm:
  case Triple::armeb:
    OS << " GOARM=7";
    break;
  case Triple::aarch64:
  case Triple::aarch64_be:
    OS << " GOARM64=v8.0";
    break;
  case Triple::ppc64:
  case Triple::ppc64le:
    OS << " GOPPC64=power8";
    break;
  case Triple::riscv64:
    OS << " GORISCV64=rva20u64";
    break;
  default:
    break;
  }

  OS << " X:";
  for (size_t I = 0, E = Config.Experiments.size(); I != E; ++I) {
    if (I != 0)
      OS << ',';
    OS << Config.Experiments[I];
  }
  OS << '\n';

  if (Config.SourceKind == GoObj::SourceKind::Compiler)
    OS << '\n';
  OS << "!\n";
}

} // end anonymous namespace

GoObjObjectWriter::GoObjObjectWriter(
    std::unique_ptr<MCGoObjObjectTargetWriter> MOTW, raw_pwrite_stream &OS,
    MCGoObjObjectWriterConfig Config)
    : TargetObjectWriter(std::move(MOTW)), OS(OS), Config(std::move(Config)) {
  if (this->Config.SourceKind == GoObj::SourceKind::Assembly)
    this->Config.DefaultDefinedSymbolBlock =
        GoObj::DefinedSymbolBlock::Nonpkgdef;
}

GoObjObjectWriter::~GoObjObjectWriter() = default;

void GoObjObjectWriter::setAssembler(MCAssembler *Asm) {
  MCObjectWriter::setAssembler(Asm);
  TargetObjectWriter->setAssembler(Asm);
}

void GoObjObjectWriter::reset() {
  MCObjectWriter::reset();
  Relocations.clear();
}

bool GoObjObjectWriter::isSymbolRefDifferenceFullyResolvedImpl(
    const MCSymbol &SymA, const MCFragment &FB, bool InSet,
    bool IsPCRel) const {
  if (IsPCRel && !SymA.isTemporary())
    return false;
  return MCObjectWriter::isSymbolRefDifferenceFullyResolvedImpl(
      SymA, FB, InSet, IsPCRel);
}

void GoObjObjectWriter::recordRelocation(const MCFragment &F,
                                         const MCFixup &Fixup, MCValue Target,
                                         uint64_t &FixedValue) {
  const MCFixupKindInfo &Info =
      Asm->getBackend().getFixupKindInfo(Fixup.getKind());
  assert(Info.TargetSize % 8 == 0 && "Target size must be byte-aligned");
  Relocations.push_back(
      {Target.getAddSym(), Target.getSubSym(), F.getParent(),
       Asm->getFragmentOffset(F) + Fixup.getOffset(), Target.getConstant(),
       TargetObjectWriter->getRelocType(Target, Fixup),
       static_cast<uint8_t>(Info.TargetSize / 8), Fixup.isPCRel()});
  FixedValue = 0;
}

uint64_t GoObjObjectWriter::writeObject() {
  const uint64_t StartOffset = OS.tell();

  std::vector<GoObjSymbol> Symbols;

  for (const MCSymbol &Symbol : Asm->symbols()) {
    if (!Symbol.isCommon())
      continue;
    GoObjSymbol GoSym;
    GoSym.Name = Symbol.getName().str();
    GoSym.Symbol = &Symbol;
    GoSym.DefinedBlock = Config.DefaultDefinedSymbolBlock;
    GoSym.ABI = GoObj::SymABIstatic;
    GoSym.Type = GoObj::SBSS;
    GoSym.Size = Symbol.getCommonSize();
    if (MaybeAlign Alignment = Symbol.getCommonAlignment())
      GoSym.Align = checkedUint32(Alignment->value(), "common alignment");
    Symbols.push_back(std::move(GoSym));
  }

  for (const MCSection &Section : *Asm) {
    uint64_t SectionSize = Asm->getSectionAddressSize(Section);
    if (SectionSize == 0)
      continue;

    SmallString<0> Contents;
    if (!Section.isBssSection())
      appendSectionContents(Contents, *Asm, Section);

    struct SectionSymbol {
      const MCSymbol *Symbol = nullptr;
      uint64_t Offset = 0;
    };
    std::vector<SectionSymbol> SectionSymbols;
    for (const MCSymbol &Symbol : Asm->symbols()) {
      if (Symbol.isTemporary() || !Symbol.isInSection() ||
          &Symbol.getSection() != &Section)
        continue;
      uint64_t Offset = Asm->getSymbolOffset(Symbol);
      if (Offset > SectionSize)
        report_fatal_error("GoObj symbol offset is outside its section");
      SectionSymbols.push_back({&Symbol, Offset});
    }

    std::stable_sort(SectionSymbols.begin(), SectionSymbols.end(),
                     [](const SectionSymbol &LHS, const SectionSymbol &RHS) {
                       return LHS.Offset < RHS.Offset;
                     });

    auto AddSectionSymbol = [&](const MCSymbol *MCSym, StringRef Name,
                                uint64_t Begin, uint64_t End) {
      uint64_t Size = End - Begin;
      ArrayRef<char> Data;
      if (!Section.isBssSection()) {
        if (End > Contents.size())
          report_fatal_error("GoObj section data is smaller than its layout");
        Data = ArrayRef<char>(Contents.data() + Begin, Size);
      }
      uint8_t Type = getGoObjSymbolType(&Section);
      uint16_t ABI = MCSym ? Asm->getContext()
                                 .getGoObjSymbolABI(MCSym)
                                 .value_or(GoObj::SymABI0)
                           : GoObj::SymABI0;
      addDefinedSymbol(Symbols, MCSym, &Section, Begin, End,
                       Config.DefaultDefinedSymbolBlock, Name, Type, ABI, Size,
                       Data);
    };

    if (SectionSymbols.empty()) {
      AddSectionSymbol(nullptr, Section.getName(), 0, SectionSize);
      continue;
    }

    if (SectionSymbols.front().Offset != 0)
      AddSectionSymbol(nullptr, Section.getName(), 0,
                       SectionSymbols.front().Offset);

    for (size_t I = 0, E = SectionSymbols.size(); I != E; ++I) {
      uint64_t Begin = SectionSymbols[I].Offset;
      uint64_t End = I + 1 == E ? SectionSize : SectionSymbols[I + 1].Offset;
      AddSectionSymbol(SectionSymbols[I].Symbol,
                       SectionSymbols[I].Symbol->getName(), Begin, End);
    }
  }

  bool HasGoFuncMetadata = false;
  uint32_t PCQuantum =
      getGoObjPCQuantum(Asm->getContext().getTargetTriple());
  if (Config.SourceKind == GoObj::SourceKind::Compiler) {
    for (uint32_t I = 0, E = checkedUint32(Symbols.size(), "symbol count");
         I != E; ++I) {
      if (Symbols[I].Type != GoObj::STEXT || Symbols[I].Size == 0 ||
          !Symbols[I].Symbol)
        continue;

      uint32_t StackSize = Asm->getContext()
                               .getGoObjSymbolStackSize(Symbols[I].Symbol)
                               .value_or(0);
      uint64_t CodeSize = Symbols[I].Size;

      SmallVector<std::pair<uint64_t, int32_t>, 8> PCSPEntries;
      if (const auto *Entries = Asm->getContext().getGoObjSymbolPCSPEntries(
              Symbols[I].Symbol)) {
        for (const MCContext::GoObjPCSPEntry &Entry : *Entries) {
          if (!Entry.Label->isInSection())
            continue;
          uint64_t EventPC = Asm->getSymbolOffset(*Entry.Label) -
                             Symbols[I].SectionBegin;
          if (EventPC <= CodeSize)
            PCSPEntries.push_back({EventPC, Entry.Value});
        }
        llvm::stable_sort(PCSPEntries, [](const auto &LHS, const auto &RHS) {
          return LHS.first < RHS.first;
        });
      }

      uint32_t FuncInfoSym = addAuxCarrierSymbol(
          Symbols, GoObj::DefinedSymbolBlock::Symdef,
          makeFuncInfoData(StackSize));
      uint32_t PcspSym = addAuxCarrierSymbol(
          Symbols, GoObj::DefinedSymbolBlock::Nonpkgdef,
          PCSPEntries.empty()
              ? makeConstantPCTab(static_cast<int32_t>(StackSize), CodeSize,
                                  PCQuantum)
              : makePCSPTab(PCSPEntries, CodeSize, PCQuantum));
      uint32_t PcfileSym = addAuxCarrierSymbol(
          Symbols, GoObj::DefinedSymbolBlock::Nonpkgdef,
          makeConstantPCTab(0, CodeSize, PCQuantum));
      uint32_t PclineSym = addAuxCarrierSymbol(
          Symbols, GoObj::DefinedSymbolBlock::Nonpkgdef,
          makeConstantPCTab(1, CodeSize, PCQuantum));

      Symbols[I].Auxiliaries.push_back({GoObj::AuxFuncInfo, FuncInfoSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxPcsp, PcspSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxPcfile, PcfileSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxPcline, PclineSym});
      HasGoFuncMetadata = true;
    }
  }

  DenseMap<const MCSymbol *, uint32_t> DefinedSymbolIndexes;
  for (uint32_t I = 0, E = checkedUint32(Symbols.size(), "symbol count");
       I != E; ++I) {
    if (Symbols[I].Symbol)
      DefinedSymbolIndexes[Symbols[I].Symbol] = I;
  }

  std::vector<uint32_t> SymdefSymbols;
  std::vector<uint32_t> Hashed64defSymbols;
  std::vector<uint32_t> HasheddefSymbols;
  std::vector<uint32_t> NonpkgdefSymbols;
  for (uint32_t I = 0, E = checkedUint32(Symbols.size(), "symbol count");
       I != E; ++I) {
    switch (Symbols[I].DefinedBlock) {
    case GoObj::DefinedSymbolBlock::Symdef:
      SymdefSymbols.push_back(I);
      break;
    case GoObj::DefinedSymbolBlock::Hashed64def:
      Hashed64defSymbols.push_back(I);
      break;
    case GoObj::DefinedSymbolBlock::Hasheddef:
      HasheddefSymbols.push_back(I);
      break;
    case GoObj::DefinedSymbolBlock::Nonpkgdef:
      NonpkgdefSymbols.push_back(I);
      break;
    }
  }

  std::vector<uint32_t> DefinedSymbolOrder;
  DefinedSymbolOrder.reserve(Symbols.size());
  DefinedSymbolOrder.insert(DefinedSymbolOrder.end(), SymdefSymbols.begin(),
                            SymdefSymbols.end());
  DefinedSymbolOrder.insert(DefinedSymbolOrder.end(), Hashed64defSymbols.begin(),
                            Hashed64defSymbols.end());
  DefinedSymbolOrder.insert(DefinedSymbolOrder.end(), HasheddefSymbols.begin(),
                            HasheddefSymbols.end());
  DefinedSymbolOrder.insert(DefinedSymbolOrder.end(), NonpkgdefSymbols.begin(),
                            NonpkgdefSymbols.end());

  std::vector<GoObjSymRef> DefinedSymRefs(Symbols.size());
  auto SetDefinedSymRefs = [&](ArrayRef<uint32_t> SymbolIndexes,
                               uint32_t PkgIdx) {
    for (uint32_t I = 0, E = checkedUint32(SymbolIndexes.size(),
                                           "defined symbol block size");
         I != E; ++I)
      DefinedSymRefs[SymbolIndexes[I]] = {PkgIdx, I};
  };
  SetDefinedSymRefs(SymdefSymbols, GoObj::PkgIdxSelf);
  SetDefinedSymRefs(Hashed64defSymbols, GoObj::PkgIdxHashed64);
  SetDefinedSymRefs(HasheddefSymbols, GoObj::PkgIdxHashed);
  SetDefinedSymRefs(NonpkgdefSymbols, GoObj::PkgIdxNone);

  auto FindContainingSymbol =
      [&](const MCSection *Section, uint64_t Offset) -> std::optional<uint32_t> {
    for (uint32_t I = 0, E = checkedUint32(Symbols.size(), "symbol count");
         I != E; ++I) {
      const GoObjSymbol &Sym = Symbols[I];
      if (Sym.Section != Section)
        continue;
      if (Sym.SectionBegin <= Offset && Offset < Sym.SectionEnd)
        return I;
    }
    return std::nullopt;
  };

  std::vector<GoObjSymbol> NonPkgRefs;
  StringMap<uint32_t> NonPkgRefIndexes;
  auto GetNonPkgRefSymIdx = [&](const MCSymbol *Sym) {
    StringRef Name = Sym->getName();
    if (Name.empty())
      report_fatal_error("GoObj relocation target has an empty name");

    uint16_t ABI =
        Asm->getContext().getGoObjSymbolABI(Sym).value_or(GoObj::SymABI0);
    std::string Key = (Name + "#" + Twine(ABI)).str();
    auto It = NonPkgRefIndexes.find(Key);
    if (It != NonPkgRefIndexes.end())
      return It->second;

    uint32_t SymIdx = checkedUint32(NonpkgdefSymbols.size() +
                                        NonPkgRefs.size(),
                                    "non-package reference index");
    NonPkgRefIndexes[Key] = SymIdx;

    GoObjSymbol Ref;
    Ref.Name = Name.str();
    Ref.ABI = ABI;
    NonPkgRefs.push_back(std::move(Ref));
    return SymIdx;
  };

  auto GetTargetSymRef = [&](const GoObjRelocationEntry &Reloc,
                             int64_t &Addend) {
    if (!Reloc.Symbol)
      report_fatal_error("GoObj relocation without a target symbol");

    if (auto It = DefinedSymbolIndexes.find(Reloc.Symbol);
        It != DefinedSymbolIndexes.end())
      return DefinedSymRefs[It->second];

    if (Reloc.Symbol->isInSection()) {
      uint64_t TargetOffset = Asm->getSymbolOffset(*Reloc.Symbol);
      if (std::optional<uint32_t> SymIdx =
              FindContainingSymbol(&Reloc.Symbol->getSection(), TargetOffset)) {
        Addend += static_cast<int64_t>(TargetOffset -
                                       Symbols[*SymIdx].SectionBegin);
        return DefinedSymRefs[*SymIdx];
      }
    }

    if (Reloc.Symbol->isUndefined())
      return GoObjSymRef{GoObj::PkgIdxNone,
                         GetNonPkgRefSymIdx(Reloc.Symbol)};

    report_fatal_error("unsupported GoObj relocation target symbol");
  };

  for (const GoObjRelocationEntry &Reloc : Relocations) {
    if (Reloc.Subtractor)
      report_fatal_error("GoObj relocation subtractors are not implemented");

    std::optional<uint32_t> SourceSymIdx =
        FindContainingSymbol(Reloc.Section, Reloc.Offset);
    if (!SourceSymIdx)
      report_fatal_error("GoObj relocation offset is outside all symbols");

    GoObjSymbol &Source = Symbols[*SourceSymIdx];
    uint64_t LocalOffset = Reloc.Offset - Source.SectionBegin;
    if (LocalOffset >
        static_cast<uint64_t>(std::numeric_limits<int32_t>::max()))
      report_fatal_error("GoObj relocation offset exceeds int32 range");

    int64_t Addend = getGoObjRelocAddend(Reloc);
    GoObjSymRef TargetSymRef = GetTargetSymRef(Reloc, Addend);

    Source.Relocations.push_back(
        {static_cast<uint32_t>(LocalOffset), Reloc.Size,
         checkedUint16(Reloc.Type, "relocation type"), Addend,
         TargetSymRef.PkgIdx, TargetSymRef.SymIdx});
  }

  for (GoObjSymbol &Symbol : Symbols) {
    llvm::stable_sort(Symbol.Relocations,
                      [](const GoObjSymbol::Relocation &LHS,
                         const GoObjSymbol::Relocation &RHS) {
                        return LHS.Offset < RHS.Offset;
                      });
  }

  SmallString<0> Body;
  raw_svector_ostream BodyOS(Body);
  support::endian::Writer W(BodyOS, llvm::endianness::little);
  StringMap<uint32_t> StringOffsets;

  auto CurrentOffset = [&]() {
    return checkedUint32(GoObj::HeaderSize + BodyOS.tell(), "object offset");
  };

  auto AddString = [&](StringRef S) {
    if (StringOffsets.contains(S))
      return;
    StringOffsets[S] = CurrentOffset();
    BodyOS.write(S.data(), S.size());
  };

  auto WriteStringRef = [&](StringRef S) {
    auto It = StringOffsets.find(S);
    assert(It != StringOffsets.end() && "string must be interned first");
    W.write<uint32_t>(checkedUint32(S.size(), "string length"));
    W.write<uint32_t>(It->second);
  };

  auto WriteSymbolRecord = [&](const GoObjSymbol &Symbol) {
    WriteStringRef(Symbol.Name);
    W.write<uint16_t>(Symbol.ABI);
    W.write<uint8_t>(Symbol.Type);
    W.write<uint8_t>(0);
    W.write<uint8_t>(0);
    W.write<uint32_t>(checkedUint32(Symbol.Size, "symbol size"));
    W.write<uint32_t>(Symbol.Align);
  };

  AddString("");
  if (HasGoFuncMetadata)
    AddString("llvm-ir");
  for (const GoObjSymbol &Symbol : Symbols)
    AddString(Symbol.Name);
  for (const GoObjSymbol &Symbol : NonPkgRefs)
    AddString(Symbol.Name);

  std::array<uint32_t, GoObj::NBlk> Offsets = {};
  auto MarkBlock = [&](GoObj::Block Block) { Offsets[Block] = CurrentOffset(); };
  auto WriteSymbolBlock = [&](ArrayRef<uint32_t> SymbolIndexes) {
    for (uint32_t Index : SymbolIndexes)
      WriteSymbolRecord(Symbols[Index]);
  };

  MarkBlock(GoObj::BlkAutolib);
  MarkBlock(GoObj::BlkPkgIdx);
  MarkBlock(GoObj::BlkFile);
  if (HasGoFuncMetadata)
    WriteStringRef("llvm-ir");

  MarkBlock(GoObj::BlkSymdef);
  WriteSymbolBlock(SymdefSymbols);

  MarkBlock(GoObj::BlkHashed64def);
  WriteSymbolBlock(Hashed64defSymbols);

  MarkBlock(GoObj::BlkHasheddef);
  WriteSymbolBlock(HasheddefSymbols);

  MarkBlock(GoObj::BlkNonpkgdef);
  WriteSymbolBlock(NonpkgdefSymbols);

  MarkBlock(GoObj::BlkNonpkgref);
  for (const GoObjSymbol &Symbol : NonPkgRefs)
    WriteSymbolRecord(Symbol);

  MarkBlock(GoObj::BlkRefFlags);
  MarkBlock(GoObj::BlkHash64);
  MarkBlock(GoObj::BlkHash);

  MarkBlock(GoObj::BlkRelocIdx);
  uint32_t RelocCount = 0;
  for (uint32_t Index : DefinedSymbolOrder) {
    const GoObjSymbol &Symbol = Symbols[Index];
    W.write<uint32_t>(RelocCount);
    RelocCount += checkedUint32(Symbol.Relocations.size(),
                                "symbol relocation count");
  }
  W.write<uint32_t>(RelocCount);

  MarkBlock(GoObj::BlkAuxIdx);
  uint32_t AuxCount = 0;
  for (uint32_t Index : DefinedSymbolOrder) {
    const GoObjSymbol &Symbol = Symbols[Index];
    W.write<uint32_t>(AuxCount);
    AuxCount += checkedUint32(Symbol.Auxiliaries.size(), "symbol aux count");
  }
  W.write<uint32_t>(AuxCount);

  MarkBlock(GoObj::BlkDataIdx);
  uint32_t DataOffset = 0;
  for (uint32_t Index : DefinedSymbolOrder) {
    const GoObjSymbol &Symbol = Symbols[Index];
    W.write<uint32_t>(DataOffset);
    DataOffset += checkedUint32(Symbol.Data.size(), "symbol data size");
  }
  W.write<uint32_t>(DataOffset);

  MarkBlock(GoObj::BlkReloc);
  for (uint32_t Index : DefinedSymbolOrder) {
    const GoObjSymbol &Symbol = Symbols[Index];
    for (const GoObjSymbol::Relocation &Reloc : Symbol.Relocations) {
      W.write<uint32_t>(Reloc.Offset);
      W.write<uint8_t>(Reloc.Size);
      W.write<uint16_t>(Reloc.Type);
      W.write<uint64_t>(static_cast<uint64_t>(Reloc.Addend));
      W.write<uint32_t>(Reloc.PkgIdx);
      W.write<uint32_t>(Reloc.SymIdx);
    }
  }

  MarkBlock(GoObj::BlkAux);
  for (uint32_t Index : DefinedSymbolOrder) {
    const GoObjSymbol &Symbol = Symbols[Index];
    for (const GoObjSymbol::Auxiliary &Aux : Symbol.Auxiliaries) {
      if (Aux.TargetSymbolIndex >= DefinedSymRefs.size())
        report_fatal_error("GoObj auxiliary target symbol index is invalid");
      GoObjSymRef Ref = DefinedSymRefs[Aux.TargetSymbolIndex];
      W.write<uint8_t>(Aux.Type);
      W.write<uint32_t>(Ref.PkgIdx);
      W.write<uint32_t>(Ref.SymIdx);
    }
  }

  MarkBlock(GoObj::BlkData);
  for (uint32_t Index : DefinedSymbolOrder) {
    const GoObjSymbol &Symbol = Symbols[Index];
    BodyOS.write(Symbol.Data.data(), Symbol.Data.size());
  }

  MarkBlock(GoObj::BlkRefName);
  MarkBlock(GoObj::BlkEnd);

  SmallString<GoObj::HeaderSize> Header;
  raw_svector_ostream HeaderOS(Header);
  support::endian::Writer HeaderW(HeaderOS, llvm::endianness::little);
  HeaderOS.write(GoObj::Magic, GoObj::MagicSize);
  for (uint8_t Byte : Config.Fingerprint)
    HeaderW.write<uint8_t>(Byte);
  HeaderW.write<uint32_t>(getGoObjFlags(Config));

  for (uint32_t I = 0; I != GoObj::NBlk; ++I)
    HeaderW.write<uint32_t>(Offsets[I]);

  assert(Header.size() == GoObj::HeaderSize && "unexpected GoObj header size");
  writeGoObjectTextHeader(OS, Asm->getContext().getTargetTriple(), Config);
  OS.write(Header.data(), Header.size());
  OS.write(Body.data(), Body.size());

  return OS.tell() - StartOffset;
}

std::unique_ptr<MCObjectWriter> llvm::createGoObjObjectWriter(
    std::unique_ptr<MCGoObjObjectTargetWriter> MOTW, raw_pwrite_stream &OS) {
  return std::make_unique<GoObjObjectWriter>(std::move(MOTW), OS);
}

std::unique_ptr<MCObjectWriter> llvm::createGoObjObjectWriter(
    std::unique_ptr<MCGoObjObjectTargetWriter> MOTW, raw_pwrite_stream &OS,
    MCGoObjObjectWriterConfig Config) {
  return std::make_unique<GoObjObjectWriter>(std::move(MOTW), OS,
                                             std::move(Config));
}
