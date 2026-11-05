; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O2 -verify-machineinstrs < %s | FileCheck %s --check-prefixes=CHECK,UNALIGNED
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -mattr=+strict-align -O2 -verify-machineinstrs < %s | FileCheck %s --check-prefixes=CHECK,STRICT
;
; Only bounded zero fills of Go stack objects receive the expanded store budget.
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1 immarg)
declare goabiinternal void @observe(ptr)
declare void @observe_c(ptr)

define goabiinternal void @stack_257() {
; CHECK-LABEL: stack_257:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [257 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 257, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_511() {
; CHECK-LABEL: stack_511:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [511 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 511, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_512() {
; CHECK-LABEL: stack_512:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [512 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 512, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_767() {
; CHECK-LABEL: stack_767:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [767 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 767, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_768() {
; CHECK-LABEL: stack_768:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [768 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 768, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_769() {
; CHECK-LABEL: stack_769:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [769 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 769, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_1024() {
; CHECK-LABEL: stack_1024:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [1024 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 1024, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_1025() {
; CHECK-LABEL: stack_1025:
; CHECK: bl {{memset|bzero}}
; CHECK: bl observe
  %a = alloca [1025 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 1025, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_4096() {
; CHECK-LABEL: stack_4096:
; CHECK: bl {{memset|bzero}}
; CHECK: bl observe
  %a = alloca [4096 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 4096, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @heap(ptr %p) {
; CHECK-LABEL: heap:
; CHECK: bl {{memset|bzero}}
  call void @llvm.memset.p0.i64(ptr align 16 %p, i8 0, i64 768, i1 false)
  call goabiinternal void @observe(ptr %p)
  ret void
}

define goabiinternal void @dynamic(i64 %n) {
; CHECK-LABEL: dynamic:
; CHECK: bl {{memset|bzero}}
  %a = alloca [1024 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 %n, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @nonzero() {
; CHECK-LABEL: nonzero:
; CHECK: bl {{memset|bzero}}
  %a = alloca [768 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 7, i64 768, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define  void @c_stack() {
; CHECK-LABEL: c_stack:
; CHECK: bl {{memset|bzero}}
  %a = alloca [768 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 768, i1 false)
  call  void @observe_c(ptr %a)
  ret void
}

; The policy does not override a size-optimized function or volatile memset.
define goabiinternal void @size_optimized() optsize {
; CHECK-LABEL: size_optimized:
; CHECK: bl {{memset|bzero}}
  %a = alloca [768 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 768, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @volatile_stack() {
; CHECK-LABEL: volatile_stack:
; CHECK: bl {{memset|bzero}}
  %a = alloca [768 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 768, i1 true)
  call goabiinternal void @observe(ptr %a)
  ret void
}

; Keep the normal store-type selection when vector registers are forbidden.
define goabiinternal void @no_float() noimplicitfloat {
; CHECK-LABEL: no_float:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK-NOT: movi
; CHECK: stp xzr, xzr
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [768 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 768, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

; Byte alignment can use the ordinary unaligned stores, but must not expand
; hundreds of byte accesses on a strict-alignment target.
define goabiinternal void @unaligned_stack() {
; CHECK-LABEL: unaligned_stack:
; UNALIGNED-NOT: bl memset
; UNALIGNED: stp
; UNALIGNED-NOT: bl memset
; STRICT: bl memset
; CHECK: bl observe
  %a = alloca [784 x i8], align 16
  %p = getelementptr i8, ptr %a, i64 1
  call void @llvm.memset.p0.i64(ptr align 1 %p, i8 0, i64 768, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}
