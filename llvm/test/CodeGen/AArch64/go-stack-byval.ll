; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O2 -verify-machineinstrs < %s | FileCheck %s

%large = type [40000 x i64]

declare goabiinternal void @consume(ptr byval(%large) align 8)

define goabiinternal void @copy_large_stack_argument(ptr %source) {
; CHECK-LABEL: copy_large_stack_argument:
; CHECK-NOT: memcpy
; CHECK: ldr q31, [x{{[0-9]+}}]
; CHECK-NEXT: str q31, [x{{[0-9]+}}]
; CHECK: b.hs
; CHECK: bl consume
entry:
  call goabiinternal void @consume(ptr byval(%large) align 8 %source)
  ret void
}

define goabiinternal i64 @read_incoming_stack_argument(
    ptr byval(%large) align 8 %value) {
; CHECK-LABEL: read_incoming_stack_argument:
; CHECK: ldr x0, [sp, #8]
; CHECK-NEXT: ret
entry:
  %result = load i64, ptr %value, align 8
  ret i64 %result
}

define goabiinternal void @write_memory_result(
    ptr byref(%large) align 8 %result) #0 {
; CHECK-LABEL: write_memory_result:
; CHECK: str x{{[0-9]+}}, [sp, #8]
; CHECK-NEXT: ret
entry:
  store i64 42, ptr %result, align 8
  ret void
}

define goabiinternal i64 @copy_large_memory_result() {
; CHECK-LABEL: copy_large_memory_result:
; CHECK-NOT: memcpy
; CHECK: bl write_memory_result
; CHECK: ldr q31, [x{{[0-9]+}}]
; CHECK-NEXT: str q31, [x{{[0-9]+}}]
; CHECK: b.hs
entry:
  %result = alloca %large, align 8
  call goabiinternal void @write_memory_result(
      ptr byref(%large) align 8 %result) #0
  %value = load i64, ptr %result, align 8
  ret i64 %value
}

attributes #0 = { "go_memory_results"="0" }
