//===- MCContext.h - Machine Code Context -----------------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_MC_MCCONTEXT_H
#define LLVM_MC_MCCONTEXT_H

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"
#include "llvm/BinaryFormat/Dwarf.h"
#include "llvm/BinaryFormat/XCOFF.h"
#include "llvm/MC/MCAsmMacro.h"
#include "llvm/MC/MCDwarf.h"
#include "llvm/MC/MCGOFFAttributes.h"
#include "llvm/MC/MCPseudoProbe.h"
#include "llvm/MC/MCSection.h"
#include "llvm/MC/MCSectionGOFF.h"
#include "llvm/MC/MCSectionGoObj.h"
#include "llvm/MC/MCSymbolTableEntry.h"
#include "llvm/MC/SectionKind.h"
#include "llvm/Support/Allocator.h"
#include "llvm/Support/Compiler.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/MD5.h"
#include "llvm/Support/StringSaver.h"
#include "llvm/Support/raw_ostream.h"
#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace llvm {

class CodeViewContext;
class MCAsmInfo;
class MCExpr;
class MCInst;
class MCLabel;
class MCObjectFileInfo;
class MCRegisterInfo;
class MCSection;
class MCSectionCOFF;
class MCSectionDXContainer;
class MCSectionELF;
class MCSectionGoObj;
class MCSectionMachO;
class MCSectionSPIRV;
class MCSectionWasm;
class MCSectionXCOFF;
class MCStreamer;
class MCSubtargetInfo;
class MCSymbol;
class MCSymbolELF;
class MCSymbolWasm;
class MCSymbolXCOFF;
class MCTargetOptions;
class MDNode;
template <typename T> class SmallVectorImpl;
class SMDiagnostic;
class SMLoc;
class SourceMgr;
enum class EmitDwarfUnwindType;

namespace wasm {
struct WasmSignature;
}

/// Context object for machine code objects.  This class owns all of the
/// sections that it creates.
///
class MCContext {
public:
  using SymbolTable = StringMap<MCSymbolTableValue, BumpPtrAllocator &>;
  using DiagHandlerTy =
      std::function<void(const SMDiagnostic &, bool, const SourceMgr &,
                         std::vector<const MDNode *> &)>;
  enum Environment {
    IsMachO,
    IsELF,
    IsGOFF,
    IsCOFF,
    IsSPIRV,
    IsWasm,
    IsXCOFF,
    IsDXContainer,
    IsGoObj
  };

  struct GoObjPCSPEntry {
    const MCSymbol *Label;
    int32_t Value;
  };

  struct GoObjStackMapLocation {
    enum LocationType : uint8_t {
      Unprocessed,
      Register,
      Direct,
      Indirect,
      Constant,
      ConstantIndex,
    };

    LocationType Type;
    uint16_t Size;
    uint16_t DwarfRegNum;
    int64_t Offset;
  };

  struct GoObjStackMapEntry {
    const MCExpr *CallsiteOffsetExpr;
    uint64_t ID;
    bool IsIndirectCall;
    uint64_t StackSize;
    uint32_t PointerSize;
    uint32_t NumDeoptLocations;
    std::vector<GoObjStackMapLocation> Locations;
  };

  struct GoObjRelocOverride {
    uint32_t Offset;
    uint16_t Type;
  };

  struct GoObjMarkerReloc {
    const MCSymbol *Target = nullptr;
    uint16_t Type = 0;
    int64_t Addend = 0;
  };

  struct GoObjImport {
    std::string PackagePath;
    std::string PackagePrefix;
    std::array<uint8_t, 8> Fingerprint = {};
  };

  struct GoObjImportedSymbolRef {
    std::string PackagePrefix;
    uint32_t SymIdx = 0;
    uint8_t Flags2 = 0;
  };

  struct GoObjDebugInlineFrame {
    const MCSymbol *Callee = nullptr;
    std::string CallFile;
    uint32_t CallLine = 0;
    uint64_t SiteID = 0;
  };

  // Labels keep source and inline state attached to final machine layout.
  struct GoObjDebugLocation {
    const MCSymbol *Label = nullptr;
    std::string File;
    uint32_t Line = 0;
    std::vector<GoObjDebugInlineFrame> InlineFrames;
    std::vector<GoObjDebugInlineFrame> AnchorChildFrames;
  };

  struct GoObjFunctionDebugInfo {
    std::string File;
    uint32_t StartLine = 0;
    std::vector<GoObjDebugLocation> Locations;
  };

private:
  Environment Env;

  /// The name of the Segment where Swift5 Reflection Section data will be
  /// outputted
  StringRef Swift5ReflectionSegmentName;

  /// The triple for this object.
  Triple TT;

  /// The SourceMgr for this object, if any.
  const SourceMgr *SrcMgr = nullptr;

  /// The SourceMgr for inline assembly, if any.
  std::unique_ptr<SourceMgr> InlineSrcMgr;
  std::vector<const MDNode *> LocInfos;

  DiagHandlerTy DiagHandler;

  /// The MCAsmInfo for this target.
  const MCAsmInfo &MAI;

  /// The MCRegisterInfo for this target.
  const MCRegisterInfo *MRI = nullptr;

  /// The MCObjectFileInfo for this target.
  const MCObjectFileInfo *MOFI = nullptr;

  /// The MCSubtargetInfo for this target.
  const MCSubtargetInfo *MSTI = nullptr;

  std::unique_ptr<CodeViewContext> CVContext;

  /// Allocator object used for creating machine code objects.
  ///
  /// We use a bump pointer allocator to avoid the need to track all allocated
  /// objects.
  BumpPtrAllocator Allocator;

  /// For MCFragment instances.
  BumpPtrAllocator FragmentAllocator;

  SpecificBumpPtrAllocator<MCSectionCOFF> COFFAllocator;
  SpecificBumpPtrAllocator<MCSectionDXContainer> DXCAllocator;
  SpecificBumpPtrAllocator<MCSectionELF> ELFAllocator;
  SpecificBumpPtrAllocator<MCSectionMachO> MachOAllocator;
  SpecificBumpPtrAllocator<MCSectionGOFF> GOFFAllocator;
  SpecificBumpPtrAllocator<MCSectionGoObj> GoObjAllocator;
  SpecificBumpPtrAllocator<MCSectionSPIRV> SPIRVAllocator;
  SpecificBumpPtrAllocator<MCSectionWasm> WasmAllocator;
  SpecificBumpPtrAllocator<MCSectionXCOFF> XCOFFAllocator;
  SpecificBumpPtrAllocator<MCInst> MCInstAllocator;

  SpecificBumpPtrAllocator<wasm::WasmSignature> WasmSignatureAllocator;

  /// Bindings of names to symbol table values.
  SymbolTable Symbols;

  /// MC symbols known to denote Go functions, including declarations.
  DenseSet<const MCSymbol *> GoObjFunctionSymbols;

