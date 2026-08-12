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
CMake package, shared LLVM library, component archives, and `FileCheck`. The
pass plugin is not part of the LLVM release: Go's `make.bash` builds and
installs the matching plugin through `cmd/dist`.

New release tags use a UTC timestamp in the form
`goallc-llvm23.1.0-YYYYMMDDTHHMMSSZ` and trigger
`.github/workflows/goallc-release.yml`. Historical `goallc-llvm23.1.0-vN`
tags remain accepted so their payloads can be rebuilt. The workflow builds a
relocatable Linux payload natively on both amd64 and arm64, and publishes each
`.tar.zst` archive together with its SHA-256 file on the tag's GitHub Release.
Consumers must select the asset matching the host architecture and pin both
the tag and archive digest.

Every pull request targeting `llvm23.1.master` also runs
`.github/workflows/goallc-ci.yml`. It builds and tests native Linux amd64 and
arm64 payloads from the pull request head revision. The unprivileged build
uploads Actions artifacts; after the complete matrix succeeds,
`.github/workflows/goallc-ci-publish.yml` copies the archives and checksums to
the rolling `goallc-llvm-ci` prerelease without executing pull request code or
payloads. Only the newest successful revision of each open pull request is
retained, and closing the pull request removes its assets.

The rolling prerelease is a CI transport, not a stable LLVM release. A Go pull
request can opt in to a matching LLVM pull request payload, but merged Go code
must continue to pin an immutable timestamped LLVM release.
