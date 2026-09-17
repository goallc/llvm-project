; RUN: llc -mtriple=x86_64-linux-gnu -mcpu=x86-64 -verify-machineinstrs < %s | FileCheck %s

; Soft-float removes vector register classes even when SSE2 is available.
; Memory operations must select integer types instead of splitting a vector.
; CHECK-LABEL: copy:
; CHECK-NOT: xmm
; CHECK: retq
define void @copy(ptr %dst, ptr %src) "use-soft-float"="true" {
  call void @llvm.memcpy.p0.p0.i64(ptr align 16 %dst, ptr align 16 %src, i64 16, i1 false)
  ret void
}

; CHECK-LABEL: move:
; CHECK-NOT: xmm
; CHECK: retq
define void @move(ptr %dst, ptr %src) "use-soft-float"="true" {
  call void @llvm.memmove.p0.p0.i64(ptr align 16 %dst, ptr align 16 %src, i64 16, i1 false)
  ret void
}

; CHECK-LABEL: clear:
; CHECK-NOT: xmm
; CHECK: retq
define void @clear(ptr %dst) "use-soft-float"="true" {
  call void @llvm.memset.p0.i64(ptr align 16 %dst, i8 0, i64 16, i1 false)
  ret void
}

declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)
declare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1)
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)
