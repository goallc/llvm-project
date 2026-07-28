//===- lib/MC/GoObjObjectWriter.cpp - Go object writer -------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/BinaryFormat/GoObj.h"
#include "llvm/MC/MCAsmBackend.h"
#include "llvm/MC/MCAsmInfo.h"
#include "llvm/MC/MCAssembler.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCDwarf.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCGoObjObjectWriter.h"
#include "llvm/MC/MCSection.h"
#include "llvm/MC/MCValue.h"
#include "llvm/Support/Alignment.h"
#include "llvm/Support/EndianStream.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/MathExtras.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/TargetParser/Triple.h"
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <limits>
#include <optional>
#include <string>
#include <utility>
#include <vector>

using namespace llvm;

int64_t MCGoObjObjectTargetWriter::getRelocAddend(const MCValue &Target,
                                                  const MCFixup &) const {
  return Target.getConstant();
}

namespace {

struct GoObjSymRef {
  uint32_t PkgIdx = GoObj::PkgIdxInvalid;
  uint32_t SymIdx = 0;
};

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
    Auxiliary(uint8_t Type, uint32_t TargetSymbolIndex)
        : Type(Type), TargetSymbolIndex(TargetSymbolIndex) {}
    Auxiliary(uint8_t Type, GoObjSymRef DirectTarget)
        : Type(Type), DirectTarget(DirectTarget) {}

    uint8_t Type;
    uint32_t TargetSymbolIndex = 0;
    std::optional<GoObjSymRef> DirectTarget;
  };

  std::string Name;
  const MCSymbol *Symbol = nullptr;
  const MCSection *Section = nullptr;
  uint64_t SectionBegin = 0;
  uint64_t SectionEnd = 0;
  GoObj::DefinedSymbolBlock DefinedBlock = GoObj::DefinedSymbolBlock::Symdef;
  uint8_t Type = GoObj::Sxxx;
  uint8_t Flag = 0;
  uint8_t Flag2 = 0;
  uint16_t ABI = 0;
  uint64_t Size = 0;
  uint32_t Align = 0;
  SmallString<0> Data;
  std::vector<Relocation> Relocations;
  std::vector<Auxiliary> Auxiliaries;
};

struct GoObjPCTabEntry {
  uint64_t PC = 0;
  int32_t Value = 0;
};

struct GoObjFuncDebugLines {
  SmallVector<uint32_t, 4> Files;
  SmallVector<GoObjPCTabEntry, 8> PCFile;
  SmallVector<GoObjPCTabEntry, 8> PCLine;
  int32_t StartLine = 1;

