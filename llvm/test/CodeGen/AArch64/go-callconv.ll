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
; A64: str x[[BASE]], [sp, #40]
; A64-DAG: str x{{[0-9]+}}, [x[[BASE]], #8]
; A64-DAG: str x{{[0-9]+}}, [x[[BASE]], #16]
; A64: bl abi0_second_int
; A64: ldr x[[BASE_RELOAD:[0-9]+]], [sp, #40]
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

attributes #0 = { "go_results_tuple" }
