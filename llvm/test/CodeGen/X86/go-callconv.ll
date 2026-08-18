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

define goabi0 void @"abi0_second_int<ABI0>"(
    ptr byval(i64) align 8 %a.home, ptr byval(i64) align 8 %b.home,
    ptr goret(i64) align 8 "goretindex"="0" %result.home) {
; X86-LABEL: "abi0_second_int<ABI0>":
; X86: leaq 24(%rsp), %[[RESULT_HOME:r[a-z0-9]+]]
; X86: leaq 16(%rsp), %[[B_HOME:r[a-z0-9]+]]
; X86-NEXT: movq (%[[B_HOME]]), %[[VALUE:r[a-z0-9]+]]
; X86: movq %[[VALUE]], (%[[RESULT_HOME]])
; X86: retq
entry:
  %b = load i64, ptr %b.home, align 8
  store i64 %b, ptr %result.home, align 8
  ret void
}

define goabiinternal i64 @abi0_call_second_int() {
; X86-LABEL: abi0_call_second_int:
; X86: movq %rsp, %[[BASE:r[a-z0-9]+]]
; X86: movq %{{r[a-z0-9]+}}, 8(%[[BASE]])
; X86: movq %{{r[a-z0-9]+}}, (%[[BASE]])
; X86: callq "abi0_second_int<ABI0>"
; X86: movq %rsp, %[[RELOAD:r[a-z0-9]+]]
; X86: movq 16(%[[RELOAD]]), %rax
entry:
  %a.home = alloca i64, align 8
  %b.home = alloca i64, align 8
  store i64 11, ptr %a.home, align 8
  store i64 22, ptr %b.home, align 8
  %result.home = alloca i64, align 8
  call goabi0 void @"abi0_second_int<ABI0>"(
      ptr byval(i64) align 8 %a.home, ptr byval(i64) align 8 %b.home,
      ptr goret(i64) align 8 "goretindex"="0" %result.home)
  %ret = load i64, ptr %result.home, align 8
  ret i64 %ret
}

define goabiinternal i64 @tuple_stackret(
    i64 %a, i64 %b, i64 %c,
    ptr goret([2 x i64]) align 8 "goretindex"="1" %array.result) {
; X86-LABEL: tuple_stackret:
; X86: leaq 8(%rsp), %[[RESULT_HOME:r[a-z0-9]+]]
; X86-DAG: movq %rbx, (%[[RESULT_HOME]])
; X86-DAG: movq %{{r[a-z0-9]+}}, 8(%[[RESULT_HOME]])
; X86: retq
entry:
  %arr0 = insertvalue [2 x i64] poison, i64 %b, 0
  %arr1 = insertvalue [2 x i64] %arr0, i64 %c, 1
  store [2 x i64] %arr1, ptr %array.result, align 8
  ret i64 %a
}

%single.result = type { i64, [2 x i64] }

define goabiinternal void @single_struct_stackret(
    i64 %a, i64 %b, i64 %c,
    ptr goret(%single.result) align 8 "goretindex"="0" %result.home) {
; X86-LABEL: single_struct_stackret:
; X86: leaq 8(%rsp), %[[RESULT_HOME:r[a-z0-9]+]]
; X86-DAG: movq %{{r[a-z0-9]+}}, (%[[RESULT_HOME]])
; X86-DAG: movq %rbx, 8(%[[RESULT_HOME]])
; X86-DAG: movq %{{r[a-z0-9]+}}, 16(%[[RESULT_HOME]])
; X86: retq
entry:
  %arr0 = insertvalue [2 x i64] poison, i64 %b, 0
  %arr1 = insertvalue [2 x i64] %arr0, i64 %c, 1
  %ret0 = insertvalue %single.result poison, i64 %a, 0
  %ret1 = insertvalue %single.result %ret0, [2 x i64] %arr1, 1
  store %single.result %ret1, ptr %result.home, align 8
  ret void
}

