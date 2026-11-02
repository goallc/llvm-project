#!/usr/bin/env bash
set -euo pipefail
root=$1
revision=$2
exe=
case $(uname -s) in MINGW*|MSYS*) exe=.exe ;; esac
config="$root/bin/llvm-config$exe"
# Resolve both paths through Python because Git Bash and native Windows tools
# can spell the same path differently.
python3 - "$root" "$("$config" --prefix)" <<'PY'
import pathlib, sys
assert pathlib.Path(sys.argv[1]).resolve() == pathlib.Path(sys.argv[2]).resolve()
PY
test "$("$config" --version)" = 23.1.4
test "$("$config" --build-mode)" = Release
grep -Fx "llvm_revision=$revision" "$root/share/goallc/build-manifest"
grep -Fx 'llvm_dirty=false' "$root/share/goallc/build-manifest"
grep -Fx 'dependency_mode=bundled-static' "$root/share/goallc/build-manifest"
for target in X86 AArch64; do
  "$config" --targets-built | tr ' ' '\n' | grep -Fx "$target"
done
for tool in FileCheck llc llvm-ar llvm-config opt; do
  test -f "$root/bin/$tool$exe"
done
for file in lib/libLLVMCore.a lib/libz.a lib/libzstd.a include/llvm-c/Core.h lib/cmake/llvm/LLVMConfig.cmake; do
  test -f "$root/$file"
done
for tool in llc opt; do
  env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH "$root/bin/$tool$exe" --version
 done
libs=$("$config" --link-static --system-libs)
case "$libs" in *libzstd.a*|*/opt/homebrew/*) echo "nonrelocatable system libs: $libs" >&2; exit 1 ;; esac
# CMake consumers must find the bundled dependencies after relocation too.
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
cat > "$probe/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.20)
project(PayloadConsumer LANGUAGES C CXX)
find_package(LLVM REQUIRED CONFIG)
if(NOT TARGET zstd::libzstd_static)
  message(FATAL_ERROR "missing bundled static zstd")
endif()
CMAKE
cmake -S "$probe" -B "$probe/build" -G Ninja -DLLVM_DIR="$root/lib/cmake/llvm"
