//===-- llvm-goobj-toolexec.cpp - Go toolchain integration ------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// A go build -toolexec wrapper that augments a Go package archive with LLVM IR
// compiled as Go object files.
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/Analysis/CGSCCPassManager.h"
#include "llvm/Analysis/RuntimeLibcallInfo.h"
#include "llvm/Analysis/TargetLibraryInfo.h"
#include "llvm/CodeGen/CommandFlags.h"
#include "llvm/CodeGen/GoCallingConv.h"
#include "llvm/CodeGen/LinkAllCodegenComponents.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/IR/DiagnosticPrinter.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassManager.h"
#include "llvm/IR/Verifier.h"
#include "llvm/IRReader/IRReader.h"
#include "llvm/InitializePasses.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Passes/OptimizationLevel.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Support/CodeGen.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/InitLLVM.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/Program.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/WithColor.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetLoweringObjectFile.h"
#include "llvm/Target/TargetMachine.h"
#include <algorithm>
#include <memory>
#include <optional>
#include <string>

using namespace llvm;

static codegen::RegisterCodeGenFlags CGF;
static codegen::RegisterMTuneFlag MTF;

static cl::OptionCategory GoObjToolCat("llvm-goobj-toolexec options");

static cl::list<std::string>
    IRInputs("llvm-ir",
             cl::desc("Additional LLVM IR file to compile for the "
                      "selected Go package archive"),
             cl::value_desc("path"), cl::ZeroOrMore, cl::cat(GoObjToolCat));

static cl::opt<std::string>
    PackagePath("package-path",
                cl::desc("Go package path to record in generated Go object "
                         "files (default: compile -p value)"),
                cl::value_desc("path"), cl::cat(GoObjToolCat));

static cl::opt<std::string>
    CompilePackage("compile-package",
                   cl::desc("Only augment this Go compile package "
                            "(default: augment packages with local .ll files)"),
                   cl::value_desc("package"), cl::cat(GoObjToolCat));

static cl::opt<std::string>
    GoPackTool("go-pack-tool",
               cl::desc("Path to Go pack tool (default: sibling of the Go "
                        "tool being wrapped, or go tool pack)"),
               cl::value_desc("path"), cl::cat(GoObjToolCat));

static cl::opt<std::string>
    TargetTriple("mtriple",
                 cl::desc("Override target triple for LLVM IR compilation "
                          "(default: infer from the wrapped Go compiler)"),
                 cl::value_desc("triple"), cl::cat(GoObjToolCat));

static cl::opt<char>
    OptLevel("O",
             cl::desc("Optimization level. [-O0, -O1, -O2, or -O3] "
                      "(default = '-O2')"),
             cl::Prefix, cl::init('2'), cl::cat(GoObjToolCat));

static cl::opt<bool>
    DisableVerify("disable-verify",
                  cl::desc("Do not verify LLVM IR before code generation"),
                  cl::init(false), cl::cat(GoObjToolCat));

static cl::opt<std::string> GoToolPath(cl::Positional,
                                       cl::desc("<go tool path>"),
                                       cl::cat(GoObjToolCat));

static cl::list<std::string> GoToolArgs(cl::ConsumeAfter,
                                        cl::desc("<go tool arguments>..."),
                                        cl::cat(GoObjToolCat));

namespace {
class GoObjDiagnosticHandler : public DiagnosticHandler {
public:
  bool HasErrors = false;

  bool handleDiagnostics(const DiagnosticInfo &DI) override {
    if (DI.getSeverity() == DS_Error)
      HasErrors = true;
    DiagnosticPrinterRawOStream DP(errs());
    DI.print(DP);
    errs() << '\n';
    return true;
  }
};

struct SymabisSymbol {
  std::string Name;
  std::string ABI;
};

struct GoObjectHeader {
  std::string GOOS;
  std::string GOARCH;
  std::string Version;
  std::string Experiments;
};
} // namespace

static void reportError(Twine Msg) {
  WithColor::error(errs(), "llvm-goobj-toolexec") << Msg << '\n';
}

