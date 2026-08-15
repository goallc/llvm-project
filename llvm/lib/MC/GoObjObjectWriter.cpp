//===- lib/MC/GoObjObjectWriter.cpp - Go object writer -------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "GoObjStackMapUtils.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringExtras.h"
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
#include "llvm/Support/SHA256.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/TargetParser/Triple.h"
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <functional>
#include <limits>
#include <optional>
#include <string>
#include <tuple>
#include <type_traits>
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

std::string goObjPathToPrefix(StringRef Path) {
  size_t Slash = Path.rfind('/');
  size_t LastSegment = Slash == StringRef::npos ? 0 : Slash + 1;
  SmallString<128> Prefix;
  constexpr char Hex[] = "0123456789abcdef";
  for (size_t I = 0; I != Path.size(); ++I) {
    uint8_t C = static_cast<uint8_t>(Path[I]);
    if (C <= ' ' || (C == '.' && I >= LastSegment) || C == '%' || C == '"' ||
        C >= 0x7f) {
      Prefix.push_back('%');
      Prefix.push_back(Hex[C >> 4]);
      Prefix.push_back(Hex[C & 0xf]);
    } else {
      Prefix.push_back(static_cast<char>(C));
    }
  }
  return Prefix.str().str();
}

struct GoObjSymbol {
  struct Relocation {
    uint32_t Offset = 0;
    uint8_t Size = 0;
    uint16_t Type = 0;
    int64_t Addend = 0;
    uint32_t PkgIdx = GoObj::PkgIdxInvalid;
    uint32_t SymIdx = 0;
    std::optional<uint32_t> TargetSymbolIndex;
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
  std::optional<std::array<uint8_t, GoObj::HashSize>> ContentHash;
  std::optional<std::array<uint8_t, GoObj::Hash64Size>> ContentHash64;
  std::vector<Relocation> Relocations;
  std::vector<Auxiliary> Auxiliaries;
};

struct GoObjPCTabEntry {
  uint64_t PC = 0;
  int32_t Value = 0;
};

struct GoObjInlineTreeNode {
  int32_t Parent = -1;
  uint32_t File = 0;
  int32_t Line = 0;
  const MCSymbol *Callee = nullptr;
  int32_t ParentPC = -1;
  uint64_t SiteID = 0;
};

struct GoObjFuncDebugLines {
  SmallVector<uint32_t, 4> Files;
  SmallVector<GoObjPCTabEntry, 8> PCFile;
  SmallVector<GoObjPCTabEntry, 8> PCLine;
  SmallVector<GoObjPCTabEntry, 8> PCInline;
  SmallVector<GoObjInlineTreeNode, 4> InlineTree;
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

  StringRef Name = Section->getName();
  if (Name.starts_with(".noptrdata"))
    return GoObj::SNOPTRDATA;
  if (Name.starts_with(".noptrbss"))
    return GoObj::SNOPTRBSS;
  if (Section->isBssSection())
    return GoObj::SBSS;
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
                                uint8_t FuncID, uint8_t FuncFlag,
                                ArrayRef<uint32_t> Files, int32_t StartLine,
                                ArrayRef<GoObjInlineTreeNode> InlineTree) {
  SmallString<0> Data;
  raw_svector_ostream OS(Data);
  support::endian::Writer W(OS, llvm::endianness::little);
  W.write<uint32_t>(ArgSize);   // Args.
  W.write<uint32_t>(StackSize); // Locals.
  W.write<uint8_t>(FuncID);
  W.write<uint8_t>(FuncFlag);
  W.write<uint8_t>(0);
  W.write<uint8_t>(0);
  W.write<uint32_t>(static_cast<uint32_t>(StartLine));
  W.write<uint32_t>(checkedUint32(Files.size(), "GoObj FuncInfo file count"));
  for (uint32_t File : Files)
    W.write<uint32_t>(File);
  W.write<uint32_t>(
      checkedUint32(InlineTree.size(), "GoObj FuncInfo inline tree count"));
  for (const GoObjInlineTreeNode &Node : InlineTree) {
    W.write<uint32_t>(static_cast<uint32_t>(Node.Parent));
    W.write<uint32_t>(Node.File);
    W.write<uint32_t>(static_cast<uint32_t>(Node.Line));
    W.write<uint32_t>(0); // Callee package index, patched after ref numbering.
    W.write<uint32_t>(0); // Callee symbol index, patched after ref numbering.
    W.write<uint32_t>(static_cast<uint32_t>(Node.ParentPC));
  }
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
  struct StackObject {
    int32_t FrameOffset;
    uint32_t ByteSize;
    uint32_t PointerBytes;
    SmallVector<uint8_t, 8> Bitmap;

    bool operator==(const StackObject &Other) const {
      return FrameOffset == Other.FrameOffset && ByteSize == Other.ByteSize &&
             PointerBytes == Other.PointerBytes && Bitmap == Other.Bitmap;
    }
  };

  SmallString<0> Args;
  SmallString<0> Locals;
  SmallString<0> PCData;
  SmallString<0> OpenDefer;
  SmallVector<uint32_t, 4> IndirectCallOffsets;
  SmallVector<StackObject, 4> StackObjects;
};

struct GoObjGCFrameLayout {
  uint32_t FuncInfoLocalsSize;
  uint32_t StackObjectVarpOffset;
  uint32_t GCLocalsStart;
  uint32_t GCLocalsSize;
  uint32_t GCLocalsBitOffset;
  uint32_t EntryArgsStart;
};

GoObjGCFrameLayout getGoObjGCFrameLayout(const Triple &TT, uint32_t StackSize,
                                         uint32_t PointerSize,
                                         bool HasFramePointer) {
  // At an amd64 function entry, RSP points at the return address. Entry
  // argument pointer locations in the entry stack map are relative to that
  // pre-frame RSP, so the caller's argument area begins one word above it. The
  // same bias applies after subtracting StackSize for ordinary statepoints.
  if (TT.getArch() == Triple::x86_64) {
    if (StackSize == 0)
      return {0, 0, 0, 0, 0, PointerSize};
    if (!PointerSize || StackSize < PointerSize || StackSize % PointerSize != 0)
      report_fatal_error("X86 GoObj frame has invalid GC layout");

    if (HasFramePointer) {
      // A suspended amd64 frame includes the next callee's return-address word
      // below its current SP in _func.locals. LLVM stack-map locations are
      // relative to the pre-call SP, so bit 0 has no non-negative location.
      // The saved frame pointer at the top of the frame is excluded from the
      // scannable locals area.
      return {StackSize, StackSize - PointerSize,
              0,         StackSize - PointerSize,
              1,         PointerSize};
    }

    // Frameless functions do not reserve the saved-frame-pointer word. Their
    // entire physical frame is scannable and the first stack-map word is bit 0.
    return {StackSize, StackSize, 0, StackSize, 0, PointerSize};
  }
  if (TT.getArch() != Triple::aarch64)
    return {StackSize, StackSize, 0, StackSize, 0, 0};
  if (StackSize == 0)
    return {0, 0, 0, 0, 0, PointerSize};
  if (!PointerSize || StackSize < 2 * PointerSize ||
      StackSize % PointerSize != 0)
    report_fatal_error("AArch64 GoObj frame has invalid GC layout");

  // Go arm64 frames keep LR at 0(SP). The caller's FP link occupies the top
  // word at frame.varp, and this function's FP link is stored below SP for the
  // next callee. _func.locals is frame.varp-SP, so it excludes LR from the
  // physical frame size. Locals pointer maps exclude both reserved words and
  // therefore describe [SP+PointerSize, frame.varp).
  return {StackSize - PointerSize,
          StackSize - PointerSize,
          PointerSize,
          StackSize - 2 * PointerSize,
          0,
          PointerSize};
}

struct GoObjStackMapPair {
  SmallVector<uint8_t, 8> Args;
  SmallVector<uint8_t, 8> Locals;

