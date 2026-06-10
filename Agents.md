# GoObj/Go Toolchain Integration Notes

This branch contains the initial LLVM-side support for emitting Go link object
files and integrating LLVM IR into the Go toolchain through `go build
-toolexec`.

## Current Branch State

- Working branch: `codex/goobj-support`
- Remote repository used for this work:
  `git@github.com:zhouguangyuan0718/llvm-project.git`
- Important commits:
  - `c94609213323` - Add Go object file support
  - `fbfd2a9d3c98` - Support GoObj emission from LLVM IR
  - `2737bfdd3157` - Add GoObj toolexec integration tool
  - `7ed69afd615f` - Discover GoObj IR inputs from Go packages

## Implemented Capabilities

- Added GoObj object format support sufficient for Go toolchain experiments.
- Added LLVM IR to GoObj emission from LLVM CodeGen.
- Added `llvm-goobj-toolexec`, a real LLVM tool for `go build -toolexec`
  integration.
- `llvm-goobj-toolexec` now:
  - passes through non-`compile` Go tool invocations unchanged;
  - scans the Go package source directory for local `.ll` files during each Go
    `compile` invocation;
  - infers exported LLVM IR functions and emits a temporary Go `symabis` file;
  - removes Go compile `-complete` when symabis entries are present, because
    bodyless Go declarations otherwise fail under `-complete`;
  - compiles the discovered LLVM IR to GoObj object files through LLVM CodeGen;
  - appends those objects into the Go package archive using either a sibling
    `pack` tool or `go tool pack`;
  - still supports explicit `--llvm-ir`, restricted to `main` by default or to
    `--compile-package` / `--package-path` when provided.

## Key Files

- `llvm/tools/llvm-goobj-toolexec/llvm-goobj-toolexec.cpp`
- `llvm/tools/llvm-goobj-toolexec/CMakeLists.txt`
- `llvm/lib/CodeGen/CodeGenTargetMachineImpl.cpp`
- `llvm/test/CodeGen/X86/goobj-filetype.ll`
- `llvm/test/CodeGen/X86/goobj-link-go-toolchain.test`
- `llvm/test/CodeGen/X86/goobj-toolexec-go-toolchain.test`
- `llvm/test/CodeGen/X86/Inputs/goobj-toolexec-module/`
- `llvm/test/MC/GoObj/`

## Test Shape

The current toolexec test intentionally uses a real Go-style module layout
instead of a Python wrapper:

- `cmd/app` is the `main` package.
- `dep` is an imported package.
- `dep/answer.go` declares a bodyless function.
- `dep/answer.ll` defines the corresponding Go symbol.
- The test builds the main package with:

```sh
go build -a -ldflags=-w -toolexec llvm-goobj-toolexec -o toolexec-linked ./cmd/app
```

The `-ldflags=-w` requirement is intentional for now because generated GoObj
does not yet provide the Go DWARF metadata expected by the Go linker.

## Validation Commands

From the repository root:

```sh
ninja -C llvm/cmake-build-debug llvm-goobj-toolexec -j6
llvm/cmake-build-debug/bin/llvm-lit \
  llvm/test/CodeGen/X86/goobj-filetype.ll \
  llvm/test/CodeGen/X86/goobj-link-go-toolchain.test \
  llvm/test/CodeGen/X86/goobj-toolexec-go-toolchain.test \
  llvm/test/MC/GoObj -v
git diff --check
```

The tests currently assume the local Go 1.26 tree at:

```text
/home/zgy/02.golang/stablego/go1.26
```

## Known Limitations / Next Work

- DWARF is not supported yet for generated GoObj; continue requiring
  `-ldflags=-w` until Go-compatible debug metadata is implemented.
- Archive `PKGDEF` generation is intentionally out of scope for now.
- The current IR discovery is package-directory based and only scans immediate
  `.ll` files next to the package's `.go` sources.
- Go ABI support is selected only from explicit LLVM IR calling conventions:
  `goabi0` maps to Go `ABI0`, and `goabiinternal` maps to Go `ABIInternal`.
- The LLVM IR functions used by Go stubs need Go symbol names such as
  `example.com/module/pkg.Func`.
- Future work toward a Go compiler backend should preserve the package-oriented
  flow: Go source package -> Go compile package archive -> LLVM-generated GoObj
  members appended to that archive -> Go linker.