  /// Package-local indices assigned to Go object definitions by the frontend.
  DenseMap<const MCSymbol *, uint32_t> GoObjPackageSymbolIndexes;

  /// Compiler-validated cgo directives serialized in the Go object header.
  std::string GoObjCgoPragmas;

  /// Go object definitions that are resolved by name instead of package index.
  DenseSet<const MCSymbol *> GoObjNonPackageSymbols;

  /// Go object symbol stack sizes keyed by MC symbol.
  DenseMap<const MCSymbol *, uint32_t> GoObjSymbolStackSizes;

  /// Go object symbol argument sizes keyed by MC symbol.
  DenseMap<const MCSymbol *, uint32_t> GoObjSymbolArgSizes;

  /// Whether a Go object symbol uses a frame pointer, keyed by MC symbol.
  DenseMap<const MCSymbol *, bool> GoObjSymbolHasFramePointers;

  /// Go object symbol flags keyed by MC symbol.
  DenseMap<const MCSymbol *, std::pair<uint8_t, uint8_t>> GoObjSymbolFlags;

  /// Go object function ID and function flags keyed by MC symbol.
  DenseMap<const MCSymbol *, std::pair<uint8_t, uint8_t>> GoObjFunctionInfos;

  /// Native Go content-addressable identity hashes keyed by MC symbol.
  DenseMap<const MCSymbol *, std::string> GoObjSymbolContentHashes;

  /// Go object data-relocation type overrides keyed by MC symbol. LLVM IR
  /// constants describe an address but not Go's weak-address variants.
  DenseMap<const MCSymbol *, std::vector<GoObjRelocOverride>>
      GoObjRelocOverrides;

  /// Go object data relocations whose inferred relocation kind is weak.
  DenseMap<const MCSymbol *, std::vector<uint32_t>> GoObjWeakRelocs;

  /// Go object zero-width R_KEEP targets keyed by their source symbol.
  DenseMap<const MCSymbol *, std::vector<const MCSymbol *>> GoObjKeepTargets;

  /// Go object zero-width linker marker relocations keyed by source symbol.
  DenseMap<const MCSymbol *, std::vector<GoObjMarkerReloc>>
      GoObjMarkerRelocs;

  /// Imported packages and their opaque linker fingerprints, in source order.
  std::vector<GoObjImport> GoObjImports;

  /// Indexed imported references keyed by their MC symbol.
  DenseMap<const MCSymbol *, GoObjImportedSymbolRef> GoObjImportedSymbolRefs;

  /// Explicit LLVM global alignments for Go object data symbols.
  DenseMap<const MCSymbol *, uint32_t> GoObjSymbolAlignments;

  /// Exact LLVM global sizes for Go object data symbols.
  DenseMap<const MCSymbol *, uint64_t> GoObjSymbolSizes;

  /// Go type auxiliary targets for data symbols.
  DenseMap<const MCSymbol *, const MCSymbol *> GoObjGotypeTargets;

  /// Go object pcsp entries keyed by MC symbol.
  DenseMap<const MCSymbol *, std::vector<GoObjPCSPEntry>>
      GoObjSymbolPCSPEntries;

  /// Whether a Go object function is unsafe for asynchronous preemption over
  /// its complete PC range.
  DenseMap<const MCSymbol *, bool> GoObjSymbolAsyncUnsafe;

  /// Go object statepoint stack maps keyed by function MC symbol.
  DenseMap<const MCSymbol *, std::vector<GoObjStackMapEntry>>
      GoObjSymbolStackMapEntries;

  DenseMap<const MCSymbol *, GoObjFunctionDebugInfo> GoObjFunctionDebugInfos;
  DenseSet<const MCSymbol *> GoObjInlineAnchorSymbols;

  /// A mapping from a local label number and an instance count to a symbol.
  /// For example, in the assembly
  ///     1:
  ///     2:
  ///     1:
  /// We have three labels represented by the pairs (1, 0), (2, 0) and (1, 1)
  DenseMap<std::pair<unsigned, unsigned>, MCSymbol *> LocalSymbols;

  /// Keeps track of labels that are used in inline assembly.
  StringMap<MCSymbol *, BumpPtrAllocator &> InlineAsmUsedLabelNames;

  /// Instances of directional local labels.
  DenseMap<unsigned, MCLabel *> Instances;
  /// NextInstance() creates the next instance of the directional local label
  /// for the LocalLabelVal and adds it to the map if needed.
  unsigned NextInstance(unsigned LocalLabelVal);
  /// GetInstance() gets the current instance of the directional local label
  /// for the LocalLabelVal and adds it to the map if needed.
  unsigned GetInstance(unsigned LocalLabelVal);

  /// SHT_LLVM_BB_ADDR_MAP version to emit.
  uint8_t BBAddrMapVersion = 5;

  /// The file name of the log file from the environment variable
  /// AS_SECURE_LOG_FILE.  Which must be set before the .secure_log_unique
  /// directive is used or it is an error.
  std::string SecureLogFile;
  /// The stream that gets written to for the .secure_log_unique directive.
  std::unique_ptr<raw_fd_ostream> SecureLog;
  /// Boolean toggled when .secure_log_unique / .secure_log_reset is seen to
  /// catch errors if .secure_log_unique appears twice without
  /// .secure_log_reset appearing between them.
  bool SecureLogUsed = false;

  /// The compilation directory to use for DW_AT_comp_dir.
  SmallString<128> CompilationDir;

  /// Prefix replacement map for source file information.
  SmallVector<std::pair<std::string, std::string>, 0> DebugPrefixMap;

  /// The main file name if passed in explicitly.
  std::string MainFileName;

  /// The dwarf file and directory tables from the dwarf .file directive.
  /// We now emit a line table for each compile unit. To reduce the prologue
  /// size of each line table, the files and directories used by each compile
  /// unit are separated.
  std::map<unsigned, MCDwarfLineTable> MCDwarfLineTablesCUMap;

  /// The current dwarf line information from the last dwarf .loc directive.
  MCDwarfLoc CurrentDwarfLoc;
  bool DwarfLocSeen = false;

  /// Generate dwarf debugging info for assembly source files.
  bool GenDwarfForAssembly = false;

  /// The current dwarf file number when generate dwarf debugging info for
  /// assembly source files.
  unsigned GenDwarfFileNumber = 0;

  /// Sections for generating the .debug_ranges and .debug_aranges sections.
  SetVector<MCSection *> SectionsForRanges;

  /// The information gathered from labels that will have dwarf label
  /// entries when generating dwarf assembly source files.
  std::vector<MCGenDwarfLabelEntry> MCGenDwarfLabelEntries;

  /// The string to embed in the debug information for the compile unit, if
  /// non-empty.
  StringRef DwarfDebugFlags;

  /// The string to embed in as the dwarf AT_producer for the compile unit, if
  /// non-empty.
  StringRef DwarfDebugProducer;

  /// The maximum version of dwarf that we should emit.
  uint16_t DwarfVersion = 4;

