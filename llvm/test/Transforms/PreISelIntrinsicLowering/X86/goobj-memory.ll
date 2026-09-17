; RUN: opt -mtriple=x86_64-unknown-linux-goobj -passes=pre-isel-intrinsic-lowering -S < %s | FileCheck %s

; Preserve zero fills for the Go bzero implementation, without pretending that
; a general memset implementation exists.
; CHECK-LABEL: define goabiinternal void @zero(
; CHECK-NEXT: call void @llvm.memset.p0.i64(ptr %dst, i8 0, i64 %size, i1 false)
; CHECK-NEXT: ret void
define goabiinternal void @zero(ptr %dst, i64 %size) {
  call void @llvm.memset.p0.i64(ptr %dst, i8 0, i64 %size, i1 false)
  ret void
}

; CHECK-LABEL: define goabiinternal void @small_fill(
; CHECK-NEXT: call void @llvm.memset.inline.p0.i64(ptr %dst, i8 %byte, i64 32, i1 false)
; CHECK-NEXT: ret void
define goabiinternal void @small_fill(ptr %dst, i8 %byte) {
  call void @llvm.memset.p0.i64(ptr %dst, i8 %byte, i64 32, i1 false)
  ret void
}

; CHECK-LABEL: define goabiinternal void @large_fill(
; CHECK-NOT: call
; CHECK: store
; CHECK-NOT: call
; CHECK: ret void
define goabiinternal void @large_fill(ptr %dst, i8 %byte, i64 %size) {
  call void @llvm.memset.p0.i64(ptr %dst, i8 %byte, i64 %size, i1 false)
  ret void
}

declare void @llvm.memset.p0.i64(ptr, i8, i64, i1 immarg)
