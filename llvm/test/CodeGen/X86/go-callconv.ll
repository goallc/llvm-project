; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 < %s | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -O0 -filetype=null < %s

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

; GoObj guarantees only 8-byte incoming stack alignment. A function which
; clobbers the reserved Go zero register must therefore use an unaligned fixed
; XMM15 spill instead of requiring stack realignment.
define goabiinternal void @goobj_xmm15_spill() {
entry:
  call void asm sideeffect "", "~{xmm15}"()
  ret void
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

%go.abi.pad = type { i8 }
%go.empty = type {}
%go.empty.carrier = type { %go.empty, %go.abi.pad }

define goabiinternal i64 @pad_does_not_use_register(
    i64 %a, %go.empty.carrier %pad, i64 %b) {
; X86-LABEL: pad_does_not_use_register:
; X86: movq %rbx, %rax
; X86: retq
entry:
  ret i64 %b
}

define goabiinternal { i64, %go.empty.carrier, i64 }
    @pad_does_not_use_result_register(i64 %a, i64 %b) #0 {
; X86-LABEL: pad_does_not_use_result_register:
; X86-NOT: movq %rcx
; X86: retq
entry:
  %r0 = insertvalue { i64, %go.empty.carrier, i64 } poison, i64 %a, 0
  %r1 = insertvalue { i64, %go.empty.carrier, i64 } %r0, i64 %b, 2
  ret { i64, %go.empty.carrier, i64 } %r1
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
; X86: movq %rsp, %[[BASE:r[a-z0-9]+]]
; X86: movq $22, 8(%[[BASE]])
; X86: movq $11, (%[[BASE]])
; X86: callq abi0_second_int
; X86: movq %rsp, %[[RELOAD:r[a-z0-9]+]]
; X86: movq 16(%[[RELOAD]]), %rax
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

%pair = type { i64, i64 }

define goabiinternal i64 @stack_pair(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4,
    i64 %a5, i64 %a6, i64 %a7, i64 %a8, %pair %value) {
; X86-LABEL: stack_pair:
; X86-DAG: movq 8(%rsp), %[[LEFT:r[a-z0-9]+]]
; X86-DAG: movq 16(%rsp), %[[RIGHT:r[a-z0-9]+]]
; X86: addq %[[RIGHT]], %[[LEFT]]
; X86: retq
entry:
  %left = extractvalue %pair %value, 0
  %right = extractvalue %pair %value, 1
  %sum = add i64 %left, %right
  ret i64 %sum
}

define goabiinternal i64 @call_stack_pair() {
; X86-LABEL: call_stack_pair:
; X86-DAG: movq $13, (%[[BASE:r[a-z0-9]+]])
; X86-DAG: movq $17, 8(%[[BASE]])
; X86: callq stack_pair
entry:
  %result = call goabiinternal i64 @stack_pair(
      i64 0, i64 1, i64 2, i64 3, i64 4,
      i64 5, i64 6, i64 7, i64 8,
      %pair { i64 13, i64 17 })
  ret i64 %result
}

define goabiinternal [8 x i8] @stack_bytes([8 x i8] %value) {
; X86-LABEL: stack_bytes:
; X86-DAG: movb 8(%rsp), %{{[a-z0-9]+}}
; X86-DAG: movb 15(%rsp), %{{[a-z0-9]+}}
; X86-DAG: movb %{{[a-z0-9]+}}, 16(%rsp)
; X86-DAG: movb %{{[a-z0-9]+}}, 23(%rsp)
; X86: retq
entry:
  ret [8 x i8] %value
}

define goabiinternal i16 @call_stack_bytes() {
; X86-LABEL: call_stack_bytes:
; X86-DAG: movb $1, (%[[BASE:r[a-z0-9]+]])
; X86-DAG: movb $8, 7(%[[BASE]])
; X86: callq stack_bytes
; X86: movq %rsp, %[[RESULT_BASE:r[a-z0-9]+]]
; X86-DAG: movzbl 8(%[[RESULT_BASE]]), %{{[a-z0-9]+}}
; X86-DAG: movzbl 15(%[[RESULT_BASE]]), %{{[a-z0-9]+}}
entry:
  %result = call goabiinternal [8 x i8] @stack_bytes(
      [8 x i8] [i8 1, i8 2, i8 3, i8 4, i8 5, i8 6, i8 7, i8 8])
  %first = extractvalue [8 x i8] %result, 0
  %last = extractvalue [8 x i8] %result, 7
  %first.ext = zext i8 %first to i16
  %last.ext = zext i8 %last to i16
  %first.high = shl i16 %first.ext, 8
  %combined = or i16 %first.high, %last.ext
  ret i16 %combined
}

attributes #0 = { "go_results_tuple" }
