; RUN: llc -mtriple=aarch64-apple-darwin -verify-machineinstrs < %s \
; RUN:   | FileCheck %s

%direct.results = type {
  ptr, i64, i64, i64, i64, i64, i64, i64,
  i64, i64, i64, i64, i64, i64, i64, ptr
}

declare goabiinternal %direct.results @overflow_results(
    ptr goret(ptr) align 8 "goretindex"="16",
    ptr goret(ptr) align 8 "goretindex"="17") #0

define void @statepoint_with_register_and_stack_results()
    gc "statepoint-example" {
entry:
  %stack.result.0 = alloca ptr, align 8
  %stack.result.1 = alloca ptr, align 8
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 0, i32 0,
          ptr elementtype(%direct.results (ptr, ptr)) @overflow_results,
          i32 2, i32 0,
          ptr goret(ptr) align 8 "goretindex"="16" %stack.result.0,
          ptr goret(ptr) align 8 "goretindex"="17" %stack.result.1,
          i32 0, i32 0) #0
  %result = call %direct.results
      @llvm.experimental.gc.result.direct.results(token %token)
  %first_pointer = extractvalue %direct.results %result, 0
  %last_register_pointer = extractvalue %direct.results %result, 15
  %first_stack_pointer = load ptr, ptr %stack.result.0, align 8
  %stack_pointer = load ptr, ptr %stack.result.1, align 8
  call void @use(ptr %first_pointer)
  call void @use(ptr %last_register_pointer)
  call void @use(ptr %first_stack_pointer)
  call void @use(ptr %stack_pointer)
  ret void
}

; CHECK-LABEL: _statepoint_with_register_and_stack_results:
; CHECK:       bl _overflow_results
; CHECK:       ldr x8, [sp, #8]
; CHECK:       mov [[REGISTER:x[0-9]+]], x15
; CHECK:       str x8, [sp, #40]
; CHECK:       ldr x8, [sp, #16]
; CHECK:       ldr [[STACK0:x[0-9]+]], [sp, #40]
; CHECK:       str x8, [sp, #32]
; CHECK:       mov [[STACK1:x[0-9]+]], x8
; CHECK:       bl _use
; CHECK:       mov x0, [[REGISTER]]
; CHECK-NEXT:  bl _use
; CHECK:       mov x0, [[STACK0]]
; CHECK-NEXT:  bl _use
; CHECK:       mov x0, [[STACK1]]
; CHECK-NEXT:  bl _use

declare void @use(ptr)
declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare %direct.results
    @llvm.experimental.gc.result.direct.results(token)

attributes #0 = { "go_results_tuple" }