  /// The format of dwarf that we emit.
  dwarf::DwarfFormat DwarfFormat = dwarf::DWARF32;

  /// Honor temporary labels, this is useful for debugging semantic
  /// differences between temporary and non-temporary labels (primarily on
  /// Darwin).
  bool SaveTempLabels = false;
  bool UseNamesOnTempLabels = false;

  /// The Compile Unit ID that we are currently processing.
  unsigned DwarfCompileUnitID = 0;

  /// A collection of MCPseudoProbe in the current module
  MCPseudoProbeTable PseudoProbeTable;

  struct COFFSectionKey {
    std::string SectionName;
    StringRef GroupName;
    int SelectionKey;
    unsigned UniqueID;

    COFFSectionKey(StringRef SectionName, StringRef GroupName, int SelectionKey,
                   unsigned UniqueID)
        : SectionName(SectionName), GroupName(GroupName),
          SelectionKey(SelectionKey), UniqueID(UniqueID) {}

    bool operator<(const COFFSectionKey &Other) const {
      return std::tie(SectionName, GroupName, SelectionKey, UniqueID) <
             std::tie(Other.SectionName, Other.GroupName, Other.SelectionKey,
                      Other.UniqueID);
    }
  };

  struct WasmSectionKey {
    std::string SectionName;
    StringRef GroupName;
    unsigned UniqueID;

    WasmSectionKey(StringRef SectionName, StringRef GroupName,
                   unsigned UniqueID)
        : SectionName(SectionName), GroupName(GroupName), UniqueID(UniqueID) {}

    bool operator<(const WasmSectionKey &Other) const {
      return std::tie(SectionName, GroupName, UniqueID) <
             std::tie(Other.SectionName, Other.GroupName, Other.UniqueID);
    }
  };

  struct XCOFFSectionKey {
    // Section name.
    std::string SectionName;
    // Section property.
    // For csect section, it is storage mapping class.
    // For debug section, it is section type flags.
    union {
      XCOFF::StorageMappingClass MappingClass;
      XCOFF::DwarfSectionSubtypeFlags DwarfSubtypeFlags;
    };
    bool IsCsect;

    XCOFFSectionKey(StringRef SectionName,
                    XCOFF::StorageMappingClass MappingClass)
        : SectionName(SectionName), MappingClass(MappingClass), IsCsect(true) {}

    XCOFFSectionKey(StringRef SectionName,
                    XCOFF::DwarfSectionSubtypeFlags DwarfSubtypeFlags)
        : SectionName(SectionName), DwarfSubtypeFlags(DwarfSubtypeFlags),
          IsCsect(false) {}

    bool operator<(const XCOFFSectionKey &Other) const {
      if (IsCsect && Other.IsCsect)
        return std::tie(SectionName, MappingClass) <
               std::tie(Other.SectionName, Other.MappingClass);
      if (IsCsect != Other.IsCsect)
        return IsCsect;
      return std::tie(SectionName, DwarfSubtypeFlags) <
             std::tie(Other.SectionName, Other.DwarfSubtypeFlags);
    }
  };

  StringMap<MCSectionMachO *> MachOUniquingMap;
  std::map<COFFSectionKey, MCSectionCOFF *> COFFUniquingMap;
  StringMap<MCSectionELF *> ELFUniquingMap;
  std::map<std::string, MCSectionGOFF *> GOFFUniquingMap;
  StringMap<MCSectionGoObj *> GoObjUniquingMap;
  std::map<WasmSectionKey, MCSectionWasm *> WasmUniquingMap;
  std::map<XCOFFSectionKey, MCSectionXCOFF *> XCOFFUniquingMap;
  StringMap<MCSectionDXContainer *> DXCUniquingMap;
  StringMap<bool> RelSecNames;

  SpecificBumpPtrAllocator<MCSubtargetInfo> MCSubtargetAllocator;

  /// Do automatic reset in destructor
  bool AutoReset;

  bool HadError = false;

  void reportCommon(SMLoc Loc,
                    std::function<void(SMDiagnostic &, const SourceMgr *)>);

  MCSymbolTableEntry &getSymbolTableEntry(StringRef Name);

  MCSymbol *createSymbolImpl(const MCSymbolTableEntry *Name, bool IsTemporary);
  MCSymbol *createRenamableSymbol(const Twine &Name, bool AlwaysAddSuffix,
                                  bool IsTemporary);

  MCSymbol *getOrCreateDirectionalLocalSymbol(unsigned LocalLabelVal,
                                              unsigned Instance);

  template <typename Symbol>
  Symbol *getOrCreateSectionSymbol(StringRef Section);

  MCSectionELF *createELFSectionImpl(StringRef Section, unsigned Type,
                                     unsigned Flags, unsigned EntrySize,
                                     const MCSymbolELF *Group, bool IsComdat,
                                     unsigned UniqueID,
                                     const MCSymbolELF *LinkedToSym);

  MCSymbolXCOFF *createXCOFFSymbolImpl(const MCSymbolTableEntry *Name,
                                       bool IsTemporary);

  template <typename TAttr>
  MCSectionGOFF *getGOFFSection(SectionKind Kind, StringRef Name,
                                TAttr SDAttributes, MCSection *Parent,
                                bool IsVirtual);

  /// Map of currently defined macros.
  StringMap<MCAsmMacro> MacroMap;

  // Symbols must be assigned to a section with a compatible entry size and
  // flags. This map is used to assign unique IDs to sections to distinguish
  // between sections with identical names but incompatible entry sizes and/or
  // flags. This can occur when a symbol is explicitly assigned to a section,
  // e.g. via __attribute__((section("myname"))). The map key is the tuple
  // (section name, flags, entry size).
  DenseMap<std::tuple<StringRef, unsigned, unsigned>, unsigned> ELFEntrySizeMap;

  // This set is used to record the generic mergeable section names seen.
  // These are sections that are created as mergeable e.g. .debug_str. We need
  // to avoid assigning non-mergeable symbols to these sections. It is used
  // to prevent non-mergeable symbols being explicitly assigned  to mergeable
  // sections (e.g. via _attribute_((section("myname")))).
  DenseSet<StringRef> ELFSeenGenericMergeableSections;

public:
  LLVM_ABI explicit MCContext(const Triple &TheTriple, const MCAsmInfo &MAI,
                              const MCRegisterInfo &MRI,
                              const MCSubtargetInfo &MSTI,
                              const SourceMgr *Mgr = nullptr,
                              bool DoAutoReset = true,
                              StringRef Swift5ReflSegmentName = {});
  MCContext(const MCContext &) = delete;
  MCContext &operator=(const MCContext &) = delete;
  LLVM_ABI ~MCContext();

  Environment getObjectFileType() const { return Env; }
  bool isELF() const { return Env == IsELF; }
  bool isGoObj() const { return Env == IsGoObj; }
  bool isMachO() const { return Env == IsMachO; }
  bool isXCOFF() const { return Env == IsXCOFF; }

