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

define goabiinternal ptr @pointer_morestack_statepoint(ptr %pointer)
    "frame-pointer"="non-leaf" "go-stack-growth-statepoint" {
entry:
  %buf = alloca [8192 x i8], align 16
  %slot = getelementptr inbounds [8192 x i8], ptr %buf, i64 0, i64 8191
  store volatile i8 1, ptr %slot, align 1
  ret ptr %pointer
}

define goabiinternal ptr @mixed_register_and_stack_pointer_args(
    ptr %p0,
    i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5,
    i64 %a6, i64 %a7, i64 %a8, i64 %a9, i64 %a10,
    i64 %a11, i64 %a12, i64 %a13, i64 %a14, i64 %a15,
    ptr %p16) "frame-pointer"="non-leaf" "go-stack-growth-statepoint" {
entry:
  %buf = alloca [8192 x i8], align 16
  %slot = getelementptr inbounds [8192 x i8], ptr %buf, i64 0, i64 8191
  store volatile i8 1, ptr %slot, align 1
  %pointer = select i1 true, ptr %p0, ptr %p16
  ret ptr %pointer
}

; CHECK-LABEL: name: closure_morestack_statepoint
; CHECK-NOT: ANNOTATION_LABEL
; CHECK: STATEPOINT 5147424658422983495, 0, 0, &"runtime.morestack<ABI0>",
; CHECK-SAME: 2, 22, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0,
; CHECK-SAME: csr_aarch64_go, implicit-def $sp,
; CHECK-SAME: implicit-def dead early-clobber $lr,
; CHECK-SAME: implicit $x3, implicit $x26
; CHECK-NOT: BL

; CHECK-LABEL: name: pointer_morestack_statepoint
; CHECK: STRXui $x0, $sp, 1
; CHECK: STATEPOINT 5147424658422983495, 0, 0, &"runtime.morestack_noctxt<ABI0>",
; CHECK-SAME: 2, 22, 2, 0, 2, 0, 2, 1, 1, 8, $sp, 8,
; CHECK-SAME: 2, 0, 2, 1, 0, 0,
; CHECK-SAME: csr_aarch64_go, implicit-def $sp,
; CHECK-SAME: implicit-def dead early-clobber $lr,
; CHECK-SAME: implicit $x3
; CHECK: $x0 = LDRXui $sp, 1
; CHECK-NOT: BL

; CHECK-LABEL: name: mixed_register_and_stack_pointer_args
; CHECK: STATEPOINT 5147424658422983495, 0, 0, &"runtime.morestack_noctxt<ABI0>",
; CHECK-SAME: 2, 22, 2, 0, 2, 0, 2, 2,
; CHECK-SAME: 1, 8, $sp, 16, 1, 8, $sp, 8,
; CHECK-SAME: 2, 0, 2, 2, 0, 0, 1, 1,
; CHECK-SAME: csr_aarch64_go, implicit-def $sp,
; CHECK-SAME: implicit-def dead early-clobber $lr,
; CHECK-SAME: implicit $x3
