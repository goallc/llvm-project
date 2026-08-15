; REQUIRES: aarch64-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s

declare goabi0 void @"runtime.morestack<builtin.244><ABI0>"()
declare goabi0 void @"runtime.morestack_noctxt<builtin.246><ABI0>"()
declare goabi0 void @"runtime.morestackc<builtin.245><ABI0>"()

define goabiinternal i64 @closure_morestack_call(
    i64 %value, ptr nest %ctxt) "frame-pointer"="non-leaf"
 {
entry:
  %buf = alloca [8192 x i8], align 16
  %slot = getelementptr inbounds [8192 x i8], ptr %buf, i64 0, i64 8191
  store volatile i8 1, ptr %slot, align 1
  %capture = load i64, ptr %ctxt, align 8
  %sum = add i64 %capture, %value
  ret i64 %sum
}

define goabiinternal ptr @pointer_morestack_call(ptr %pointer)
    "frame-pointer"="non-leaf" {
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
    ptr preallocated(ptr) align 8 %p16.home) "frame-pointer"="non-leaf" {
entry:
  %p16 = load ptr, ptr %p16.home, align 8
  %buf = alloca [8192 x i8], align 16
  %slot = getelementptr inbounds [8192 x i8], ptr %buf, i64 0, i64 8191
  store volatile i8 1, ptr %slot, align 1
  %pointer = select i1 true, ptr %p0, ptr %p16
  ret ptr %pointer
}

define goabiinternal void @systemstack_growth() "frame-pointer"="non-leaf"
 "go-systemstack" {
entry:
  %buf = alloca [8192 x i8], align 16
  %slot = getelementptr inbounds [8192 x i8], ptr %buf, i64 0, i64 8191
  store volatile i8 1, ptr %slot, align 1
  ret void
}

; CHECK-LABEL: name: closure_morestack_call
; CHECK-NOT: ANNOTATION_LABEL
; CHECK: BL &"runtime.morestack<builtin.244><ABI0>", implicit-def $lr, implicit $sp,
; CHECK-SAME: implicit $x3, implicit $x26
; CHECK: STACKMAP 5147419139155979380, 0
; CHECK-NOT: STATEPOINT

; CHECK-LABEL: name: pointer_morestack_call
; CHECK: STRXui $x0, $sp, 1
; CHECK: BL &"runtime.morestack_noctxt<builtin.246><ABI0>", implicit-def $lr, implicit $sp,
; CHECK-SAME: implicit $x3
; CHECK: $x0 = LDRXui $sp, 1
; CHECK: STACKMAP 5147419139155979380, 0, 1, 8, $sp, 8
; CHECK-NOT: BL

; CHECK-LABEL: name: mixed_register_and_stack_pointer_args
; CHECK: BL &"runtime.morestack_noctxt<builtin.246><ABI0>", implicit-def $lr, implicit $sp,
; CHECK-SAME: implicit $x3
; CHECK: STACKMAP 5147419139155979380, 0,
; CHECK-SAME: 1, 8, $sp, 16, 1, 8, $sp, 8

; CHECK-LABEL: name: systemstack_growth
; CHECK: $x17 = LDRXui $x28, 3
; CHECK: BL &"runtime.morestackc<builtin.245><ABI0>", implicit-def $lr, implicit $sp,
; CHECK-SAME: implicit $x3
; CHECK: STACKMAP 5147419139155979380, 0
