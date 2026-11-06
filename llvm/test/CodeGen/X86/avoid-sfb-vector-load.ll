; RUN: llc -mtriple=x86_64 -mattr=+sse2,-avx -verify-machineinstrs < %s | FileCheck %s --check-prefix=SSE
; RUN: llc -mtriple=x86_64 -mattr=+avx -verify-machineinstrs < %s | FileCheck %s --check-prefix=AVX
;
; Both paths write half of a subsequently consumed vector. The intervening
; store may alias either half: retain both loads after it, rather than reuse the
; stored scalar. The vector arithmetic must still receive all 128 loaded bits.
;
; SSE-LABEL: half_store_alias:
; SSE:       movl %ecx, (%rsi)
; SSE-NEXT:  movsd (%rdi), %xmm0
; SSE-NEXT:  movhps 8(%rdi), %xmm0
; SSE-NEXT:  paddq {{.*}}, %xmm0
; SSE-NEXT:  retq
;
; AVX-LABEL: half_store_alias:
; AVX:       movl %ecx, (%rsi)
; AVX-NEXT:  vmovsd (%rdi), %xmm0
; AVX-NEXT:  vmovhps 8(%rdi), %xmm0, %xmm0
; AVX-NEXT:  vpaddq {{.*}}, %xmm0, %xmm0
; AVX-NEXT:  retq
;
target triple = "x86_64-unknown-linux-gnu"
define <2 x i64> @half_store_alias(ptr %p, ptr %q, i64 %v, i32 %touch, i1 %upper) {
entry:
  br i1 %upper, label %high, label %low
high:
  %hi = getelementptr i8, ptr %p, i64 8
  store i64 %v, ptr %hi, align 1
  br label %join
low:
  store i64 %v, ptr %p, align 1
  br label %join
join:
  store i32 %touch, ptr %q, align 1
  %both = load <2 x i64>, ptr %p, align 1
  %result = add <2 x i64> %both, <i64 1, i64 3>
  ret <2 x i64> %result
}