  const StringRef &getSwift5ReflectionSegmentName() const {
    return Swift5ReflectionSegmentName;
  }
  const Triple &getTargetTriple() const { return TT; }
  const SourceMgr *getSourceManager() const { return SrcMgr; }

  LLVM_ABI void initInlineSourceManager();
  SourceMgr *getInlineSourceManager() { return InlineSrcMgr.get(); }
  std::vector<const MDNode *> &getLocInfos() { return LocInfos; }
  void setDiagnosticHandler(DiagHandlerTy DiagHandler) {
    this->DiagHandler = DiagHandler;
  }

  void setObjectFileInfo(const MCObjectFileInfo *Mofi) { MOFI = Mofi; }

  const MCAsmInfo &getAsmInfo() const { return MAI; }

  const MCRegisterInfo *getRegisterInfo() const { return MRI; }

  const MCObjectFileInfo *getObjectFileInfo() const { return MOFI; }

  const MCSubtargetInfo *getSubtargetInfo() const { return MSTI; }

  LLVM_ABI const MCTargetOptions &getTargetOptions() const;

  LLVM_ABI CodeViewContext &getCVContext();

  void setUseNamesOnTempLabels(bool Value) { UseNamesOnTempLabels = Value; }

  /// \name Module Lifetime Management
  /// @{

  /// reset - return object to right after construction state to prepare
  /// to process a new module
  LLVM_ABI void reset();

  /// @}

  /// \name McInst Management

  /// Create and return a new MC instruction.
  LLVM_ABI MCInst *createMCInst();

  /// \name Symbol Management
  /// @{

  /// Create a new linker temporary symbol with the specified prefix (Name) or
  /// "tmp". This creates a "l"-prefixed symbol for Mach-O and is identical to
  /// createNamedTempSymbol for other object file formats.
  LLVM_ABI MCSymbol *createLinkerPrivateTempSymbol();
  LLVM_ABI MCSymbol *createLinkerPrivateSymbol(const Twine &Name);

  /// Create a temporary symbol with a unique name. The name will be omitted
  /// in the symbol table if UseNamesOnTempLabels is false (default except
  /// MCAsmStreamer). The overload without Name uses an unspecified name.
  LLVM_ABI MCSymbol *createTempSymbol();
  LLVM_ABI MCSymbol *createTempSymbol(const Twine &Name,
                                      bool AlwaysAddSuffix = true);

  /// Create a temporary symbol with a unique name whose name cannot be
  /// omitted in the symbol table. This is rarely used.
  LLVM_ABI MCSymbol *createNamedTempSymbol();
  LLVM_ABI MCSymbol *createNamedTempSymbol(const Twine &Name);

  /// Get or create a symbol for a basic block. For non-always-emit symbols,
  /// this behaves like createTempSymbol, except that it uses the
  /// InternalSymbolPrefix. When AlwaysEmit is true, behaves like
  /// getOrCreateSymbol, prefixed with InternalSymbolPrefix.
  LLVM_ABI MCSymbol *createBlockSymbol(const Twine &Name,
                                       bool AlwaysEmit = false);

  /// Create a local, non-temporary symbol like an ELF mapping symbol. Calling
  /// the function with the same name will generate new, unique instances.
  LLVM_ABI MCSymbol *createLocalSymbol(StringRef Name);

  /// Create the definition of a directional local symbol for numbered label
  /// (used for "1:" definitions).
  LLVM_ABI MCSymbol *createDirectionalLocalSymbol(unsigned LocalLabelVal);

  /// Create and return a directional local symbol for numbered label (used
  /// for "1b" or 1f" references).
  LLVM_ABI MCSymbol *getDirectionalLocalSymbol(unsigned LocalLabelVal,
                                               bool Before);

  /// Lookup the symbol inside with the specified \p Name.  If it exists,
  /// return it.  If not, create a forward reference and return it.
  ///
  /// \param Name - The symbol name, which must be unique across all symbols.
  LLVM_ABI MCSymbol *getOrCreateSymbol(const Twine &Name);

  /// Variant of getOrCreateSymbol that handles backslash-escaped symbols.
  /// For example, parse "a\"b\\" as a"\.
  LLVM_ABI MCSymbol *parseSymbol(const Twine &Name);

  /// Gets a symbol that will be defined to the final stack offset of a local
  /// variable after codegen.
  ///
  /// \param Idx - The index of a local variable passed to \@llvm.localescape.
  LLVM_ABI MCSymbol *getOrCreateFrameAllocSymbol(const Twine &FuncName,
                                                 unsigned Idx);

  LLVM_ABI MCSymbol *getOrCreateParentFrameOffsetSymbol(const Twine &FuncName);

  LLVM_ABI MCSymbol *getOrCreateLSDASymbol(const Twine &FuncName);

  /// Get the symbol for \p Name, or null.
  LLVM_ABI MCSymbol *lookupSymbol(const Twine &Name) const;

  /// Clone a symbol for the .set directive, replacing it in the symbol table.
  /// Existing references to the original symbol remain unchanged, and the
  /// original symbol is not emitted to the symbol table.
  LLVM_ABI MCSymbol *cloneSymbol(MCSymbol &Sym);

  /// Set value for a symbol.
  LLVM_ABI void setSymbolValue(MCStreamer &Streamer, const Twine &Sym,
                               uint64_t Val);

  /// getSymbols - Get a reference for the symbol table for clients that
  /// want to, for example, iterate over all symbols. 'const' because we
  /// still want any modifications to the table itself to use the MCContext
  /// APIs.
  const SymbolTable &getSymbols() const { return Symbols; }

  /// isInlineAsmLabel - Return true if the name is a label referenced in
  /// inline assembly.
  MCSymbol *getInlineAsmLabel(StringRef Name) const {
    return InlineAsmUsedLabelNames.lookup(Name);
  }

  /// registerInlineAsmLabel - Records that the name is a label referenced in
  /// inline assembly.
  LLVM_ABI void registerInlineAsmLabel(MCSymbol *Sym);

  void setGoObjFunctionSymbol(const MCSymbol *Sym) {
    GoObjFunctionSymbols.insert(Sym);
  }

  bool isGoObjFunctionSymbol(const MCSymbol *Sym) const {
    return GoObjFunctionSymbols.contains(Sym);
  }

  void setGoObjPackageSymbolIndex(const MCSymbol *Sym, uint32_t Index) {
    GoObjPackageSymbolIndexes[Sym] = Index;
  }

  std::optional<uint32_t>
  getGoObjPackageSymbolIndex(const MCSymbol *Sym) const {
    auto It = GoObjPackageSymbolIndexes.find(Sym);
    if (It == GoObjPackageSymbolIndexes.end())
      return std::nullopt;
    return It->second;
  }

  void setGoObjCgoPragmas(StringRef Pragmas) {
    GoObjCgoPragmas = Pragmas.str();
  }

