; RUN: opt -passes='default<O2>' -S %s | FileCheck %s

declare token @llvm.call.preallocated.setup(i32)
declare ptr @llvm.call.preallocated.arg(token, i32)
declare void @left_callee(ptr preallocated(i32))
declare void @right_callee(ptr preallocated(i32))

; Each setup owns one physical outgoing call frame. SimplifyCFG must not merge
; identical setup/arg pairs from mutually exclusive branches and then let two
; calls consume the same token.
define void @branch_local_call_frames(i1 %condition) {
; CHECK-LABEL: define void @branch_local_call_frames(
; CHECK: %left.setup = {{(tail )?}}call token @llvm.call.preallocated.setup(i32 1)
; CHECK: call void @left_callee
; CHECK: %right.setup = {{(tail )?}}call token @llvm.call.preallocated.setup(i32 1)
; CHECK: call void @right_callee
entry:
  br i1 %condition, label %left, label %right

left:
  %left.setup = call token @llvm.call.preallocated.setup(i32 1)
  %left.home = call ptr @llvm.call.preallocated.arg(token %left.setup, i32 0) preallocated(i32)
  store i32 1, ptr %left.home, align 4
  call void @left_callee(ptr preallocated(i32) %left.home)
      ["preallocated"(token %left.setup)]
  br label %exit

right:
  %right.setup = call token @llvm.call.preallocated.setup(i32 1)
  %right.home = call ptr @llvm.call.preallocated.arg(token %right.setup, i32 0) preallocated(i32)
  store i32 2, ptr %right.home, align 4
  call void @right_callee(ptr preallocated(i32) %right.home)
      ["preallocated"(token %right.setup)]
  br label %exit

exit:
  ret void
}
