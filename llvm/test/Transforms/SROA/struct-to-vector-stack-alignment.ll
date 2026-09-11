; RUN: opt -passes='sroa<aggregate-to-vector>' -S %s | FileCheck %s
; RUN: opt -data-layout="e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S64" \
; RUN:   -passes='sroa<aggregate-to-vector>' -S %s | FileCheck %s --check-prefix=STACK64

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%struct.ptr5 = type { ptr, ptr, ptr, ptr, ptr }

declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)

define void @natural_stack_alignment(ptr %src) {
; STACK64-LABEL: define void @natural_stack_alignment(
; STACK64:         %dst.sroa.0 = alloca <5 x ptr>, align 8
; CHECK-LABEL: define void @natural_stack_alignment(
; CHECK-SAME: ptr [[SRC:%.*]]) {
; CHECK-NEXT:  entry:
; CHECK-NEXT:    [[DST:%.*]] = alloca <5 x ptr>, align 16
; CHECK-NEXT:    [[COPY:%.*]] = load volatile <5 x ptr>, ptr [[SRC]], align 8
; CHECK-NEXT:    store volatile <5 x ptr> [[COPY]], ptr [[DST]], align 16
; CHECK-NEXT:    ret void
;
entry:
  %dst = alloca %struct.ptr5, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %dst, ptr align 8 %src,
                                   i64 40, i1 true)
  ret void
}

define void @explicit_stronger_alignment(ptr %src) {
; STACK64-LABEL: define void @explicit_stronger_alignment(
; STACK64:         %dst.sroa.0 = alloca <5 x ptr>, align 64
; CHECK-LABEL: define void @explicit_stronger_alignment(
; CHECK-SAME: ptr [[SRC:%.*]]) {
; CHECK-NEXT:  entry:
; CHECK-NEXT:    [[DST:%.*]] = alloca <5 x ptr>, align 64
; CHECK-NEXT:    [[COPY:%.*]] = load volatile <5 x ptr>, ptr [[SRC]], align 8
; CHECK-NEXT:    store volatile <5 x ptr> [[COPY]], ptr [[DST]], align 64
; CHECK-NEXT:    ret void
;
entry:
  %dst = alloca %struct.ptr5, align 64
  call void @llvm.memcpy.p0.p0.i64(ptr align 64 %dst, ptr align 8 %src,
                                   i64 40, i1 true)
  ret void
}