  StringRef getGoObjCgoPragmas() const { return GoObjCgoPragmas; }

  void setGoObjSymbolNonPackage(const MCSymbol *Sym) {
    GoObjNonPackageSymbols.insert(Sym);
  }

  bool isGoObjSymbolNonPackage(const MCSymbol *Sym) const {
    return GoObjNonPackageSymbols.contains(Sym);
  }

  void setGoObjSymbolStackSize(const MCSymbol *Sym, uint32_t StackSize) {
    GoObjSymbolStackSizes[Sym] = StackSize;
  }

  std::optional<uint32_t> getGoObjSymbolStackSize(const MCSymbol *Sym) const {
    auto It = GoObjSymbolStackSizes.find(Sym);
    if (It == GoObjSymbolStackSizes.end())
      return std::nullopt;
    return It->second;
  }

  void setGoObjSymbolArgSize(const MCSymbol *Sym, uint32_t ArgSize) {
    GoObjSymbolArgSizes[Sym] = ArgSize;
  }

  std::optional<uint32_t> getGoObjSymbolArgSize(const MCSymbol *Sym) const {
    auto It = GoObjSymbolArgSizes.find(Sym);
    if (It == GoObjSymbolArgSizes.end())
      return std::nullopt;
    return It->second;
  }

  void setGoObjSymbolHasFramePointer(const MCSymbol *Sym,
                                     bool HasFramePointer) {
    GoObjSymbolHasFramePointers[Sym] = HasFramePointer;
  }

  std::optional<bool>
  getGoObjSymbolHasFramePointer(const MCSymbol *Sym) const {
    auto It = GoObjSymbolHasFramePointers.find(Sym);
    if (It == GoObjSymbolHasFramePointers.end())
      return std::nullopt;
    return It->second;
  }

  void setGoObjSymbolFlags(const MCSymbol *Sym, uint8_t Flag, uint8_t Flag2) {
    GoObjSymbolFlags[Sym] = {Flag, Flag2};
  }

  std::optional<std::pair<uint8_t, uint8_t>>
  getGoObjSymbolFlags(const MCSymbol *Sym) const {
    auto It = GoObjSymbolFlags.find(Sym);
    if (It == GoObjSymbolFlags.end())
      return std::nullopt;
    return It->second;
  }

  void setGoObjFunctionInfo(const MCSymbol *Sym, uint8_t FuncID,
                            uint8_t FuncFlag) {
    GoObjFunctionInfos[Sym] = {FuncID, FuncFlag};
  }

  std::optional<std::pair<uint8_t, uint8_t>>
  getGoObjFunctionInfo(const MCSymbol *Sym) const {
    auto It = GoObjFunctionInfos.find(Sym);
    if (It == GoObjFunctionInfos.end())
      return std::nullopt;
    return It->second;
  }

  void setGoObjSymbolContentHash(const MCSymbol *Sym, std::string Hash) {
    GoObjSymbolContentHashes[Sym] = std::move(Hash);
  }

  StringRef getGoObjSymbolContentHash(const MCSymbol *Sym) const {
    auto It = GoObjSymbolContentHashes.find(Sym);
    if (It == GoObjSymbolContentHashes.end())
      return {};
    return It->second;
  }

  void setGoObjRelocOverrides(const MCSymbol *Sym,
                              std::vector<GoObjRelocOverride> Overrides) {
    GoObjRelocOverrides[Sym] = std::move(Overrides);
  }

  const std::vector<GoObjRelocOverride> *
  getGoObjRelocOverrides(const MCSymbol *Sym) const {
    auto It = GoObjRelocOverrides.find(Sym);
    if (It == GoObjRelocOverrides.end())
      return nullptr;
    return &It->second;
  }

  void setGoObjWeakRelocs(const MCSymbol *Sym,
                          std::vector<uint32_t> Offsets) {
    GoObjWeakRelocs[Sym] = std::move(Offsets);
  }

  const std::vector<uint32_t> *
  getGoObjWeakRelocs(const MCSymbol *Sym) const {
    auto It = GoObjWeakRelocs.find(Sym);
    if (It == GoObjWeakRelocs.end())
      return nullptr;
    return &It->second;
  }

  void setGoObjKeepTargets(const MCSymbol *Sym,
                           std::vector<const MCSymbol *> Targets) {
    GoObjKeepTargets[Sym] = std::move(Targets);
  }

  const std::vector<const MCSymbol *> *
  getGoObjKeepTargets(const MCSymbol *Sym) const {
    auto It = GoObjKeepTargets.find(Sym);
    if (It == GoObjKeepTargets.end())
      return nullptr;
    return &It->second;
  }

  void setGoObjMarkerRelocs(const MCSymbol *Sym,
                            std::vector<GoObjMarkerReloc> Relocs) {
    GoObjMarkerRelocs[Sym] = std::move(Relocs);
  }

  const std::vector<GoObjMarkerReloc> *
  getGoObjMarkerRelocs(const MCSymbol *Sym) const {
    auto It = GoObjMarkerRelocs.find(Sym);
    if (It == GoObjMarkerRelocs.end())
      return nullptr;
    return &It->second;
  }

  void setGoObjImports(std::vector<GoObjImport> Imports) {
    GoObjImports = std::move(Imports);
  }

  ArrayRef<GoObjImport> getGoObjImports() const { return GoObjImports; }

  void setGoObjImportedSymbolRef(const MCSymbol *Sym,
                                 GoObjImportedSymbolRef Ref) {
    GoObjImportedSymbolRefs[Sym] = std::move(Ref);
  }

  const GoObjImportedSymbolRef *
  getGoObjImportedSymbolRef(const MCSymbol *Sym) const {
    auto It = GoObjImportedSymbolRefs.find(Sym);
    if (It == GoObjImportedSymbolRefs.end())
      return nullptr;
    return &It->second;
  }

  void setGoObjSymbolAlignment(const MCSymbol *Sym, uint32_t Alignment) {
    GoObjSymbolAlignments[Sym] = Alignment;
  }

  std::optional<uint32_t>
  getGoObjSymbolAlignment(const MCSymbol *Sym) const {
    auto It = GoObjSymbolAlignments.find(Sym);
    if (It == GoObjSymbolAlignments.end())
      return std::nullopt;
    return It->second;
  }

  void setGoObjSymbolSize(const MCSymbol *Sym, uint64_t Size) {
    GoObjSymbolSizes[Sym] = Size;
  }

  std::optional<uint64_t> getGoObjSymbolSize(const MCSymbol *Sym) const {
    auto It = GoObjSymbolSizes.find(Sym);
    if (It == GoObjSymbolSizes.end())
      return std::nullopt;
    return It->second;
  }

  void setGoObjGotypeTarget(const MCSymbol *Sym, const MCSymbol *Target) {
    GoObjGotypeTargets[Sym] = Target;
  }

