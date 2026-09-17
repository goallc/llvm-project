; RUN: llc -mtriple=aarch64-linux-goobj -O0 -fast-isel -verify-machineinstrs -stop-after=finalize-isel < %s | FileCheck %s
; RUN: llc -mtriple=aarch64-linux-goobj -O0 -verify-machineinstrs -filetype=obj < %s -o /dev/null
; RUN: llc -mtriple=aarch64-linux-goobj -O2 -verify-machineinstrs -filetype=obj < %s -o /dev/null

; Go uses X8 for the ninth integer argument/result. FastISel's AAPCS
; call/return lowering must defer to the Go-aware SelectionDAG lowering.
declare goabiinternal i64 @ninth(i64, i64, i64, i64, i64, i64, i64, i64, i64)

; CHECK-LABEL: name: call_ninth
; CHECK: BL @ninth, {{.*}}implicit $x8
define goabiinternal i64 @call_ninth() "frame-pointer"="non-leaf" {
  %v = call goabiinternal i64 @ninth(i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7, i64 8, i64 9)
  ret i64 %v
}

; CHECK-LABEL: name: return_nine
; CHECK: RET_ReallyLR {{.*}}implicit $x8
define goabiinternal { i64, i64, i64, i64, i64, i64, i64, i64, i64 } @return_nine() {
  ret { i64, i64, i64, i64, i64, i64, i64, i64, i64 } { i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7, i64 8, i64 9 }
}
