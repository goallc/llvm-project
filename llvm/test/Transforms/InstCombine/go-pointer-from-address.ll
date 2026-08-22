; RUN: opt -S -passes='default<O2>' %s | FileCheck %s

declare ptr @llvm.go.pointer.from.address.p0.i64(i64)
declare void @may_grow_stack()

define ptr @restore_across_call(i64 %address) {
; CHECK-LABEL: @restore_across_call(
; CHECK:       %pointer = {{(tail )?}}call ptr @llvm.go.pointer.from.address.p0.i64(i64 %address)
; CHECK-NEXT:  {{(tail )?}}call void @may_grow_stack()
; CHECK-NEXT:  ret ptr %pointer
  %pointer = call ptr @llvm.go.pointer.from.address.p0.i64(i64 %address)
  call void @may_grow_stack()
  ret ptr %pointer
}
