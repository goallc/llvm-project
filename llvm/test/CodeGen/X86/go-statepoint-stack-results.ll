; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs < %s \
; RUN:   | FileCheck %s

%results = type {
  ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr,
  ptr, ptr, ptr
}

declare goabiinternal %results @overflow_results() #0

define void @statepoint_with_register_and_stack_results()
    gc "statepoint-example" {
entry:
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 0, i32 0, ptr elementtype(%results ()) @overflow_results,
          i32 0, i32 0, i32 0, i32 0) #0
  %result = call %results @llvm.experimental.gc.result.results(token %token)
  %first_pointer = extractvalue %results %result, 0
  %last_register_pointer = extractvalue %results %result, 8
  %first_stack_pointer = extractvalue %results %result, 9
  %stack_pointer = extractvalue %results %result, 10
  call void @use(ptr %first_pointer)
  call void @use(ptr %last_register_pointer)
  call void @use(ptr %first_stack_pointer)
  call void @use(ptr %stack_pointer)
  ret void
}

; CHECK-LABEL: statepoint_with_register_and_stack_results:
; CHECK:       callq overflow_results
; CHECK:       movq %rsp, [[RESULT_SP:%r[a-z0-9]+]]
; CHECK-DAG:   movq ([[RESULT_SP]]), [[STACK0:%r[a-z0-9]+]]
; CHECK-DAG:   movq 8([[RESULT_SP]]), [[STACK1:%r[a-z0-9]+]]

declare void @use(ptr)
declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare %results @llvm.experimental.gc.result.results(token)

attributes #0 = { "go_results_tuple" }
