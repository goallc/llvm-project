#!/usr/bin/env bash
# Pinned, PIC static dependencies for the relocatable LLVM payload.
set -euo pipefail
: "${GOALLC_DEPS_BUILD:?set GOALLC_DEPS_BUILD}"
: "${GOALLC_DEPS_INSTALL:?set GOALLC_DEPS_INSTALL}"
mkdir -p "$GOALLC_DEPS_BUILD" "$GOALLC_DEPS_INSTALL"
common=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  "-DCMAKE_INSTALL_PREFIX=$GOALLC_DEPS_INSTALL" -DCMAKE_INSTALL_LIBDIR=lib)
if [[ -n ${GOALLC_CCACHE:-} ]]; then
  common+=("-DCMAKE_C_COMPILER_LAUNCHER=$GOALLC_CCACHE" "-DCMAKE_CXX_COMPILER_LAUNCHER=$GOALLC_CCACHE")
fi
if [[ $(uname -s) == Darwin ]]; then
  common+=("-DCMAKE_OSX_DEPLOYMENT_TARGET=${GOALLC_MACOS_DEPLOYMENT_TARGET:-13.0}")
fi
if [[ -n ${GOALLC_CMAKE_TOOLCHAIN_FILE:-} ]]; then
  common+=("-DCMAKE_TOOLCHAIN_FILE=$GOALLC_CMAKE_TOOLCHAIN_FILE")
fi
fetch() {
  local name=$1 url=$2 sha=$3
  local archive="$GOALLC_DEPS_BUILD/$name.tar.gz"
  if [[ ! -f $archive ]]; then
    curl --fail --location --retry 5 "$url" -o "$archive.tmp"
    mv "$archive.tmp" "$archive"
  fi
  python3 - "$archive" "$sha" <<'PY'
import hashlib, pathlib, sys
p = pathlib.Path(sys.argv[1])
if hashlib.sha256(p.read_bytes()).hexdigest() != sys.argv[2]:
    raise SystemExit('SHA-256 mismatch: ' + str(p))
PY
  if [[ ! -d "$GOALLC_DEPS_BUILD/$name" ]]; then
    tar -xzf "$archive" -C "$GOALLC_DEPS_BUILD"
  fi
}
fetch zlib-1.3.2 https://zlib.net/fossils/zlib-1.3.2.tar.gz bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16
fetch zstd-1.5.7 https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3
cmake -S "$GOALLC_DEPS_BUILD/zlib-1.3.2" -B "$GOALLC_DEPS_BUILD/zlib-build" "${common[@]}" \
  -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_STATIC=ON -DZLIB_BUILD_TESTING=OFF
cmake --build "$GOALLC_DEPS_BUILD/zlib-build" --parallel "${GOALLC_BUILD_JOBS:-4}"
cmake --install "$GOALLC_DEPS_BUILD/zlib-build"
# zlib uses a different static basename on Windows; expose a uniform archive.
if [[ -f "$GOALLC_DEPS_INSTALL/lib/libzs.a" ]]; then
  cp "$GOALLC_DEPS_INSTALL/lib/libzs.a" "$GOALLC_DEPS_INSTALL/lib/libz.a"
fi
cmake -S "$GOALLC_DEPS_BUILD/zstd-1.5.7/build/cmake" -B "$GOALLC_DEPS_BUILD/zstd-build" "${common[@]}" \
  -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF
cmake --build "$GOALLC_DEPS_BUILD/zstd-build" --parallel "${GOALLC_BUILD_JOBS:-4}"
cmake --install "$GOALLC_DEPS_BUILD/zstd-build"
mkdir -p "$GOALLC_DEPS_INSTALL/share/licenses/goallc-deps"
cp "$GOALLC_DEPS_BUILD/zlib-1.3.2/LICENSE" "$GOALLC_DEPS_INSTALL/share/licenses/goallc-deps/zlib.txt"
cp "$GOALLC_DEPS_BUILD/zstd-1.5.7/LICENSE" "$GOALLC_DEPS_INSTALL/share/licenses/goallc-deps/zstd.txt"
