import argparse
import os
import shlex
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
    parser.add_argument("--toolexec", required=True)
    parser.add_argument("--work-dir", required=True)
    args = parser.parse_args()

    go = find_go()
    if not go:
        print("goobj toolexec test skipped: Go toolchain not found")
        return 0

    go_version = run([go, "version"], check=False)
    if go_version.returncode or "go1.26" not in go_version.stdout:
        print("goobj toolexec test skipped: Go 1.26 toolchain not found")
        sys.stdout.write(go_version.stdout)
        return 0

    go_env = run([go, "env", "GOOS", "GOARCH"], check=False)
    if go_env.returncode:
        print("goobj toolexec test skipped: go env failed")
        sys.stdout.write(go_env.stdout)
        return 0
    goos, goarch = go_env.stdout.splitlines()[:2]
    if (goos, goarch) != ("linux", "amd64"):
        print(f"goobj toolexec test skipped: unsupported Go target {goos}/{goarch}")
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

    env = os.environ.copy()
    env["GOCACHE"] = str(work_dir / "gocache")

    linked = work_dir / "toolexec-linked"
    toolexec = " ".join(
        shlex.quote(arg)
        for arg in [
            args.toolexec,
            "--llvm-ir",
            str(work_dir / "ext.ll"),
        ]
    )
    run(
        [
            go,
            "build",
            "-a",
            "-ldflags=-w",
            "-toolexec",
            toolexec,
            "-o",
            str(linked),
            "main.go",
        ],
        cwd=work_dir,
        env=env,
    )

    result = run([str(linked)], cwd=work_dir)
    if result.stdout.strip() != "123":
        sys.stdout.write(result.stdout)
        raise SystemExit("toolexec-linked executable did not print 123")
    print("goobj toolexec test output: 123")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
