#!/usr/bin/env python3

"""Merge LLVM component archives into the GoALLC static library."""

import argparse
import os
import subprocess
import tempfile
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--format", choices=("darwin", "gnu"), required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--ar")
    parser.add_argument("--libtool")
    parser.add_argument("archives", nargs="+")
    return parser.parse_args()


def merge_darwin(args, output, members):
    if not args.libtool:
        raise SystemExit("--libtool is required for Darwin archives")
    subprocess.run(
        [args.libtool, "-static", "-D", "-o", str(output), *members],
        check=True,
    )


def merge_gnu(args, output, members):
    subprocess.run([args.ar, "rcsD", str(output), *members], check=True)


def extract_members(args, directory):
    if not args.ar:
        raise SystemExit("--ar is required to extract component archives")

    members = []
    member_number = 0
    for archive_number, archive in enumerate(args.archives):
        archive_dir = directory / f"{archive_number:04d}"
        archive_dir.mkdir()
        subprocess.run([args.ar, "x", archive], cwd=archive_dir, check=True)
        for member in sorted(archive_dir.iterdir()):
            unique_member = directory / f"{member_number:06d}_{member.name}"
            member.rename(unique_member)
            members.append(str(unique_member))
            member_number += 1
    return members


def main():
    args = parse_args()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")
    try:
        temporary.unlink()
    except FileNotFoundError:
        pass

    with tempfile.TemporaryDirectory(
        prefix="goallc-archive-", dir=output.parent
    ) as temporary_directory:
        members = extract_members(args, Path(temporary_directory))
        if args.format == "darwin":
            merge_darwin(args, temporary, members)
        else:
            merge_gnu(args, temporary, members)
    os.replace(temporary, output)


if __name__ == "__main__":
    main()