  bool operator==(const GoObjStackMapPair &Other) const {
    return Args == Other.Args && Locals == Other.Locals;
  }
};

struct GoObjAllocaPtrMapRecord {
  MCContext::GoObjStackMapLocation Base;
  uint64_t ByteOffset;
  uint64_t ByteSize;
  uint64_t Alignment;
  uint64_t PointerSize;
  uint64_t BitCount;
  SmallVector<uint64_t, 4> BitmapWords;
};

struct GoObjOpenDeferRecord {
  MCContext::GoObjStackMapLocation Bits;
  MCContext::GoObjStackMapLocation Slots;
  uint64_t SlotCount;
};

bool sameStackMapLocation(const MCContext::GoObjStackMapLocation &LHS,
                          const MCContext::GoObjStackMapLocation &RHS) {
  return LHS.Type == RHS.Type && LHS.Size == RHS.Size &&
         LHS.DwarfRegNum == RHS.DwarfRegNum && LHS.Offset == RHS.Offset;
}

bool sameOpenDeferRecord(const GoObjOpenDeferRecord &LHS,
                         const GoObjOpenDeferRecord &RHS) {
  return sameStackMapLocation(LHS.Bits, RHS.Bits) &&
         sameStackMapLocation(LHS.Slots, RHS.Slots) &&
         LHS.SlotCount == RHS.SlotCount;
}

bool sameAllocaPtrMapBase(const GoObjAllocaPtrMapRecord &LHS,
                          const GoObjAllocaPtrMapRecord &RHS) {
  return LHS.Base.Type == RHS.Base.Type && LHS.Base.Size == RHS.Base.Size &&
         LHS.Base.DwarfRegNum == RHS.Base.DwarfRegNum &&
         LHS.Base.Offset == RHS.Base.Offset;
}

bool sameAllocaPtrMapLayout(const GoObjAllocaPtrMapRecord &LHS,
                            const GoObjAllocaPtrMapRecord &RHS) {
  return sameAllocaPtrMapBase(LHS, RHS) && LHS.ByteOffset == RHS.ByteOffset &&
         LHS.ByteSize == RHS.ByteSize && LHS.Alignment == RHS.Alignment &&
         LHS.PointerSize == RHS.PointerSize && LHS.BitCount == RHS.BitCount &&
         LHS.BitmapWords == RHS.BitmapWords;
}

int64_t
getAllocaPtrMapConstant(const MCContext::GoObjStackMapLocation &Location,
                        StringRef Description) {
  if (Location.Type != MCContext::GoObjStackMapLocation::Constant)
    report_fatal_error("GoObj alloca ptrmap " + Description +
                       " is not a constant");
  return Location.Offset;
}

uint64_t getNonnegativeAllocaPtrMapConstant(
    const MCContext::GoObjStackMapLocation &Location, StringRef Description) {
  int64_t Value = getAllocaPtrMapConstant(Location, Description);
  if (Value < 0)
    report_fatal_error("GoObj alloca ptrmap " + Description + " is negative");
  return static_cast<uint64_t>(Value);
}

std::optional<GoObjOpenDeferRecord>
parseOpenDeferRecord(const MCContext::GoObjStackMapEntry &Entry) {
  if (Entry.NumDeoptLocations > Entry.Locations.size())
    report_fatal_error("GoObj statepoint deopt location count is invalid");
  ArrayRef<MCContext::GoObjStackMapLocation> Deopts =
      ArrayRef(Entry.Locations).take_front(Entry.NumDeoptLocations);
  auto IsConstant = [](const auto &Location, int64_t Value) {
    return Location.Type == MCContext::GoObjStackMapLocation::Constant &&
           Location.Offset == Value;
  };

  std::optional<size_t> Begin;
  bool SawEnd = false;
  for (auto [Index, Location] : llvm::enumerate(Deopts)) {
    if (IsConstant(Location, GoObj::OpenDeferBeginMagic)) {
      if (Begin)
        report_fatal_error(
            "GoObj statepoint contains multiple open-defer records");
      Begin = Index;
    }
    SawEnd |= IsConstant(Location, GoObj::OpenDeferEndMagic);
  }
  if (!Begin) {
    if (SawEnd)
      report_fatal_error("GoObj open-defer protocol is truncated");
    return std::nullopt;
  }
  if (*Begin + 2 >= Deopts.size())
    report_fatal_error("GoObj open-defer protocol is truncated");
  uint64_t ProtocolLength = getNonnegativeAllocaPtrMapConstant(
      Deopts[*Begin + 1], "open-defer leading protocol length");
  uint64_t SlotCount = getNonnegativeAllocaPtrMapConstant(
      Deopts[*Begin + 2], "open-defer slot count");
  if (ProtocolLength != 6 || ProtocolLength > Deopts.size() - *Begin - 1)
    report_fatal_error("GoObj open-defer protocol length is invalid");
  size_t End = *Begin + static_cast<size_t>(ProtocolLength) - 1;
  if (!IsConstant(Deopts[End], GoObj::OpenDeferEndMagic) ||
      getNonnegativeAllocaPtrMapConstant(
          Deopts[End + 1], "open-defer trailing protocol length") !=
          ProtocolLength)
    report_fatal_error("GoObj open-defer protocol envelope is malformed");
  if (SlotCount == 0)
    report_fatal_error("GoObj open-defer protocol has no closure slots");

  const auto &Bits = Deopts[*Begin + 3];
  if (Bits.Type != MCContext::GoObjStackMapLocation::Direct)
    report_fatal_error("GoObj open-defer bits is not a direct frame location");
  const auto &Slots = Deopts[*Begin + 4];
  if (Slots.Type != MCContext::GoObjStackMapLocation::Direct)
    report_fatal_error(
        "GoObj open-defer closure slots are not a direct frame location");
  return GoObjOpenDeferRecord{Bits, Slots, SlotCount};
}

SmallVector<GoObjAllocaPtrMapRecord, 4>
parseAllocaPtrMapRecords(const MCContext::GoObjStackMapEntry &Entry) {
  if (Entry.NumDeoptLocations > Entry.Locations.size())
    report_fatal_error("GoObj statepoint deopt location count is invalid");
  ArrayRef<MCContext::GoObjStackMapLocation> Deopts =
      ArrayRef(Entry.Locations).take_front(Entry.NumDeoptLocations);

  auto IsConstant = [](const auto &Location, int64_t Value) {
    return Location.Type == MCContext::GoObjStackMapLocation::Constant &&
           Location.Offset == Value;
  };
  bool HasProtocolMarker = llvm::any_of(Deopts, [&](const auto &Location) {
    return IsConstant(Location, GoObj::AllocaPtrMapBeginMagic) ||
           IsConstant(Location, GoObj::AllocaPtrMapEndMagic);
  });
  if (!HasProtocolMarker)
    return {};
  if (Deopts.size() < 6 ||
      !IsConstant(Deopts[Deopts.size() - 2], GoObj::AllocaPtrMapEndMagic))
    report_fatal_error("GoObj alloca ptrmap protocol is truncated");

  uint64_t ProtocolLength = getNonnegativeAllocaPtrMapConstant(
      Deopts.back(), "trailing protocol length");
  if (ProtocolLength < 4 || ProtocolLength >= Deopts.size())
    report_fatal_error("GoObj alloca ptrmap protocol length is invalid");
  size_t ProtocolStart = Deopts.size() - ProtocolLength - 1;
  if (!IsConstant(Deopts[ProtocolStart], GoObj::AllocaPtrMapBeginMagic) ||
      getNonnegativeAllocaPtrMapConstant(Deopts[ProtocolStart + 1],
                                         "leading protocol length") !=
          ProtocolLength ||
      !IsConstant(Deopts[ProtocolStart + ProtocolLength - 1],
                  GoObj::AllocaPtrMapEndMagic))
    report_fatal_error("GoObj alloca ptrmap protocol envelope is malformed");

  uint64_t RecordCount = getNonnegativeAllocaPtrMapConstant(
      Deopts[ProtocolStart + 2], "record count");
  size_t Cursor = ProtocolStart + 3;
  size_t RecordsEnd = ProtocolStart + ProtocolLength - 1;
  if (RecordCount > (RecordsEnd - Cursor) / 10)
    report_fatal_error("GoObj alloca ptrmap record count is invalid");
  SmallVector<GoObjAllocaPtrMapRecord, 4> Records;
  Records.reserve(static_cast<size_t>(RecordCount));
  for (uint64_t RecordIndex = 0; RecordIndex != RecordCount; ++RecordIndex) {
    if (Cursor > RecordsEnd || RecordsEnd - Cursor < 10)
      report_fatal_error("GoObj alloca ptrmap record header is malformed");
    if (!IsConstant(Deopts[Cursor], GoObj::AllocaPtrMapRecordTag))
      report_fatal_error("GoObj alloca ptrmap record tag is invalid");
    uint64_t RecordLength =
        getNonnegativeAllocaPtrMapConstant(Deopts[Cursor + 1], "record length");
    uint64_t WordCount = getNonnegativeAllocaPtrMapConstant(
        Deopts[Cursor + 9], "bitmap word count");
    if (WordCount > RecordsEnd - Cursor - 10 ||
        RecordLength != 10 + WordCount || RecordLength > RecordsEnd - Cursor)
      report_fatal_error("GoObj alloca ptrmap record length is invalid");

    const auto &Base = Deopts[Cursor + 2];
    if (Base.Type != MCContext::GoObjStackMapLocation::Direct)
      report_fatal_error(
          "GoObj alloca ptrmap base is not a direct frame location");
    uint64_t WordBits = getNonnegativeAllocaPtrMapConstant(Deopts[Cursor + 8],
                                                           "bitmap word width");
    if (WordBits != GoObj::AllocaPtrMapBitmapWordBits)
      report_fatal_error("GoObj alloca ptrmap bitmap word width is invalid");

    GoObjAllocaPtrMapRecord Record{
        Base,
        getNonnegativeAllocaPtrMapConstant(Deopts[Cursor + 3], "byte offset"),
        getNonnegativeAllocaPtrMapConstant(Deopts[Cursor + 4], "byte size"),
        getNonnegativeAllocaPtrMapConstant(Deopts[Cursor + 5], "alignment"),
        getNonnegativeAllocaPtrMapConstant(Deopts[Cursor + 6], "pointer size"),
        getNonnegativeAllocaPtrMapConstant(Deopts[Cursor + 7], "bit count"),
        {}};
    Record.BitmapWords.reserve(WordCount);
    for (uint64_t Word = 0; Word != WordCount; ++Word)
      Record.BitmapWords.push_back(static_cast<uint64_t>(
          getAllocaPtrMapConstant(Deopts[Cursor + 10 + Word], "bitmap word")));
    Records.push_back(std::move(Record));
    Cursor += RecordLength;
  }
  if (Cursor != RecordsEnd)
    report_fatal_error(
        "GoObj alloca ptrmap record count does not cover protocol payload");
  return Records;
}

GoObjStatepointStackMaps makeStatepointStackMaps(
    const MCAssembler &Asm, const GoObjSymbol &Function, uint32_t StackSize,
    uint32_t ArgSize, uint32_t PCQuantum,
    ArrayRef<MCContext::GoObjStackMapEntry> StackMapEntries,
    ArrayRef<GoObjPCTabEntry> PCSPEntries) {
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
  const Triple &TT = Asm.getContext().getTargetTriple();
  bool HasFramePointer = Asm.getContext()
                             .getGoObjSymbolHasFramePointer(Function.Symbol)
                             .value_or(false);
  GoObjGCFrameLayout FrameLayout =
      getGoObjGCFrameLayout(TT, StackSize, PointerSize, HasFramePointer);
  uint16_t StackPointerDwarfRegNum = getGoObjStackPointerDwarfReg(TT);
  auto NormalizeFrameLocation = [&](MCContext::GoObjStackMapLocation Location) {
    // X86 register allocation may keep a statepoint spill addressed from
    // RBP. In a Go frame RBP is frame.varp, at SP+StackSize-PointerSize.
    // Normalize it to the SP-relative coordinate system used by Go maps.
    constexpr uint16_t X86FramePointerDwarfRegNum = 6;
    if (TT.getArch() == Triple::x86_64 && HasFramePointer &&
        Location.DwarfRegNum == X86FramePointerDwarfRegNum) {
      Location.DwarfRegNum = StackPointerDwarfRegNum;
      Location.Offset += FrameLayout.StackObjectVarpOffset;
    }
    return Location;
  };
  uint32_t NBits = checkedUint32(
      FrameLayout.GCLocalsBitOffset +
          divideCeil(static_cast<uint64_t>(FrameLayout.GCLocalsSize),
                     PointerSize),
      "GoObj locals stack map bit count");
  if (ArgSize % PointerSize != 0)
    report_fatal_error("GoObj argument area is not pointer-aligned");
  uint32_t ArgsNBits = ArgSize / PointerSize;
  size_t LocalsBytesPerBitmap = divideCeil(NBits, 8u);
  size_t ArgsBytesPerBitmap = divideCeil(ArgsNBits, 8u);
  uint64_t OrdinaryArgsStart =
      static_cast<uint64_t>(StackSize) + FrameLayout.EntryArgsStart;
  struct FunctionAllocaRecord {
    GoObjAllocaPtrMapRecord Layout;
    goobj::StackMapSlotKind Kind;
    uint64_t SeenOrdinaryEntries = 0;
    bool SawUnmatchedGCLive = false;
  };
  SmallVector<FunctionAllocaRecord, 4> FunctionAllocaRecords;
  uint64_t OrdinaryEntryCount =
      llvm::count_if(ResolvedEntries, [](const ResolvedEntry &Resolved) {
        return Resolved.Entry->ID != GoObj::EntryArgsStackMapID;
      });
  std::optional<GoObjOpenDeferRecord> FunctionOpenDefer;
  uint64_t OpenDeferEntryCount = 0;
  for (const ResolvedEntry &Resolved : ResolvedEntries) {
    std::optional<GoObjOpenDeferRecord> Record =
        parseOpenDeferRecord(*Resolved.Entry);
    if (Resolved.Entry->ID == GoObj::EntryArgsStackMapID) {
      if (Record)
        report_fatal_error("GoObj entry metadata contains open-defer state");
      continue;
    }
    if (!Record)
      continue;
    ++OpenDeferEntryCount;
    Record->Bits = NormalizeFrameLocation(Record->Bits);
    Record->Slots = NormalizeFrameLocation(Record->Slots);
    auto IsDirectSPAddress = [&](const auto &Location) {
      return Location.Type == MCContext::GoObjStackMapLocation::Direct &&
             Location.Size == PointerSize &&
             Location.DwarfRegNum == StackPointerDwarfRegNum &&
             Location.Offset >= 0;
    };
    if (!IsDirectSPAddress(Record->Bits) || !IsDirectSPAddress(Record->Slots))
      report_fatal_error(
          "GoObj open-defer state is not a pointer-sized SP location");
    if (!FunctionOpenDefer)
      FunctionOpenDefer = std::move(*Record);
    else if (!sameOpenDeferRecord(*FunctionOpenDefer, *Record))
      report_fatal_error(
          "GoObj open-defer frame locations change between statepoints");
  }
  if (FunctionOpenDefer && OpenDeferEntryCount != OrdinaryEntryCount)
    report_fatal_error(
        "GoObj open-defer frame state is missing from an ordinary statepoint");

  SmallString<0> OpenDeferData;
  if (FunctionOpenDefer) {
    int64_t VarpOffset =
        static_cast<int64_t>(FrameLayout.StackObjectVarpOffset);
    auto OffsetBelowVarp = [&](int64_t Offset, StringRef Description) {
      if (Offset >= VarpOffset)
        report_fatal_error(Twine("GoObj open-defer ") + Description +
                           " is not below varp");
      return static_cast<uint64_t>(VarpOffset - Offset);
    };
    int64_t FirstSlotOffset = FunctionOpenDefer->Slots.Offset;
    if (FunctionOpenDefer->SlotCount == 0 ||
        FunctionOpenDefer->SlotCount >
            static_cast<uint64_t>(std::numeric_limits<int64_t>::max()) /
                PointerSize)
      report_fatal_error(
          "GoObj open-defer closure slots do not fit below varp");
    int64_t SlotBytes =
        static_cast<int64_t>(FunctionOpenDefer->SlotCount * PointerSize);
    if (FirstSlotOffset > VarpOffset - SlotBytes)
      report_fatal_error(
          "GoObj open-defer closure slots do not fit below varp");
    appendUvarint(OpenDeferData,
                  OffsetBelowVarp(FunctionOpenDefer->Bits.Offset, "bits"));
    appendUvarint(OpenDeferData,
                  OffsetBelowVarp(FirstSlotOffset, "first slot"));
  }

  auto BuildPair = [&](const MCContext::GoObjStackMapEntry &Entry) {
    bool IsEntryArgs = Entry.ID == GoObj::EntryArgsStackMapID;
    GoObjStackMapPair Pair{SmallVector<uint8_t, 8>(ArgsBytesPerBitmap, 0),
                           SmallVector<uint8_t, 8>(LocalsBytesPerBitmap, 0)};
    SmallVector<std::pair<int64_t, int64_t>, 4> AllocaRanges;
    DenseSet<uint32_t> AllocaArgsPointerBits;
    DenseSet<uint32_t> AllocaLocalsPointerBits;
    if (Entry.NumDeoptLocations > Entry.Locations.size())
      report_fatal_error("GoObj statepoint deopt location count is invalid");
    ArrayRef<MCContext::GoObjStackMapLocation> GCLiveLocations =
        ArrayRef(Entry.Locations).drop_front(Entry.NumDeoptLocations);
    for (const GoObjAllocaPtrMapRecord &Record :
         parseAllocaPtrMapRecords(Entry)) {
      if (IsEntryArgs)
        report_fatal_error("GoObj entry metadata contains an alloca ptrmap");
      MCContext::GoObjStackMapLocation RecordBase =
          NormalizeFrameLocation(Record.Base);
      if (RecordBase.Size != PointerSize ||
          RecordBase.DwarfRegNum != StackPointerDwarfRegNum)
        report_fatal_error(
            "GoObj alloca ptrmap base is not a pointer-sized SP location");
      if (Record.ByteOffset != 0)
        report_fatal_error(
            "GoObj alloca ptrmap first version requires zero byte offset");
      if (!Record.ByteSize || Record.ByteSize % PointerSize != 0 ||
          Record.PointerSize != PointerSize ||
          Record.BitCount != Record.ByteSize / PointerSize ||
          Record.BitmapWords.size() != divideCeil(Record.BitCount, 64u))
        report_fatal_error("GoObj alloca ptrmap layout is inconsistent");
      if (Record.Alignment < PointerSize || !isPowerOf2_64(Record.Alignment) ||
          RecordBase.Offset < 0 ||
          static_cast<uint64_t>(RecordBase.Offset) % Record.Alignment != 0)
        report_fatal_error("GoObj alloca ptrmap alignment is invalid");
      if (Record.ByteSize >
          static_cast<uint64_t>(std::numeric_limits<int64_t>::max()) -
              static_cast<uint64_t>(RecordBase.Offset))
        report_fatal_error("GoObj alloca ptrmap frame range overflows");
      int64_t RangeStart = RecordBase.Offset;
      int64_t RangeEnd = RangeStart + static_cast<int64_t>(Record.ByteSize);
      for (const auto &[ExistingStart, ExistingEnd] : AllocaRanges) {
        if (RangeStart == ExistingStart && RangeEnd == ExistingEnd)
          report_fatal_error(
              "GoObj alloca ptrmap contains a duplicate frame record");
        if (RangeStart < ExistingEnd && ExistingStart < RangeEnd)
          report_fatal_error(
              "GoObj alloca ptrmap records overlap in one callsite");
      }
      AllocaRanges.push_back({RangeStart, RangeEnd});

      bool IsActive = llvm::any_of(
          GCLiveLocations,
          [&](const MCContext::GoObjStackMapLocation &Location) {
            MCContext::GoObjStackMapLocation Normalized =
                NormalizeFrameLocation(Location);
            return Normalized.Type ==
                       MCContext::GoObjStackMapLocation::Direct &&
                   Normalized.Size == RecordBase.Size &&
                   Normalized.DwarfRegNum == RecordBase.DwarfRegNum &&
                   Normalized.Offset == RecordBase.Offset;
          });

      uint64_t PaddingBits = Record.BitmapWords.size() * 64 - Record.BitCount;
      if (PaddingBits && (Record.BitmapWords.back() >> (64 - PaddingBits)) != 0)
        report_fatal_error(
            "GoObj alloca ptrmap bitmap padding bits are nonzero");
      std::optional<goobj::StackMapSlotKind> RecordKind =
          goobj::classifyOrdinaryStackMapRange(
              RangeStart, Record.ByteSize, PointerSize,
              FrameLayout.GCLocalsStart, FrameLayout.GCLocalsSize,
              FrameLayout.GCLocalsBitOffset, OrdinaryArgsStart, ArgSize);
      if (!RecordKind)
        report_fatal_error(
            "GoObj alloca ptrmap range is not entirely in args or locals");
      bool HasPointer = false;
      for (uint64_t Bit = 0; Bit != Record.BitCount; ++Bit) {
        int64_t SlotOffset =
            RangeStart + static_cast<int64_t>(Bit * PointerSize);
        goobj::StackMapSlot Slot = goobj::classifyOrdinaryStackMapSlot(
            SlotOffset, /*IsIndirect=*/true, PointerSize,
            FrameLayout.GCLocalsStart, FrameLayout.GCLocalsSize,
            FrameLayout.GCLocalsBitOffset, OrdinaryArgsStart, ArgSize);
        assert(Slot.Kind == *RecordKind &&
               "validated alloca range changed frame region");
        if ((Record.BitmapWords[Bit / 64] & (uint64_t(1) << (Bit % 64))) == 0)
          continue;
        HasPointer = true;
        // The layout record is interpretation-free. A matching direct
        // gc-live base means this pointer word is live at this callsite.
        if (IsActive) {
          DenseSet<uint32_t> &AllocaPointerBits =
              Slot.Kind == goobj::StackMapSlotKind::Args
                  ? AllocaArgsPointerBits
                  : AllocaLocalsPointerBits;
          if (!AllocaPointerBits.insert(Slot.Bit).second)
            report_fatal_error(
                "GoObj alloca ptrmap contains a duplicate pointer slot");
          SmallVector<uint8_t, 8> &Bitmap =
              Slot.Kind == goobj::StackMapSlotKind::Args ? Pair.Args
                                                         : Pair.Locals;
          Bitmap[Slot.Bit / 8] |= uint8_t(1u << (Slot.Bit % 8));
        }
      }
      if (!HasPointer)
        report_fatal_error("GoObj alloca ptrmap contains no pointer slots");

      GoObjAllocaPtrMapRecord NormalizedRecord = Record;
      NormalizedRecord.Base = RecordBase;
      auto FunctionRecord = llvm::find_if(
          FunctionAllocaRecords, [&](const FunctionAllocaRecord &Existing) {
            return sameAllocaPtrMapLayout(Existing.Layout, NormalizedRecord);
          });
      if (FunctionRecord == FunctionAllocaRecords.end()) {
        FunctionAllocaRecords.push_back(
            {NormalizedRecord, *RecordKind, 1, !IsActive});
      } else {
        if (FunctionRecord->Kind != *RecordKind)
          report_fatal_error(
              "GoObj alloca ptrmap frame region changes between statepoints");
        ++FunctionRecord->SeenOrdinaryEntries;
        FunctionRecord->SawUnmatchedGCLive |= !IsActive;
      }
    }

    for (const MCContext::GoObjStackMapLocation &RawLoc : GCLiveLocations) {
      MCContext::GoObjStackMapLocation Loc = NormalizeFrameLocation(RawLoc);
      // Statepoint lowering does not allocate a spill slot for a null GC
      // pointer.  A path-sensitive constant fold can therefore leave a null
      // base/derived pair in the stack map even when the original IR operand
      // was not syntactically null.  Null needs neither scanning nor stack
      // relocation, so omit it from the Go pointer maps.  Keep every other
      // non-frame location fail-closed.
      if (goobj::isNullGCLiveLocation(Loc))
        continue;
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
      std::optional<SmallVector<int64_t, 4>> PointerWordOffsets =
          goobj::expandStackMapPointerWords(
              Loc.Offset, Loc.Size,
              Loc.Type == MCContext::GoObjStackMapLocation::Indirect,
              PointerSize);
      if (!PointerWordOffsets || Loc.DwarfRegNum != StackPointerDwarfRegNum)
        report_fatal_error(
            Twine("GoObj statepoint in ") + Function.Name +
            " contains an invalid pointer stack slot: size=" + Twine(Loc.Size) +
            ", dwarf-reg=" + Twine(Loc.DwarfRegNum) +
            ", offset=" + Twine(Loc.Offset));

      for (int64_t WordOffset : *PointerWordOffsets) {
        if (IsEntryArgs) {
          std::optional<uint32_t> Bit = goobj::classifyEntryArgsStackMapSlot(
              WordOffset, PointerSize, FrameLayout.EntryArgsStart, ArgSize);
          if (Loc.Type != MCContext::GoObjStackMapLocation::Indirect || !Bit)
            report_fatal_error(
                "GoObj entry argument stack map contains an invalid argument "
                "pointer slot");
          Pair.Args[*Bit / 8] |= uint8_t(1u << (*Bit % 8));
          continue;
        }
        goobj::StackMapSlot Slot = goobj::classifyOrdinaryStackMapSlot(
            WordOffset, Loc.Type == MCContext::GoObjStackMapLocation::Indirect,
            PointerSize, FrameLayout.GCLocalsStart, FrameLayout.GCLocalsSize,
            FrameLayout.GCLocalsBitOffset, OrdinaryArgsStart, ArgSize);
        switch (Slot.Kind) {
        case goobj::StackMapSlotKind::Invalid:
          report_fatal_error(
              "GoObj ordinary statepoint contains an invalid pointer stack "
              "slot");
        case goobj::StackMapSlotKind::Direct:
          // Direct describes the pointer value SP+Offset, not a pointer stored
          // at SP+Offset. Statepoint lowering rematerializes that address after
          // stack movement; neither the locals nor args bitmap should scan the
          // slot's contents.
          break;
        case goobj::StackMapSlotKind::Args:
          if (AllocaArgsPointerBits.contains(Slot.Bit))
            report_fatal_error(
                "GoObj alloca ptrmap overlaps an ordinary GC root slot");
          Pair.Args[Slot.Bit / 8] |= uint8_t(1u << (Slot.Bit % 8));
          break;
        case goobj::StackMapSlotKind::Locals:
          if (AllocaLocalsPointerBits.contains(Slot.Bit))
            report_fatal_error(
                "GoObj alloca ptrmap overlaps an ordinary GC root slot");
          Pair.Locals[Slot.Bit / 8] |= uint8_t(1u << (Slot.Bit % 8));
          break;
        }
      }
    }
    return Pair;
  };

  const ResolvedEntry *EntryArgsEntry = nullptr;
  for (const ResolvedEntry &Resolved : ResolvedEntries) {
    if (Resolved.Entry->ID == GoObj::EntryArgsStackMapID) {
      if (EntryArgsEntry)
        report_fatal_error(
            "GoObj function contains multiple entry argument stack maps");
      EntryArgsEntry = &Resolved;
      continue;
    }
  }
  if (!EntryArgsEntry)
    report_fatal_error("GoObj function has no entry argument stack map");
  if (EntryArgsEntry->Entry->IsIndirectCall)
    report_fatal_error("GoObj entry argument stack map is a callsite");

  SmallVector<GoObjStackMapPair, 8> Pairs;
  Pairs.push_back(BuildPair(*EntryArgsEntry->Entry));
  SmallVector<GoObjPCTabEntry, 16> PCDataEntries;
  // PCSP is derived from the Machine CFG. Whenever control flow returns to
  // the entry stack depth, restore Go's entry value (-1). The runtime
  // normalizes that value to ArgsPointerMaps bitmap 0. This covers the
  // pre-frame morestack slow path without naming the helper or manufacturing
  // a statepoint for its raw ABI0 call.
  for (const GoObjPCTabEntry &Entry : PCSPEntries)
    if (Entry.Value == 0 && Entry.PC < Function.Size)
      PCDataEntries.push_back({Entry.PC, -1});
  std::optional<uint64_t> PreviousCallsitePC;
  SmallVector<uint32_t, 4> IndirectCallOffsets;
  for (const ResolvedEntry &Resolved : ResolvedEntries) {
    if (Resolved.Entry->ID == GoObj::EntryArgsStackMapID)
      continue;
    if (PreviousCallsitePC && *PreviousCallsitePC == Resolved.CallsitePC)
      report_fatal_error("GoObj statepoint callsites have duplicate PCs");
    PreviousCallsitePC = Resolved.CallsitePC;
    const MCContext::GoObjStackMapEntry &Entry = *Resolved.Entry;
    if (Entry.IsIndirectCall) {
      if (Resolved.CallsitePC >= Function.Size)
        report_fatal_error(
            "GoObj indirect statepoint callsite is outside its function");
      IndirectCallOffsets.push_back(checkedUint32(
          Resolved.CallsitePC, "GoObj indirect statepoint callsite offset"));
    }
    if (Entry.PointerSize != PointerSize)
      report_fatal_error(
          "GoObj statepoint pointer size changes within a function");
    GoObjStackMapPair Pair = BuildPair(Entry);
    auto It = llvm::find(Pairs, Pair);
    uint32_t MapIndex;
    if (It == Pairs.end()) {
      MapIndex = checkedUint32(Pairs.size(), "GoObj stack map index");
      Pairs.push_back(std::move(Pair));
    } else {
      MapIndex = checkedUint32(It - Pairs.begin(), "GoObj stack map index");
    }
    if (MapIndex > static_cast<uint32_t>(std::numeric_limits<int32_t>::max()))
      report_fatal_error("GoObj stack map index exceeds int32 limit");

    // GoObj records statepoint callsites at the beginning of the CALL. The
    // live-out map remains in effect until another statepoint or a CFG-derived
    // return to the entry stack depth changes it.
    PCDataEntries.push_back(
        {Resolved.CallsitePC, static_cast<int32_t>(MapIndex)});
  }

  SmallVector<GoObjStatepointStackMaps::StackObject, 4> FunctionStackObjects;
  for (const FunctionAllocaRecord &FunctionRecord : FunctionAllocaRecords) {
    if (!FunctionRecord.SawUnmatchedGCLive)
      continue;
    if (FunctionRecord.SeenOrdinaryEntries != OrdinaryEntryCount)
      report_fatal_error(
          "GoObj stack object layout is missing from a function statepoint");

    const GoObjAllocaPtrMapRecord &Record = FunctionRecord.Layout;
    std::optional<int32_t> FrameOffset = goobj::getStackObjectFrameOffset(
        FunctionRecord.Kind, Record.Base.Offset,
        FrameLayout.StackObjectVarpOffset, OrdinaryArgsStart);
    if (!FrameOffset)
      report_fatal_error(
          "GoObj stack object cannot be represented relative to argp or varp");
    if (Record.ByteSize >
        static_cast<uint64_t>(std::numeric_limits<int32_t>::max()))
      report_fatal_error("GoObj stack object size exceeds int32");
    uint64_t HighestPointerBit = 0;
    for (uint64_t Bit = 0; Bit != Record.BitCount; ++Bit)
      if (Record.BitmapWords[Bit / 64] & (uint64_t(1) << (Bit % 64)))
        HighestPointerBit = Bit;
    uint64_t PointerBytes = (HighestPointerBit + 1) * PointerSize;
    if (PointerBytes > Record.ByteSize ||
        PointerBytes >
            static_cast<uint64_t>(std::numeric_limits<int32_t>::max()))
      report_fatal_error("GoObj stack object pointer bytes are invalid");
    size_t BitmapBytes = divideCeil(PointerBytes / PointerSize, 8u);
    size_t PaddedBitmapBytes = alignTo(BitmapBytes, PointerSize);
    SmallVector<uint8_t, 8> Bitmap(PaddedBitmapBytes, 0);
    for (uint64_t Bit = 0; Bit <= HighestPointerBit; ++Bit)
      if (Record.BitmapWords[Bit / 64] & (uint64_t(1) << (Bit % 64)))
        Bitmap[Bit / 8] |= uint8_t(1u << (Bit % 8));
    FunctionStackObjects.push_back(
        {*FrameOffset,
         checkedUint32(Record.ByteSize, "GoObj stack object size"),
         checkedUint32(PointerBytes, "GoObj stack object pointer bytes"),
         std::move(Bitmap)});
  }
  llvm::sort(FunctionStackObjects, [](const auto &LHS, const auto &RHS) {
    return LHS.FrameOffset < RHS.FrameOffset;
  });

  SmallVector<SmallVector<uint8_t, 8>, 8> ArgsBitmaps;
  SmallVector<SmallVector<uint8_t, 8>, 8> LocalsBitmaps;
  ArgsBitmaps.reserve(Pairs.size());
  LocalsBitmaps.reserve(Pairs.size());
  for (GoObjStackMapPair &Pair : Pairs) {
    ArgsBitmaps.push_back(std::move(Pair.Args));
    LocalsBitmaps.push_back(std::move(Pair.Locals));
  }
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
  Result.Args = makeStackMap(ArgsNBits, ArgsBitmaps);
  Result.Locals = makeStackMap(NBits, LocalsBitmaps);
  Result.PCData =
      makePCTab(-1, NormalizedPCDataEntries, Function.Size, PCQuantum);
  Result.OpenDefer = std::move(OpenDeferData);
  Result.IndirectCallOffsets = std::move(IndirectCallOffsets);
  Result.StackObjects = std::move(FunctionStackObjects);
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

uint32_t recordFunctionFile(GoObjFuncDebugLines &Info,
                            uint32_t ObjectFileIndex) {
  if (!llvm::is_contained(Info.Files, ObjectFileIndex))
    Info.Files.push_back(ObjectFileIndex);
  // PCDATA_File indexes the CU-wide file block. FuncInfo.File only catalogs
  // the subset referenced by this function.
  return ObjectFileIndex;
}

uint32_t addAuxCarrierSymbol(std::vector<GoObjSymbol> &Symbols,
                             GoObj::DefinedSymbolBlock Block,
                             ArrayRef<char> Data) {
  GoObjSymbol Sym;
  Sym.DefinedBlock = Block;
  // Match cmd/internal/obj's anonymous auxiliary symbols. These records are
  // addressed by their GoObj indexes, not by name, and therefore use ABI0.
  // Marking an unnamed symbol static makes the Go linker treat it as a
  // file-local symbol; external linking then cannot omit it from the ELF
  // symbol table and rejects its empty name.
  Sym.ABI = GoObj::SymABI0;
  Sym.Type = GoObj::SRODATA;
  Sym.Align = 1;
  Sym.Size = Data.size();
  Sym.Data.append(Data.begin(), Data.end());
  uint32_t Index = checkedUint32(Symbols.size(), "symbol count");
  Symbols.push_back(std::move(Sym));
  return Index;
}

std::array<uint8_t, GoObj::HashSize> makeGoObjContentHash(char SectionMarker,
                                                          ArrayRef<char> Data) {
  SHA256 Hasher;
  const char Version = 1;
  Hasher.update(StringRef(&Version, 1));

  SmallString<9> Header;
  raw_svector_ostream HeaderOS(Header);
  support::endian::Writer HeaderWriter(HeaderOS, llvm::endianness::little);
  HeaderWriter.write<uint64_t>(Data.size());
  HeaderWriter.write<uint8_t>(SectionMarker);
  Hasher.update(StringRef(Header.data(), Header.size()));

  while (!Data.empty() && Data.back() == 0)
    Data = Data.drop_back();
  if (!Data.empty())
    Hasher.update(StringRef(Data.data(), Data.size()));

  std::array<uint8_t, 32> FullHash = Hasher.final();
  std::array<uint8_t, GoObj::HashSize> Hash;
  std::copy_n(FullHash.begin(), Hash.size(), Hash.begin());
  return Hash;
}

std::array<uint8_t, GoObj::HashSize>
makeGoObjContentHash(const GoObjSymbol &Symbol, ArrayRef<GoObjSymbol> Symbols) {
  SHA256 Hasher;
  const char Version = 1;
  Hasher.update(StringRef(&Version, 1));

  SmallString<16> Encoded;
  raw_svector_ostream OS(Encoded);
  support::endian::Writer W(OS, llvm::endianness::little);
  W.write<uint64_t>(Symbol.Size);
  W.write<uint8_t>('F');
  Hasher.update(StringRef(Encoded.data(), Encoded.size()));
  ArrayRef<char> Data(Symbol.Data);
  while (!Data.empty() && Data.back() == 0)
    Data = Data.drop_back();
  if (!Data.empty())
    Hasher.update(StringRef(Data.data(), Data.size()));

  for (const GoObjSymbol::Relocation &Reloc : Symbol.Relocations) {
    Encoded.clear();
    W.write<uint32_t>(Reloc.Offset);
    W.write<uint8_t>(Reloc.Size);
    W.write<uint8_t>(checkedUint16(Reloc.Type, "content hash relocation type"));
    W.write<uint64_t>(static_cast<uint64_t>(Reloc.Addend));
    Hasher.update(StringRef(Encoded.data(), Encoded.size()));
    if (!Reloc.TargetSymbolIndex || *Reloc.TargetSymbolIndex >= Symbols.size())
      report_fatal_error(
          "GoObj synthetic hashed relocation has no local target");
    const GoObjSymbol &Target = Symbols[*Reloc.TargetSymbolIndex];
    if (Target.DefinedBlock == GoObj::DefinedSymbolBlock::Hashed64def) {
      if (Target.Data.size() != GoObj::Hash64Size)
        report_fatal_error("GoObj short-hashed target has invalid size");
      const char Kind = 0;
      Hasher.update(StringRef(&Kind, 1));
      Hasher.update(StringRef(Target.Data.data(), Target.Data.size()));
    } else if (Target.DefinedBlock == GoObj::DefinedSymbolBlock::Hasheddef) {
      if (!Target.ContentHash)
        report_fatal_error("GoObj hashed target has no content hash");
      const char Kind = 1;
      Hasher.update(StringRef(&Kind, 1));
      Hasher.update(ArrayRef<uint8_t>(*Target.ContentHash));
    } else {
      report_fatal_error(
          "GoObj synthetic hashed relocation target is not content-addressed");
    }
  }

  std::array<uint8_t, 32> FullHash = Hasher.final();
  std::array<uint8_t, GoObj::HashSize> Hash;
  std::copy_n(FullHash.begin(), Hash.size(), Hash.begin());
  return Hash;
}

uint32_t getOrAddHashedAuxCarrierSymbol(std::vector<GoObjSymbol> &Symbols,
                                        StringMap<uint32_t> &CarrierIndexes,
                                        char SectionMarker,
                                        ArrayRef<char> Data) {
  std::string Key;
  Key.reserve(Data.size() + 1);
  Key.push_back(SectionMarker);
  if (!Data.empty())
    Key.append(Data.data(), Data.size());
  auto It = CarrierIndexes.find(Key);
  if (It != CarrierIndexes.end())
    return It->second;

  GoObjSymbol Sym;
  Sym.DefinedBlock = GoObj::DefinedSymbolBlock::Hasheddef;
  Sym.ABI = GoObj::SymABI0;
  Sym.Type = GoObj::SRODATA;
  Sym.Align = 1;
  Sym.Size = Data.size();
  Sym.Data.append(Data.begin(), Data.end());
  Sym.ContentHash = makeGoObjContentHash(SectionMarker, Data);
  uint32_t Index = checkedUint32(Symbols.size(), "symbol count");
  Symbols.push_back(std::move(Sym));
  CarrierIndexes.insert({Key, Index});
  return Index;
}

uint32_t getOrAddGCBitmapCarrierSymbol(std::vector<GoObjSymbol> &Symbols,
                                       StringMap<uint32_t> &CarrierIndexes,
                                       uint32_t PointerSize,
                                       ArrayRef<uint8_t> Bitmap) {
  if (Bitmap.empty() || Bitmap.size() % PointerSize != 0)
    report_fatal_error("GoObj stack-object GC bitmap has invalid size");
  StringRef Bytes(reinterpret_cast<const char *>(Bitmap.data()), Bitmap.size());
  std::string Key = (Twine(PointerSize) + ":" + Bytes).str();
  auto It = CarrierIndexes.find(Key);
  if (It != CarrierIndexes.end())
    return It->second;

  GoObjSymbol Sym;
  Sym.DefinedBlock = Bitmap.size() == GoObj::Hash64Size
                         ? GoObj::DefinedSymbolBlock::Hashed64def
                         : GoObj::DefinedSymbolBlock::Hasheddef;
  // Match cmd/compile's reflectdata.GCSym identity. Besides making object
  // inspection useful, the Go linker uses the runtime.gcbits prefix to group
  // these content-addressed symbols into its dedicated GC-bitmap section.
  Sym.Name = "runtime.gcbits." + toHex(Bitmap, /*LowerCase=*/true);
  Sym.ABI = GoObj::SymABI0;
  Sym.Type = GoObj::SRODATA;
  Sym.Flag = GoObj::SymFlagDupok | GoObj::SymFlagLocal;
  Sym.Align = PointerSize;
  Sym.Size = Bitmap.size();
  Sym.Data.append(Bytes.begin(), Bytes.end());
  if (Sym.DefinedBlock == GoObj::DefinedSymbolBlock::Hasheddef)
    Sym.ContentHash = makeGoObjContentHash(0, Sym.Data);
  uint32_t Index = checkedUint32(Symbols.size(), "symbol count");
  Symbols.push_back(std::move(Sym));
  CarrierIndexes.insert({Key, Index});
  return Index;
}

uint32_t addStackObjectCarrierSymbol(
    std::vector<GoObjSymbol> &Symbols, StringMap<uint32_t> &BitmapIndexes,
    uint32_t PointerSize,
    ArrayRef<GoObjStatepointStackMaps::StackObject> StackObjects) {
  if (StackObjects.empty())
    report_fatal_error("cannot emit an empty GoObj stack-object carrier");
  if (PointerSize != 4 && PointerSize != 8)
    report_fatal_error("unsupported GoObj stack-object pointer size");

  GoObjSymbol Sym;
  Sym.DefinedBlock = GoObj::DefinedSymbolBlock::Hasheddef;
  Sym.ABI = GoObj::SymABI0;
  Sym.Type = GoObj::SRODATA;
  Sym.Align = 4;
  raw_svector_ostream OS(Sym.Data);
  support::endian::Writer W(OS, llvm::endianness::little);
  if (PointerSize == 8)
    W.write<uint64_t>(StackObjects.size());
  else
    W.write<uint32_t>(
        checkedUint32(StackObjects.size(), "GoObj stack-object count"));
  for (const GoObjStatepointStackMaps::StackObject &Object : StackObjects) {
    W.write<uint32_t>(static_cast<uint32_t>(Object.FrameOffset));
    W.write<uint32_t>(Object.ByteSize);
    W.write<uint32_t>(Object.PointerBytes);
    uint32_t RelocOffset =
        checkedUint32(Sym.Data.size(), "GoObj stack-object relocation");
    W.write<uint32_t>(0);
    uint32_t BitmapIndex = getOrAddGCBitmapCarrierSymbol(
        Symbols, BitmapIndexes, PointerSize, Object.Bitmap);
    GoObjSymbol::Relocation Reloc;
    Reloc.Offset = RelocOffset;
    Reloc.Size = 4;
    Reloc.Type = GoObj::R_ADDROFF;
    Reloc.TargetSymbolIndex = BitmapIndex;
    Sym.Relocations.push_back(Reloc);
  }
  Sym.Size = Sym.Data.size();
  Sym.ContentHash = makeGoObjContentHash(Sym, Symbols);
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
                             const MCGoObjObjectWriterConfig &Config,
                             StringRef CgoPragmas) {
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

  if (!CgoPragmas.empty()) {
    if (Config.SourceKind == GoObj::SourceKind::Compiler)
      OS << '\n';
    OS << "\n$$\n\n$$\n\n";
    OS << "\n$$  // cgo\n" << CgoPragmas << '\n';
    OS << "\n$$\n\n";
  }

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
  GoObjRelocationEntry Reloc{
      Target.getAddSym(), Target.getSubSym(), F.getParent(),
      Asm->getFragmentOffset(F) + Fixup.getOffset(),
      TargetObjectWriter->getRelocAddend(Target, Fixup),
      TargetObjectWriter->getRelocType(Target, Fixup), RelocSize,
      Fixup.isPCRel(), unsigned(Fixup.getKind())};
  Relocations.push_back(Reloc);
  FixedValue = 0;
}

uint64_t GoObjObjectWriter::writeObject() {
  const uint64_t StartOffset = OS.tell();

  StringRef ABI0Suffix = GoObj::ABI0SymbolSuffix;
  StringRef BuiltinPrefix = GoObj::BuiltinSymbolSuffixPrefix;
  StringRef LinknameSuffix = GoObj::LinknameSymbolSuffix;
  struct GoObjSymbolIdentity {
    StringRef Name;
    std::optional<uint32_t> BuiltinIndex;
    bool IsLinknameRef = false;
    bool IsABI0 = false;
  };
  auto GetSymbolIdentity = [&](const MCSymbol *Sym) {
    if (!Sym)
      return GoObjSymbolIdentity{};
    StringRef Name = Sym->getName();
    bool IsABI0 = Name.consume_back(ABI0Suffix);
    if (IsABI0 && (Name.empty() || Name.ends_with(ABI0Suffix)))
      report_fatal_error("invalid Go ABI0 symbol name");

    bool IsLinknameRef = Name.consume_back(LinknameSuffix);
    if (Name.contains(LinknameSuffix))
      report_fatal_error("invalid Go linkname symbol name");

    std::optional<uint32_t> BuiltinIndex;
    size_t BuiltinBegin = Name.rfind(BuiltinPrefix);
    if (BuiltinBegin != StringRef::npos) {
      StringRef Base = Name.take_front(BuiltinBegin);
      StringRef Index = Name.drop_front(BuiltinBegin + BuiltinPrefix.size());
      if (Base.empty() || Base.contains(BuiltinPrefix) ||
          !Index.consume_back(">") || Index.empty())
        report_fatal_error("invalid Go builtin symbol name");
      uint32_t ParsedIndex = 0;
      if (Index.getAsInteger(10, ParsedIndex))
        report_fatal_error("invalid Go builtin symbol index");
      Name = Base;
      BuiltinIndex = ParsedIndex;
    }
    if (BuiltinIndex && IsLinknameRef)
      report_fatal_error("conflicting Go builtin and linkname symbol identity");
    if ((BuiltinIndex || IsLinknameRef) &&
        (Name.empty() || Name.contains(BuiltinPrefix) ||
         Name.contains(LinknameSuffix)))
      report_fatal_error("invalid Go builtin symbol name");
    return GoObjSymbolIdentity{Name, BuiltinIndex, IsLinknameRef, IsABI0};
  };
  auto GetSymbolName = [&](const MCSymbol *Sym) -> StringRef {
    return GetSymbolIdentity(Sym).Name;
  };
  auto GetSymbolABI = [&](const MCSymbol *Sym, bool IsFunction) {
    if (GetSymbolIdentity(Sym).IsABI0) {
      if (!IsFunction)
        report_fatal_error("Go ABI0 suffix requires a function symbol");
      return GoObj::SymABI0;
    }
    return IsFunction ? GoObj::SymABIInternal : GoObj::SymABI0;
  };

  std::vector<GoObjSymbol> Symbols;
  DenseSet<const MCSymbol *> SeenPrivateRelocationTargets;
  SmallVector<const MCSymbol *, 8> PrivateRelocationTargets;
  for (const GoObjRelocationEntry &Reloc : Relocations) {
    if (Reloc.Symbol && Reloc.Symbol->isTemporary() &&
        Reloc.Symbol->isInSection() &&
        SeenPrivateRelocationTargets.insert(Reloc.Symbol).second)
      PrivateRelocationTargets.push_back(Reloc.Symbol);
  }

  for (const MCSymbol &Symbol : Asm->symbols()) {
    if (!Symbol.isCommon())
      continue;
    GoObjSymbolIdentity Identity = GetSymbolIdentity(&Symbol);
    if (Identity.BuiltinIndex || Identity.IsLinknameRef)
      report_fatal_error(
          "Go builtin and linkname suffixes require an undefined symbol");
    if (Identity.IsABI0)
      report_fatal_error("Go ABI0 suffix requires a function symbol");
    GoObjSymbol GoSym;
    GoSym.Name = Identity.Name.str();
    GoSym.Symbol = &Symbol;
    GoSym.DefinedBlock = Asm->getContext().isGoObjSymbolNonPackage(&Symbol)
                             ? GoObj::DefinedSymbolBlock::Nonpkgdef
                             : Config.DefaultDefinedSymbolBlock;
    GoSym.ABI = GoObj::SymABIstatic;
    GoSym.Type = GoObj::SBSS;
    GoSym.Size = Symbol.getCommonSize();
    if (MaybeAlign Alignment = Symbol.getCommonAlignment())
      GoSym.Align = checkedUint32(Alignment->value(), "common alignment");
    Symbols.push_back(std::move(GoSym));
  }

  for (const MCSection &Section : *Asm) {
    uint64_t SectionSize = Asm->getSectionAddressSize(Section);
    const size_t FirstSectionSymbol = Symbols.size();

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

    bool HasReferencedPrivateSymbol =
        llvm::any_of(PrivateRelocationTargets, [&](const MCSymbol *MCSym) {
          return &MCSym->getSection() == &Section;
        });
    if (SectionSize == 0 && SectionSymbols.empty() &&
        !HasReferencedPrivateSymbol)
      continue;

    auto AddSectionSymbol = [&](const MCSymbol *MCSym, StringRef Name,
                                uint64_t Begin, uint64_t End) {
      if (MCSym) {
        GoObjSymbolIdentity Identity = GetSymbolIdentity(MCSym);
        if (Identity.BuiltinIndex || Identity.IsLinknameRef)
          report_fatal_error(
              "Go builtin and linkname suffixes require an undefined symbol");
      }
      uint64_t Size = End - Begin;
      ArrayRef<char> Data;
      if (!Section.isBssSection() && Size != 0) {
        if (End > Contents.size())
          report_fatal_error("GoObj section data is smaller than its layout");
        Data = ArrayRef<char>(Contents.data() + Begin, Size);
      }
      uint8_t Type = getGoObjSymbolType(&Section);
      uint16_t ABI = GetSymbolABI(
          MCSym, MCSym && Asm->getContext().isGoObjFunctionSymbol(MCSym));
      uint8_t Flag = 0;
      uint8_t Flag2 = 0;
      uint32_t Align = 0;
      if (MCSym) {
        if (std::optional<std::pair<uint8_t, uint8_t>> Flags =
                Asm->getContext().getGoObjSymbolFlags(MCSym)) {
          Flag = Flags->first;
          Flag2 = Flags->second;
        }
        Align = Asm->getContext().getGoObjSymbolAlignment(MCSym).value_or(0);
      }
      GoObj::DefinedSymbolBlock DefinedBlock =
          MCSym && Asm->getContext().isGoObjSymbolNonPackage(MCSym)
              ? GoObj::DefinedSymbolBlock::Nonpkgdef
              : Config.DefaultDefinedSymbolBlock;
      addDefinedSymbol(Symbols, MCSym, &Section, Begin, End, DefinedBlock, Name,
                       Type, Flag, Flag2, ABI, Size, Align, Data);
      if (MCSym) {
        StringRef Hash = Asm->getContext().getGoObjSymbolContentHash(MCSym);
        if (Hash.size() == GoObj::Hash64Size) {
          Symbols.back().DefinedBlock = GoObj::DefinedSymbolBlock::Hashed64def;
          std::array<uint8_t, GoObj::Hash64Size> Value;
          std::copy(Hash.bytes_begin(), Hash.bytes_end(), Value.begin());
          Symbols.back().ContentHash64 = Value;
        } else if (Hash.size() == GoObj::HashSize) {
          Symbols.back().DefinedBlock = GoObj::DefinedSymbolBlock::Hasheddef;
          std::array<uint8_t, GoObj::HashSize> Value;
          std::copy(Hash.bytes_begin(), Hash.bytes_end(), Value.begin());
          Symbols.back().ContentHash = Value;
        } else if (!Hash.empty()) {
          report_fatal_error("invalid GoObj content-addressable hash size");
        }
      }
    };

    if (SectionSymbols.empty() && SectionSize != 0) {
      AddSectionSymbol(nullptr, Section.getName(), 0, SectionSize);
    } else if (!SectionSymbols.empty()) {
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
          if (*ExactSize > SectionSize - Begin || Begin + *ExactSize > End)
            report_fatal_error(
                "GoObj global size overlaps the next section symbol");
          End = Begin + *ExactSize;
        }
        AddSectionSymbol(SectionSymbols[I].Symbol,
                         GetSymbolName(SectionSymbols[I].Symbol), Begin, End);
      }
    }

    // LLVM private constants are emitted as temporary MC symbols. Usually a
    // surrounding section or global symbol is a sufficient GoObj carrier, but
    // an exact-sized preceding global can leave a private constant in an
    // uncovered section gap. Materialize only referenced, exact-sized,
    // read-only temporaries. This includes zero-sized constants: their empty
    // ranges can never be found by FindContainingSymbol, so relocations must
    // refer to their directly indexed symbols. This is the MC equivalent of
    // the Go compiler's local, content-addressable string/constant symbols.
    if (getGoObjSymbolType(&Section) != GoObj::SRODATA)
      continue;
    for (const MCSymbol *MCSym : PrivateRelocationTargets) {
      if (&MCSym->getSection() != &Section)
        continue;
      uint64_t Begin = Asm->getSymbolOffset(*MCSym);
      bool Covered = false;
      for (size_t I = FirstSectionSymbol; I != Symbols.size(); ++I) {
        const GoObjSymbol &Sym = Symbols[I];
        if (Sym.Section == &Section && Sym.SectionBegin <= Begin &&
            Begin < Sym.SectionEnd) {
          Covered = true;
          break;
        }
      }
      if (Covered)
        continue;

      std::optional<uint64_t> ExactSize =
          Asm->getContext().getGoObjSymbolSize(MCSym);
      if (!ExactSize || *ExactSize > SectionSize - Begin)
        continue;
      uint64_t End = Begin + *ExactSize;
      for (size_t I = FirstSectionSymbol; I != Symbols.size(); ++I) {
        const GoObjSymbol &Sym = Symbols[I];
        if (Sym.Section == &Section && Begin < Sym.SectionEnd &&
            Sym.SectionBegin < End)
          report_fatal_error(
              "GoObj private constant overlaps an existing symbol carrier");
      }

      ArrayRef<char> Data;
      if (*ExactSize != 0)
        Data = ArrayRef<char>(Contents.data() + Begin, *ExactSize);
      uint32_t Align =
          Asm->getContext().getGoObjSymbolAlignment(MCSym).value_or(1);
      addDefinedSymbol(Symbols, MCSym, &Section, Begin, End,
                       GoObj::DefinedSymbolBlock::Hasheddef, MCSym->getName(),
                       GoObj::SRODATA,
                       GoObj::SymFlagDupok | GoObj::SymFlagLocal, 0,
                       GoObj::SymABI0, *ExactSize, Align, Data);
      // The native Go object identity includes relocations as well as data.
      // Compute it after all MC fixups have been assigned to their carriers.
    }
  }

