; REQUIRES: aarch64-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s

define goabiinternal i64 @closure_morestack_statepoint(
    i64 %value, ptr nest %ctxt) "frame-pointer"="non-leaf"
    "go-stack-growth-statepoint" {
entry:
  %buf = alloca [8192 x i8], align 16
  %slot = getelementptr inbounds [8192 x i8], ptr %buf, i64 0, i64 8191
  store volatile i8 1, ptr %slot, align 1
  %capture = load i64, ptr %ctxt, align 8
  %sum = add i64 %capture, %value
  ret i64 %sum
}

; CHECK-LABEL: name: closure_morestack_statepoint
; CHECK-NOT: ANNOTATION_LABEL
; CHECK: STATEPOINT 5147424658422983495, 0, 0, &runtime.morestack,
; CHECK-SAME: 2, 22, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0,
; CHECK-SAME: csr_aarch64_go, implicit-def $sp,
; CHECK-SAME: implicit-def dead early-clobber $lr,
; CHECK-SAME: implicit $x3, implicit $x26
; CHECK-NOT: BL
