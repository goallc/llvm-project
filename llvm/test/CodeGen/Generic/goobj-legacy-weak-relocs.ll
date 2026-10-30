; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o /dev/null 2>&1 | FileCheck %s
; REQUIRES: x86-registered-target
; CHECK: LLVM ERROR: GoObj weak relocations require R_WEAK in !goobj.relocs
@target = external global i8
@source = constant ptr @target, !goobj.weak_relocs !0
!0 = !{i32 0}