  uint32_t PCQuantum = getGoObjPCQuantum(Asm->getContext().getTargetTriple());
  std::vector<GoObjFuncDebugLines> FuncDebugLines(Symbols.size());
  std::vector<std::string> FilePaths;
  StringMap<uint32_t> FileIndexes;
  StringMap<uint32_t> AuxCarrierIndexes;
  StringMap<uint32_t> GCBitmapCarrierIndexes;
  struct PendingFuncInfoPatch {
    uint32_t CarrierSymbol = 0;
    uint32_t FileCount = 0;
    std::vector<GoObjInlineTreeNode> InlineTree;
  };
  std::vector<PendingFuncInfoPatch> PendingFuncInfoPatches;
  auto GetFallbackFile = [&]() {
    return getOrAddFileIndex(FileIndexes, FilePaths, "llvm-ir");
  };

  if (Config.SourceKind == GoObj::SourceKind::Compiler) {
    auto GetInlineIndex =
        [&](GoObjFuncDebugLines &Info,
            ArrayRef<MCContext::GoObjDebugInlineFrame> Frames) {
          int32_t Parent = -1;
          for (const MCContext::GoObjDebugInlineFrame &Frame : Frames) {
            int32_t Existing = -1;
            for (uint32_t NodeIndex = 0,
                          NodeEnd = checkedUint32(Info.InlineTree.size(),
                                                  "GoObj inline tree size");
                 NodeIndex != NodeEnd; ++NodeIndex) {
              const GoObjInlineTreeNode &Node = Info.InlineTree[NodeIndex];
              if (Node.SiteID != Frame.SiteID)
                continue;
              if (Node.Parent != Parent || Node.Callee != Frame.Callee ||
                  Node.Line != static_cast<int32_t>(Frame.CallLine))
                report_fatal_error("inconsistent GoObj inline site identity");
              Existing = static_cast<int32_t>(NodeIndex);
              break;
            }
            if (Existing >= 0) {
              Parent = Existing;
              continue;
            }

            uint32_t ObjectFileIndex =
                getOrAddFileIndex(FileIndexes, FilePaths, Frame.CallFile);
            recordFunctionFile(Info, ObjectFileIndex);
            GoObjInlineTreeNode Node;
            Node.Parent = Parent;
            Node.File = ObjectFileIndex;
            Node.Line = static_cast<int32_t>(Frame.CallLine);
            Node.Callee = Frame.Callee;
            Node.SiteID = Frame.SiteID;
            Parent = static_cast<int32_t>(Info.InlineTree.size());
            Info.InlineTree.push_back(std::move(Node));
          }
          return Parent;
        };

    // Preserve complete DILocation/inlinedAt chains separately from the
    // flattened MC line table.
    for (uint32_t I = 0, E = checkedUint32(Symbols.size(), "symbol count");
         I != E; ++I) {
      GoObjSymbol &Sym = Symbols[I];
      if (Sym.Type != GoObj::STEXT || Sym.Size == 0 || !Sym.Symbol)
        continue;
      const auto *DebugInfo =
          Asm->getContext().getGoObjFunctionDebugInfo(Sym.Symbol);
      if (!DebugInfo)
        continue;

      GoObjFuncDebugLines &Info = FuncDebugLines[I];
      if (DebugInfo->StartLine != 0)
        Info.StartLine = static_cast<int32_t>(DebugInfo->StartLine);
      if (!DebugInfo->File.empty())
        recordFunctionFile(
            Info, getOrAddFileIndex(FileIndexes, FilePaths, DebugInfo->File));

      for (const MCContext::GoObjDebugLocation &Location :
           DebugInfo->Locations) {
        if (!Location.Label || !Location.Label->isInSection() ||
            &Location.Label->getSection() != Sym.Section)
          report_fatal_error(
              "GoObj debug location is outside its function section");
        uint64_t LabelOffset = Asm->getSymbolOffset(*Location.Label);
        if (LabelOffset < Sym.SectionBegin || LabelOffset >= Sym.SectionEnd)
          report_fatal_error("GoObj debug location is outside its function");
        uint64_t PC = LabelOffset - Sym.SectionBegin;
        if (PC % PCQuantum != 0)
          report_fatal_error("GoObj debug location is not PC-quantum aligned");

        uint32_t FileIndex =
            getOrAddFileIndex(FileIndexes, FilePaths,
                              Location.File.empty() ? StringRef("llvm-ir")
                                                    : StringRef(Location.File));
        recordFunctionFile(Info, FileIndex);
        Info.PCFile.push_back({PC, static_cast<int32_t>(FileIndex)});
        Info.PCLine.push_back({PC, static_cast<int32_t>(Location.Line)});
        Info.PCInline.push_back(
            {PC, GetInlineIndex(Info, Location.InlineFrames)});

        if (!Location.AnchorChildFrames.empty()) {
          int32_t Child = GetInlineIndex(Info, Location.AnchorChildFrames);
          if (Child < 0)
            report_fatal_error("GoObj inline anchor has no child node");
          if (PC > static_cast<uint64_t>(std::numeric_limits<int32_t>::max()))
            report_fatal_error("GoObj inline ParentPC exceeds int32 range");
          GoObjInlineTreeNode &Node = Info.InlineTree[Child];
          if (Node.ParentPC >= 0 && Node.ParentPC != static_cast<int32_t>(PC))
            report_fatal_error(
                "duplicate GoObj inline anchor has conflicting PC");
          Node.ParentPC = static_cast<int32_t>(PC);
        }
      }
      for (const GoObjInlineTreeNode &Node : Info.InlineTree)
        if (Node.ParentPC < 0)
          report_fatal_error(
              "GoObj inline tree node has no final-layout anchor");
    }

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

            // The side table is authoritative when present; consuming both
            // would make same-PC ordering depend on line-table lowering.
            if (Sym.Symbol &&
                Asm->getContext().getGoObjFunctionDebugInfo(Sym.Symbol))
              break;

            std::string Path =
                getDwarfFilePath(LineTable, LineEntry.getFileNum());
            uint32_t ObjectFileIndex =
                getOrAddFileIndex(FileIndexes, FilePaths, Path);
            GoObjFuncDebugLines &Info = FuncDebugLines[I];
            uint32_t CUFileIndex = recordFunctionFile(Info, ObjectFileIndex);
            uint64_t PC = LabelOffset - Sym.SectionBegin;
            int32_t Line = static_cast<int32_t>(LineEntry.getLine());
            Info.PCFile.push_back({PC, static_cast<int32_t>(CUFileIndex)});
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
      uint32_t PointerSize =
          Asm->getContext().getAsmInfo().getCodePointerSize();
      GoObjGCFrameLayout FrameLayout = getGoObjGCFrameLayout(
          Asm->getContext().getTargetTriple(), StackSize, PointerSize,
          Asm->getContext()
              .getGoObjSymbolHasFramePointer(Symbols[I].Symbol)
              .value_or(false));
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
        // Empty blocks can place multiple state transitions at one PC. Keep
        // the final transition, which describes the following emitted code.
        SmallVector<GoObjPCTabEntry, 8> NormalizedPCSPEntries;
        for (const GoObjPCTabEntry &Entry : PCSPEntries) {
          if (!NormalizedPCSPEntries.empty() &&
              NormalizedPCSPEntries.back().PC == Entry.PC)
            NormalizedPCSPEntries.back().Value = Entry.Value;
          else
            NormalizedPCSPEntries.push_back(Entry);
        }
        PCSPEntries = std::move(NormalizedPCSPEntries);
      }