static std::optional<std::string> getGoToolFlag(ArrayRef<std::string> Args,
                                                StringRef Flag) {
  for (size_t I = 0; I != Args.size(); ++I) {
    StringRef Arg = Args[I];
    if (Arg == Flag && I + 1 != Args.size())
      return Args[I + 1];
    std::string Prefix = (Flag + "=").str();
    if (Arg.starts_with(Prefix))
      return Arg.drop_front(Prefix.size()).str();
  }
  return std::nullopt;
}

static int execute(ArrayRef<std::string> Args) {
  SmallVector<StringRef, 16> ArgRefs;
  for (const std::string &Arg : Args)
    ArgRefs.push_back(Arg);

  std::string ErrMsg;
  bool ExecutionFailed = false;
  int RC = sys::ExecuteAndWait(ArgRefs[0], ArgRefs, std::nullopt, {}, 0, 0,
                               &ErrMsg, &ExecutionFailed);
  if (ExecutionFailed) {
    reportError("failed to execute '" + Twine(ArgRefs[0]) + "': " + ErrMsg);
    return 1;
  }
  if (RC < 0) {
    reportError("'" + Twine(ArgRefs[0]) + "' exited abnormally");
    return 1;
  }
  return RC;
}

static bool ensureGoObjPackagePath(StringRef Path) {
  auto &Options = cl::getRegisteredOptions();
  auto It = Options.find("goobj-package-path");
  if (It == Options.end())
    return false;
  if (It->second->getNumOccurrences() != 0)
    return true;
  return !It->second->addOccurrence(0, "goobj-package-path", Path);
}

static bool setCodeGenOption(StringRef Name, StringRef Value) {
  auto &Options = cl::getRegisteredOptions();
  auto It = Options.find(Name);
  if (It == Options.end())
    return false;
  if (It->second->getNumOccurrences() != 0)
    return true;
  return !It->second->addOccurrence(0, Name, Value);
}

static Expected<GoObjectHeader> readGoObjectHeader(StringRef ArchivePath) {
  ErrorOr<std::unique_ptr<MemoryBuffer>> BufferOrErr =
      MemoryBuffer::getFile(ArchivePath, /*IsText=*/false,
                            /*RequiresNullTerminator=*/false);
  if (!BufferOrErr)
    return createStringError(BufferOrErr.getError(),
                             "cannot read Go archive '" + ArchivePath + "'");

  StringRef Buffer = (*BufferOrErr)->getBuffer();
  size_t HeaderPos = Buffer.find("go object ");
  if (HeaderPos == StringRef::npos)
    return createStringError(inconvertibleErrorCode(),
                             "Go archive has no object header: " + ArchivePath);

  StringRef HeaderLine = Buffer.drop_front(HeaderPos).take_until(
      [](char C) { return C == '\n' || C == '\r'; });
  SmallVector<StringRef, 8> Fields;
  HeaderLine.split(Fields, ' ', /*MaxSplit=*/-1, /*KeepEmpty=*/false);
  if (Fields.size() < 5 || Fields[0] != "go" || Fields[1] != "object")
    return createStringError(inconvertibleErrorCode(),
                             "malformed Go object header in '" + ArchivePath +
                                 "'");

  GoObjectHeader Header{Fields[2].str(), Fields[3].str(), Fields[4].str(), ""};
  for (StringRef Field : drop_begin(Fields, 5))
    if (Field.consume_front("X:"))
      Header.Experiments = Field.str();
  return Header;
}

static Expected<std::string> getGoObjTriple(const GoObjectHeader &Header) {
  StringRef Arch;
  if (Header.GOARCH == "amd64")
    Arch = "x86_64";
  else if (Header.GOARCH == "arm64")
    Arch = "aarch64";
  else
    return createStringError(inconvertibleErrorCode(),
                             "unsupported Go architecture: " + Header.GOARCH);

  StringRef Vendor = Header.GOOS == "darwin" ? "apple" : "unknown";
  return (Arch + "-" + Vendor + "-" + Header.GOOS + "-goobj").str();
}

