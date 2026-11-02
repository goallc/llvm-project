#!/usr/bin/env bash

# Copyright 2026 The GoALLC Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

set -euo pipefail

usage() {
	cat <<'EOF'
usage: llvm/utils/goallc/build-payload.bash

Build and atomically install a complete GoALLC LLVM payload.

Configuration is supplied through environment variables:

  GOALLC_LLVM_SOURCE   llvm-project checkout (default: checkout containing this script)
  GOALLC_LLVM_BUILD    CMake build directory
  GOALLC_LLVM_INSTALL  installed LLVM payload directory (outside build tree)
  GOALLC_BUILD_TYPE    LLVM CMake build type (default: Release)
  GOALLC_LLVM_TARGETS  LLVM targets separated by semicolons (default: X86;AArch64)
  GOALLC_MACOS_DEPLOYMENT_TARGET
                       Darwin deployment target (default: Go's current 13.0)
  GOALLC_BUILD_JOBS    parallel LLVM build jobs
  GOALLC_CCACHE        ccache executable; auto-detected when unset
  GOALLC_CMAKE_TOOLCHAIN_FILE
                       optional CMake toolchain (Windows: llvm-mingw)
  GOALLC_DEPS_BUILD    pinned dependency build/cache directory

The default payload is an ignored build-goallc-payload-* directory at the
llvm-project root. The install is staged and then replaces the previous
payload as a directory, so a failed install cannot leave a partially updated
payload at the selected path.

EOF
}

die() {
	printf 'goallc build: %s\n' "$*" >&2
	exit 1
}

physical_dir() {
	(cd "$1" && pwd -P)
}

same_directory() {
	[[ -d "$1" && -d "$2" ]] || return 1
	[[ "$(physical_dir "$1")" == "$(physical_dir "$2")" ]]
}

script_dir=$(physical_dir "$(dirname "${BASH_SOURCE[0]}")")
default_llvm_project=$(physical_dir "$script_dir/../../..")
if [[ $# -eq 1 && ( "$1" == -h || "$1" == --help || "$1" == help ) ]]; then
	usage
	exit 0
fi
if [[ $# -ne 0 ]]; then
	usage >&2
	exit 2
fi

llvm_project=${GOALLC_LLVM_SOURCE:-"$default_llvm_project"}
[[ -d "$llvm_project/llvm" ]] || die "LLVM source directory not found: $llvm_project/llvm"
llvm_project=$(physical_dir "$llvm_project")
llvm_source="$llvm_project/llvm"

build_type=${GOALLC_BUILD_TYPE:-Release}
case "$build_type" in
Debug|Release|RelWithDebInfo|MinSizeRel)
	;;
*)
	die "unsupported GOALLC_BUILD_TYPE: $build_type"
	;;
esac
build_suffix=$(printf '%s' "$build_type" | tr '[:upper:]' '[:lower:]')
llvm_build=${GOALLC_LLVM_BUILD:-"$llvm_source/cmake-build-goallc-$build_suffix"}
llvm_install=${GOALLC_LLVM_INSTALL:-"$llvm_project/build-goallc-payload-$build_suffix"}
llvm_targets=${GOALLC_LLVM_TARGETS:-X86;AArch64}

mkdir -p "$(dirname "$llvm_build")" "$(dirname "$llvm_install")"
llvm_build=$(cd "$(dirname "$llvm_build")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$llvm_build")")
llvm_install=$(cd "$(dirname "$llvm_install")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$llvm_install")")
if command -v cygpath >/dev/null 2>&1; then
    llvm_build=$(cygpath -m "$llvm_build")
    llvm_install=$(cygpath -m "$llvm_install")
fi
case "$llvm_install" in
/|/usr|/usr/local|/opt|/opt/homebrew)
	die "refusing unsafe GOALLC_LLVM_INSTALL: $llvm_install"
	;;
esac
[[ "$llvm_install" != "$llvm_build" ]] || die "LLVM build and install directories must differ"
[[ "$llvm_install" != "$llvm_source" ]] || die "LLVM install directory must not be the source directory"
case "$llvm_install/" in
"$llvm_build"/*)
	die "LLVM install directory must be outside the LLVM build tree"
	;;
"$llvm_source"/*)
	die "LLVM install directory must be outside the LLVM source tree"
	;;
esac

if [[ -n ${GOALLC_BUILD_JOBS:-} ]]; then
	build_jobs=$GOALLC_BUILD_JOBS
elif command -v sysctl >/dev/null 2>&1; then
	build_jobs=$(sysctl -n hw.logicalcpu 2>/dev/null || printf '4')
elif command -v nproc >/dev/null 2>&1; then
	build_jobs=$(nproc)
else
	build_jobs=4
fi
case "$build_jobs" in
''|*[!0-9]*) die "GOALLC_BUILD_JOBS must be a positive integer" ;;
esac
[[ "$build_jobs" -gt 0 ]] || die "GOALLC_BUILD_JOBS must be a positive integer"

ccache_path=${GOALLC_CCACHE:-}
if [[ -z "$ccache_path" && -x /opt/homebrew/bin/ccache ]]; then
	ccache_path=/opt/homebrew/bin/ccache
elif [[ -z "$ccache_path" ]] && command -v ccache >/dev/null 2>&1; then
	ccache_path=$(command -v ccache)
fi
cmake_launcher_args=()
if [[ -n "$ccache_path" ]]; then
	[[ -x "$ccache_path" ]] || die "GOALLC_CCACHE is not executable: $ccache_path"
	ccache_path=$(cd "$(dirname "$ccache_path")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$ccache_path")")
	cmake_launcher_args+=(
		"-DCMAKE_C_COMPILER_LAUNCHER=$ccache_path"
		"-DCMAKE_CXX_COMPILER_LAUNCHER=$ccache_path"
	)
fi
cmake_platform_args=()
macos_deployment_target=
if [[ "$(uname -s)" == Darwin ]]; then
	macos_deployment_target=${GOALLC_MACOS_DEPLOYMENT_TARGET:-13.0}
	cmake_platform_args+=("-DCMAKE_OSX_DEPLOYMENT_TARGET=$macos_deployment_target")
fi

exe=
shared_llvm=ON
cmake_runtime_args=()
case "$(uname -s)" in
Darwin) ;;
Linux) cmake_runtime_args+=("-DCMAKE_EXE_LINKER_FLAGS=-static-libstdc++ -static-libgcc") ;;
MINGW*|MSYS*)
    exe=.exe
    shared_llvm=OFF
    cmake_runtime_args+=("-DCMAKE_EXE_LINKER_FLAGS=-static")
    ;;
*) die "unsupported host: $(uname -s)" ;;
esac
if [[ -n ${GOALLC_CMAKE_TOOLCHAIN_FILE:-} ]]; then
    cmake_platform_args+=("-DCMAKE_TOOLCHAIN_FILE=$GOALLC_CMAKE_TOOLCHAIN_FILE")
fi
deps_build=${GOALLC_DEPS_BUILD:-"$llvm_build-deps"}
deps_install="$deps_build/install"
GOALLC_DEPS_BUILD="$deps_build" GOALLC_DEPS_INSTALL="$deps_install" \
GOALLC_BUILD_JOBS="$build_jobs" "$script_dir/build-static-deps.bash"

payload_version() {
	"$1/bin/llvm-config$exe" --version
}

validate_payload_files() {
	local root=$1
	local path
	for path in \
		bin/llvm-config \
		bin/llvm-ar \
		bin/llc \
		bin/opt \
		bin/FileCheck; do
		[[ -x "$root/$path$exe" ]] || die "incomplete LLVM payload: missing executable $root/$path$exe"
	done
	for path in \
		include/llvm-c/Core.h \
		include/llvm/Config/llvm-config.h \
		lib/cmake/llvm/LLVMConfig.cmake \
		lib/cmake/llvm/AddLLVM.cmake \
		lib/cmake/llvm/LLVMExports.cmake \
		lib/libLLVMCore.a \
		lib/libz.a \
		lib/libzstd.a; do
		[[ -f "$root/$path" ]] || die "incomplete LLVM payload: missing $root/$path"
	done
	case "$(uname -s)" in
	Darwin)
		compgen -G "$root/lib/libLLVM*.dylib" >/dev/null || die "incomplete LLVM payload: missing libLLVM dylib"
		;;
	Linux)
		compgen -G "$root/lib/libLLVM.so*" >/dev/null || die "incomplete LLVM payload: missing libLLVM shared object"
		;;
	MINGW*|MSYS*) ;;
	*)
		die "unsupported host: $(uname -s)"
		;;
	esac
}

validate_payload() {
	local root=$1
	local expected_prefix=$2
	validate_payload_files "$root"
	case "$(payload_version "$root")" in
	23|23.*)
		;;
	*)
		die "LLVM payload must be version 23: $(payload_version "$root")"
		;;
	esac
	same_directory "$("$root/bin/llvm-config$exe" --prefix)" "$expected_prefix" || \
		die "LLVM payload prefix mismatch: expected $expected_prefix, got $("$root/bin/llvm-config$exe" --prefix)"
	local target
	local built_targets
	built_targets=" $("$root/bin/llvm-config$exe" --targets-built) "
	for target in $(printf '%s' "$llvm_targets" | tr ';' ' '); do
		case "$built_targets" in
		*" $target "*) ;;
		*) die "LLVM payload does not contain requested target $target" ;;
		esac
	done
}

stage_root=
backup_payload=
payload_activated=false
cleanup_install() {
	if [[ "$payload_activated" == true && ( -e "$llvm_install" || -L "$llvm_install" ) ]]; then
		rm -rf "$llvm_install"
	fi
	if [[ -n "$backup_payload" && -e "$backup_payload" ]]; then
		mv "$backup_payload" "$llvm_install"
	fi
	if [[ -n "$stage_root" && -d "$stage_root" ]]; then
		rm -rf "$stage_root"
	fi
}
trap cleanup_install EXIT
trap 'exit 1' HUP INT TERM

write_llvm_manifest() {
	local root=$1
	local revision=unknown
	local dirty=unknown
	if git -C "$llvm_project" rev-parse --verify HEAD >/dev/null 2>&1; then
		revision=$(git -C "$llvm_project" rev-parse HEAD)
		if [[ -n $(git -C "$llvm_project" status --porcelain --untracked-files=no) ]]; then
			dirty=true
		else
			dirty=false
		fi
	fi
	mkdir -p "$root/share/goallc"
	{
		printf 'format=1\n'
		printf 'dependency_mode=bundled-static\n'
		printf 'zlib=1.3.2\nzstd=1.5.7\n'
		printf 'llvm_revision=%s\n' "$revision"
		printf 'llvm_dirty=%s\n' "$dirty"
		printf 'build_type=%s\n' "$build_type"
		printf 'targets=%s\n' "$llvm_targets"
		printf 'build_dir=%s\n' "$llvm_build"
		printf 'install_prefix=%s\n' "$llvm_install"
		printf 'ccache=%s\n' "${ccache_path:-disabled}"
		if [[ -n "$macos_deployment_target" ]]; then
			printf 'macos_deployment_target=%s\n' "$macos_deployment_target"
		fi
	} >"$root/share/goallc/build-manifest"
}

build_llvm() {
	[[ ! -L "$llvm_install" ]] || \
		die "GOALLC_LLVM_INSTALL must name the real payload directory when building, not a symlink: $llvm_install"
	printf 'Configuring LLVM in %s\n' "$llvm_build"
	cmake -S "$llvm_source" -B "$llvm_build" -G Ninja \
		-DCMAKE_BUILD_TYPE="$build_type" \
		-DCMAKE_INSTALL_PREFIX="$llvm_install" \
		-DCMAKE_INSTALL_MESSAGE=NEVER \
		-DLLVM_ENABLE_PROJECTS= \
		-DLLVM_TARGETS_TO_BUILD="$llvm_targets" \
		-DLLVM_ENABLE_ASSERTIONS=ON \
		-DLLVM_BUILD_TESTS=OFF \
		-DLLVM_INCLUDE_TESTS=ON \
		-DLLVM_BUILD_TOOLS=ON \
		-DLLVM_BUILD_UTILS=ON \
		-DLLVM_INSTALL_UTILS=ON \
		-DLLVM_INCLUDE_EXAMPLES=OFF \
		-DLLVM_INCLUDE_BENCHMARKS=OFF \
		-DBUILD_SHARED_LIBS=OFF \
		-DLLVM_BUILD_LLVM_DYLIB="$shared_llvm" \
		-DLLVM_LINK_LLVM_DYLIB="$shared_llvm" \
		-DLLVM_ENABLE_RTTI=OFF \
		-DLLVM_ENABLE_ZLIB=FORCE_ON -DZLIB_USE_STATIC_LIBS=ON \
		-DLLVM_ENABLE_ZSTD=FORCE_ON -DLLVM_USE_STATIC_ZSTD=ON \
		-DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_LIBEDIT=OFF \
		-DLLVM_ENABLE_CURL=OFF -DLLVM_ENABLE_HTTPLIB=OFF \
		-DLLVM_ENABLE_TERMINFO=OFF \
		"-DCMAKE_PREFIX_PATH=$deps_install" \
		"-DZLIB_ROOT=$deps_install" \
		"-Dzstd_LIBRARY=$deps_install/lib/libzstd.a" \
		"-Dzstd_STATIC_LIBRARY=$deps_install/lib/libzstd.a" \
		"-Dzstd_INCLUDE_DIR=$deps_install/include" \
		'-DGOALLC_BUNDLED_STATIC_LIBS=z;zstd' \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
		${cmake_launcher_args[@]+"${cmake_launcher_args[@]}"} \
		${cmake_platform_args[@]+"${cmake_platform_args[@]}"} \
		${cmake_runtime_args[@]+"${cmake_runtime_args[@]}"}
	cmake --build "$llvm_build" --parallel "$build_jobs"

	stage_root=$(mktemp -d "$(dirname "$llvm_install")/.goallc-install.XXXXXX")
	printf 'Staging LLVM install under %s\n' "$stage_root"
	staged_payload="$stage_root/payload"
	cmake --install "$llvm_build" --prefix "$staged_payload"
	cp -R "$deps_install/include/." "$staged_payload/include/"
	cp -R "$deps_install/lib/." "$staged_payload/lib/"
	mkdir -p "$staged_payload/share/licenses"
	cp -R "$deps_install/share/licenses/." "$staged_payload/share/licenses/"
	cp "$llvm_source/LICENSE.TXT" "$staged_payload/share/licenses/llvm.txt"
	# Preserve compiler-runtime notices when those runtimes are embedded.
	if [[ "$(uname -s)" == Linux ]]; then
		for notice in /usr/share/doc/gcc-*-base/copyright /usr/share/doc/libstdc++*/copyright /usr/share/doc/libgcc*/copyright; do
			[[ -f "$notice" ]] || continue
			cp "$notice" "$staged_payload/share/licenses/$(basename "$(dirname "$notice")").txt"
		done
	fi
	if [[ -n ${GOALLC_TOOLCHAIN_LICENSE:-} ]]; then
		cp "$GOALLC_TOOLCHAIN_LICENSE" "$staged_payload/share/licenses/toolchain.txt"
	fi
	# Imported CMake targets and dependency lookup must survive relocation.
	python3 - "$staged_payload" "$deps_install" <<'PYRELOCATE'
import os, pathlib, sys
root = pathlib.Path(sys.argv[1])
old = sys.argv[2]
for p in (root / 'lib/cmake').rglob('*.cmake'):
    prefix = '${CMAKE_CURRENT_LIST_DIR}/' + os.path.relpath(root, p.parent)
    p.write_text(p.read_text().replace(old, prefix))
PYRELOCATE
	[[ -d "$staged_payload" ]] || die "CMake did not create staged payload $staged_payload"
	# Do not execute llvm-config under DESTDIR: it deliberately derives its
	# install layout from its current executable path. Check the complete file
	# set here and execute the tools only after activation at their final path.
	validate_payload_files "$staged_payload"
	write_llvm_manifest "$staged_payload"

	backup_payload=
	if [[ -e "$llvm_install" || -L "$llvm_install" ]]; then
		backup_payload="$llvm_install.previous.$$"
		[[ ! -e "$backup_payload" ]] || die "temporary backup already exists: $backup_payload"
		mv "$llvm_install" "$backup_payload"
	fi
	mv "$staged_payload" "$llvm_install"
	payload_activated=true
	validate_payload "$llvm_install" "$llvm_install"
	{
		printf 'llvm_version=%s\n' "$(payload_version "$llvm_install")"
		printf 'static_system_libs=%s\n' "$("$llvm_install/bin/llvm-config$exe" --link-static --system-libs)"
	} >>"$llvm_install/share/goallc/build-manifest"
	if [[ -n "$backup_payload" ]]; then
		rm -rf "$backup_payload"
		backup_payload=
	fi
	rm -rf "$stage_root"
	stage_root=
	payload_activated=false
	if [[ -n "$ccache_path" ]]; then
		"$ccache_path" -s
	fi
}

build_llvm