      int32_t InitialUnsafePointValue =
          Asm->getContext().isGoObjSymbolAsyncUnsafe(Symbols[I].Symbol)
              ? GoObj::UnsafePointUnsafe
              : GoObj::UnsafePointSafe;

      GoObjFuncDebugLines &LineInfo = FuncDebugLines[I];
      if (LineInfo.Files.empty())
        recordFunctionFile(LineInfo, GetFallbackFile());
      auto NormalizePCTab = [&](auto &Entries) {
        llvm::stable_sort(Entries, [](const auto &LHS, const auto &RHS) {
          return LHS.PC < RHS.PC;
        });
        using EntriesT = std::decay_t<decltype(Entries)>;
        EntriesT Normalized;
        for (const GoObjPCTabEntry &Entry : Entries) {
          if (!Normalized.empty() && Normalized.back().PC == Entry.PC)
            Normalized.back().Value = Entry.Value;
          else
            Normalized.push_back(Entry);
        }
        Entries = std::move(Normalized);
      };
      NormalizePCTab(LineInfo.PCFile);
      NormalizePCTab(LineInfo.PCLine);
      NormalizePCTab(LineInfo.PCInline);

      auto [FuncID, FuncFlag] =
          Asm->getContext()
              .getGoObjFunctionInfo(Symbols[I].Symbol)
              .value_or(std::make_pair(uint8_t(0), uint8_t(0)));
      uint32_t FuncInfoSym = addAuxCarrierSymbol(
          Symbols, GoObj::DefinedSymbolBlock::Symdef,
          makeFuncInfoData(ArgSize, FrameLayout.FuncInfoLocalsSize, FuncID,
                           FuncFlag, LineInfo.Files, LineInfo.StartLine,
                           LineInfo.InlineTree));
      if (!LineInfo.InlineTree.empty())
        PendingFuncInfoPatches.push_back(
            {FuncInfoSym,
             checkedUint32(LineInfo.Files.size(), "GoObj FuncInfo file count"),
             std::vector<GoObjInlineTreeNode>(LineInfo.InlineTree.begin(),
                                              LineInfo.InlineTree.end())});
      uint32_t PcspSym = getOrAddHashedAuxCarrierSymbol(
          Symbols, AuxCarrierIndexes, 'P',
          PCSPEntries.empty()
              ? makeConstantPCTab(static_cast<int32_t>(StackSize), CodeSize,
                                  PCQuantum)
              : makePCTab(0, PCSPEntries, CodeSize, PCQuantum));
      int32_t InitialFile = LineInfo.hasLines()
                                ? LineInfo.PCFile.front().Value
                                : static_cast<int32_t>(LineInfo.Files.front());
      int32_t InitialLine = LineInfo.hasLines() ? LineInfo.PCLine.front().Value
                                                : LineInfo.StartLine;
      uint32_t PcfileSym = getOrAddHashedAuxCarrierSymbol(
          Symbols, AuxCarrierIndexes, 'P',
          makePCTab(InitialFile, LineInfo.PCFile, CodeSize, PCQuantum));
      uint32_t PclineSym = getOrAddHashedAuxCarrierSymbol(
          Symbols, AuxCarrierIndexes, 'P',
          makePCTab(InitialLine, LineInfo.PCLine, CodeSize, PCQuantum));
      uint32_t PcinlineSym = getOrAddHashedAuxCarrierSymbol(
          Symbols, AuxCarrierIndexes, 'P',
          makePCTab(-1, LineInfo.PCInline, CodeSize, PCQuantum));
      SmallString<0> ArgsMap = makeEmptyStackMap();
      SmallString<0> LocalsMap = makeEmptyStackMap();
      SmallString<0> StackMapIndex = makeConstantPCTab(-1, CodeSize, PCQuantum);
      std::optional<uint32_t> StackObjectsSym;
      std::optional<uint32_t> OpenDeferSym;
      if (const auto *Entries = Asm->getContext().getGoObjSymbolStackMapEntries(
              Symbols[I].Symbol)) {
        if (!Entries->empty()) {
          GoObjStatepointStackMaps Maps = makeStatepointStackMaps(
              *Asm, Symbols[I], StackSize, ArgSize, PCQuantum, *Entries,
              PCSPEntries);
          for (uint32_t Offset : Maps.IndirectCallOffsets)
            Symbols[I].Relocations.push_back({Offset, 0, GoObj::R_CALLIND, 0,
                                              GoObj::PkgIdxInvalid, 0,
                                              std::nullopt});
          ArgsMap = std::move(Maps.Args);
          LocalsMap = std::move(Maps.Locals);
          StackMapIndex = std::move(Maps.PCData);
          if (!Maps.StackObjects.empty())
            StackObjectsSym = addStackObjectCarrierSymbol(
                Symbols, GCBitmapCarrierIndexes,
                Asm->getContext().getAsmInfo().getCodePointerSize(),
                Maps.StackObjects);
          if (!Maps.OpenDefer.empty())
            OpenDeferSym = getOrAddHashedAuxCarrierSymbol(
                Symbols, AuxCarrierIndexes, 'F', Maps.OpenDefer);
        }
      }
      uint32_t ArgsMapSym = getOrAddHashedAuxCarrierSymbol(
          Symbols, AuxCarrierIndexes, 'F', ArgsMap);
      uint32_t LocalsMapSym = getOrAddHashedAuxCarrierSymbol(
          Symbols, AuxCarrierIndexes, 'F', LocalsMap);
      uint32_t StackMapIndexSym = getOrAddHashedAuxCarrierSymbol(
          Symbols, AuxCarrierIndexes, 'P', StackMapIndex);
      uint32_t UnsafePointSym = getOrAddHashedAuxCarrierSymbol(
          Symbols, AuxCarrierIndexes, 'P',
          makeConstantPCTab(InitialUnsafePointValue, CodeSize, PCQuantum));

