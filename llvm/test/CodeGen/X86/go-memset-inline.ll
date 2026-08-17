; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -mem-intrinsic-expand-size=801 < %s | FileCheck %s

declare void @llvm.memset.p0.i64(ptr writeonly, i8, i64, i1 immarg)

define goabiinternal void @constant_memset(ptr %dst) {
; CHECK-LABEL: constant_memset:
; CHECK: rep
; CHECK-SAME: stos
; CHECK-NOT: callq memset
; CHECK: retq
  call void @llvm.memset.p0.i64(ptr align 8 %dst, i8 0, i64 800, i1 false)
  ret void
}

define goabi0 void @"dynamic_memset<ABI0>"(
    ptr byval(ptr) align 8 %dst.home,
    ptr byval(i64) align 8 %size.home) {
; CHECK-LABEL: "dynamic_memset<ABI0>":
; CHECK: movb $0,
; CHECK: incq
; CHECK: cmpq
; CHECK-NOT: callq memset
; CHECK: retq
  %dst = load ptr, ptr %dst.home, align 8
  %size = load i64, ptr %size.home, align 8
  call void @llvm.memset.p0.i64(ptr align 1 %dst, i8 0, i64 %size, i1 false)
  ret void
}
