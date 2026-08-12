; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O2 -verify-machineinstrs < %s | FileCheck %s

%large = type [40000 x i64]

declare goabiinternal void @consume(ptr byval(%large) align 8)

define goabiinternal void @copy_large_stack_argument(ptr %source) {
; CHECK-LABEL: copy_large_stack_argument:
; CHECK-NOT: memcpy
; CHECK: rep;movsq
; CHECK: callq consume
entry:
  call goabiinternal void @consume(ptr byval(%large) align 8 %source)
  ret void
}

define goabiinternal i64 @read_incoming_stack_argument(
    ptr byval(%large) align 8 %value) {
; CHECK-LABEL: read_incoming_stack_argument:
; CHECK: movq 8(%rsp), %rax
; CHECK-NEXT: retq
entry:
  %result = load i64, ptr %value, align 8
  ret i64 %result
}

define goabiinternal void @write_memory_result(
    ptr byref(%large) align 8 %result) #0 {
; CHECK-LABEL: write_memory_result:
; CHECK: movq $42, 8(%rsp)
; CHECK-NEXT: retq
entry:
  store i64 42, ptr %result, align 8
  ret void
}

define goabiinternal i64 @copy_large_memory_result() {
; CHECK-LABEL: copy_large_memory_result:
; CHECK-NOT: memcpy
; CHECK: callq write_memory_result
; CHECK: rep;movsq
entry:
  %result = alloca %large, align 8
  call goabiinternal void @write_memory_result(
      ptr byref(%large) align 8 %result) #0
  %value = load i64, ptr %result, align 8
  ret i64 %value
}

attributes #0 = { "go_memory_results"="0" }
