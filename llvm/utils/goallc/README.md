# GoALLC LLVM payloads

`build-payload.bash` is the canonical builder for the installed LLVM payload
consumed by the GoALLC Go repository. It deliberately keeps the CMake build
tree separate from the install tree, stages `cmake --install`, validates the
complete development payload, and replaces the selected install directory as
one unit.

From the llvm-project checkout root:

```sh
GOALLC_LLVM_BUILD=/path/to/llvm-build \
GOALLC_LLVM_INSTALL=/path/to/llvm-payload \
GOALLC_BUILD_TYPE=Release \
GOALLC_LLVM_TARGETS='X86;AArch64' \
GOALLC_CCACHE=/path/to/ccache \
  ./llvm/utils/goallc/build-payload.bash
```

The payload contains the LLVM tools, installed source and generated headers,
CMake package, component archives, and `FileCheck`. Linux and Darwin also
include shared LLVM for plugin development; Windows uses static LLVM. The
pass plugin is not part of the LLVM release: Go's `make.bash` builds and
installs the matching plugin through `cmd/dist`.

New release tags use a UTC timestamp in the form
`goallc-llvm23.1.0-YYYYMMDDTHHMMSSZ` and trigger
`.github/workflows/goallc-release.yml`. Historical `goallc-llvm23.1.0-vN`
tags remain accepted. Existing release assets are immutable: publish a new tag
instead of overwriting an archive. The workflow builds native Linux amd64/arm64,
Darwin arm64 and Windows amd64 payloads, and publishes each
`.tar.zst` archive together with its SHA-256 file on the tag's GitHub Release.
Consumers must select the asset matching the host architecture and pin both
the tag and archive digest.

The Windows asset is named
`goallc-llvm23.1.0-<timestamp>-windows-amd64.tar.zst`, with a matching
`.tar.zst.sha256` file. It contains native `.exe` tools, headers, CMake exports,
and static LLVM/zlib/zstd archives. Both PR CI and release builds check the
Windows GoObj TLS/SEH fixture; release packaging also verifies the archive's
checksum before upload. The release workflow never overwrites an existing
asset.

Every pull request targeting `llvm23.1.master` also runs
`.github/workflows/goallc-ci.yml`. It builds and tests all four native host
payloads from the pull request head revision. The unprivileged build
uploads Actions artifacts; after the complete matrix succeeds,
`.github/workflows/goallc-ci-publish.yml` copies the archives and checksums to
the rolling `goallc-llvm-ci` prerelease without executing pull request code or
payloads. Only the newest successful revision of each open pull request is
retained, and closing the pull request removes its assets.

The rolling prerelease is a CI transport, not a stable LLVM release. A Go pull
request can opt in to a matching LLVM pull request payload, but merged Go code
must continue to pin an immutable timestamped LLVM release.

## Static dependency closure

All payloads build PIC static zlib 1.3.2 and zstd 1.5.7 from the SHA-256-pinned
sources in `build-static-deps.bash`. Optional libxml2, libedit, HTTP and curl
support is disabled. `llvm-config --link-static --system-libs` reports portable
library names; CMake consumers resolve the bundled archives after relocation.
The payload is a developer input, not the end-user Go SDK.

Darwin uses deployment target 13.0 for LLVM and dependencies. Linux release
runners use Ubuntu 22.04. Windows uses the pinned llvm-mingw UCRT toolchain in
`setup-windows-toolchain.bash`; LLVM, bindings and Go pass must use that same
C++ ABI. MSVC libraries are not supported by this release path.
The setup also installs SHA-256-pinned ccache and passes a native Windows
launcher path to CMake. CI and release jobs report the resulting cache statistics.

Configuration variables are listed by `build-payload.bash --help`. The source
revision, dirty flag, build mode, targets, dependency versions and deployment
target are recorded in `share/goallc/build-manifest`. Build directories remain
in developer provenance; final Go SDK metadata retains portable source fields.

CI moves each installed payload and validates its tools and CMake exports with
`validate-payload.bash`. The Go repository separately owns static SDK builds,
standard `distpack` archives, dependency audits, relocation and runtime/cgo
qualification. Passing this payload pipeline alone does not qualify a Go SDK.
