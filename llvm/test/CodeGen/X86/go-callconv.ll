; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 < %s | FileCheck %s --check-prefix=X86

define goabiinternal i64 @second_int(i64 %a, i64 %b) {
; X86-LABEL: second_int:
; X86: movq %rbx, %rax
; X86: retq
entry:
  ret i64 %b
}

define goabiinternal double @second_fp(double %a, double %b) {
; X86-LABEL: second_fp:
; X86: mov{{[a-z]+}} %xmm1, %xmm0
; X86: retq
entry:
  ret double %b
}

define goabiinternal i64 @call_second_int() {
; X86-LABEL: call_second_int:
; X86: mov{{[lq]}} $11, %{{e|r}}ax
; X86: mov{{[lq]}} $22, %{{e|r}}bx
; X86: callq second_int
entry:
  %ret = call goabiinternal i64 @second_int(i64 11, i64 22)
  ret i64 %ret
}

define goabi0 i64 @abi0_second_int(i64 %a, i64 %b) {
; X86-LABEL: abi0_second_int:
; X86: movq 16(%rsp), %rax
; X86: movq %rax, 24(%rsp)
; X86: retq
entry:
  ret i64 %b
}

define goabi0 i64 @abi0_call_second_int() {
; X86-LABEL: abi0_call_second_int:
; X86: movq %rsp, %rax
; X86: movq $22, 8(%rax)
; X86: movq $11, (%rax)
; X86: callq abi0_second_int
; X86: movq 16(%rax), %rax
entry:
  %ret = call goabi0 i64 @abi0_second_int(i64 11, i64 22)
  ret i64 %ret
}

define goabiinternal { i64, [2 x i64] } @tuple_stackret(i64 %a, i64 %b, i64 %c) #0 {
; X86-LABEL: tuple_stackret:
; X86-DAG: movq %rbx, 8(%rsp)
; X86-DAG: movq %rcx, 16(%rsp)
; X86: retq
entry:
  %arr0 = insertvalue [2 x i64] poison, i64 %b, 0
  %arr1 = insertvalue [2 x i64] %arr0, i64 %c, 1
  %ret0 = insertvalue { i64, [2 x i64] } poison, i64 %a, 0
  %ret1 = insertvalue { i64, [2 x i64] } %ret0, [2 x i64] %arr1, 1
  ret { i64, [2 x i64] } %ret1
}

define goabiinternal { i64, [2 x i64] } @single_struct_stackret(i64 %a, i64 %b, i64 %c) {
; X86-LABEL: single_struct_stackret:
; X86-DAG: movq %rax, 8(%rsp)
; X86-DAG: movq %rbx, 16(%rsp)
; X86-DAG: movq %rcx, 24(%rsp)
; X86: retq
entry:
  %arr0 = insertvalue [2 x i64] poison, i64 %b, 0
  %arr1 = insertvalue [2 x i64] %arr0, i64 %c, 1
  %ret0 = insertvalue { i64, [2 x i64] } poison, i64 %a, 0
  %ret1 = insertvalue { i64, [2 x i64] } %ret0, [2 x i64] %arr1, 1
  ret { i64, [2 x i64] } %ret1
}

attributes #0 = { "go_results_tuple" }