static Error configureGoObjForArchive(StringRef ArchivePath) {
  Expected<GoObjectHeader> HeaderOrErr = readGoObjectHeader(ArchivePath);
  if (!HeaderOrErr)
    return HeaderOrErr.takeError();
  const GoObjectHeader &Header = *HeaderOrErr;

  if (TargetTriple.empty()) {
    Expected<std::string> TripleOrErr = getGoObjTriple(Header);
    if (!TripleOrErr)
      return TripleOrErr.takeError();
    TargetTriple = *TripleOrErr;
  }

  if (!setCodeGenOption("goobj-version", Header.Version) ||
      !setCodeGenOption("goobj-experiments", Header.Experiments))
    return createStringError(inconvertibleErrorCode(),
                             "GoObj code generation options are unavailable");

  if (llvm::is_contained(GoToolArgs, "-shared") &&
      !setCodeGenOption("goobj-shared", "true"))
    return createStringError(inconvertibleErrorCode(),
                             "GoObj shared option is unavailable");
  return Error::success();
}

static void initializeCodeGenForTool() {
  InitializeAllTargets();
  InitializeAllTargetMCs();
  InitializeAllAsmPrinters();
  InitializeAllAsmParsers();

  PassRegistry &Registry = *PassRegistry::getPassRegistry();
  initializeCore(Registry);
  initializeCodeGen(Registry);
  initializeLoopStrengthReducePass(Registry);
  initializePostInlineEntryExitInstrumenterPass(Registry);
  initializeUnreachableBlockElimLegacyPassPass(Registry);
  initializeConstantHoistingLegacyPassPass(Registry);
  initializeScalarOpts(Registry);
  initializeIPO(Registry);
  initializeVectorization(Registry);
  initializeScalarizeMaskedMemIntrinLegacyPassPass(Registry);
  initializeTransformUtils(Registry);
  initializeScavengerTestPass(Registry);
}

static std::optional<OptimizationLevel> getIROptimizationLevel(char Level) {
  switch (Level) {
  case '0':
    return std::nullopt;
  case '1':
    return OptimizationLevel::O1;
  case '2':
    return OptimizationLevel::O2;
  case '3':
    return OptimizationLevel::O3;
  default:
    return std::nullopt;
  }
}

static void optimizeIRModule(Module &M, TargetMachine &TM, char Level) {
  std::optional<OptimizationLevel> IROptLevel = getIROptimizationLevel(Level);
  if (!IROptLevel)
    return;

  LoopAnalysisManager LAM;
  FunctionAnalysisManager FAM;
  CGSCCAnalysisManager CGAM;
  ModuleAnalysisManager MAM;

  PassBuilder PB(&TM);
  TargetLibraryInfoImpl TLII(M.getTargetTriple(), TM.Options.VecLib);
  FAM.registerPass([&] { return TargetLibraryAnalysis(TLII); });
  MAM.registerPass([&] {
    return RuntimeLibraryAnalysis(
        M.getTargetTriple(), TM.Options.ExceptionModel, TM.Options.FloatABIType,
        TM.Options.EABIVersion, TM.Options.MCOptions.ABIName,
        TM.Options.VecLib);
  });

  PB.registerModuleAnalyses(MAM);
  PB.registerCGSCCAnalyses(CGAM);
  PB.registerFunctionAnalyses(FAM);
  PB.registerLoopAnalyses(LAM);
  PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);

  ModulePassManager MPM = PB.buildPerModuleDefaultPipeline(*IROptLevel);
  MPM.run(M, MAM);
}

static std::optional<StringRef> getSymabisABIForFunction(const Function &F) {
  if (goabi::isGoABIInternalCallingConv(F.getCallingConv()))
    return StringRef("ABIInternal");
  if (goabi::isGoABI0CallingConv(F.getCallingConv()))
    return StringRef("ABI0");
  return std::nullopt;
}

static void addSymabisSymbol(SmallVectorImpl<SymabisSymbol> &Symbols,
                             StringSet<> &Seen, StringRef Symbol,
                             StringRef ABI) {
  if (Seen.insert(Symbol).second)
    Symbols.push_back({Symbol.str(), ABI.str()});
}

static void addIRInput(SmallVectorImpl<std::string> &Inputs, StringSet<> &Seen,
                       StringRef IRPath) {
  if (Seen.insert(IRPath).second)
    Inputs.push_back(IRPath.str());
}

