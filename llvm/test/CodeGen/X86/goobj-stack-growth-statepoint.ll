; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s

define goabiinternal i64 @morestack_statepoint(i64 %value) "go-stack-growth-statepoint" {
entry:
  %buf = alloca [5000 x i8], align 16
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  ret i64 %value
}

; CHECK-LABEL: name: morestack_statepoint
; CHECK-NOT: ANNOTATION_LABEL
; CHECK: STATEPOINT 5147424658422983495, 0, 0, &runtime.morestack_noctxt,
; CHECK-SAME: 2, 22, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0,
; CHECK-SAME: csr_64_go, implicit-def $rsp, implicit-def $ssp
; CHECK-NOT: CALL64pcrel32
