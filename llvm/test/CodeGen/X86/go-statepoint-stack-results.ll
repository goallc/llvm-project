; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs < %s \
; RUN:   | FileCheck %s

%direct.results = type {
  ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr,
  ptr
}

declare goabiinternal %direct.results @overflow_results(
    ptr goret(ptr) align 8 "goretindex"="9",
    ptr goret(ptr) align 8 "goretindex"="10") #0

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
          ptr goret(ptr) align 8 "goretindex"="9" %stack.result.0,
          ptr goret(ptr) align 8 "goretindex"="10" %stack.result.1,
          i32 0, i32 0) #0
  %result = call %direct.results
      @llvm.experimental.gc.result.direct.results(token %token)
  %first_pointer = extractvalue %direct.results %result, 0
  %last_register_pointer = extractvalue %direct.results %result, 8
  %first_stack_pointer = load ptr, ptr %stack.result.0, align 8
  %stack_pointer = load ptr, ptr %stack.result.1, align 8
  call void @use(ptr %first_pointer)
  call void @use(ptr %last_register_pointer)
  call void @use(ptr %first_stack_pointer)
  call void @use(ptr %stack_pointer)
  ret void
}

; CHECK-LABEL: statepoint_with_register_and_stack_results:
; CHECK:       callq overflow_results
; CHECK-DAG:   movq (%rsp), [[STACK0:%r[a-z0-9]+]]
; CHECK-DAG:   movq 8(%rsp), [[STACK1:%r[a-z0-9]+]]

declare void @use(ptr)
declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare %direct.results
    @llvm.experimental.gc.result.direct.results(token)

attributes #0 = { "go_results_tuple" }
