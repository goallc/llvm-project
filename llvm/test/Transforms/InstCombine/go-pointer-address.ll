; RUN: opt -S -passes='default<O2>' %s | FileCheck %s

declare i64 @llvm.go.pointer.address.i64.p0(ptr)
declare void @may_grow_stack()

define i1 @observe_across_call(ptr %pointer) {
; CHECK-LABEL: @observe_across_call(
; CHECK:       %before = {{(tail )?}}call i64 @llvm.go.pointer.address.i64.p0(ptr %pointer)
; CHECK-NEXT:  {{(tail )?}}call void @may_grow_stack()
; CHECK-NEXT:  %after = {{(tail )?}}call i64 @llvm.go.pointer.address.i64.p0(ptr %pointer)
; CHECK-NEXT:  %same = icmp eq i64 %before, %after
; CHECK-NEXT:  ret i1 %same
  %before = call i64 @llvm.go.pointer.address.i64.p0(ptr %pointer)
  call void @may_grow_stack()
  %after = call i64 @llvm.go.pointer.address.i64.p0(ptr %pointer)
  %same = icmp eq i64 %before, %after
  ret i1 %same
}