  const MCSymbol *getGoObjGotypeTarget(const MCSymbol *Sym) const {
    auto It = GoObjGotypeTargets.find(Sym);
    if (It == GoObjGotypeTargets.end())
      return nullptr;
    return It->second;
  }

  void setGoObjSymbolPCSPEntries(const MCSymbol *Sym,
                                 std::vector<GoObjPCSPEntry> Entries) {
    GoObjSymbolPCSPEntries[Sym] = std::move(Entries);
  }

  const std::vector<GoObjPCSPEntry> *
  getGoObjSymbolPCSPEntries(const MCSymbol *Sym) const {
    auto It = GoObjSymbolPCSPEntries.find(Sym);
    if (It == GoObjSymbolPCSPEntries.end())
      return nullptr;
    return &It->second;
  }

  void setGoObjSymbolAsyncUnsafe(const MCSymbol *Sym, bool AsyncUnsafe) {
    GoObjSymbolAsyncUnsafe[Sym] = AsyncUnsafe;
  }

  bool isGoObjSymbolAsyncUnsafe(const MCSymbol *Sym) const {
    return GoObjSymbolAsyncUnsafe.lookup(Sym);
  }

  void addGoObjSymbolStackMapEntry(const MCSymbol *Sym,
                                   GoObjStackMapEntry Entry) {
    GoObjSymbolStackMapEntries[Sym].push_back(std::move(Entry));
  }

  const std::vector<GoObjStackMapEntry> *
  getGoObjSymbolStackMapEntries(const MCSymbol *Sym) const {
    auto It = GoObjSymbolStackMapEntries.find(Sym);
    if (It == GoObjSymbolStackMapEntries.end())
      return nullptr;
    return &It->second;
  }

  void setGoObjFunctionSource(const MCSymbol *Sym, StringRef File,
                              uint32_t StartLine) {
    GoObjFunctionDebugInfo &Info = GoObjFunctionDebugInfos[Sym];
    Info.File = File.str();
    Info.StartLine = StartLine;
  }

  void addGoObjDebugLocation(const MCSymbol *Sym, GoObjDebugLocation Location) {
    GoObjFunctionDebugInfos[Sym].Locations.push_back(std::move(Location));
  }

  const GoObjFunctionDebugInfo *
  getGoObjFunctionDebugInfo(const MCSymbol *Sym) const {
    auto It = GoObjFunctionDebugInfos.find(Sym);
    return It == GoObjFunctionDebugInfos.end() ? nullptr : &It->second;
  }

  void markGoObjInlineAnchor(const MCSymbol *Sym) {
    GoObjInlineAnchorSymbols.insert(Sym);
  }

  bool isGoObjInlineAnchor(const MCSymbol *Sym) const {
    return GoObjInlineAnchorSymbols.contains(Sym);
  }

  /// Allocates and returns a new `WasmSignature` instance (with empty parameter
  /// and return type lists).
  LLVM_ABI wasm::WasmSignature *createWasmSignature();

  /// @}

  /// \name Section Management
  /// @{

  /// Return the MCSection for the specified mach-o section.  This requires
  /// the operands to be valid.
  LLVM_ABI MCSectionMachO *getMachOSection(StringRef Segment, StringRef Section,
                                           unsigned TypeAndAttributes,
                                           unsigned Reserved2, SectionKind K,
                                           const char *BeginSymName = nullptr);

  MCSectionMachO *getMachOSection(StringRef Segment, StringRef Section,
                                  unsigned TypeAndAttributes, SectionKind K,
                                  const char *BeginSymName = nullptr) {
    return getMachOSection(Segment, Section, TypeAndAttributes, 0, K,
                           BeginSymName);
  }

  MCSectionELF *getELFSection(const Twine &Section, unsigned Type,
                              unsigned Flags) {
    return getELFSection(Section, Type, Flags, 0, "", false);
  }

  MCSectionELF *getELFSection(const Twine &Section, unsigned Type,
                              unsigned Flags, unsigned EntrySize) {
    return getELFSection(Section, Type, Flags, EntrySize, "", false,
                         MCSection::NonUniqueID, nullptr);
  }

  MCSectionELF *getELFSection(const Twine &Section, unsigned Type,
                              unsigned Flags, unsigned EntrySize,
                              const Twine &Group, bool IsComdat) {
    return getELFSection(Section, Type, Flags, EntrySize, Group, IsComdat,
                         MCSection::NonUniqueID, nullptr);
  }

  LLVM_ABI MCSectionELF *getELFSection(const Twine &Section, unsigned Type,
                                       unsigned Flags, unsigned EntrySize,
                                       const Twine &Group, bool IsComdat,
                                       unsigned UniqueID,
                                       const MCSymbolELF *LinkedToSym);

  LLVM_ABI MCSectionELF *getELFSection(const Twine &Section, unsigned Type,
                                       unsigned Flags, unsigned EntrySize,
                                       const MCSymbolELF *Group, bool IsComdat,
                                       unsigned UniqueID,
                                       const MCSymbolELF *LinkedToSym);

  /// Get a section with the provided group identifier. This section is
  /// named by concatenating \p Prefix with '.' then \p Suffix. The \p Type
  /// describes the type of the section and \p Flags are used to further
  /// configure this named section.
  LLVM_ABI MCSectionELF *getELFNamedSection(const Twine &Prefix,
                                            const Twine &Suffix, unsigned Type,
                                            unsigned Flags,
                                            unsigned EntrySize = 0);

  LLVM_ABI MCSectionELF *
  createELFRelSection(const Twine &Name, unsigned Type, unsigned Flags,
                      unsigned EntrySize, const MCSymbolELF *Group,
                      const MCSectionELF *RelInfoSection);

  LLVM_ABI MCSectionELF *createELFGroupSection(const MCSymbolELF *Group,
                                               bool IsComdat);

  LLVM_ABI void recordELFMergeableSectionInfo(StringRef SectionName,
                                              unsigned Flags, unsigned UniqueID,
                                              unsigned EntrySize);

  LLVM_ABI bool isELFImplicitMergeableSectionNamePrefix(StringRef Name);

  LLVM_ABI bool isELFGenericMergeableSection(StringRef Name);

  /// Return the unique ID of the section with the given name, flags and entry
  /// size, if it exists.
  LLVM_ABI std::optional<unsigned>
  getELFUniqueIDForEntsize(StringRef SectionName, unsigned Flags,
                           unsigned EntrySize);

  LLVM_ABI MCSectionGOFF *getGOFFSection(SectionKind Kind, StringRef Name,
                                         GOFF::SDAttr SDAttributes);
  LLVM_ABI MCSectionGOFF *getGOFFSection(SectionKind Kind, StringRef Name,
                                         GOFF::EDAttr EDAttributes,
                                         MCSection *Parent);
  LLVM_ABI MCSectionGOFF *getGOFFSection(SectionKind Kind, StringRef Name,
                                         GOFF::PRAttr PRAttributes,
                                         MCSection *Parent);

