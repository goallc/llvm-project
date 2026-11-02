#!/usr/bin/env python3
"""Write or check a portable SHA-256 sidecar without host-specific tools."""

import argparse
import hashlib
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()

    digest = hashlib.sha256()
    with args.archive.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    line = f"{digest.hexdigest()}  {args.archive.name}\n".encode("utf-8")
    sidecar = Path(str(args.archive) + ".sha256")
    if args.check:
        if sidecar.read_bytes() != line:
            raise SystemExit(f"SHA-256 mismatch: {args.archive}")
        print(f"{args.archive.name}: OK")
    else:
        # The privileged artifact publisher expects one LF-terminated line,
        # including for archives produced by native Windows Python.
        sidecar.write_bytes(line)


if __name__ == "__main__":
    main()