static void addSourceDirectory(SmallVectorImpl<std::string> &Dirs,
                               StringSet<> &Seen, StringRef SourcePath) {
  if (!sys::path::extension(SourcePath).equals_insensitive(".go"))
    return;

  SmallString<128> Dir(SourcePath);
  sys::path::remove_filename(Dir);
  if (Dir.empty())
    Dir = ".";
  if (Seen.insert(Dir).second)
    Dirs.push_back(std::string(Dir));
}

static Error collectPackageIRInputs(SmallVectorImpl<std::string> &Inputs,
                                    StringSet<> &SeenInputs) {
  SmallVector<std::string, 8> SourceDirs;
  StringSet<> SeenDirs;
  for (const std::string &Arg : GoToolArgs)
    addSourceDirectory(SourceDirs, SeenDirs, Arg);

  SmallVector<std::string, 8> Discovered;
  for (const std::string &Dir : SourceDirs) {
    std::error_code EC;
    for (sys::fs::directory_iterator It(Dir, EC), End; !EC && It != End;
         It.increment(EC)) {
      StringRef Path = It->path();
      if (!sys::path::extension(Path).equals_insensitive(".ll"))
        continue;
      if (sys::fs::is_regular_file(Path))
        Discovered.push_back(Path.str());
    }
    if (EC)
      return createStringError(EC, "cannot scan package directory '" + Dir +
                                       "' for LLVM IR files");
  }

  std::sort(Discovered.begin(), Discovered.end());
  for (const std::string &IR : Discovered)
    addIRInput(Inputs, SeenInputs, IR);
  return Error::success();
}

static Error collectSymabisSymbols(StringRef IRPath,
                                   SmallVectorImpl<SymabisSymbol> &Symbols,
                                   StringSet<> &Seen) {
  LLVMContext Context;
  SMDiagnostic Err;
  std::unique_ptr<Module> M = parseIRFile(IRPath, Err, Context);
  if (!M) {
    std::string Msg;
    raw_string_ostream OS(Msg);
    Err.print("llvm-goobj-toolexec", OS);
    return createStringError(inconvertibleErrorCode(), OS.str());
  }

  for (const Function &F : *M) {
    if (F.isDeclaration() || F.hasLocalLinkage() || F.getName().empty())
      continue;
    if (std::optional<StringRef> ABI = getSymabisABIForFunction(F))
      addSymabisSymbol(Symbols, Seen, F.getName(), *ABI);
  }
  return Error::success();
}

static SmallVector<std::string, 16> getGoToolCommand() {
  SmallVector<std::string, 16> Args;
  Args.push_back(GoToolPath);
  llvm::append_range(Args, GoToolArgs);
  return Args;
}

static bool shouldAddExplicitIRInputs(StringRef GoPackage) {
  if (IRInputs.empty())
    return false;
  if (!CompilePackage.empty())
    return GoPackage == CompilePackage;
  if (!PackagePath.empty())
    return GoPackage == PackagePath;
  return GoPackage == "main";
}

