; RUN: llc -mtriple=x86_64-unknown-linux-gnu -stop-after=codegenprepare \
; RUN:   -o - %s | FileCheck %s
; REQUIRES: x86-registered-target

declare ptr @llvm.go.pointer.from.address.p0.i64(i64)
declare void @may_grow_stack()

define ptr @restore_across_call(i64 %address) {
; CHECK-LABEL: define ptr @restore_across_call(
; CHECK:       %pointer = call ptr @llvm.go.pointer.from.address.p0.i64(i64 %address)
; CHECK-NEXT:  call void @may_grow_stack()
; CHECK-NEXT:  ret ptr %pointer
  %pointer = call ptr @llvm.go.pointer.from.address.p0.i64(i64 %address)
  call void @may_grow_stack()
  ret ptr %pointer
}
