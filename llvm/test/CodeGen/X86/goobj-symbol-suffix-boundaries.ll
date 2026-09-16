; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

; Storage suffix markers embedded in an ordinary name are not suffixes.
; In particular, short Go string constants include a quoted payload in their
; symbol name. Preserve that identity in both definitions and relocations.
@"go:string.\22<builtin.\22" = constant i8 1
@"go:string.\22<builtin.42>\22" = constant i8 2
@"go:string.\22<linkname>\22" = constant i8 3
@"go:string.\22<goallc.fmv.baseline>\22" = constant i8 4
@"go:string.\22<ABI0>\22" = constant i8 5
@"pkg.<builtin.42>.data" = external global i8, !goobj.import !0
@"pkg.<linkname>.data" = external global i8, !goobj.import !1
@references = global [7 x ptr] [ptr @"go:string.\22<builtin.\22", ptr @"go:string.\22<builtin.42>\22", ptr @"go:string.\22<linkname>\22", ptr @"go:string.\22<goallc.fmv.baseline>\22", ptr @"go:string.\22<ABI0>\22", ptr @"pkg.<builtin.42>.data", ptr @"pkg.<linkname>.data"]

!0 = !{!"pkg", i32 0, i32 0}
!1 = !{!"pkg", i32 1, i32 0}
!goobj.imports = !{!2}
!2 = !{!"pkg", !"pkg", !"0123456789abcdef"}

; CHECK-DAG: go:string."<builtin."
; CHECK-DAG: go:string."<builtin.42>"
; CHECK-DAG: go:string."<linkname>"
; CHECK-DAG: go:string."<goallc.fmv.baseline>"
; CHECK-DAG: go:string."<ABI0>"
; CHECK-DAG: pkg.<builtin.42>.data
; CHECK-DAG: pkg.<linkname>.data
