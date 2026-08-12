; RUN: opt -S -passes=loop-reduce < %s | FileCheck %s

target triple = "x86_64-unknown-linux-gnu"

declare void @safepoint()
declare token @llvm.experimental.gc.statepoint.p0(i64, i32, ptr, i32, i32, ...)

; LSR must not create a loop-carried pointer after statepoint rewriting. Such a
; pointer would not be represented by the gc-live and gc.relocate operands that
; were already fixed by RewriteStatepointsForGC.
;
; CHECK-LABEL: define void @loop_with_statepoint(
; CHECK: loop:
; CHECK-NEXT: %index = phi i64 [ 0, %entry ], [ %index.next, %loop ]
; CHECK-NEXT: %offset = mul i64 %index, 56
; CHECK-NEXT: %element = getelementptr i8, ptr %base, i64 %offset
; CHECK-NEXT: store i8 0, ptr %element
; CHECK-NEXT: %statepoint = call token
; CHECK-NEXT: %index.next = add nuw i64 %index, 1
define void @loop_with_statepoint(ptr %base, i64 %count) gc "statepoint-example" {
entry:
  br label %loop

loop:
  %index = phi i64 [ 0, %entry ], [ %index.next, %loop ]
  %offset = mul i64 %index, 56
  %element = getelementptr i8, ptr %base, i64 %offset
  store i8 0, ptr %element
  %statepoint = call token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 0, i32 0, ptr elementtype(void ()) @safepoint, i32 0, i32 0, i32 0, i32 0)
  %index.next = add nuw i64 %index, 1
  %done = icmp eq i64 %index.next, %count
  br i1 %done, label %exit, label %loop

exit:
  ret void
}

; Keep checking the positive side of the policy: an otherwise identical loop
; without a statepoint is still strength-reduced to a pointer induction
; variable.
;
; CHECK-LABEL: define void @loop_without_statepoint(
; CHECK: loop:
; CHECK-NEXT: %[[PTR_IV:lsr\.iv[0-9]*]] = phi ptr
; CHECK-NOT: mul i64
; CHECK: %scevgep = getelementptr i8, ptr %[[PTR_IV]], i64 56
define void @loop_without_statepoint(ptr %base, i64 %count) {
entry:
  br label %loop

loop:
  %index = phi i64 [ 0, %entry ], [ %index.next, %loop ]
  %offset = mul i64 %index, 56
  %element = getelementptr i8, ptr %base, i64 %offset
  store i8 0, ptr %element
  %index.next = add nuw i64 %index, 1
  %done = icmp eq i64 %index.next, %count
  br i1 %done, label %exit, label %loop

exit:
  ret void
}