      Symbols[I].Auxiliaries.push_back({GoObj::AuxFuncInfo, FuncInfoSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxFuncdata, ArgsMapSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxFuncdata, LocalsMapSym});
      if (StackObjectsSym)
        Symbols[I].Auxiliaries.push_back(
            {GoObj::AuxFuncdata, *StackObjectsSym});
      if (OpenDeferSym) {
        if (!StackObjectsSym)
          Symbols[I].Auxiliaries.emplace_back(GoObj::AuxFuncdata,
                                              GoObjSymRef{});
        // FUNCDATA_InlTree is unused by the current runtime, but funcdata is
        // positional and open-coded defer information is slot 4.
        Symbols[I].Auxiliaries.emplace_back(GoObj::AuxFuncdata, GoObjSymRef{});
        Symbols[I].Auxiliaries.push_back({GoObj::AuxFuncdata, *OpenDeferSym});
      }
      Symbols[I].Auxiliaries.push_back({GoObj::AuxPcsp, PcspSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxPcfile, PcfileSym});
      Symbols[I].Auxiliaries.push_back({GoObj::AuxPcline, PclineSym});
      if (!LineInfo.InlineTree.empty())
        Symbols[I].Auxiliaries.push_back({GoObj::AuxPcinline, PcinlineSym});
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

