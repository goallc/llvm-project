; RUN: llc -mtriple=aarch64-apple-darwin -verify-machineinstrs < %s \
; RUN:   | FileCheck %s

%results = type {
  ptr, i64, i64, i64, i64, i64, i64, i64,
  i64, i64, i64, i64, i64, i64, i64, ptr,
  ptr, ptr
}
%memory_result = type [722 x i64]

declare goabiinternal %results @overflow_results() #0
declare goabiinternal void @two_memory_results(
    ptr goret(%memory_result) "goretindex"="0" align 8,
    ptr goret(%memory_result) "goretindex"="1" align 8)

define void @statepoint_with_register_and_stack_results()
    gc "statepoint-example" {
entry:
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 0, i32 0, ptr elementtype(%results ()) @overflow_results,
          i32 0, i32 0, i32 0, i32 0) #0
  %result = call %results @llvm.experimental.gc.result.results(token %token)
  %first_pointer = extractvalue %results %result, 0
  %last_register_pointer = extractvalue %results %result, 15
  %first_stack_pointer = extractvalue %results %result, 16
  %stack_pointer = extractvalue %results %result, 17
  call void @use(ptr %first_pointer)
  call void @use(ptr %last_register_pointer)
  call void @use(ptr %first_stack_pointer)
  call void @use(ptr %stack_pointer)
  ret void
}

; CHECK-LABEL: _statepoint_with_register_and_stack_results:
; CHECK:       bl _overflow_results
; CHECK-DAG:   ldp [[STACK0:x[0-9]+]], [[STACK1:x[0-9]+]], [sp, #8]
; CHECK-DAG:   mov [[REGISTER:x[0-9]+]], x15
; CHECK:       bl _use
; CHECK:       mov x0, [[REGISTER]]
; CHECK-NEXT:  bl _use
; CHECK:       mov x0, [[STACK0]]
; CHECK-NEXT:  bl _use
; CHECK:       mov x0, [[STACK1]]
; CHECK-NEXT:  bl _use

declare void @use(ptr)
declare void @use_i64(i64)

define goabiinternal void @statepoint_with_two_memory_results()
    gc "statepoint-example" {
entry:
  %first = alloca %memory_result, align 8
  %second = alloca %memory_result, align 8
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0,
          ptr elementtype(void (ptr, ptr)) @two_memory_results,
          i32 2, i32 0,
          ptr goret(%memory_result) "goretindex"="0" align 8 %first,
          ptr goret(%memory_result) "goretindex"="1" align 8 %second,
          i32 0, i32 0)
  %first_value = load i64, ptr %first, align 8
  %second_value = load i64, ptr %second, align 8
  call void @use_i64(i64 %first_value)
  call void @use_i64(i64 %second_value)
  ret void
}

; CHECK-LABEL: _statepoint_with_two_memory_results:
; CHECK:       bl _two_memory_results
; CHECK:       bl _use_i64
; CHECK:       bl _use_i64

declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare %results @llvm.experimental.gc.result.results(token)

attributes #0 = { "go_results_tuple" }
