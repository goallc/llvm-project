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
        print("goobj AArch64 frame test skipped: Go toolchain not found")
        return 0

    go_version = run([go, "version"], check=False)
    if go_version.returncode or not any(
        version in go_version.stdout for version in ("go1.26", "go1.27")
    ):
        print("goobj AArch64 frame test skipped: Go 1.26/1.27 not found")
        sys.stdout.write(go_version.stdout)
        return 0

    go_env = run([go, "env", "GOOS", "GOARCH", "GOROOT"], check=False)
    if go_env.returncode:
        print("goobj AArch64 frame test skipped: go env failed")
        sys.stdout.write(go_env.stdout)
        return 0
    goos, goarch, goroot = go_env.stdout.splitlines()[:3]
    if (goos, goarch) != ("darwin", "arm64"):
        print(f"goobj AArch64 frame test skipped: unsupported target {goos}/{goarch}")
        return 0

    work_dir = Path(args.work_dir)
    if work_dir.exists():
        shutil.rmtree(work_dir)
    work_dir.mkdir(parents=True)

    write(
        work_dir / "main.go",
        """package main

func largeFrame() int64

func main() {
	if got := largeFrame(); got != 123 {
		panic(got)
	}
	println(123)
}
""",
    )
    write(work_dir / "symabis", "def main.largeFrame ABIInternal\n")
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

    archive_data = (work_dir / "main.a").read_bytes()
    header_start = archive_data.find(b"go object ")
    header_end = archive_data.find(b"\n", header_start)
    if header_start < 0 or header_end < 0:
        raise SystemExit("Go compiler archive does not contain an object header")
    go_header = archive_data[header_start:header_end].decode("utf-8")
    header_fields = go_header.split()
    if len(header_fields) < 5:
        raise SystemExit(f"malformed Go object header: {go_header}")
    goobj_version = header_fields[4]
    _, separator, goobj_experiments = go_header.partition(" X:")

    write(
        work_dir / "frame.ll",
        """target triple = "aarch64-apple-darwin-goobj"

declare goabiinternal void @"runtime.GC"()

define goabiinternal i64 @"main.largeFrame"() #0 {
entry:
  %buffer = alloca [8192 x i8], align 16
  %last = getelementptr inbounds [8192 x i8], ptr %buffer, i64 0, i64 8191
  store volatile i8 1, ptr %last, align 1
  call goabiinternal void @"runtime.GC"()
  ret i64 123
}

attributes #0 = { "frame-pointer"="non-leaf" }
""",
    )
    run(
        [
            args.llc,
            "-mtriple=aarch64-apple-darwin-goobj",
            "-goobj-package-path=main",
            f"-goobj-version={goobj_version}",
            f"-goobj-experiments={goobj_experiments if separator else ''}",
            "-filetype=obj",
            "frame.ll",
            "-o",
            "frame.o",
        ],
        cwd=work_dir,
    )
    run([go, "tool", "pack", "r", "main.a", "frame.o"], cwd=work_dir)

    write(
        work_dir / "simple.go",
        """package main

func main() {}
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
            str(go_work / "b001" / "importcfg.link"),
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
    print("goobj AArch64 frame test output: 123")


if __name__ == "__main__":
    raise SystemExit(main())