  // Package export data refers to definitions by the indices assigned by the
  // Go frontend. Machine layout may reorder definitions, and optimization can
  // remove compiler-only auxiliary definitions, so rebuild the package block
  // around the explicit indices instead of exposing MC layout order. Empty
  // slots preserve indices for definitions that LLVM does not emit; LLVM-owned
  // auxiliary definitions follow the frontend-owned range.
  DenseMap<uint32_t, uint32_t> IndexedSymdefs;
  std::vector<uint32_t> UnindexedSymdefs;
  std::optional<uint32_t> MaxSymdefIndex;
  for (uint32_t I : SymdefSymbols) {
    std::optional<uint32_t> Index =
        Symbols[I].Symbol
            ? Asm->getContext().getGoObjPackageSymbolIndex(Symbols[I].Symbol)
            : std::nullopt;
    if (!Index) {
      UnindexedSymdefs.push_back(I);
      continue;
    }
    if (*Index == UINT32_MAX)
      report_fatal_error("GoObj package symbol index is too large");
    if (!IndexedSymdefs.try_emplace(*Index, I).second)
      report_fatal_error("duplicate GoObj package symbol index");
    MaxSymdefIndex = std::max(MaxSymdefIndex.value_or(0), *Index);
  }
  if (MaxSymdefIndex) {
    std::vector<uint32_t> OrderedSymdefs;
    OrderedSymdefs.reserve(static_cast<size_t>(*MaxSymdefIndex) + 1 +
                           UnindexedSymdefs.size());
    for (uint32_t Index = 0; Index <= *MaxSymdefIndex; ++Index) {
      auto It = IndexedSymdefs.find(Index);
      if (It != IndexedSymdefs.end()) {
        OrderedSymdefs.push_back(It->second);
        continue;
      }
      GoObjSymbol Placeholder;
      Placeholder.DefinedBlock = GoObj::DefinedSymbolBlock::Symdef;
      Placeholder.Type = GoObj::SRODATA;
      Symbols.push_back(std::move(Placeholder));
      OrderedSymdefs.push_back(
          checkedUint32(Symbols.size() - 1, "symbol count"));
    }
    OrderedSymdefs.insert(OrderedSymdefs.end(), UnindexedSymdefs.begin(),
                          UnindexedSymdefs.end());
    SymdefSymbols = std::move(OrderedSymdefs);
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

  // LLVM keeps suffixed builtin declarations separate from canonical
  // definitions so their function types may differ.  GoObj, however, uses a
  // same-object definition when its canonical name and ABI match.
  StringMap<uint32_t> DefinedSymbolIdentityIndexes;
  for (uint32_t I : DefinedSymbolOrder) {
    const GoObjSymbol &Symbol = Symbols[I];
    if (Symbol.Name.empty())
      continue;
    DefinedSymbolIdentityIndexes.try_emplace(
        (Twine(Symbol.Name) + "#" + Twine(Symbol.ABI)).str(), I);
  }
  auto FindDefinedSymRef = [&](StringRef Name,
                               uint16_t ABI) -> std::optional<GoObjSymRef> {
    auto It =
        DefinedSymbolIdentityIndexes.find((Name + "#" + Twine(ABI)).str());
    if (It == DefinedSymbolIdentityIndexes.end())
      return std::nullopt;
    return DefinedSymRefs[It->second];
  };

  for (GoObjSymbol &Symbol : Symbols) {
    for (GoObjSymbol::Relocation &Reloc : Symbol.Relocations) {
      if (!Reloc.TargetSymbolIndex)
        continue;
      if (*Reloc.TargetSymbolIndex >= DefinedSymRefs.size())
        report_fatal_error(
            "GoObj synthetic relocation target index is invalid");
      GoObjSymRef Ref = DefinedSymRefs[*Reloc.TargetSymbolIndex];
      Reloc.PkgIdx = Ref.PkgIdx;
      Reloc.SymIdx = Ref.SymIdx;
    }
  }

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
  auto GetNonPkgRefSymIdx = [&](const MCSymbol *Sym, bool IsFunction) {
    GoObjSymbolIdentity Identity = GetSymbolIdentity(Sym);
    StringRef Name = Identity.Name;
    if (Name.empty())
      report_fatal_error("GoObj relocation target has an empty name");

    uint16_t ABI = GetSymbolABI(Sym, IsFunction);
    std::string Key = (Name + "#" + Twine(ABI)).str();
    auto It = NonPkgRefIndexes.find(Key);
    if (It != NonPkgRefIndexes.end()) {
      if (Identity.IsLinknameRef)
        NonPkgRefs[It->second - NonpkgdefSymbols.size()].Flag2 |=
            GoObj::SymFlagLinkname;
      return It->second;
    }

    uint32_t SymIdx = checkedUint32(NonpkgdefSymbols.size() + NonPkgRefs.size(),
                                    "non-package reference index");
    NonPkgRefIndexes[Key] = SymIdx;

    GoObjSymbol Ref;
    Ref.Name = Name.str();
    Ref.ABI = ABI;
    if (Identity.IsLinknameRef)
      Ref.Flag2 |= GoObj::SymFlagLinkname;
    NonPkgRefs.push_back(std::move(Ref));
    return SymIdx;
  };

  std::vector<std::string> PackagePrefixes(1, "");
  StringMap<uint32_t> PackageIndexes;
  PackageIndexes[""] = GoObj::PkgIdxInvalid;
  auto GetPackageIndex = [&](StringRef Prefix) {
    if (Prefix.empty())
      report_fatal_error("GoObj imported reference has an empty package");
    auto It = PackageIndexes.find(Prefix);
    if (It != PackageIndexes.end())
      return It->second;
    uint32_t Index =
        checkedUint32(PackagePrefixes.size(), "package index count");
    PackagePrefixes.push_back(Prefix.str());
    PackageIndexes[Prefix] = Index;
    return Index;
  };

  struct IndexedRef {
    GoObjSymRef Ref;
    std::string Name;
    uint8_t Flags2 = 0;
  };
  std::vector<IndexedRef> IndexedRefs;
  DenseMap<uint64_t, uint32_t> IndexedRefIndexes;
  auto TrimInlineHash = [](StringRef Name) {
    // Match cmd/internal/obj.TrimInlineHash. The Go compiler inserts the
    // base64 encoding of an 8-byte inline-call-stack hash between '#'
    // delimiters. RefName is a tooling aid and intentionally omits it.
    constexpr size_t InlineHashLength = 12;
    size_t Begin = Name.find('#');
    if (Begin == StringRef::npos ||
        Name.size() < Begin + InlineHashLength + 2 ||
        Name[Begin + InlineHashLength + 1] != '#')
      return Name.str();
    return (Name.take_front(Begin) +
            Name.drop_front(Begin + InlineHashLength + 2))
        .str();
  };
  auto RecordIndexedRef = [&](GoObjSymRef Ref, StringRef Name, uint8_t Flags2) {
    uint64_t Key = (static_cast<uint64_t>(Ref.PkgIdx) << 32) | Ref.SymIdx;
    auto It = IndexedRefIndexes.find(Key);
    if (It != IndexedRefIndexes.end()) {
      const IndexedRef &Existing = IndexedRefs[It->second];
      if (Existing.Name != Name || Existing.Flags2 != Flags2)
        report_fatal_error("conflicting GoObj indexed symbol reference");
      return;
    }
    IndexedRefIndexes[Key] =
        checkedUint32(IndexedRefs.size(), "indexed reference count");
    IndexedRefs.push_back({Ref, Name.str(), Flags2});
  };

  auto ResolveTargetSymRef = [&](const MCSymbol *Target, unsigned RelocType,
                                 int64_t &Addend) {
    if (!Target)
      report_fatal_error("GoObj relocation without a target symbol");

    if (auto It = DefinedSymbolIndexes.find(Target);
        It != DefinedSymbolIndexes.end())
      return std::make_pair(DefinedSymRefs[It->second],
                            std::optional<uint32_t>(It->second));

    if (Target->isInSection()) {
      uint64_t TargetOffset = Asm->getSymbolOffset(*Target);
      if (std::optional<uint32_t> SymIdx =
              FindContainingSymbol(&Target->getSection(), TargetOffset)) {
        Addend +=
            static_cast<int64_t>(TargetOffset - Symbols[*SymIdx].SectionBegin);
        return std::make_pair(DefinedSymRefs[*SymIdx], SymIdx);
      }
    }

    if (Target->isUndefined()) {
      GoObjSymbolIdentity Identity = GetSymbolIdentity(Target);
      if (const MCContext::GoObjImportedSymbolRef *Metadata =
              Asm->getContext().getGoObjImportedSymbolRef(Target)) {
        if (Identity.BuiltinIndex || Identity.IsLinknameRef)
          report_fatal_error("conflicting GoObj symbol reference identity");
        GoObjSymRef Ref{GetPackageIndex(Metadata->PackagePrefix),
                        Metadata->SymIdx};
        RecordIndexedRef(Ref, TrimInlineHash(Identity.Name), Metadata->Flags2);
        return std::make_pair(Ref, std::optional<uint32_t>());
      }
      bool IsFunction;
      switch (RelocType) {
      case GoObj::R_CALL:
      case GoObj::R_CALLARM:
      case GoObj::R_CALLARM64:
      case GoObj::R_CALLPOWER:
      case GoObj::R_CALLMIPS:
        IsFunction = true;
        break;
      default:
        IsFunction = Asm->getContext().isGoObjFunctionSymbol(Target);
        break;
      }
      if (Identity.BuiltinIndex && !Identity.IsLinknameRef) {
        if (std::optional<GoObjSymRef> Ref = FindDefinedSymRef(
                Identity.Name, GetSymbolABI(Target, IsFunction)))
          return std::make_pair(*Ref, std::optional<uint32_t>());
        return std::make_pair(
            GoObjSymRef{GoObj::PkgIdxBuiltin, *Identity.BuiltinIndex},
            std::optional<uint32_t>());
      }
      return std::make_pair(
          GoObjSymRef{GoObj::PkgIdxNone,
                      GetNonPkgRefSymIdx(Target, IsFunction)},
          std::optional<uint32_t>());
    }

    report_fatal_error(
        Twine("unsupported GoObj relocation target symbol: name=") +
        Target->getName() +
        " temporary=" + Twine(static_cast<unsigned>(Target->isTemporary())) +
        " variable=" + Twine(static_cast<unsigned>(Target->isVariable())) +
        " absolute=" + Twine(static_cast<unsigned>(Target->isAbsolute())) +
        " in-section=" + Twine(static_cast<unsigned>(Target->isInSection())) +
        " undefined=" + Twine(static_cast<unsigned>(Target->isUndefined())));
  };
  auto GetTargetSymRef = [&](const MCSymbol *Target, unsigned RelocType,
                             int64_t &Addend) {
    return ResolveTargetSymRef(Target, RelocType, Addend).first;
  };

  SmallVector<GoObjRelocationEntry> MergedRelocations;
  for (const GoObjRelocationEntry &Reloc : Relocations) {
    bool SameSource = false;
    if (!MergedRelocations.empty()) {
      std::optional<uint32_t> PreviousSource = FindContainingSymbol(
          MergedRelocations.back().Section, MergedRelocations.back().Offset);
      std::optional<uint32_t> CurrentSource =
          FindContainingSymbol(Reloc.Section, Reloc.Offset);
      SameSource = PreviousSource && CurrentSource &&
                   *PreviousSource == *CurrentSource;
    }
    if (!SameSource || !TargetObjectWriter->mergeRelocations(
                           MergedRelocations.back(), Reloc))
      MergedRelocations.push_back(Reloc);
  }

  for (const GoObjRelocationEntry &Reloc : MergedRelocations) {
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

    // Native x86 Go objects intentionally leave the internal-linking TLS
    // relocation target empty. The linker resolves R_TLS_LE against its
    // synthetic runtime.tlsg symbol and supplies that symbol itself when it
    // translates the relocation for external ELF linking.
    const Triple::ArchType Arch = Asm->getContext().getTargetTriple().getArch();
    const bool IsX86TLSLE = (Arch == Triple::x86 || Arch == Triple::x86_64) &&
                            (RelocType & ~GoObj::R_WEAK) == GoObj::R_TLS_LE;
    GoObjSymRef TargetSymRef;
    std::optional<uint32_t> TargetSymbolIndex;
    if (!IsX86TLSLE)
      std::tie(TargetSymRef, TargetSymbolIndex) =
          ResolveTargetSymRef(Reloc.Symbol, Reloc.Type, Addend);

    Source.Relocations.push_back(
        {static_cast<uint32_t>(LocalOffset), Reloc.Size, RelocType, Addend,
         TargetSymRef.PkgIdx, TargetSymRef.SymIdx, TargetSymbolIndex});
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
      int64_t Addend = 0;
      GoObjSymRef TargetSymRef = GetTargetSymRef(Target, GoObj::R_KEEP, Addend);
      Source.Relocations.push_back({0, 0, GoObj::R_KEEP, Addend,
                                    TargetSymRef.PkgIdx, TargetSymRef.SymIdx,
                                    std::nullopt});
    }
  }

