//===-- llvm/BinaryFormat/GoObj.h - Go object constants ---------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Constants for the Go gc toolchain object format defined by
// cmd/internal/goobj in the Go source tree.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_BINARYFORMAT_GOOBJ_H
#define LLVM_BINARYFORMAT_GOOBJ_H

#include <cstdint>

namespace llvm {
namespace GoObj {

// LLVM global names carry this suffix when they identify the ABI0 form of a
// Go function. GoObj serialization strips it and records ABI0 separately.
inline constexpr char ABI0SymbolSuffix[] = "<ABI0>";

// "GoNoSplt" encoded as the stable STACKMAP identifier for the function-level
// entry argument pointer map. This record is metadata-only: it is present for
// both split and nosplit functions and never denotes a callsite.
inline constexpr uint64_t EntryArgsStackMapID = 0x476f4e6f53706c74ULL;

// GoALLC encodes pointer maps for fixed allocas as a self-describing suffix of
// statepoint deopt locations:
//
//   ordinary-deopt*, BEGIN, protocol-length, record-count,
//     (RECORD-TAG, record-length, direct-base, byte-offset, byte-size,
//     alignment,
//      pointer-size, bit-count, word-bits, word-count, bitmap-word*)*,
//   END, protocol-length
//
// Protocol length counts BEGIN through END and excludes its trailing duplicate;
// record length counts RECORD-TAG through the final bitmap word. A matching
// direct alloca in the statepoint gc-live operands says that the record's
// contents contribute to that callsite's ArgsPointerMaps or
// LocalsPointerMaps, according to the alloca's frame region. An unmatched
// record identifies a function-level native Go StackObject; argument/result
// objects use a non-negative argp-relative offset and local objects use a
// negative varp-relative offset. The producer must repeat that same layout at
// every ordinary statepoint. The direct address itself remains a rematerialized
// frame index, not a bitmap slot. The first contract has no version, requires a
// whole alloca at byte offset zero, and uses 64-bit bitmap words. Bit N, stored
// low-bit first, describes the pointer-sized slot at direct-base + byte-offset
// + N * pointer-size. Padding bits must be zero.
// These tags are intentionally small enough to remain inline StackMaps
// constants; bitmap payload words may use the StackMaps constant pool.
inline constexpr int64_t AllocaPtrMapBeginMagic = 0x47414c41; // "GALA"
inline constexpr int64_t AllocaPtrMapEndMagic = 0x414c4c43;   // "ALLC"
inline constexpr int64_t AllocaPtrMapRecordTag = 0x414c4f43;  // "ALOC"
inline constexpr uint32_t AllocaPtrMapBitmapWordBits = 64;

// Open-coded defer frame locations are carried in the ordinary statepoint
// deopt prefix. The alloca ptrmap envelope, when present, follows this record:
//
//   BEGIN, protocol-length, slot-count, defer-bits-base, slots-array-base,
//   END, protocol-length
//
// Protocol length counts BEGIN through END and excludes its trailing duplicate.
// Every base is a direct frame address. The slots base denotes one fixed
// [slot-count x pointer] alloca, so its elements remain consecutive through
// frame layout without requiring a target-specific fixed stack area.
inline constexpr int64_t OpenDeferBeginMagic = 0x474f4446; // "GODF"
inline constexpr int64_t OpenDeferEndMagic = 0x46444f47;   // "FDOG"

// Special values in PCDATA_UnsafePoint (PCDATA stream 0).
inline constexpr int32_t UnsafePointSafe = -1;
inline constexpr int32_t UnsafePointUnsafe = -2;

inline constexpr char Magic[] = {'\0', 'g', 'o', '1', '2', '0', 'l', 'd'};
inline constexpr uint32_t MagicSize = sizeof(Magic);
inline constexpr uint32_t FingerprintSize = 8;

enum Block : uint8_t {
  BlkAutolib = 0,
  BlkPkgIdx,
  BlkFile,
  BlkSymdef,
  BlkHashed64def,
  BlkHasheddef,
  BlkNonpkgdef,
  BlkNonpkgref,
  BlkRefFlags,
  BlkHash64,
  BlkHash,
  BlkRelocIdx,
  BlkAuxIdx,
  BlkDataIdx,
  BlkReloc,
  BlkAux,
  BlkData,
  BlkRefName,
  BlkEnd,
  NBlk,
};

inline constexpr uint32_t HeaderSize =
    MagicSize + FingerprintSize + sizeof(uint32_t) + NBlk * sizeof(uint32_t);
static_assert(HeaderSize == 96, "Go object header size changed");

inline constexpr uint32_t StringRefSize = 8;
inline constexpr uint32_t SymSize = StringRefSize + 2 + 1 + 1 + 1 + 4 + 4;
inline constexpr uint32_t SymRefSize = 8;
inline constexpr uint32_t RelocSize = 4 + 1 + 2 + 8 + SymRefSize;
inline constexpr uint32_t AuxSize = 1 + SymRefSize;
inline constexpr uint32_t RefFlagsSize = SymRefSize + 1 + 1;
inline constexpr uint32_t RefNameSize = SymRefSize + StringRefSize;
inline constexpr uint32_t Hash64Size = 8;
inline constexpr uint32_t HashSize = 16;

enum AuxType : uint8_t {
  AuxGotype = 0,
  AuxFuncInfo,
  AuxFuncdata,
  AuxDwarfInfo,
  AuxDwarfLoc,
  AuxDwarfRanges,
  AuxDwarfLines,
  AuxPcsp,
  AuxPcfile,
  AuxPcline,
  AuxPcinline,
  AuxPcdata,
  AuxWasmImport,
  AuxWasmType,
  AuxSehUnwindInfo,
};

enum PackageIndex : uint32_t {
  PkgIdxNone = (1u << 31) - 1,
  PkgIdxHashed64 = PkgIdxNone - 1,
  PkgIdxHashed = PkgIdxNone - 2,
  PkgIdxBuiltin = PkgIdxNone - 3,
  PkgIdxSelf = PkgIdxNone - 4,
  PkgIdxSpecial = PkgIdxSelf,
  PkgIdxInvalid = 0,
};

enum ObjectFlags : uint32_t {
  ObjFlagShared = 1u << 0,
  ObjFlagFromAssembly = 1u << 2,
  ObjFlagUnlinkable = 1u << 3,
  ObjFlagStd = 1u << 4,
};

enum class SourceKind : uint8_t {
  Assembly,
  Compiler,
};

enum class DefinedSymbolBlock : uint8_t {
  Symdef,
  Hashed64def,
  Hasheddef,
  Nonpkgdef,
};

inline constexpr uint16_t SymABI0 = 0;
inline constexpr uint16_t SymABIInternal = 1;
inline constexpr uint16_t SymABIstatic = UINT16_MAX;

enum SymKind : uint8_t {
  Sxxx = 0,
  STEXT = 1,
  STEXTFIPS = 2,
  SRODATA = 3,
  SRODATAFIPS = 4,
  SNOPTRDATA = 5,
  SNOPTRDATAFIPS = 6,
  SDATA = 7,
  SDATAFIPS = 8,
  SBSS = 9,
  SNOPTRBSS = 10,
  STLSBSS = 11,
  SDWARFCUINFO = 12,
  SDWARFCONST = 13,
  SDWARFFCN = 14,
  SDWARFABSFCN = 15,
  SDWARFTYPE = 16,
  SDWARFVAR = 17,
  SDWARFRANGE = 18,
  SDWARFLOC = 19,
  SDWARFLINES = 20,
  SDWARFADDR = 21,
  SLIBFUZZER_8BIT_COUNTER = 22,
  SCOVERAGE_COUNTER = 23,
  SCOVERAGE_AUXVAR = 24,
  SSEHUNWINDINFO = 25,
};

enum SymFlag : uint8_t {
  SymFlagDupok = 1u << 0,
  SymFlagLocal = 1u << 1,
  SymFlagTypelink = 1u << 2,
  SymFlagLeaf = 1u << 3,
  SymFlagNoSplit = 1u << 4,
  SymFlagReflectMethod = 1u << 5,
  SymFlagGoType = 1u << 6,
};

enum SymFlag2 : uint8_t {
  SymFlagUsedInIface = 1u << 0,
  SymFlagItab = 1u << 1,
  SymFlagDict = 1u << 2,
  SymFlagPkgInit = 1u << 3,
  SymFlagLinkname = 1u << 4,
  SymFlagABIWrapper = 1u << 5,
  SymFlagWasmExport = 1u << 6,
};

enum RelocType : uint16_t {
  R_ADDR = 1,
  R_ADDRPOWER = 2,
  R_ADDRARM64 = 3,
  R_ADDRMIPS = 4,
  R_ADDROFF = 5,
  R_SIZE = 6,
  R_CALL = 7,
  R_CALLARM = 8,
  R_CALLARM64 = 9,
  R_CALLIND = 10,
  R_CALLPOWER = 11,
  R_CALLMIPS = 12,
  R_CONST = 13,
  R_PCREL = 14,
  R_TLS_LE = 15,
  R_TLS_IE = 16,
  R_GOTOFF = 17,
  R_PLT0 = 18,
  R_PLT1 = 19,
  R_PLT2 = 20,
  R_USEFIELD = 21,
  R_USETYPE = 22,
  R_USEIFACE = 23,
  R_USEIFACEMETHOD = 24,
  R_USENAMEDMETHOD = 25,
  R_METHODOFF = 26,
  R_KEEP = 27,
  R_POWER_TOC = 28,
  R_GOTPCREL = 29,
  R_JMPMIPS = 30,
  R_DWARFSECREF = 31,
  R_ARM64_TLS_LE = 32,
  R_ARM64_TLS_IE = 33,
  R_ARM64_GOTPCREL = 34,
  R_ARM64_GOT = 35,
  R_ARM64_PCREL = 36,
  R_ARM64_PCREL_LDST8 = 37,
  R_ARM64_PCREL_LDST16 = 38,
  R_ARM64_PCREL_LDST32 = 39,
  R_ARM64_PCREL_LDST64 = 40,
  R_ARM64_LDST8 = 41,
  R_ARM64_LDST16 = 42,
  R_ARM64_LDST32 = 43,
  R_ARM64_LDST64 = 44,
  R_ARM64_LDST128 = 45,

  // A zero-width ordering edge between package initialization records.
  R_INITORDER = 102,

  R_WEAK = 1u << 15,
  R_WEAKADDR = R_WEAK | R_ADDR,
  R_WEAKADDROFF = R_WEAK | R_ADDROFF,
};

} // end namespace GoObj
} // end namespace llvm

#endif // LLVM_BINARYFORMAT_GOOBJ_H
