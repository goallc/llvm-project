; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj \
; RUN:   -o /dev/null %s 2>&1 | FileCheck %s
; RUN: not --crash llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj \
; RUN:   -o /dev/null %s 2>&1 | FileCheck %s

; A GoObj function with Machine StackMaps must also describe its late
; stack-growth call as a statepoint. Without the frontend attribute, reject the
; function instead of allowing the preceding call's map to cover the raw
; runtime.morestack call.

declare void @callee()

define goabiinternal void @missing_stack_growth_attribute()
    gc "statepoint-example" {
entry:
  call token (i64, i32, ptr, i32, i32, ...)
    @llvm.experimental.gc.statepoint.p0(
      i64 0, i32 0, ptr elementtype(void ()) @callee, i32 0, i32 0,
      i32 0, i32 0)
  ret void
}

declare token @llvm.experimental.gc.statepoint.p0(
  i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)

; CHECK: LLVM ERROR: GoObj statepoints require the
; CHECK-SAME: go-stack-growth-statepoint function attribute