  LLVM_ABI MCSectionCOFF *
  getCOFFSection(StringRef Section, unsigned Characteristics,
                 StringRef COMDATSymName, int Selection,
                 unsigned UniqueID = MCSection::NonUniqueID);

  LLVM_ABI MCSectionCOFF *getCOFFSection(StringRef Section,
                                         unsigned Characteristics);

  /// Gets or creates a section equivalent to Sec that is associated with the
  /// section containing KeySym. For example, to create a debug info section
  /// associated with an inline function, pass the normal debug info section
  /// as Sec and the function symbol as KeySym.
  LLVM_ABI MCSectionCOFF *
  getAssociativeCOFFSection(MCSectionCOFF *Sec, const MCSymbol *KeySym,
                            unsigned UniqueID = MCSection::NonUniqueID);

  LLVM_ABI MCSectionSPIRV *getSPIRVSection();

  LLVM_ABI MCSectionGoObj *getGoObjSection(StringRef Section, SectionKind K);

  MCSectionWasm *getWasmSection(const Twine &Section, SectionKind K,
                                unsigned Flags = 0) {
    return getWasmSection(Section, K, Flags, "", ~0);
  }

  LLVM_ABI MCSectionWasm *getWasmSection(const Twine &Section, SectionKind K,
                                         unsigned Flags, const Twine &Group,
                                         unsigned UniqueID);

  LLVM_ABI MCSectionWasm *getWasmSection(const Twine &Section, SectionKind K,
                                         unsigned Flags,
                                         const MCSymbolWasm *Group,
                                         unsigned UniqueID);

  /// Get the section for the provided Section name
  LLVM_ABI MCSectionDXContainer *getDXContainerSection(StringRef Section,
                                                       SectionKind K);

  LLVM_ABI bool hasXCOFFSection(StringRef Section,
                                XCOFF::CsectProperties CsectProp) const;

  LLVM_ABI MCSectionXCOFF *getXCOFFSection(
      StringRef Section, SectionKind K,
      std::optional<XCOFF::CsectProperties> CsectProp = std::nullopt,
      bool MultiSymbolsAllowed = false,
      std::optional<XCOFF::DwarfSectionSubtypeFlags> DwarfSubtypeFlags =
          std::nullopt);

  // Create and save a copy of STI and return a reference to the copy.
  LLVM_ABI MCSubtargetInfo &getSubtargetCopy(const MCSubtargetInfo &STI);

  uint8_t getBBAddrMapVersion() const { return BBAddrMapVersion; }

  /// @}

  /// \name Dwarf Management
  /// @{

  /// Get the compilation directory for DW_AT_comp_dir
  /// The compilation directory should be set with \c setCompilationDir before
  /// calling this function. If it is unset, an empty string will be returned.
  StringRef getCompilationDir() const { return CompilationDir; }

  /// Set the compilation directory for DW_AT_comp_dir
  void setCompilationDir(StringRef S) { CompilationDir = S.str(); }

  /// Add an entry to the debug prefix map.
  LLVM_ABI void addDebugPrefixMapEntry(const std::string &From,
                                       const std::string &To);

  /// Remap one path in-place as per the debug prefix map.
  LLVM_ABI void remapDebugPath(SmallVectorImpl<char> &Path);

  // Remaps all debug directory paths in-place as per the debug prefix map.
  LLVM_ABI void RemapDebugPaths();

  /// Get the main file name for use in error messages and debug
  /// info. This can be set to ensure we've got the correct file name
  /// after preprocessing or for -save-temps.
  const std::string &getMainFileName() const { return MainFileName; }

  /// Set the main file name and override the default.
  void setMainFileName(StringRef S) { MainFileName = std::string(S); }

  /// Creates an entry in the dwarf file and directory tables.
  LLVM_ABI Expected<unsigned>
  getDwarfFile(StringRef Directory, StringRef FileName, unsigned FileNumber,
               std::optional<MD5::MD5Result> Checksum,
               std::optional<StringRef> Source, unsigned CUID);

  LLVM_ABI bool isValidDwarfFileNumber(unsigned FileNumber, unsigned CUID = 0);

  const std::map<unsigned, MCDwarfLineTable> &getMCDwarfLineTables() const {
    return MCDwarfLineTablesCUMap;
  }

  MCDwarfLineTable &getMCDwarfLineTable(unsigned CUID) {
    return MCDwarfLineTablesCUMap[CUID];
  }

  const MCDwarfLineTable &getMCDwarfLineTable(unsigned CUID) const {
    auto I = MCDwarfLineTablesCUMap.find(CUID);
    assert(I != MCDwarfLineTablesCUMap.end());
    return I->second;
  }

  const SmallVectorImpl<MCDwarfFile> &getMCDwarfFiles(unsigned CUID = 0) {
    return getMCDwarfLineTable(CUID).getMCDwarfFiles();
  }

  const SmallVectorImpl<std::string> &getMCDwarfDirs(unsigned CUID = 0) {
    return getMCDwarfLineTable(CUID).getMCDwarfDirs();
  }

  unsigned getDwarfCompileUnitID() { return DwarfCompileUnitID; }

  void setDwarfCompileUnitID(unsigned CUIndex) { DwarfCompileUnitID = CUIndex; }

  /// Specifies the "root" file and directory of the compilation unit.
  /// These are "file 0" and "directory 0" in DWARF v5.
  void setMCLineTableRootFile(unsigned CUID, StringRef CompilationDir,
                              StringRef Filename,
                              std::optional<MD5::MD5Result> Checksum,
                              std::optional<StringRef> Source) {
    getMCDwarfLineTable(CUID).setRootFile(CompilationDir, Filename, Checksum,
                                          Source);
  }

  /// Reports whether MD5 checksum usage is consistent (all-or-none).
  bool isDwarfMD5UsageConsistent(unsigned CUID) const {
    return getMCDwarfLineTable(CUID).isMD5UsageConsistent();
  }

  /// Saves the information from the currently parsed dwarf .loc directive
  /// and sets DwarfLocSeen.  When the next instruction is assembled an entry
  /// in the line number table with this information and the address of the
  /// instruction will be created.
  void setCurrentDwarfLoc(unsigned FileNum, unsigned Line, unsigned Column,
                          unsigned Flags, unsigned Isa,
                          unsigned Discriminator) {
    CurrentDwarfLoc.setFileNum(FileNum);
    CurrentDwarfLoc.setLine(Line);
    CurrentDwarfLoc.setColumn(Column);
    CurrentDwarfLoc.setFlags(Flags);
    CurrentDwarfLoc.setIsa(Isa);
    CurrentDwarfLoc.setDiscriminator(Discriminator);
    DwarfLocSeen = true;
  }

  void clearDwarfLocSeen() { DwarfLocSeen = false; }

  bool getDwarfLocSeen() { return DwarfLocSeen; }
  const MCDwarfLoc &getCurrentDwarfLoc() { return CurrentDwarfLoc; }