  for (GoObjSymbol &Source : Symbols) {
    if (!Source.Symbol)
      continue;
    const auto *Markers = Asm->getContext().getGoObjMarkerRelocs(Source.Symbol);
    if (!Markers)
      continue;
    for (const MCContext::GoObjMarkerReloc &Marker : *Markers) {
      int64_t Addend = Marker.Addend;
      GoObjSymRef TargetSymRef =
          GetTargetSymRef(Marker.Target, Marker.Type, Addend);
      Source.Relocations.push_back({0, 0, Marker.Type, Addend,
                                    TargetSymRef.PkgIdx, TargetSymRef.SymIdx,
                                    std::nullopt});
    }
  }

  for (GoObjSymbol &Source : Symbols) {
    if (!Source.Symbol)
      continue;
    const MCSymbol *Target =
        Asm->getContext().getGoObjGotypeTarget(Source.Symbol);
    if (!Target)
      continue;
    int64_t Addend = 0;
    GoObjSymRef TargetSymRef =
        GetTargetSymRef(Target, GoObj::R_USETYPE, Addend);
    if (Addend != 0)
      report_fatal_error("GoObj gotype auxiliary target has an addend");
    Source.Auxiliaries.emplace_back(GoObj::AuxGotype, TargetSymRef);
  }

