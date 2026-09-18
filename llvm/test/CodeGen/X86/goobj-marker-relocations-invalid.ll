; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o /dev/null 2>&1 | FileCheck %s

@source = global i8 0, section ".noptrdata"
@target = external global i8
@llvm.compiler.used = appending global [2 x ptr] [ptr @source, ptr @target], section "llvm.metadata"

!goobj.marker_relocs = !{!0}
!0 = !{ptr @source, ptr @target, i32 1, i64 0}

; CHECK: LLVM ERROR: unsupported !goobj.marker_relocs type
