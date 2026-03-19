; RUN: llc -mtriple=x86_64-unknown-linux-gnu < %s | FileCheck %s

; CHECK-LABEL: go_int_args:
; CHECK: movq %rax, -8(%rsp)
; CHECK: movq %rbx, -16(%rsp)
; CHECK: movq %rcx, -24(%rsp)
; CHECK: movq %rdi, -32(%rsp)
; CHECK: movq %rsi, -40(%rsp)
; CHECK: movq %r8, -48(%rsp)
; CHECK: movq %r9, -56(%rsp)
; CHECK: movq %r10, -64(%rsp)
; CHECK: movq %r11, -72(%rsp)
define gocc void @go_int_args(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7, i64 %a8) {
entry:
  %p0 = alloca i64, align 8
  %p1 = alloca i64, align 8
  %p2 = alloca i64, align 8
  %p3 = alloca i64, align 8
  %p4 = alloca i64, align 8
  %p5 = alloca i64, align 8
  %p6 = alloca i64, align 8
  %p7 = alloca i64, align 8
  %p8 = alloca i64, align 8
  store i64 %a0, ptr %p0, align 8
  store i64 %a1, ptr %p1, align 8
  store i64 %a2, ptr %p2, align 8
  store i64 %a3, ptr %p3, align 8
  store i64 %a4, ptr %p4, align 8
  store i64 %a5, ptr %p5, align 8
  store i64 %a6, ptr %p6, align 8
  store i64 %a7, ptr %p7, align 8
  store i64 %a8, ptr %p8, align 8
  ret void
}

; CHECK-LABEL: go_float_args:
; CHECK: movss %xmm0, -4(%rsp)
; CHECK: movsd %xmm1, -16(%rsp)
; CHECK: retq
define gocc void @go_float_args(float %a0, double %a1) {
entry:
  %p0 = alloca float, align 4
  %p1 = alloca double, align 8
  store float %a0, ptr %p0, align 4
  store double %a1, ptr %p1, align 8
  ret void
}

; CHECK-LABEL: go_ret_i64:
; CHECK: movq %rdi, %rax
; CHECK: retq
define gocc i64 @go_ret_i64(i64 %x) {
entry:
  ret i64 %x
}

; CHECK-LABEL: go_ret_double:
; CHECK: addsd %xmm1, %xmm0
; CHECK: retq
define gocc double @go_ret_double(double %x, double %y) {
entry:
  %sum = fadd double %x, %y
  ret double %sum
}


; CHECK-LABEL: go_ret_two_i64:
; CHECK: leaq 1(%rdi), %rax
; CHECK: leaq 2(%rdi), %rbx
; CHECK: retq
define gocc { i64, i64 } @go_ret_two_i64(i64 %x) {
entry:
  %a = add i64 %x, 1
  %b = add i64 %x, 2
  %r0 = insertvalue { i64, i64 } poison, i64 %a, 0
  %r1 = insertvalue { i64, i64 } %r0, i64 %b, 1
  ret { i64, i64 } %r1
}

; CHECK-LABEL: go_ret_i64_f64:
; CHECK: leaq 3(%rdi), %rax
; CHECK: addsd {{.*}}, %xmm0
; CHECK: retq
define gocc { i64, double } @go_ret_i64_f64(i64 %x, double %y) {
entry:
  %a = add i64 %x, 3
  %b = fadd double %y, 1.000000e+00
  %r0 = insertvalue { i64, double } poison, i64 %a, 0
  %r1 = insertvalue { i64, double } %r0, double %b, 1
  ret { i64, double } %r1
}

; CHECK-LABEL: go_ret_f32_f64:
; CHECK: addss {{.*}}, %xmm0
; CHECK: addsd {{.*}}, %xmm1
; CHECK: retq
define gocc { float, double } @go_ret_f32_f64(float %x, double %y) {
entry:
  %a = fadd float %x, 1.000000e+00
  %b = fadd double %y, 2.000000e+00
  %r0 = insertvalue { float, double } poison, float %a, 0
  %r1 = insertvalue { float, double } %r0, double %b, 1
  ret { float, double } %r1
}


; CHECK-LABEL: go_ret_ten_i64:
; CHECK: movq $10, {{[0-9]+}}(%rsp)
define gocc { i64, i64, i64, i64, i64, i64, i64, i64, i64, i64 } @go_ret_ten_i64() {
entry:
  ret { i64, i64, i64, i64, i64, i64, i64, i64, i64, i64 }
      { i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7, i64 8, i64 9, i64 10 }
}

; CHECK-LABEL: call_go_ret_ten_i64:
; CHECK: callq go_ret_ten_i64
; CHECK: movq {{[0-9]+}}(%rsp), %rax
define gocc i64 @call_go_ret_ten_i64() {
entry:
  %rv = call gocc { i64, i64, i64, i64, i64, i64, i64, i64, i64, i64 } @go_ret_ten_i64()
  %x = extractvalue { i64, i64, i64, i64, i64, i64, i64, i64, i64, i64 } %rv, 9
  ret i64 %x
}

; CHECK-LABEL: go_ret_sixteen_f64:
; CHECK: movsd {{.*}}, {{[0-9]+}}(%rsp)
define gocc { double, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double } @go_ret_sixteen_f64() {
entry:
  ret { double, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double }
      { double 1.0, double 2.0, double 3.0, double 4.0, double 5.0, double 6.0, double 7.0, double 8.0,
        double 9.0, double 10.0, double 11.0, double 12.0, double 13.0, double 14.0, double 15.0, double 16.0 }
}

; CHECK-LABEL: call_go_ret_sixteen_f64:
; CHECK: callq go_ret_sixteen_f64
; CHECK: movsd {{[0-9]+}}(%rsp), %xmm0
define gocc double @call_go_ret_sixteen_f64() {
entry:
  %rv = call gocc { double, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double } @go_ret_sixteen_f64()
  %x = extractvalue { double, double, double, double, double, double, double, double, double, double, double, double, double, double, double, double } %rv, 15
  ret double %x
}
