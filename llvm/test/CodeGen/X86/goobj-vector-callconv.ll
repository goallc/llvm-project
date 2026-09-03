; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s

declare goabi0 void @"runtime.morestack_noctxt<builtin.246><ABI0>"()

%fifteen_f64 = type { double, double, double, double, double,
                      double, double, double, double, double,
                      double, double, double, double, double }

define goabiinternal <16 x i8> @vector_morestack_call(<16 x i8> %value) {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  ret <16 x i8> %value
}

; CHECK-LABEL: name: vector_morestack_call
; CHECK: MOVUPSmr $rsp, 1, $noreg, 8, $noreg, $xmm0
; CHECK: CALL64pcrel32 &"runtime.morestack_noctxt<builtin.246><ABI0>"
; CHECK: $xmm0 = MOVUPSrm $rsp, 1, $noreg, 8, $noreg
; CHECK: RET 0, $xmm0

define goabiinternal <32 x i8> @vector256_morestack_call(<32 x i8> %value) #0 {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  ret <32 x i8> %value
}

; CHECK-LABEL: name: vector256_morestack_call
; CHECK: VMOVUPSYmr $rsp, 1, $noreg, 8, $noreg, $ymm0
; CHECK: CALL64pcrel32 &"runtime.morestack_noctxt<builtin.246><ABI0>"
; CHECK: $ymm0 = VMOVUPSYrm $rsp, 1, $noreg, 8, $noreg
; CHECK: RET 0, $ymm0

define goabiinternal <64 x i8> @vector512_morestack_call(<64 x i8> %value) #1 {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  ret <64 x i8> %value
}

; CHECK-LABEL: name: vector512_morestack_call
; CHECK: VMOVUPSZmr $rsp, 1, $noreg, 8, $noreg, $zmm0
; CHECK: CALL64pcrel32 &"runtime.morestack_noctxt<builtin.246><ABI0>"
; CHECK: $zmm0 = VMOVUPSZrm $rsp, 1, $noreg, 8, $noreg
; CHECK: RET 0, $zmm0

define goabiinternal <32 x i8> @fifteenth_vector256(
    <32 x i8> %v0, <32 x i8> %v1, <32 x i8> %v2, <32 x i8> %v3,
    <32 x i8> %v4, <32 x i8> %v5, <32 x i8> %v6, <32 x i8> %v7,
    <32 x i8> %v8, <32 x i8> %v9, <32 x i8> %v10, <32 x i8> %v11,
    <32 x i8> %v12, <32 x i8> %v13, <32 x i8> %v14) #0 {
entry:
  ret <32 x i8> %v14
}

; The fifteenth Go FP slot is register 14. Register 15 and all of its aliases
; remain reserved for Go's architectural zero register.
; CHECK-LABEL: name: fifteenth_vector256
; CHECK-NOT: $ymm15
; CHECK: $ymm0 = COPY $ymm14
; CHECK: RET 0, $ymm0

define goabiinternal <64 x i8> @fifteenth_vector512(
    <64 x i8> %v0, <64 x i8> %v1, <64 x i8> %v2, <64 x i8> %v3,
    <64 x i8> %v4, <64 x i8> %v5, <64 x i8> %v6, <64 x i8> %v7,
    <64 x i8> %v8, <64 x i8> %v9, <64 x i8> %v10, <64 x i8> %v11,
    <64 x i8> %v12, <64 x i8> %v13, <64 x i8> %v14) #1 {
entry:
  ret <64 x i8> %v14
}

; CHECK-LABEL: name: fifteenth_vector512
; CHECK-NOT: $zmm15
; CHECK: $zmm0 = COPY $zmm14
; CHECK: RET 0, $zmm0

define goabiinternal void @vector256_stack_argument(
    ptr byval(<32 x i8>) align 8 %value) #0 {
entry:
  %loaded = load volatile <32 x i8>, ptr %value, align 8
  ret void
}

; CHECK-LABEL: name: vector256_stack_argument
; CHECK: $ymm0 = VMOVUPSYrm $rsp, 1, $noreg, 8, $noreg

define goabiinternal void @vector512_stack_argument(
    ptr byval(<64 x i8>) align 8 %value) #1 {
