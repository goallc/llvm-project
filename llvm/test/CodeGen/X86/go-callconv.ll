; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 < %s | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O2 < %s | FileCheck %s --check-prefix=X86-O2
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

define goabi0 i64 @"abi0_second_int<ABI0>"(
    ptr byval(i64) align 8 %a.home,
    ptr byval(i64) align 8 %b.home) {
; X86-LABEL: "abi0_second_int<ABI0>":
; X86: leaq 16(%rsp), %[[BHOME:r[a-z0-9]+]]
; X86: movq (%[[BHOME]]), %[[B:r[a-z0-9]+]]
; X86: movq %[[B]], 24(%rsp)
; X86: retq
entry:
  %b = load i64, ptr %b.home, align 8
  ret i64 %b
}

define goabi0 i64 @"abi0_call_second_int<ABI0>"() {
; X86-LABEL: "abi0_call_second_int<ABI0>":
; X86-DAG: movq $11, [[ASRC:[0-9]+]](%rsp)
; X86-DAG: movq $22, [[BSRC:[0-9]+]](%rsp)
; X86: movq [[BSRC]](%rsp), %[[B:r[a-z0-9]+]]
; X86: movq %rsp, %[[BASE:r[a-z0-9]+]]
; X86: movq %[[B]], 8(%[[BASE]])
; X86: movq [[ASRC]](%rsp), %[[A:r[a-z0-9]+]]
; X86: movq %[[A]], (%[[BASE]])
; X86: callq "abi0_second_int<ABI0>"
; X86: movq %rsp, %[[RELOAD:r[a-z0-9]+]]
; X86: movq 16(%[[RELOAD]]), %rax
entry:
  %a.home = alloca i64, align 8
  %b.home = alloca i64, align 8
  store i64 11, ptr %a.home, align 8
  store i64 22, ptr %b.home, align 8
  %ret = call goabi0 i64 @"abi0_second_int<ABI0>"(
      ptr byval(i64) align 8 %a.home,
      ptr byval(i64) align 8 %b.home)
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
%method.results = type { i64, i64, [2 x i64], double, [2 x double] }

; Aggregate arguments and results can share one outgoing call frame. Read stack
; results from the post-call SP before releasing that frame.
define goabiinternal i64 @call_method_results(ptr %callee, ptr %recv,
                                               ptr nest %ctxt) {
; X86-O2-LABEL: call_method_results:
; X86-O2:       callq *
; X86-O2:       addq 32(%rsp), %rax
; X86-O2:       addq 40(%rsp), %rax
; X86-O2:       addq 48(%rsp), %rax
; X86-O2:       addq 56(%rsp), %rax
; X86-O2:       addq ${{[0-9]+}}, %rsp
entry:
  %integers.home = alloca [2 x i64], align 8
  %floats.home = alloca [2 x double], align 8
  store [2 x i64] [i64 456, i64 789], ptr %integers.home, align 8
  store [2 x double] [double 3.4, double 5.6], ptr %floats.home, align 8
  %result = call goabiinternal %method.results %callee(
      ptr %recv, i64 123,
      ptr byval([2 x i64]) align 8 %integers.home,
      double 1.2,
      ptr byval([2 x double]) align 8 %floats.home,
      ptr nest %ctxt) #0
  %s = extractvalue %method.results %result, 0
  %a = extractvalue %method.results %result, 1
  %x = extractvalue %method.results %result, 2
  %x0 = extractvalue [2 x i64] %x, 0
  %x1 = extractvalue [2 x i64] %x, 1
  %y = extractvalue %method.results %result, 4
  %y0 = extractvalue [2 x double] %y, 0
  %y1 = extractvalue [2 x double] %y, 1
  %y0i = bitcast double %y0 to i64
  %y1i = bitcast double %y1 to i64
  %sum0 = add i64 %s, %a
  %sum1 = add i64 %sum0, %x0
  %sum2 = add i64 %sum1, %x1
  %sum3 = add i64 %sum2, %y0i
  %sum4 = add i64 %sum3, %y1i
  ret i64 %sum4
}

define goabiinternal i64 @stack_pair(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4,
    i64 %a5, i64 %a6, i64 %a7, i64 %a8,
    ptr byval(%pair) align 8 %value.home) {
; X86-LABEL: stack_pair:
; X86: leaq 8(%rsp), %[[HOME:r[a-z0-9]+]]
; X86-DAG: movq (%[[HOME]]), %[[LEFT:r[a-z0-9]+]]
; X86-DAG: movq 8(%[[HOME]]), %[[RIGHT:r[a-z0-9]+]]
; X86: addq %[[RIGHT]], %[[LEFT]]
; X86: retq
entry:
  %value = load %pair, ptr %value.home, align 8
  %left = extractvalue %pair %value, 0
  %right = extractvalue %pair %value, 1
  %sum = add i64 %left, %right
  ret i64 %sum
}

define goabiinternal i64 @call_stack_pair() {
; X86-LABEL: call_stack_pair:
; X86-DAG: movq $13, [[LEFTSRC:[0-9]+]](%rsp)
; X86-DAG: movq $17, [[RIGHTSRC:[0-9]+]](%rsp)
; X86-DAG: movq [[LEFTSRC]](%rsp), %[[LEFT:r[a-z0-9]+]]
; X86-DAG: movq [[RIGHTSRC]](%rsp), %[[RIGHT:r[a-z0-9]+]]
; X86: movq %rsp, %[[BASE:r[a-z0-9]+]]
; X86-DAG: movq %[[LEFT]], (%[[BASE]])
; X86-DAG: movq %[[RIGHT]], 8(%[[BASE]])
; X86: callq stack_pair
entry:
  %value.home = alloca %pair, align 8
  store %pair { i64 13, i64 17 }, ptr %value.home, align 8
  %result = call goabiinternal i64 @stack_pair(
      i64 0, i64 1, i64 2, i64 3, i64 4,
      i64 5, i64 6, i64 7, i64 8,
      ptr byval(%pair) align 8 %value.home)
  ret i64 %result
}

define goabiinternal [8 x i8] @stack_bytes(
    ptr byval([8 x i8]) align 1 %value.home) {
; X86-LABEL: stack_bytes:
; X86: leaq 8(%rsp), %[[HOME:r[a-z0-9]+]]
; X86-DAG: movb (%[[HOME]]), %{{[a-z0-9]+}}
; X86-DAG: movb 7(%[[HOME]]), %{{[a-z0-9]+}}
; X86-DAG: movb %{{[a-z0-9]+}}, 16(%rsp)
; X86-DAG: movb %{{[a-z0-9]+}}, 23(%rsp)
; X86: retq
entry:
  %value = load [8 x i8], ptr %value.home, align 1
  ret [8 x i8] %value
}

define goabiinternal i16 @call_stack_bytes() {
; X86-LABEL: call_stack_bytes:
; X86-DAG: movb $1, [[SRC:[0-9]+]](%rsp)
; X86-DAG: movb $8, [[SRCEND:[0-9]+]](%rsp)
; X86: movq [[SRC]](%rsp), %[[VALUE:r[a-z0-9]+]]
; X86: movq %rsp, %[[BASE:r[a-z0-9]+]]
; X86: movq %[[VALUE]], (%[[BASE]])
; X86: callq stack_bytes
; X86: movq %rsp, %[[RESULT_BASE:r[a-z0-9]+]]
; X86-DAG: movzbl 8(%[[RESULT_BASE]]), %{{[a-z0-9]+}}
; X86-DAG: movzbl 15(%[[RESULT_BASE]]), %{{[a-z0-9]+}}
entry:
  %value.home = alloca [8 x i8], align 1
  store [8 x i8] [i8 1, i8 2, i8 3, i8 4, i8 5, i8 6, i8 7, i8 8],
      ptr %value.home, align 1
  %result = call goabiinternal [8 x i8] @stack_bytes(
      ptr byval([8 x i8]) align 1 %value.home)
  %first = extractvalue [8 x i8] %result, 0
  %last = extractvalue [8 x i8] %result, 7
  %first.ext = zext i8 %first to i16
  %last.ext = zext i8 %last to i16
  %first.high = shl i16 %first.ext, 8
  %combined = or i16 %first.high, %last.ext
  ret i16 %combined
}

attributes #0 = { "go_results_tuple" }