static int compileIRToGoObj(StringRef IRPath, StringRef ObjPath,
                            StringRef Package) {
  LLVMContext Context;
  auto DiagHandler = std::make_unique<GoObjDiagnosticHandler>();
  GoObjDiagnosticHandler *DiagHandlerPtr = DiagHandler.get();
  Context.setDiagnosticHandler(std::move(DiagHandler));

  SMDiagnostic Err;
  std::unique_ptr<Module> M = parseIRFile(IRPath, Err, Context);
  if (!M) {
    Err.print("llvm-goobj-toolexec", WithColor::error(errs()));
    return 1;
  }

  Triple TT(Triple::normalize(TargetTriple));
  if (!TT.isOSBinFormatGoObj()) {
    reportError("target triple must use the GoObj object format: " +
                Twine(TargetTriple));
    return 1;
  }

  M->setTargetTriple(TT);

  std::optional<CodeGenOptLevel> CGOptLevel = CodeGenOpt::parseLevel(OptLevel);
  if (!CGOptLevel) {
    reportError("invalid optimization level");
    return 1;
  }

  Expected<std::unique_ptr<TargetMachine>> TargetOrErr =
      codegen::createTargetMachineForTriple(TT.getTriple(), *CGOptLevel);
  if (!TargetOrErr) {
    logAllUnhandledErrors(TargetOrErr.takeError(), errs(),
                          "llvm-goobj-toolexec: ");
    return 1;
  }
  std::unique_ptr<TargetMachine> Target = std::move(*TargetOrErr);
  M->setDataLayout(Target->createDataLayout());

  if (!DisableVerify && verifyModule(*M, &errs())) {
    reportError("input module cannot be verified: " + Twine(IRPath));
    return 1;
  }

  codegen::setFunctionAttributes(*M, codegen::getCPUStr(),
                                 codegen::getFeaturesStr(),
                                 codegen::getTuneCPUStr());

  optimizeIRModule(*M, *Target, OptLevel);

  if (!DisableVerify && verifyModule(*M, &errs())) {
    reportError("optimized module cannot be verified: " + Twine(IRPath));
    return 1;
  }

  std::error_code EC;
  ToolOutputFile Out(ObjPath, EC, sys::fs::OF_None);
  if (EC) {
    reportError("cannot open '" + Twine(ObjPath) + "': " + EC.message());
    return 1;
  }

  if (!ensureGoObjPackagePath(Package)) {
    reportError("GoObj package path option is unavailable");
    return 1;
  }

  Target->Options.ObjectFilenameForDebug = Out.outputFilename();
  Target->Options.VerifyArgABICompliance = 0;

  legacy::PassManager PM;
  TargetLibraryInfoImpl TLII(M->getTargetTriple(), Target->Options.VecLib);
  PM.add(new TargetLibraryInfoWrapperPass(TLII));
  PM.add(new RuntimeLibraryInfoWrapper(
      TT, Target->Options.ExceptionModel, Target->Options.FloatABIType,
      Target->Options.EABIVersion, Target->Options.MCOptions.ABIName,
      Target->Options.VecLib));

  bool HasMCErrors = false;
  MachineModuleInfoWrapperPass *MMIWP =
      new MachineModuleInfoWrapperPass(Target.get());
  MCContext &MCCtx = MMIWP->getMMI().getContext();
  MCCtx.setDiagnosticHandler([&](const SMDiagnostic &SMD, bool,
                                 const SourceMgr &,
                                 std::vector<const MDNode *> &) {
    WithColor::error(errs(), "llvm-goobj-toolexec") << SMD.getMessage() << '\n';
    HasMCErrors = true;
  });

  if (Target->addPassesToEmitFile(PM, Out.os(), nullptr,
                                  CodeGenFileType::ObjectFile, DisableVerify,
                                  MMIWP)) {
    if (!HasMCErrors)
      reportError("target does not support GoObj object emission");
    return 1;
  }

  Target->getObjFileLowering()->Initialize(MMIWP->getMMI().getContext(),
                                           *Target);
  PM.run(*M);

  if (DiagHandlerPtr->HasErrors || HasMCErrors)
    return 1;

  Out.keep();
  return 0;
}

static SmallVector<std::string, 4> getPackCommand() {
  if (!GoPackTool.empty())
    return {GoPackTool};

  SmallString<128> Path(GoToolPath);
  sys::path::remove_filename(Path);
  std::string PackName = "pack";
  if (sys::path::extension(GoToolPath).equals_insensitive(".exe"))
    PackName += ".exe";
  sys::path::append(Path, PackName);
  if (sys::fs::can_execute(Path))
    return {std::string(Path)};

  SmallString<128> GoBin(GoToolPath);
  for (int I = 0; I != 4; ++I)
    sys::path::remove_filename(GoBin);
  std::string GoName = "go";
  if (sys::path::extension(GoToolPath).equals_insensitive(".exe"))
    GoName += ".exe";
  sys::path::append(GoBin, "bin", GoName);
  if (sys::fs::can_execute(GoBin))
    return {std::string(GoBin), "tool", "pack"};

  return {};
}

