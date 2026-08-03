; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O0 < %s | FileCheck %s --check-prefix=A64

define goabiinternal i64 @second_int(i64 %a, i64 %b) {
; A64-LABEL: second_int:
; A64: mov x0, x1
; A64: ret
entry:
  ret i64 %b
}

define goabiinternal double @second_fp(double %a, double %b) {
; A64-LABEL: second_fp:
; A64: fmov d0, d1
; A64: ret
entry:
  ret double %b
}

define goabiinternal i64 @call_second_int() {
; A64-LABEL: call_second_int:
; A64: mov w8, #11
; A64: mov w0, w8
; A64: mov w8, #22
; A64: mov w1, w8
; A64: bl second_int
entry:
  %ret = call goabiinternal i64 @second_int(i64 11, i64 22)
  ret i64 %ret
}

%go.abi.pad = type { i8 }
%go.empty = type {}
%go.empty.carrier = type { %go.empty, %go.abi.pad }

define goabiinternal i64 @pad_does_not_use_register(
    i64 %a, %go.empty.carrier %pad, i64 %b) {
; A64-LABEL: pad_does_not_use_register:
; A64: mov x0, x1
; A64: ret
entry:
  ret i64 %b
}

define goabiinternal { i64, %go.empty.carrier, i64 }
    @pad_does_not_use_result_register(i64 %a, i64 %b) #0 {
; A64-LABEL: pad_does_not_use_result_register:
; A64-NOT: mov x2
; A64: ret
entry:
  %r0 = insertvalue { i64, %go.empty.carrier, i64 } poison, i64 %a, 0
  %r1 = insertvalue { i64, %go.empty.carrier, i64 } %r0, i64 %b, 2
  ret { i64, %go.empty.carrier, i64 } %r1
}

define goabi0 i64 @abi0_second_int(i64 %a, i64 %b) {
; A64-LABEL: abi0_second_int:
; Go's arm64 stack ABI reserves 0(SP) for the return PC.
; A64: ldr x[[REG:[0-9]+]], [sp, #16]
; A64: str x[[REG]], [sp, #24]
; A64: ret
entry:
  ret i64 %b
}

define goabi0 i64 @abi0_call_second_int() {
; A64-LABEL: abi0_call_second_int:
; A64: mov x[[BASE:[0-9]+]], sp
; A64-DAG: str x{{[0-9]+}}, [x[[BASE]], #8]
; A64-DAG: str x{{[0-9]+}}, [x[[BASE]], #16]
; A64: bl abi0_second_int
; A64: mov x[[BASE_RELOAD:[0-9]+]], sp
; A64: ldr x[[RET:[0-9]+]], [x[[BASE_RELOAD]], #24]
; A64: str x[[RET]], [sp, #72]
entry:
  %ret = call goabi0 i64 @abi0_second_int(i64 11, i64 22)
  ret i64 %ret
}

define goabiinternal { i64, [2 x i64] } @tuple_stackret(i64 %a, i64 %b, i64 %c) #0 {
; A64-LABEL: tuple_stackret:
; A64-DAG: str x1, [sp, #8]
; A64-DAG: str x2, [sp, #16]
; A64: ret
entry:
  %arr0 = insertvalue [2 x i64] poison, i64 %b, 0
  %arr1 = insertvalue [2 x i64] %arr0, i64 %c, 1
  %ret0 = insertvalue { i64, [2 x i64] } poison, i64 %a, 0
  %ret1 = insertvalue { i64, [2 x i64] } %ret0, [2 x i64] %arr1, 1
  ret { i64, [2 x i64] } %ret1
}

define goabiinternal { i64, [2 x i64] } @single_struct_stackret(i64 %a, i64 %b, i64 %c) {
; A64-LABEL: single_struct_stackret:
; A64-DAG: str x0, [sp, #8]
; A64-DAG: str x1, [sp, #16]
; A64-DAG: str x2, [sp, #24]
; A64: ret
entry:
  %arr0 = insertvalue [2 x i64] poison, i64 %b, 0
  %arr1 = insertvalue [2 x i64] %arr0, i64 %c, 1
  %ret0 = insertvalue { i64, [2 x i64] } poison, i64 %a, 0
  %ret1 = insertvalue { i64, [2 x i64] } %ret0, [2 x i64] %arr1, 1
  ret { i64, [2 x i64] } %ret1
}

%pair = type { i64, i64 }

define goabiinternal i64 @stack_pair(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4,
    i64 %a5, i64 %a6, i64 %a7, i64 %a8, i64 %a9,
    i64 %a10, i64 %a11, i64 %a12, i64 %a13, i64 %a14,
    %pair %value) {
; A64-LABEL: stack_pair:
; A64: ldr x0, [sp, #16]
; A64: ret
entry:
  %right = extractvalue %pair %value, 1
  ret i64 %right
}

define goabiinternal i64 @call_stack_pair() {
; A64-LABEL: call_stack_pair:
; A64-DAG: str x{{[0-9]+}}, [x{{[0-9]+}}, #8]
; A64-DAG: str x{{[0-9]+}}, [x{{[0-9]+}}, #16]
; A64: bl stack_pair
entry:
  %result = call goabiinternal i64 @stack_pair(
      i64 0, i64 1, i64 2, i64 3, i64 4,
      i64 5, i64 6, i64 7, i64 8, i64 9,
      i64 10, i64 11, i64 12, i64 13, i64 14,
      %pair { i64 13, i64 17 })
  ret i64 %result
}

attributes #0 = { "go_results_tuple" }
