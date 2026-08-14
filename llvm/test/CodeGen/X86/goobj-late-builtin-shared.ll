; REQUIRES: x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s

; Go disables builtin-index references for -linkshared. Late passes therefore
; use the ordinary ABI0 linker name when the module has no builtin declaration.

define goabiinternal void @large_frame() {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  ret void
}

; CHECK-LABEL: name: large_frame
; CHECK: CALL64pcrel32 &"runtime.morestack_noctxt<ABI0>"
; CHECK-NOT: <builtin.

!goobj.config = !{!0}
!0 = !{!"goallc.goobj", !"linux", !"amd64", !"go1.27", !"", !"", !"", !"test/pkg", !"0", !"1", !"0", !1}
!1 = !{}