static int runAugmentedCompile(ArrayRef<std::string> ActiveIRInputs) {
  if (ActiveIRInputs.empty())
    return execute(getGoToolCommand());

  std::optional<std::string> Output = getGoToolFlag(GoToolArgs, "-o");
  if (!Output) {
    reportError("wrapped compile command has no -o output archive");
    return 1;
  }

  std::string GoPackage = getGoToolFlag(GoToolArgs, "-p").value_or("");
  std::string ObjectPackage = PackagePath.empty() ? GoPackage : PackagePath;
  if (ObjectPackage.empty()) {
    reportError("cannot infer Go package path; pass --package-path");
    return 1;
  }

  SmallVector<SymabisSymbol, 8> Symbols;
  StringSet<> SeenSymbols;
  for (const std::string &IR : ActiveIRInputs) {
    if (Error Err = collectSymabisSymbols(IR, Symbols, SeenSymbols)) {
      logAllUnhandledErrors(std::move(Err), errs());
      return 1;
    }
  }

  SmallString<128> WorkDir(*Output);
  sys::path::remove_filename(WorkDir);
  if (WorkDir.empty())
    WorkDir = ".";

  SmallVector<std::string, 32> CompileArgs;
  CompileArgs.push_back(GoToolPath);
  if (!Symbols.empty()) {
    SmallString<128> SymabisPath(WorkDir);
    sys::path::append(SymabisPath, "llvm-goobj.symabis");

    std::error_code EC;
    raw_fd_ostream SymabisOS(SymabisPath, EC, sys::fs::OF_Text);
    if (EC) {
      reportError("cannot write '" + Twine(SymabisPath) + "': " + EC.message());
      return 1;
    }
    for (const SymabisSymbol &Symbol : Symbols)
      SymabisOS << "def " << Symbol.Name << ' ' << Symbol.ABI << '\n';
    SymabisOS.close();
    if (SymabisOS.has_error()) {
      reportError("cannot write '" + Twine(SymabisPath) + "'");
      return 1;
    }

    CompileArgs.push_back("-symabis");
    CompileArgs.push_back(std::string(SymabisPath));
  }

  for (const std::string &Arg : GoToolArgs) {
    if (!Symbols.empty() && Arg == "-complete")
      continue;
    CompileArgs.push_back(Arg);
  }

  if (int RC = execute(CompileArgs))
    return RC;

  if (Error Err = configureGoObjForArchive(*Output)) {
    logAllUnhandledErrors(std::move(Err), errs(), "llvm-goobj-toolexec: ");
    return 1;
  }

  SmallVector<std::string, 8> ObjectPaths;
  for (size_t I = 0; I != ActiveIRInputs.size(); ++I) {
    SmallString<128> ObjPath(WorkDir);
    sys::path::append(ObjPath, "llvm-goobj-" + Twine(I) + ".o");
    if (int RC = compileIRToGoObj(ActiveIRInputs[I], ObjPath, ObjectPackage))
      return RC;
    ObjectPaths.push_back(std::string(ObjPath));
  }

  SmallVector<std::string, 16> PackArgs = getPackCommand();
  if (PackArgs.empty()) {
    reportError("cannot find Go pack tool; pass --go-pack-tool");
    return 1;
  }
  PackArgs.push_back("r");
  PackArgs.push_back(*Output);
  llvm::append_range(PackArgs, ObjectPaths);
  return execute(PackArgs);
}

int main(int argc, char **argv) {
  InitLLVM X(argc, argv);
  initializeCodeGenForTool();

  cl::HideUnrelatedOptions(GoObjToolCat);
  cl::ParseCommandLineOptions(
      argc, argv,
      "go build -toolexec wrapper for adding LLVM IR GoObj objects\n");

  if (GoToolPath.empty()) {
    reportError("missing Go tool path; this tool is intended for go "
                "build -toolexec");
    return 1;
  }

  std::string GoToolName = sys::path::filename(GoToolPath).str();
  if (GoToolName != "compile")
    return execute(getGoToolCommand());

  std::string GoPackage = getGoToolFlag(GoToolArgs, "-p").value_or("");
  if (!CompilePackage.empty() && GoPackage != CompilePackage)
    return execute(getGoToolCommand());

  SmallVector<std::string, 8> ActiveIRInputs;
  StringSet<> SeenInputs;
  if (Error Err = collectPackageIRInputs(ActiveIRInputs, SeenInputs)) {
    logAllUnhandledErrors(std::move(Err), errs(), "llvm-goobj-toolexec: ");
    return 1;
  }
  if (shouldAddExplicitIRInputs(GoPackage)) {
    for (const std::string &IR : IRInputs)
      addIRInput(ActiveIRInputs, SeenInputs, IR);
  }

  return runAugmentedCompile(ActiveIRInputs);
}
