; REQUIRES: x86-registered-target
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-gnu < %s 2>&1 \
; RUN:   | FileCheck %s

@root = global ptr addrspace(1) null

declare void @safepoint()

define ptr addrspace(1) @not_an_alloca() gc "statepoint-example" {
entry:
  %live = load ptr addrspace(1), ptr @root, align 8,
      !llvm.statepoint.fixed_stack_home !0
  %token = call token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %live) ]
  %relocated = call ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  ret ptr addrspace(1) %relocated
}

declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
    token, i32 immarg, i32 immarg)

!0 = !{}

; CHECK: LLVM ERROR: invalid llvm.statepoint.fixed_stack_home load:
; CHECK-SAME: address is not a static alloca plus a constant offset
