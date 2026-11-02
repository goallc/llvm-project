#!/usr/bin/env bash
# Run in Git Bash on a Windows CI runner, before configuring LLVM or Go.
set -euo pipefail
: "${RUNNER_TEMP:?}"
: "${GITHUB_ENV:?}"
: "${GITHUB_PATH:?}"
name=llvm-mingw-20261020-ucrt-x86_64
archive="$RUNNER_TEMP/$name.zip"
curl --fail --location --retry 5 "https://github.com/mstorsjo/llvm-mingw/releases/download/20261020/$name.zip" -o "$archive"
python3 - "$archive" "$RUNNER_TEMP" <<'PY'
import hashlib, pathlib, sys, zipfile
p = pathlib.Path(sys.argv[1])
if hashlib.sha256(p.read_bytes()).hexdigest() != 'fd5462b7f5d93b2ff981fcd3f9c7e427e47f3203c64ea91c27bcc444eebd74cd':
    raise SystemExit('llvm-mingw SHA-256 mismatch')
with zipfile.ZipFile(p) as z:
    z.extractall(sys.argv[2])
PY
bin=$(cygpath -m "$RUNNER_TEMP/$name/bin")
printf '%s\n' "$bin" >> "$GITHUB_PATH"
printf 'CC=%s/clang.exe\nCXX=%s/clang++.exe\n' "$bin" "$bin" >> "$GITHUB_ENV"
printf 'GOALLC_TOOLCHAIN_LICENSE=%s/../LICENSE.TXT\n' "$bin" >> "$GITHUB_ENV"