  bool getGenDwarfForAssembly() { return GenDwarfForAssembly; }
  void setGenDwarfForAssembly(bool Value) { GenDwarfForAssembly = Value; }
  unsigned getGenDwarfFileNumber() { return GenDwarfFileNumber; }
  LLVM_ABI EmitDwarfUnwindType emitDwarfUnwindInfo() const;
  LLVM_ABI bool emitCompactUnwindNonCanonical() const;

  void setGenDwarfFileNumber(unsigned FileNumber) {
    GenDwarfFileNumber = FileNumber;
  }

  /// Specifies information about the "root file" for assembler clients
  /// (e.g., llvm-mc). Assumes compilation dir etc. have been set up.
  LLVM_ABI void setGenDwarfRootFile(StringRef FileName, StringRef Buffer);

  const SetVector<MCSection *> &getGenDwarfSectionSyms() {
    return SectionsForRanges;
  }

  bool addGenDwarfSection(MCSection *Sec) {
    return SectionsForRanges.insert(Sec);
  }

  LLVM_ABI void finalizeDwarfSections(MCStreamer &MCOS);

  const std::vector<MCGenDwarfLabelEntry> &getMCGenDwarfLabelEntries() const {
    return MCGenDwarfLabelEntries;
  }

  void addMCGenDwarfLabelEntry(const MCGenDwarfLabelEntry &E) {
    MCGenDwarfLabelEntries.push_back(E);
  }

  void setDwarfDebugFlags(StringRef S) { DwarfDebugFlags = S; }
  StringRef getDwarfDebugFlags() { return DwarfDebugFlags; }

  void setDwarfDebugProducer(StringRef S) { DwarfDebugProducer = S; }
  StringRef getDwarfDebugProducer() { return DwarfDebugProducer; }

  void setDwarfFormat(dwarf::DwarfFormat f) { DwarfFormat = f; }
  dwarf::DwarfFormat getDwarfFormat() const { return DwarfFormat; }

  void setDwarfVersion(uint16_t v) { DwarfVersion = v; }
  uint16_t getDwarfVersion() const { return DwarfVersion; }

  /// @}

  StringRef getSecureLogFile() { return SecureLogFile; }
  raw_fd_ostream *getSecureLog() { return SecureLog.get(); }

  void setSecureLog(std::unique_ptr<raw_fd_ostream> Value) {
    SecureLog = std::move(Value);
  }

  bool getSecureLogUsed() { return SecureLogUsed; }
  void setSecureLogUsed(bool Value) { SecureLogUsed = Value; }

  void *allocate(unsigned Size, unsigned Align = 8) {
    return Allocator.Allocate(Size, Align);
  }

  void deallocate(void *Ptr) {}

  /// Allocates a copy of the given string on the allocator managed by this
  /// context and returns the result.
  StringRef allocateString(StringRef s) {
    return StringSaver(Allocator).save(s);
  }

  bool hadError() { return HadError; }
  LLVM_ABI void diagnose(const SMDiagnostic &SMD);
  LLVM_ABI void reportError(SMLoc L, const Twine &Msg);
  LLVM_ABI void reportWarning(SMLoc L, const Twine &Msg);

  MCAsmMacro *lookupMacro(StringRef Name) {
    StringMap<MCAsmMacro>::iterator I = MacroMap.find(Name);
    return (I == MacroMap.end()) ? nullptr : &I->getValue();
  }

  void defineMacro(StringRef Name, MCAsmMacro Macro) {
    MacroMap.insert(std::make_pair(Name, std::move(Macro)));
  }

  void undefineMacro(StringRef Name) { MacroMap.erase(Name); }

  MCPseudoProbeTable &getMCPseudoProbeTable() { return PseudoProbeTable; }
};

} // end namespace llvm

// operator new and delete aren't allowed inside namespaces.
// The throw specifications are mandated by the standard.
/// Placement new for using the MCContext's allocator.
///
/// This placement form of operator new uses the MCContext's allocator for
/// obtaining memory. It is a non-throwing new, which means that it returns
/// null on error. (If that is what the allocator does. The current does, so if
/// this ever changes, this operator will have to be changed, too.)
/// Usage looks like this (assuming there's an MCContext 'Context' in scope):
/// \code
/// // Default alignment (8)
/// IntegerLiteral *Ex = new (Context) IntegerLiteral(arguments);
/// // Specific alignment
/// IntegerLiteral *Ex2 = new (Context, 4) IntegerLiteral(arguments);
/// \endcode
/// Please note that you cannot use delete on the pointer; it must be
/// deallocated using an explicit destructor call followed by
/// \c Context.Deallocate(Ptr).
///
/// \param Bytes The number of bytes to allocate. Calculated by the compiler.
/// \param C The MCContext that provides the allocator.
/// \param Alignment The alignment of the allocated memory (if the underlying
///                  allocator supports it).
/// \return The allocated memory. Could be NULL.
inline void *operator new(size_t Bytes, llvm::MCContext &C,
                          size_t Alignment = 8) noexcept {
  return C.allocate(Bytes, Alignment);
}
/// Placement delete companion to the new above.
///
/// This operator is just a companion to the new above. There is no way of
/// invoking it directly; see the new operator for more details. This operator
/// is called implicitly by the compiler if a placement new expression using
/// the MCContext throws in the object constructor.
inline void operator delete(void *Ptr, llvm::MCContext &C, size_t) noexcept {
  C.deallocate(Ptr);
}

/// This placement form of operator new[] uses the MCContext's allocator for
/// obtaining memory. It is a non-throwing new[], which means that it returns
/// null on error.
/// Usage looks like this (assuming there's an MCContext 'Context' in scope):
/// \code
/// // Default alignment (8)
/// char *data = new (Context) char[10];
/// // Specific alignment
/// char *data = new (Context, 4) char[10];
/// \endcode
/// Please note that you cannot use delete on the pointer; it must be
/// deallocated using an explicit destructor call followed by
/// \c Context.Deallocate(Ptr).
///
/// \param Bytes The number of bytes to allocate. Calculated by the compiler.
/// \param C The MCContext that provides the allocator.
/// \param Alignment The alignment of the allocated memory (if the underlying
///                  allocator supports it).
/// \return The allocated memory. Could be NULL.
inline void *operator new[](size_t Bytes, llvm::MCContext &C,
                            size_t Alignment = 8) noexcept {
  return C.allocate(Bytes, Alignment);
}

/// Placement delete[] companion to the new[] above.
///
/// This operator is just a companion to the new[] above. There is no way of
/// invoking it directly; see the new[] operator for more details. This operator
/// is called implicitly by the compiler if a placement new[] expression using
/// the MCContext throws in the object constructor.
inline void operator delete[](void *Ptr, llvm::MCContext &C) noexcept {
  C.deallocate(Ptr);
}

#endif // LLVM_MC_MCCONTEXT_H