%pair = type { i64, i64 }
; Aggregate arguments and results can share one outgoing call frame. Read stack
; results from the post-call SP before releasing that frame.
define goabiinternal i64 @call_method_results(ptr %callee, ptr %recv,
                                               ptr nest %ctxt) {
; X86-O2-LABEL: call_method_results:
; X86-O2:       callq *
; X86-O2:       movq 32(%rsp), %{{r[a-z0-9]+}}
; X86-O2:       movq 40(%rsp), %{{r[a-z0-9]+}}
; X86-O2:       movq 48(%rsp), %{{r[a-z0-9]+}}
; X86-O2:       movq 56(%rsp), %{{r[a-z0-9]+}}
; X86-O2:       addq ${{[0-9]+}}, %rsp
entry:
  %x.home = alloca [2 x i64], align 8
  %y.home = alloca [2 x double], align 8
  %x.result = alloca [2 x i64], align 8
  %y.result = alloca [2 x double], align 8
  store [2 x i64] [i64 456, i64 789], ptr %x.home, align 8
  store [2 x double] [double 3.4, double 5.6], ptr %y.home, align 8
  %result = call goabiinternal { i64, i64, double } %callee(
      ptr %recv, i64 123, ptr byval([2 x i64]) align 8 %x.home,
      double 1.2, ptr byval([2 x double]) align 8 %y.home,
      ptr goret([2 x i64]) align 8 "goretindex"="2" %x.result,
      ptr goret([2 x double]) align 8 "goretindex"="4" %y.result,
      ptr nest %ctxt) #0
  %s = extractvalue { i64, i64, double } %result, 0
  %a = extractvalue { i64, i64, double } %result, 1
  %x = load [2 x i64], ptr %x.result, align 8
  %x0 = extractvalue [2 x i64] %x, 0
  %x1 = extractvalue [2 x i64] %x, 1
  %y = load [2 x double], ptr %y.result, align 8
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
; X86: leaq 8(%rsp), %[[PAIR_HOME:r[a-z0-9]+]]
; X86-DAG: movq (%[[PAIR_HOME]]), %[[LEFT:r[a-z0-9]+]]
; X86-DAG: movq 8(%[[PAIR_HOME]]), %[[RIGHT:r[a-z0-9]+]]
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
; X86-DAG: movq %{{r[a-z0-9]+}}, (%[[BASE:r[a-z0-9]+]])
; X86-DAG: movq %{{r[a-z0-9]+}}, 8(%[[BASE]])
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

define goabiinternal void @stack_bytes(
    ptr byval([8 x i8]) align 1 %value.home,
    ptr goret([8 x i8]) align 1 "goretindex"="0" %result.home) {
; X86-LABEL: stack_bytes:
; X86: leaq 16(%rsp), %[[RESULT_HOME:r[a-z0-9]+]]
; X86: leaq 8(%rsp), %[[BYTES_HOME:r[a-z0-9]+]]
; X86-DAG: movb (%[[BYTES_HOME]]), %{{[a-z0-9]+}}
; X86-DAG: movb 7(%[[BYTES_HOME]]), %{{[a-z0-9]+}}
; X86-DAG: movb %{{[a-z0-9]+}}, (%[[RESULT_HOME]])
; X86-DAG: movb %{{[a-z0-9]+}}, 7(%[[RESULT_HOME]])
; X86: retq
entry:
  %value = load [8 x i8], ptr %value.home, align 1
  store [8 x i8] %value, ptr %result.home, align 1
  ret void
}

define goabiinternal i16 @call_stack_bytes() {
; X86-LABEL: call_stack_bytes:
; X86: movq %{{r[a-z0-9]+}}, (%[[BASE:r[a-z0-9]+]])
; X86: callq stack_bytes
; X86: movq %rsp, %[[RESULT_BASE:r[a-z0-9]+]]
; X86: movq 8(%[[RESULT_BASE]]), %{{r[a-z0-9]+}}
entry:
  %value.home = alloca [8 x i8], align 1
  %result.home = alloca [8 x i8], align 1
  store [8 x i8] [i8 1, i8 2, i8 3, i8 4, i8 5, i8 6, i8 7, i8 8],
      ptr %value.home, align 1
  call goabiinternal void @stack_bytes(
      ptr byval([8 x i8]) align 1 %value.home,
      ptr goret([8 x i8]) align 1 "goretindex"="0" %result.home)
  %result = load [8 x i8], ptr %result.home, align 1
  %first = extractvalue [8 x i8] %result, 0
  %last = extractvalue [8 x i8] %result, 7
  %first.ext = zext i8 %first to i16
  %last.ext = zext i8 %last to i16
  %first.high = shl i16 %first.ext, 8
  %combined = or i16 %first.high, %last.ext
  ret i16 %combined
}

attributes #0 = { "go_results_tuple" }
