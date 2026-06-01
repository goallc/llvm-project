import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


def find_go():
    candidates = [
        os.environ.get("LLVM_GO"),
        os.environ.get("GO"),
        "/home/zgy/02.golang/stablego/go1.26/bin/go",
        shutil.which("go"),
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    return None


def run(args, cwd=None, env=None, check=True):
    proc = subprocess.run(
        args,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if check and proc.returncode:
        sys.stdout.write(proc.stdout)
        raise SystemExit(proc.returncode)
    return proc


def write(path, contents):
    path.write_text(contents, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--llc", required=True)
    parser.add_argument("--work-dir", required=True)
    args = parser.parse_args()

    go = find_go()
    if not go:
        print("goobj link test skipped: Go toolchain not found")
        return 0

    go_version = run([go, "version"], check=False)
    if go_version.returncode or "go1.26" not in go_version.stdout:
        print("goobj link test skipped: Go 1.26 toolchain not found")
        sys.stdout.write(go_version.stdout)
        return 0

    go_env = run([go, "env", "GOOS", "GOARCH", "GOROOT"], check=False)
    if go_env.returncode:
        print("goobj link test skipped: go env failed")
        sys.stdout.write(go_env.stdout)
        return 0
    goos, goarch, goroot = go_env.stdout.splitlines()[:3]
    if (goos, goarch) != ("linux", "amd64"):
        print(f"goobj link test skipped: unsupported Go target {goos}/{goarch}")
        return 0

    work_dir = Path(args.work_dir)
    if work_dir.exists():
        shutil.rmtree(work_dir)
    work_dir.mkdir(parents=True)

    write(
        work_dir / "main.go",
        """package main

func ext() int64

func main() {
\tprintln(ext())
}
""",
    )
    write(work_dir / "symabis", "def main.ext ABI0\n")
    run(
        [
            go,
            "tool",
            "compile",
            "-p",
            "main",
            "-symabis",
            "symabis",
            "-o",
            "main.a",
            "main.go",
        ],
        cwd=work_dir,
    )

    write(
        work_dir / "ext.ll",
        """target triple = "x86_64-unknown-linux-goobj"

define void @"main.ext"() {
entry:
  call void asm sideeffect "movq $$123, 8(%rsp)", "~{memory}"()
  ret void
}
""",
    )
    run(
        [
            args.llc,
            "-mtriple=x86_64-unknown-linux-goobj",
            "-goobj-package-path=main",
            "-filetype=obj",
            "ext.ll",
            "-o",
            "ext.o",
        ],
        cwd=work_dir,
    )
    run([go, "tool", "pack", "r", "main.a", "ext.o"], cwd=work_dir)

    write(
        work_dir / "simple.go",
        """package main

func main() {
\tprintln(1)
}
""",
    )
    build = run(
        [go, "build", "-x", "-work", "-o", "simple", "simple.go"],
        cwd=work_dir,
    )
    go_work = None
    for line in build.stdout.splitlines():
        if line.startswith("WORK="):
            go_work = Path(line[len("WORK=") :])
            break
    if go_work is None:
        sys.stdout.write(build.stdout)
        raise SystemExit("go build did not print a WORK directory")

    importcfg = go_work / "b001" / "importcfg.link"
    linked = work_dir / "linked"
    link_env = os.environ.copy()
    link_env["GOROOT"] = goroot
    run(
        [
            go,
            "tool",
            "link",
            "-w",
            "-o",
            str(linked),
            "-importcfg",
            str(importcfg),
            "-buildmode=exe",
            "main.a",
        ],
        cwd=work_dir,
        env=link_env,
    )

    result = run([str(linked)], cwd=work_dir)
    if result.stdout.strip() != "123":
        sys.stdout.write(result.stdout)
        raise SystemExit("linked executable did not print 123")
    print("goobj link test output: 123")


if __name__ == "__main__":
    raise SystemExit(main())
