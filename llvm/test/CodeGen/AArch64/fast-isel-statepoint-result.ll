; RUN: llc -mtriple=aarch64-linux-gnu -O0 -fast-isel -verify-machineinstrs < %s | FileCheck %s

; An extracted condition from gc.result is not an overflow-intrinsic flag.
; gc.result has one operand, so querying binary operands before checking the
; intrinsic ID would go out of bounds.
declare { i32, i1 } @callee()
declare token @llvm.experimental.gc.statepoint.p0(i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare { i32, i1 } @llvm.experimental.gc.result.sl_i32i1s(token)

; CHECK-LABEL: branch_result:
; CHECK: bl callee
; CHECK: ret
define i32 @branch_result() gc "statepoint-example" {
  %token = call token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 0, i32 0, ptr elementtype({ i32, i1 } ()) @callee, i32 0, i32 0, i32 0, i32 0)
  %result = call { i32, i1 } @llvm.experimental.gc.result.sl_i32i1s(token %token)
  %condition = extractvalue { i32, i1 } %result, 1
  br i1 %condition, label %yes, label %no
yes:
  ret i32 11
no:
  ret i32 22
}

; CHECK-LABEL: select_result:
; CHECK: bl callee
; CHECK: ret
define i32 @select_result() gc "statepoint-example" {
  %token = call token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 0, i32 0, ptr elementtype({ i32, i1 } ()) @callee, i32 0, i32 0, i32 0, i32 0)
  %result = call { i32, i1 } @llvm.experimental.gc.result.sl_i32i1s(token %token)
  %condition = extractvalue { i32, i1 } %result, 1
  %value = select i1 %condition, i32 11, i32 22
  ret i32 %value
}