  bool hasLines() const { return !PCFile.empty() && !PCLine.empty(); }
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

uint16_t getGoObjStackPointerDwarfReg(const Triple &TT) {
  switch (TT.getArch()) {
  case Triple::x86_64:
    return 7;
  case Triple::aarch64:
  case Triple::aarch64_be:
    return 31;
  default:
    report_fatal_error(
        "GoObj statepoint stack maps do not support this architecture");
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

void addDefinedSymbol(std::vector<GoObjSymbol> &Symbols, const MCSymbol *MCSym,
                      const MCSection *Section, uint64_t SectionBegin,
                      uint64_t SectionEnd,
                      GoObj::DefinedSymbolBlock DefinedBlock, StringRef Name,
                      uint8_t Type, uint8_t Flag, uint8_t Flag2, uint16_t ABI,
                      uint64_t Size, uint32_t Align, ArrayRef<char> Data) {
  GoObjSymbol Sym;
  Sym.Name = Name.str();
  Sym.Symbol = MCSym;
  Sym.Section = Section;
  Sym.SectionBegin = SectionBegin;
  Sym.SectionEnd = SectionEnd;
  Sym.DefinedBlock = DefinedBlock;
  Sym.Type = Type;
  Sym.Flag = Flag;
  Sym.Flag2 = Flag2;
  Sym.ABI = ABI;
  Sym.Size = Size;
  Sym.Align = Align;
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

SmallString<0> makePCTab(int32_t InitialValue,
                         ArrayRef<GoObjPCTabEntry> Entries, uint64_t CodeSize,
                         uint32_t PCQuantum) {
  SmallString<0> Data;
  int32_t OldValue = -1;
  uint64_t PC = 0;
  bool Started = false;

  auto Emit = [&](uint64_t EventPC, int32_t Value) {
    if (EventPC > CodeSize)
      report_fatal_error("GoObj pc-value event exceeds function size");
    if (Started)
      appendUvarint(Data, getPCDeltaUnits(EventPC - PC, PCQuantum));
    appendVarint(Data, static_cast<int64_t>(Value) - OldValue);
    OldValue = Value;
    PC = EventPC;
    Started = true;
  };

  Emit(0, InitialValue);
  for (const GoObjPCTabEntry &Entry : Entries) {
    if (Entry.Value == OldValue)
      continue;
    Emit(Entry.PC, Entry.Value);
  }

  appendUvarint(Data, getPCDeltaUnits(CodeSize - PC, PCQuantum));
  appendUvarint(Data, 0);
  return Data;
}

SmallString<0> makeConstantPCTab(int32_t Value, uint64_t CodeSize,
                                 uint32_t PCQuantum) {
  return makePCTab(Value, {}, CodeSize, PCQuantum);
}

SmallString<0> makeFuncInfoData(uint32_t ArgSize, uint32_t StackSize,
                                ArrayRef<uint32_t> Files, int32_t StartLine) {
  SmallString<0> Data;
  raw_svector_ostream OS(Data);
  support::endian::Writer W(OS, llvm::endianness::little);
  W.write<uint32_t>(ArgSize);   // Args.
  W.write<uint32_t>(StackSize); // Locals.
  W.write<uint8_t>(0);          // FuncIDNormal.
  W.write<uint8_t>(0);          // No FuncFlag bits.
  W.write<uint8_t>(0);
  W.write<uint8_t>(0);
  W.write<uint32_t>(static_cast<uint32_t>(StartLine));
  W.write<uint32_t>(checkedUint32(Files.size(), "GoObj FuncInfo file count"));
  for (uint32_t File : Files)
    W.write<uint32_t>(File);
  W.write<uint32_t>(0); // Inline tree count.
  return Data;
}

SmallString<0> makeEmptyStackMap() {
  SmallString<0> Data;
  raw_svector_ostream OS(Data);
  support::endian::Writer W(OS, llvm::endianness::little);
  W.write<uint32_t>(1); // One bitmap, selected by PCDATA_StackMapIndex 0.
  W.write<uint32_t>(0); // Zero pointer bits.
  return Data;
}

SmallString<0> makeStackMap(uint32_t NBits,
                            ArrayRef<SmallVector<uint8_t, 8>> Bitmaps) {
  SmallString<0> Data;
  raw_svector_ostream OS(Data);
  support::endian::Writer W(OS, llvm::endianness::little);
  W.write<uint32_t>(checkedUint32(Bitmaps.size(), "GoObj stack map count"));
  W.write<uint32_t>(NBits);
  size_t BytesPerBitmap = divideCeil(NBits, 8u);
  for (const auto &Bitmap : Bitmaps) {
    if (Bitmap.size() != BytesPerBitmap)
      report_fatal_error("GoObj stack map bitmap has invalid size");
    const char *BitmapData = reinterpret_cast<const char *>(Bitmap.data());
    Data.append(BitmapData, BitmapData + Bitmap.size());
  }
  return Data;
}

struct GoObjStatepointStackMaps {
  SmallString<0> Args;
  SmallString<0> Locals;
  SmallString<0> PCData;
};

GoObjStatepointStackMaps makeStatepointStackMaps(
    const MCAssembler &Asm, const GoObjSymbol &Function, uint32_t StackSize,
    uint32_t PCQuantum,
    ArrayRef<MCContext::GoObjStackMapEntry> StackMapEntries) {
  struct ResolvedEntry {
    uint64_t CallsitePC;
    const MCContext::GoObjStackMapEntry *Entry;
  };

  SmallVector<ResolvedEntry, 8> ResolvedEntries;
  ResolvedEntries.reserve(StackMapEntries.size());
  for (const MCContext::GoObjStackMapEntry &Entry : StackMapEntries) {
    if (!Entry.CallsiteOffsetExpr)
      report_fatal_error("GoObj statepoint has no callsite offset expression");
    if (Entry.StackSize == UINT64_MAX)
      report_fatal_error(
          "GoObj statepoint stack maps do not support dynamic frames");
    if (Entry.StackSize != StackSize)
      report_fatal_error(
          "GoObj statepoint stack size does not match function metadata");
    int64_t CallsitePCValue;
    if (!Entry.CallsiteOffsetExpr->evaluateAsAbsolute(CallsitePCValue, Asm) ||
        CallsitePCValue < 0)
      report_fatal_error("GoObj statepoint callsite offset is not absolute");
    uint64_t CallsitePC = static_cast<uint64_t>(CallsitePCValue);
    if (CallsitePC > Function.Size)
      report_fatal_error(
          "GoObj statepoint callsite is outside its function range");
    if (CallsitePC % PCQuantum != 0)
      report_fatal_error("GoObj statepoint callsite has invalid PC");
    ResolvedEntries.push_back({CallsitePC, &Entry});
  }
  llvm::stable_sort(ResolvedEntries,
                    [](const ResolvedEntry &LHS, const ResolvedEntry &RHS) {
                      return LHS.CallsitePC < RHS.CallsitePC;
                    });
  uint32_t PointerSize = StackMapEntries.front().PointerSize;
  if (!PointerSize)
    report_fatal_error("GoObj statepoint has invalid pointer size");
  if (PointerSize != Asm.getContext().getAsmInfo().getCodePointerSize())
    report_fatal_error(
        "GoObj statepoint pointer size does not match its target");
  uint16_t StackPointerDwarfRegNum =
      getGoObjStackPointerDwarfReg(Asm.getContext().getTargetTriple());
  uint32_t NBits =
      checkedUint32(divideCeil(static_cast<uint64_t>(StackSize), PointerSize),
                    "GoObj locals stack map bit count");
  size_t BytesPerBitmap = divideCeil(NBits, 8u);

  SmallVector<SmallVector<uint8_t, 8>, 8> Bitmaps;
  SmallVector<GoObjPCTabEntry, 16> PCDataEntries;
  std::optional<uint64_t> PreviousCallsitePC;
  for (const ResolvedEntry &Resolved : ResolvedEntries) {
    if (PreviousCallsitePC && *PreviousCallsitePC == Resolved.CallsitePC)
      report_fatal_error("GoObj statepoint callsites have duplicate PCs");
    PreviousCallsitePC = Resolved.CallsitePC;
    const MCContext::GoObjStackMapEntry &Entry = *Resolved.Entry;
    if (Entry.PointerSize != PointerSize)
      report_fatal_error(
          "GoObj statepoint pointer size changes within a function");

    SmallVector<uint8_t, 8> Bitmap(BytesPerBitmap, 0);
    for (const MCContext::GoObjStackMapLocation &Loc : Entry.Locations) {
      switch (Loc.Type) {
      case MCContext::GoObjStackMapLocation::Direct:
      case MCContext::GoObjStackMapLocation::Indirect:
        break;
      case MCContext::GoObjStackMapLocation::Unprocessed:
      case MCContext::GoObjStackMapLocation::Register:
      case MCContext::GoObjStackMapLocation::Constant:
      case MCContext::GoObjStackMapLocation::ConstantIndex:
        report_fatal_error(
            "GoObj statepoint GC pointer is not in a stack slot");
      }
      if (Loc.Size != PointerSize || Loc.Offset < 0 ||
          Loc.DwarfRegNum != StackPointerDwarfRegNum ||
          static_cast<uint64_t>(Loc.Offset) + PointerSize > StackSize ||
          static_cast<uint64_t>(Loc.Offset) % PointerSize != 0)
        report_fatal_error(
            "GoObj statepoint contains an invalid pointer stack slot");

      // Direct describes the pointer value SP+Offset, not a pointer stored at
      // SP+Offset. Statepoint lowering rematerializes that address after stack
      // movement; marking it in FUNCDATA_LocalsPointerMaps would instead make
      // the runtime scan the alloca contents as a pointer. Address-taken stack
      // objects with pointer fields require FUNCDATA_StackObjects.
      if (Loc.Type == MCContext::GoObjStackMapLocation::Direct)
        continue;
      uint32_t Bit = static_cast<uint32_t>(Loc.Offset) / PointerSize;
      Bitmap[Bit / 8] |= uint8_t(1u << (Bit % 8));
    }

    auto It = llvm::find(Bitmaps, Bitmap);
    uint32_t MapIndex;
    if (It == Bitmaps.end()) {
      MapIndex = checkedUint32(Bitmaps.size(), "GoObj stack map index");
      Bitmaps.push_back(std::move(Bitmap));
    } else {
      MapIndex = checkedUint32(It - Bitmaps.begin(), "GoObj stack map index");
    }
    if (MapIndex > static_cast<uint32_t>(std::numeric_limits<int32_t>::max()))
      report_fatal_error("GoObj stack map index exceeds int32 limit");

    // GoObj records statepoint callsites at the beginning of the CALL. The
    // live-out map remains in effect until another statepoint, including the
    // stack-growth call, changes it.
    PCDataEntries.push_back(
        {Resolved.CallsitePC, static_cast<int32_t>(MapIndex)});
  }

  // Args and locals maps share PCDATA_StackMapIndex. Argument classification
  // is not available here yet, but the empty argument map still needs the same
  // number of entries as the locals map.
  SmallVector<SmallVector<uint8_t, 8>, 8> EmptyArgsMaps(Bitmaps.size());
  SmallVector<GoObjPCTabEntry, 16> NormalizedPCDataEntries;
  llvm::stable_sort(PCDataEntries, [](const auto &LHS, const auto &RHS) {
    if (LHS.PC != RHS.PC)
      return LHS.PC < RHS.PC;
    return LHS.Value < RHS.Value;
  });
  for (const GoObjPCTabEntry &Entry : PCDataEntries) {
    if (!NormalizedPCDataEntries.empty() &&
        NormalizedPCDataEntries.back().PC == Entry.PC)
      NormalizedPCDataEntries.back().Value = Entry.Value;
    else
      NormalizedPCDataEntries.push_back(Entry);
  }
  GoObjStatepointStackMaps Result;
  Result.Args = makeStackMap(0, EmptyArgsMaps);
  Result.Locals = makeStackMap(NBits, Bitmaps);
  Result.PCData =
      makePCTab(-1, NormalizedPCDataEntries, Function.Size, PCQuantum);
  return Result;
}

std::string getDwarfFilePath(const MCDwarfLineTable &Table, unsigned FileNum) {
  const MCDwarfFile *File = nullptr;
  const auto &Files = Table.getMCDwarfFiles();
  if (FileNum < Files.size() && !Files[FileNum].Name.empty())
    File = &Files[FileNum];
  else if (FileNum == 0 && !Table.getRootFile().Name.empty())
    File = &Table.getRootFile();
  if (!File || File->Name.empty())
    return "llvm-ir";

  SmallString<256> Path(File->Name);
  if (!sys::path::is_absolute(Path) && File->DirIndex != 0) {
    const auto &Dirs = Table.getMCDwarfDirs();
    if (File->DirIndex - 1 < Dirs.size() && !Dirs[File->DirIndex - 1].empty()) {
      Path = Dirs[File->DirIndex - 1];
      sys::path::append(Path, File->Name);
    }
  }
  return std::string(Path);
}

uint32_t getOrAddFileIndex(StringMap<uint32_t> &FileIndexes,
                           std::vector<std::string> &Files, StringRef Path) {
  auto Insert = FileIndexes.insert(
      {Path, checkedUint32(Files.size(), "GoObj file count")});
  if (Insert.second)
    Files.push_back(Path.str());
  return Insert.first->second;
}

uint32_t getOrAddLocalFileIndex(GoObjFuncDebugLines &Info,
                                uint32_t ObjectFileIndex) {
  for (uint32_t I = 0, E = checkedUint32(Info.Files.size(),
                                         "GoObj function file count");
       I != E; ++I) {
    if (Info.Files[I] == ObjectFileIndex)
      return I;
  }
  Info.Files.push_back(ObjectFileIndex);
  return checkedUint32(Info.Files.size() - 1, "GoObj function file index");
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
  StringRef GOOS = Config.GOOS.empty() ? getGoOS(TT) : Config.GOOS;
  StringRef GOARCH = Config.GOARCH.empty() ? getGoArch(TT) : Config.GOARCH;
  OS << "go object " << GOOS << ' ' << GOARCH << ' ' << Config.Version;

  if (!Config.GOARCHSettingKey.empty()) {
    OS << ' ' << Config.GOARCHSettingKey << '=' << Config.GOARCHSettingValue;
  } else {
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
  }

  OS << " X:";
  for (size_t I = 0, E = Config.Experiments.size(); I != E; ++I) {
    if (I != 0)
      OS << ',';
    OS << Config.Experiments[I];
  }
  OS << '\n';

  if (!Config.BuildID.empty())
    OS << "build id \"" << Config.BuildID << "\"\n";
  if (Config.IsMain)
    OS << "main\n";

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
  return MCObjectWriter::isSymbolRefDifferenceFullyResolvedImpl(SymA, FB, InSet,
                                                                IsPCRel);
}

void GoObjObjectWriter::recordRelocation(const MCFragment &F,
                                         const MCFixup &Fixup, MCValue Target,
                                         uint64_t &FixedValue) {
  const MCFixupKindInfo &Info =
      Asm->getBackend().getFixupKindInfo(Fixup.getKind());
  uint8_t RelocSize = TargetObjectWriter->getRelocSize(Fixup);
  if (!RelocSize) {
    assert(Info.TargetSize % 8 == 0 && "Target size must be byte-aligned");
    RelocSize = Info.TargetSize / 8;
  }
  Relocations.push_back({Target.getAddSym(), Target.getSubSym(), F.getParent(),
                         Asm->getFragmentOffset(F) + Fixup.getOffset(),
                         TargetObjectWriter->getRelocAddend(Target, Fixup),
                         TargetObjectWriter->getRelocType(Target, Fixup),
                         RelocSize, Fixup.isPCRel()});
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
          &Symbol.getSection() != &Section ||
          &Symbol == Section.getBeginSymbol())
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
      uint16_t ABI = MCSym
                         ? Asm->getContext().getGoObjSymbolABI(MCSym).value_or(
                               GoObj::SymABI0)
                         : GoObj::SymABI0;
      uint8_t Flag = 0;
      uint8_t Flag2 = 0;
      uint32_t Align = 0;
      if (MCSym) {
        if (std::optional<std::pair<uint8_t, uint8_t>> Flags =
                Asm->getContext().getGoObjSymbolFlags(MCSym)) {
          Flag = Flags->first;
          Flag2 = Flags->second;
        }
        Align =
            Asm->getContext().getGoObjSymbolAlignment(MCSym).value_or(0);
      }
      addDefinedSymbol(Symbols, MCSym, &Section, Begin, End,
                       Config.DefaultDefinedSymbolBlock, Name, Type, Flag,
                       Flag2, ABI, Size, Align, Data);
    };

    if (SectionSymbols.empty()) {
      AddSectionSymbol(nullptr, Section.getName(), 0, SectionSize);
      continue;
    }

    for (size_t I = 0, E = SectionSymbols.size(); I != E; ++I) {
      uint64_t Begin = SectionSymbols[I].Offset;
      uint64_t End = SectionSize;
      for (size_t J = I + 1; J != E; ++J) {
        if (SectionSymbols[J].Offset > Begin) {
          End = SectionSymbols[J].Offset;
          break;
        }
      }
      if (std::optional<uint64_t> ExactSize =
              Asm->getContext().getGoObjSymbolSize(
                  SectionSymbols[I].Symbol)) {
        if (*ExactSize > SectionSize - Begin ||
            Begin + *ExactSize > End)
          report_fatal_error(
              "GoObj global size overlaps the next section symbol");
        End = Begin + *ExactSize;
      }
      AddSectionSymbol(SectionSymbols[I].Symbol,
                       SectionSymbols[I].Symbol->getName(), Begin, End);
    }
  }

  uint32_t PCQuantum = getGoObjPCQuantum(Asm->getContext().getTargetTriple());
  std::vector<GoObjFuncDebugLines> FuncDebugLines(Symbols.size());
  std::vector<std::string> FilePaths;
  StringMap<uint32_t> FileIndexes;
  auto GetFallbackFile = [&]() {
    return getOrAddFileIndex(FileIndexes, FilePaths, "llvm-ir");
  };

  if (Config.SourceKind == GoObj::SourceKind::Compiler) {
    for (const auto &[CUID, LineTable] :
         Asm->getContext().getMCDwarfLineTables()) {
      (void)CUID;
      for (const auto &LineDivision :
           LineTable.getMCLineSections().getMCLineEntries()) {
        MCSection *Section = LineDivision.first;
        for (const MCDwarfLineEntry &LineEntry : LineDivision.second) {
          MCSymbol *Label = LineEntry.getLabel();
          if (!Label || !Label->isInSection())
            continue;
          uint64_t LabelOffset = Asm->getSymbolOffset(*Label);
          for (uint32_t I = 0,
                        E = checkedUint32(Symbols.size(), "symbol count");
               I != E; ++I) {
            GoObjSymbol &Sym = Symbols[I];
            if (LineEntry.getLine() == 0 || Sym.Type != GoObj::STEXT ||
                Sym.Size == 0 || Sym.Section != Section ||
                LabelOffset < Sym.SectionBegin || LabelOffset >= Sym.SectionEnd)
              continue;

            std::string Path =
                getDwarfFilePath(LineTable, LineEntry.getFileNum());
            uint32_t ObjectFileIndex =
                getOrAddFileIndex(FileIndexes, FilePaths, Path);
            GoObjFuncDebugLines &Info = FuncDebugLines[I];
            uint32_t LocalFileIndex =
                getOrAddLocalFileIndex(Info, ObjectFileIndex);
            uint64_t PC = LabelOffset - Sym.SectionBegin;
            int32_t Line = static_cast<int32_t>(LineEntry.getLine());
            Info.PCFile.push_back({PC, static_cast<int32_t>(LocalFileIndex)});
            Info.PCLine.push_back({PC, Line});
            if (Info.PCLine.size() == 1)
              Info.StartLine = Line;
            break;
          }
        }
      }
    }

    for (uint32_t I = 0, E = checkedUint32(Symbols.size(), "symbol count");
         I != E; ++I) {
      if (Symbols[I].Type != GoObj::STEXT || Symbols[I].Size == 0 ||
          !Symbols[I].Symbol)
        continue;

      uint32_t StackSize = Asm->getContext()
                               .getGoObjSymbolStackSize(Symbols[I].Symbol)
                               .value_or(0);
      uint32_t ArgSize = Asm->getContext()
                             .getGoObjSymbolArgSize(Symbols[I].Symbol)
                             .value_or(0);
      uint64_t CodeSize = Symbols[I].Size;

      SmallVector<GoObjPCTabEntry, 8> PCSPEntries;
      if (const auto *Entries =
              Asm->getContext().getGoObjSymbolPCSPEntries(Symbols[I].Symbol)) {
        for (const MCContext::GoObjPCSPEntry &Entry : *Entries) {
          if (!Entry.Label->isInSection())
            continue;
          uint64_t LabelOffset = Asm->getSymbolOffset(*Entry.Label);
          if (LabelOffset < Symbols[I].SectionBegin)
            continue;
          uint64_t EventPC = LabelOffset - Symbols[I].SectionBegin;
          if (EventPC <= CodeSize)
            PCSPEntries.push_back({EventPC, Entry.Value});
        }
        llvm::stable_sort(PCSPEntries, [](const auto &LHS, const auto &RHS) {
          return LHS.PC < RHS.PC;
        });
      }

      GoObjFuncDebugLines &LineInfo = FuncDebugLines[I];
      if (!LineInfo.hasLines())
        LineInfo.Files.push_back(GetFallbackFile());
      llvm::stable_sort(LineInfo.PCFile, [](const auto &LHS, const auto &RHS) {
        return LHS.PC < RHS.PC;
      });
      llvm::stable_sort(LineInfo.PCLine, [](const auto &LHS, const auto &RHS) {
        return LHS.PC < RHS.PC;
      });

      uint32_t FuncInfoSym = addAuxCarrierSymbol(
          Symbols, GoObj::DefinedSymbolBlock::Symdef,
          makeFuncInfoData(ArgSize, StackSize, LineInfo.Files,
                           LineInfo.StartLine));
      uint32_t PcspSym = addAuxCarrierSymbol(
          Symbols, GoObj::DefinedSymbolBlock::Nonpkgdef,
          PCSPEntries.empty()
              ? makeConstantPCTab(static_cast<int32_t>(StackSize), CodeSize,
                                  PCQuantum)
              : makePCTab(0, PCSPEntries, CodeSize, PCQuantum));
      int32_t InitialFile =
          LineInfo.hasLines() ? LineInfo.PCFile.front().Value : 0;
      int32_t InitialLine =
          LineInfo.hasLines() ? LineInfo.PCLine.front().Value : 1;
      uint32_t PcfileSym = addAuxCarrierSymbol(
          Symbols, GoObj::DefinedSymbolBlock::Nonpkgdef,
          makePCTab(InitialFile, LineInfo.PCFile, CodeSize, PCQuantum));
      uint32_t PclineSym = addAuxCarrierSymbol(
          Symbols, GoObj::DefinedSymbolBlock::Nonpkgdef,
          makePCTab(InitialLine, LineInfo.PCLine, CodeSize, PCQuantum));
      SmallString<0> ArgsMap = makeEmptyStackMap();
      SmallString<0> LocalsMap = makeEmptyStackMap();
      SmallString<0> StackMapIndex = makeConstantPCTab(0, CodeSize, PCQuantum);
      if (const auto *Entries = Asm->getContext().getGoObjSymbolStackMapEntries(
              Symbols[I].Symbol)) {
        if (!Entries->empty()) {
          GoObjStatepointStackMaps Maps = makeStatepointStackMaps(
              *Asm, Symbols[I], StackSize, PCQuantum, *Entries);
          ArgsMap = std::move(Maps.Args);
          LocalsMap = std::move(Maps.Locals);
          StackMapIndex = std::move(Maps.PCData);
        }
      }
      uint32_t ArgsMapSym = addAuxCarrierSymbol(
          Symbols, GoObj::DefinedSymbolBlock::Nonpkgdef, ArgsMap);
      uint32_t LocalsMapSym = addAuxCarrierSymbol(
          Symbols, GoObj::DefinedSymbolBlock::Nonpkgdef, LocalsMap);
      uint32_t StackMapIndexSym = addAuxCarrierSymbol(
          Symbols, GoObj::DefinedSymbolBlock::Nonpkgdef, StackMapIndex);
      uint32_t UnsafePointSym =
          addAuxCarrierSymbol(Symbols, GoObj::DefinedSymbolBlock::Nonpkgdef,
                              makeConstantPCTab(-1, CodeSize, PCQuantum));

      Symbols[I].Auxiliaries.push_back({GoObj::AuxFuncInfo, FuncInfoSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxFuncdata, ArgsMapSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxFuncdata, LocalsMapSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxPcsp, PcspSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxPcfile, PcfileSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxPcline, PclineSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxPcdata, UnsafePointSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxPcdata, StackMapIndexSym});
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
  DefinedSymbolOrder.insert(DefinedSymbolOrder.end(),
                            Hashed64defSymbols.begin(),
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

  auto FindContainingSymbol = [&](const MCSection *Section,
                                  uint64_t Offset) -> std::optional<uint32_t> {
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

    uint32_t SymIdx = checkedUint32(NonpkgdefSymbols.size() + NonPkgRefs.size(),
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
        Addend +=
            static_cast<int64_t>(TargetOffset - Symbols[*SymIdx].SectionBegin);
        return DefinedSymRefs[*SymIdx];
      }
    }

    if (Reloc.Symbol->isUndefined())
      return GoObjSymRef{GoObj::PkgIdxNone, GetNonPkgRefSymIdx(Reloc.Symbol)};

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

    uint16_t RelocType = checkedUint16(Reloc.Type, "relocation type");
    if (Source.Symbol) {
      if (const auto *Overrides =
              Asm->getContext().getGoObjRelocOverrides(Source.Symbol)) {
        auto It = std::lower_bound(
            Overrides->begin(), Overrides->end(),
            static_cast<uint32_t>(LocalOffset),
            [](const MCContext::GoObjRelocOverride &Override, uint32_t Offset) {
              return Override.Offset < Offset;
            });
        if (It != Overrides->end() && It->Offset == LocalOffset)
          RelocType = It->Type;
      }
      if (const auto *WeakRelocs =
              Asm->getContext().getGoObjWeakRelocs(Source.Symbol);
          WeakRelocs &&
          std::binary_search(WeakRelocs->begin(), WeakRelocs->end(),
                             static_cast<uint32_t>(LocalOffset)))
        RelocType |= GoObj::R_WEAK;
    }

    Source.Relocations.push_back({static_cast<uint32_t>(LocalOffset),
                                  Reloc.Size, RelocType, Addend,
                                  TargetSymRef.PkgIdx, TargetSymRef.SymIdx});
  }

  // R_KEEP has no bytes or MC fixup. It is a Go linker reachability edge
  // carried separately from normal LLVM relocations by !goobj.keep.
  for (GoObjSymbol &Source : Symbols) {
    if (!Source.Symbol)
      continue;
    const auto *Targets = Asm->getContext().getGoObjKeepTargets(Source.Symbol);
    if (!Targets)
      continue;
    for (const MCSymbol *Target : *Targets) {
      GoObjRelocationEntry Reloc;
      Reloc.Symbol = Target;
      int64_t Addend = 0;
      GoObjSymRef TargetSymRef = GetTargetSymRef(Reloc, Addend);
      Source.Relocations.push_back({0, 0, GoObj::R_KEEP, Addend,
                                    TargetSymRef.PkgIdx, TargetSymRef.SymIdx});
    }
  }

  for (GoObjSymbol &Source : Symbols) {
    if (!Source.Symbol)
      continue;
    const auto *Markers =
        Asm->getContext().getGoObjMarkerRelocs(Source.Symbol);
    if (!Markers)
      continue;
    for (const MCContext::GoObjMarkerReloc &Marker : *Markers) {
      GoObjRelocationEntry Reloc;
      Reloc.Symbol = Marker.Target;
      int64_t Addend = Marker.Addend;
      GoObjSymRef TargetSymRef = GetTargetSymRef(Reloc, Addend);
      Source.Relocations.push_back(
          {0, 0, Marker.Type, Addend, TargetSymRef.PkgIdx, TargetSymRef.SymIdx});
    }
  }

  for (GoObjSymbol &Source : Symbols) {
    if (!Source.Symbol)
      continue;
    const MCSymbol *Target =
        Asm->getContext().getGoObjGotypeTarget(Source.Symbol);
    if (!Target)
      continue;
    GoObjRelocationEntry Reloc;
    Reloc.Symbol = Target;
    int64_t Addend = 0;
    GoObjSymRef TargetSymRef = GetTargetSymRef(Reloc, Addend);
    if (Addend != 0)
      report_fatal_error("GoObj gotype auxiliary target has an addend");
    Source.Auxiliaries.emplace_back(GoObj::AuxGotype, TargetSymRef);
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
    W.write<uint8_t>(Symbol.Flag);
    W.write<uint8_t>(Symbol.Flag2);
    W.write<uint32_t>(checkedUint32(Symbol.Size, "symbol size"));
    W.write<uint32_t>(Symbol.Align);
  };

  AddString("");
  for (StringRef File : FilePaths)
    AddString(File);
  for (const GoObjSymbol &Symbol : Symbols)
    AddString(Symbol.Name);
  for (const GoObjSymbol &Symbol : NonPkgRefs)
    AddString(Symbol.Name);

  std::array<uint32_t, GoObj::NBlk> Offsets = {};
  auto MarkBlock = [&](GoObj::Block Block) {
    Offsets[Block] = CurrentOffset();
  };
  auto WriteSymbolBlock = [&](ArrayRef<uint32_t> SymbolIndexes) {
    for (uint32_t Index : SymbolIndexes)
      WriteSymbolRecord(Symbols[Index]);
  };

  MarkBlock(GoObj::BlkAutolib);
  MarkBlock(GoObj::BlkPkgIdx);
  MarkBlock(GoObj::BlkFile);
  for (StringRef File : FilePaths)
    WriteStringRef(File);

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
    RelocCount +=
        checkedUint32(Symbol.Relocations.size(), "symbol relocation count");
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
      GoObjSymRef Ref;
      if (Aux.DirectTarget) {
        Ref = *Aux.DirectTarget;
      } else {
        if (Aux.TargetSymbolIndex >= DefinedSymRefs.size())
          report_fatal_error("GoObj auxiliary target symbol index is invalid");
        Ref = DefinedSymRefs[Aux.TargetSymbolIndex];
      }
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

std::unique_ptr<MCObjectWriter>
llvm::createGoObjObjectWriter(std::unique_ptr<MCGoObjObjectTargetWriter> MOTW,
                              raw_pwrite_stream &OS) {
  return std::make_unique<GoObjObjectWriter>(std::move(MOTW), OS);
}

std::unique_ptr<MCObjectWriter>
llvm::createGoObjObjectWriter(std::unique_ptr<MCGoObjObjectTargetWriter> MOTW,
                              raw_pwrite_stream &OS,
                              MCGoObjObjectWriterConfig Config) {
  return std::make_unique<GoObjObjectWriter>(std::move(MOTW), OS,
                                             std::move(Config));
}