entry:
  %loaded = load volatile <64 x i8>, ptr %value, align 8
  ret void
}

; CHECK-LABEL: name: vector512_stack_argument
; CHECK: $zmm0 = VMOVDQU64Zrm $rsp, 1, $noreg, 8, $noreg

define goabiinternal %fifteen_f64 @vector256_stack_result(
    ptr goret(<32 x i8>) align 8 "goretindex"="15" %result) #2 {
entry:
  store volatile <32 x i8> zeroinitializer, ptr %result, align 8
  ret %fifteen_f64 poison
}

; Fifteen direct floating-point results exhaust the register result budget, so
; the following vector result uses its 8-byte-aligned goret stack home.
; CHECK-LABEL: name: vector256_stack_result
; CHECK: VMOVUPSYmr $rsp, 1, $noreg, 8, $noreg, {{.*}}$ymm0

define goabiinternal %fifteen_f64 @vector512_stack_result(
    ptr goret(<64 x i8>) align 8 "goretindex"="15" %result) #3 {
entry:
  store volatile <64 x i8> zeroinitializer, ptr %result, align 8
  ret %fifteen_f64 poison
}

; CHECK-LABEL: name: vector512_stack_result
; CHECK: VMOVDQU64Zmr $rsp, 1, $noreg, 8, $noreg, {{.*}}$zmm0

define goabiinternal <32 x i8> @vector256_avx2_callee(
    <32 x i8> %value, double %after) #0 {
entry:
  ret <32 x i8> %value
}

; CHECK-LABEL: name: vector256_avx2_callee
; CHECK: liveins:
; CHECK-NEXT: - { reg: '$ymm0'
; CHECK: RET 0, $ymm0

define goabiinternal <32 x i8> @vector256_avx_caller(
    <32 x i8> %value, double %after) #4 {
entry:
  %result = call goabiinternal <32 x i8> @vector256_avx2_callee(
      <32 x i8> %value, double %after)
  ret <32 x i8> %result
}

; AVX does not make LLVM's integer v32i8 operations legal, but it does provide
; the YMM carrier used by Go for every 256-bit SIMD lane shape. The call must
; therefore keep the same one-slot ABI when the callee additionally uses AVX2.
; CHECK-LABEL: name: vector256_avx_caller
; CHECK: liveins:
; CHECK-NEXT: - { reg: '$ymm0'
; CHECK-NEXT: - { reg: '$xmm1'
; CHECK: CALL64pcrel32 @vector256_avx2_callee{{.*}}implicit $ymm0, implicit $xmm1, implicit-def $ymm0
; CHECK: RET 0, $ymm0

define goabiinternal <64 x i8> @vector512_bw_callee(
    <64 x i8> %value, double %after) #1 {
entry:
  ret <64 x i8> %value
}

; CHECK-LABEL: name: vector512_bw_callee
; CHECK: liveins:
; CHECK-NEXT: - { reg: '$zmm0'
; CHECK: RET 0, $zmm0

define goabiinternal <64 x i8> @vector512_f_caller(
    <64 x i8> %value, double %after) #5 {
entry:
  %result = call goabiinternal <64 x i8> @vector512_bw_callee(
      <64 x i8> %value, double %after)
  ret <64 x i8> %result
}

; CHECK-LABEL: name: vector512_f_caller
; CHECK: liveins:
; CHECK-NEXT: - { reg: '$zmm0'
; CHECK-NEXT: - { reg: '$xmm1'
; CHECK: CALL64pcrel32 @vector512_bw_callee{{.*}}implicit $zmm0, implicit $xmm1, implicit-def $zmm0
; CHECK: RET 0, $zmm0

attributes #0 = { "target-features"="+avx,+avx2" }
attributes #1 = { "target-features"="+avx,+avx2,+avx512f,+avx512bw" }
attributes #2 = { "go_results_tuple" "target-features"="+avx,+avx2" }
attributes #3 = { "go_results_tuple" "target-features"="+avx,+avx2,+avx512f,+avx512bw" }
attributes #4 = { "target-features"="+avx" }
attributes #5 = { "target-features"="+avx,+avx2,+avx512f" }