  // FuncInfo stores inline callees as final Go SymRefs rather than
  // relocations, so patch them after package and symbol numbering is known.
  for (const PendingFuncInfoPatch &Patch : PendingFuncInfoPatches) {
    if (Patch.CarrierSymbol >= Symbols.size())
      report_fatal_error("GoObj FuncInfo patch references an invalid carrier");
    GoObjSymbol &Carrier = Symbols[Patch.CarrierSymbol];
    uint64_t InlineTreeOffset = 24 + static_cast<uint64_t>(Patch.FileCount) * 4;
    uint64_t RequiredSize =
        InlineTreeOffset + static_cast<uint64_t>(Patch.InlineTree.size()) * 24;
    if (Carrier.Data.size() != RequiredSize)
      report_fatal_error("GoObj FuncInfo inline tree has an invalid size");

    for (uint32_t I = 0, E = checkedUint32(Patch.InlineTree.size(),
                                           "GoObj inline tree size");
         I != E; ++I) {
      const GoObjInlineTreeNode &Node = Patch.InlineTree[I];
      if (!Node.Callee)
        report_fatal_error("GoObj inline tree node has no callee symbol");
      int64_t Addend = 0;
      GoObjSymRef Ref = GetTargetSymRef(Node.Callee, GoObj::R_CALL, Addend);
      if (Addend != 0)
        report_fatal_error("GoObj inline callee symbol has an addend");
      uint64_t NodeOffset = InlineTreeOffset + static_cast<uint64_t>(I) * 24;
      support::endian::write32le(Carrier.Data.data() + NodeOffset + 12,
                                 Ref.PkgIdx);
      support::endian::write32le(Carrier.Data.data() + NodeOffset + 16,
                                 Ref.SymIdx);
    }
  }

  for (GoObjSymbol &Symbol : Symbols) {
    llvm::stable_sort(Symbol.Relocations,
                      [](const GoObjSymbol::Relocation &LHS,
                         const GoObjSymbol::Relocation &RHS) {
                        return LHS.Offset < RHS.Offset;
                      });
  }

  // LLVM optimizations can synthesize private pointer lookup tables. Match
  // cmd/internal/obj's content identity: hash the symbol bytes and each
  // relocation's shape and globally stable target identity. Hashing only the
  // zero relocation placeholders would incorrectly merge different tables.
  DenseSet<uint32_t> ContentHashInProgress;
  std::function<void(uint32_t)> ComputeContentHash = [&](uint32_t SymbolIndex) {
    if (SymbolIndex >= Symbols.size())
      report_fatal_error("GoObj hashed definition index is invalid");
    GoObjSymbol &Symbol = Symbols[SymbolIndex];
    if (Symbol.ContentHash)
      return;
    if (Symbol.DefinedBlock != GoObj::DefinedSymbolBlock::Hasheddef)
      report_fatal_error(
          "GoObj content hash requested for a non-hashed symbol");
    if (!Symbol.Symbol || !Symbol.Symbol->isTemporary() ||
        Symbol.Type != GoObj::SRODATA)
      report_fatal_error(
          "GoObj frontend hashed definition has no content hash");
    if (!ContentHashInProgress.insert(SymbolIndex).second)
      report_fatal_error("circular GoObj content-addressable relocation");

    SHA256 Hasher;
    const char Version = 1;
    Hasher.update(StringRef(&Version, 1));
    SmallString<16> Encoded;
    raw_svector_ostream EncodedOS(Encoded);
    support::endian::Writer EncodedWriter(EncodedOS, llvm::endianness::little);
    EncodedWriter.write<uint64_t>(Symbol.Size);
    EncodedWriter.write<uint8_t>(0); // Default read-only data section.
    Hasher.update(StringRef(Encoded.data(), Encoded.size()));

    ArrayRef<char> Data(Symbol.Data);
    while (!Data.empty() && Data.back() == 0)
      Data = Data.drop_back();
    if (!Data.empty())
      Hasher.update(StringRef(Data.data(), Data.size()));

    for (const GoObjSymbol::Relocation &Reloc : Symbol.Relocations) {
      Encoded.clear();
      EncodedWriter.write<uint32_t>(Reloc.Offset);
      EncodedWriter.write<uint8_t>(Reloc.Size);
      if (Reloc.Type > std::numeric_limits<uint8_t>::max())
        report_fatal_error("GoObj content hash relocation type is too large");
      EncodedWriter.write<uint8_t>(static_cast<uint8_t>(Reloc.Type));
      EncodedWriter.write<uint64_t>(static_cast<uint64_t>(Reloc.Addend));
      Hasher.update(StringRef(Encoded.data(), Encoded.size()));

      if (Reloc.TargetSymbolIndex && *Reloc.TargetSymbolIndex == SymbolIndex) {
        Hasher.update("self symbol");
        continue;
      }
      if (Reloc.PkgIdx == GoObj::PkgIdxInvalid) {
        Hasher.update("nil symbol");
        continue;
      }

      switch (Reloc.PkgIdx) {
      case GoObj::PkgIdxHashed64: {
        if (Reloc.SymIdx >= Hashed64defSymbols.size())
          report_fatal_error("invalid GoObj short-hashed relocation target");
        const GoObjSymbol &Target = Symbols[Hashed64defSymbols[Reloc.SymIdx]];
        if (Target.Data.size() != GoObj::Hash64Size)
          report_fatal_error("GoObj short-hashed target has invalid size");
        const char Kind = 0;
        Hasher.update(StringRef(&Kind, 1));
        Hasher.update(StringRef(Target.Data.data(), Target.Data.size()));
        break;
      }
      case GoObj::PkgIdxHashed: {
        if (Reloc.SymIdx >= HasheddefSymbols.size())
          report_fatal_error("invalid GoObj hashed relocation target");
        uint32_t TargetIndex = HasheddefSymbols[Reloc.SymIdx];
        ComputeContentHash(TargetIndex);
        const char Kind = 1;
        Hasher.update(StringRef(&Kind, 1));
        Hasher.update(ArrayRef<uint8_t>(*Symbols[TargetIndex].ContentHash));
        break;
      }
      case GoObj::PkgIdxNone: {
        const char Kind = 2;
        Hasher.update(StringRef(&Kind, 1));
        if (Reloc.SymIdx < NonpkgdefSymbols.size()) {
          Hasher.update(Symbols[NonpkgdefSymbols[Reloc.SymIdx]].Name);
        } else {
          uint32_t RefIndex = Reloc.SymIdx - NonpkgdefSymbols.size();
          if (RefIndex >= NonPkgRefs.size())
            report_fatal_error("invalid GoObj non-package relocation target");
          Hasher.update(NonPkgRefs[RefIndex].Name);
        }
        break;
      }
      case GoObj::PkgIdxBuiltin: {
        const char Kind = 3;
        Hasher.update(StringRef(&Kind, 1));
        Encoded.clear();
        EncodedWriter.write<uint32_t>(Reloc.SymIdx);
        Hasher.update(StringRef(Encoded.data(), Encoded.size()));
        break;
      }
      case GoObj::PkgIdxSelf: {
        Hasher.update(goObjPathToPrefix(Config.PackagePath));
        Encoded.clear();
        EncodedWriter.write<uint32_t>(Reloc.SymIdx);
        Hasher.update(StringRef(Encoded.data(), Encoded.size()));
        break;
      }
      default:
        if (Reloc.PkgIdx >= PackagePrefixes.size())
          report_fatal_error("invalid GoObj imported relocation package");
        Hasher.update(PackagePrefixes[Reloc.PkgIdx]);
        Encoded.clear();
        EncodedWriter.write<uint32_t>(Reloc.SymIdx);
        Hasher.update(StringRef(Encoded.data(), Encoded.size()));
        break;
      }
    }

    std::array<uint8_t, 32> FullHash = Hasher.final();
    std::array<uint8_t, GoObj::HashSize> Hash;
    std::copy_n(FullHash.begin(), Hash.size(), Hash.begin());
    Symbol.ContentHash = Hash;
    ContentHashInProgress.erase(SymbolIndex);
  };
  for (uint32_t SymbolIndex : HasheddefSymbols)
    if (!Symbols[SymbolIndex].ContentHash)
      ComputeContentHash(SymbolIndex);

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
  for (const MCContext::GoObjImport &Import :
       Asm->getContext().getGoObjImports())
    AddString(Import.PackagePath);
  for (StringRef Prefix : PackagePrefixes)
    AddString(Prefix);
  for (StringRef File : FilePaths)
    AddString(File);
  for (const GoObjSymbol &Symbol : Symbols)
    AddString(Symbol.Name);
  for (const GoObjSymbol &Symbol : NonPkgRefs)
    AddString(Symbol.Name);
  for (const IndexedRef &Ref : IndexedRefs)
    AddString(Ref.Name);

  std::array<uint32_t, GoObj::NBlk> Offsets = {};
  auto MarkBlock = [&](GoObj::Block Block) {
    Offsets[Block] = CurrentOffset();
  };
  auto WriteSymbolBlock = [&](ArrayRef<uint32_t> SymbolIndexes) {
    for (uint32_t Index : SymbolIndexes)
      WriteSymbolRecord(Symbols[Index]);
  };

  MarkBlock(GoObj::BlkAutolib);
  for (const MCContext::GoObjImport &Import :
       Asm->getContext().getGoObjImports()) {
    WriteStringRef(Import.PackagePath);
    for (uint8_t Byte : Import.Fingerprint)
      W.write<uint8_t>(Byte);
  }

  MarkBlock(GoObj::BlkPkgIdx);
  for (StringRef Prefix : PackagePrefixes)
    WriteStringRef(Prefix);

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
  for (const IndexedRef &Ref : IndexedRefs) {
    if (Ref.Flags2 == 0)
      continue;
    W.write<uint32_t>(Ref.Ref.PkgIdx);
    W.write<uint32_t>(Ref.Ref.SymIdx);
    W.write<uint8_t>(0);
    W.write<uint8_t>(Ref.Flags2);
  }

  MarkBlock(GoObj::BlkHash64);
  for (uint32_t Index : Hashed64defSymbols) {
    const GoObjSymbol &Symbol = Symbols[Index];
    if (Symbol.ContentHash64) {
      BodyOS.write(reinterpret_cast<const char *>(Symbol.ContentHash64->data()),
                   Symbol.ContentHash64->size());
    } else {
      if (Symbol.Data.size() != GoObj::Hash64Size)
        report_fatal_error("GoObj short-hashed definition has invalid data");
      BodyOS.write(Symbol.Data.data(), Symbol.Data.size());
    }
  }
  MarkBlock(GoObj::BlkHash);
  for (uint32_t Index : HasheddefSymbols) {
    const GoObjSymbol &Symbol = Symbols[Index];
    if (!Symbol.ContentHash)
      report_fatal_error("GoObj hashed definition has no content hash");
    for (uint8_t Byte : *Symbol.ContentHash)
      W.write<uint8_t>(Byte);
  }

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
  for (const IndexedRef &Ref : IndexedRefs) {
    W.write<uint32_t>(Ref.Ref.PkgIdx);
    W.write<uint32_t>(Ref.Ref.SymIdx);
    WriteStringRef(Ref.Name);
  }

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
  writeGoObjectTextHeader(OS, Asm->getContext().getTargetTriple(), Config,
                          Asm->getContext().getGoObjCgoPragmas());
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
