; REQUIRES: x86-registered-target
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-gnu < %s 2>&1 \
; RUN:   | FileCheck %s

declare void @mutate(ptr)

define ptr addrspace(1) @marked_unmarked_collision(ptr addrspace(1) %p)
    gc "statepoint-example" {
entry:
  %home = alloca ptr addrspace(1), align 8
  store ptr addrspace(1) %p, ptr %home, align 8
  %marked = load ptr addrspace(1), ptr %home, align 8,
      !llvm.statepoint.fixed_stack_home !0
  %unmarked = select i1 true, ptr addrspace(1) %marked,
                            ptr addrspace(1) %marked
  %token = call token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void (ptr)) @mutate,
          i32 1, i32 0, ptr %home, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %marked,
                  ptr addrspace(1) %unmarked) ]
  %marked.relocated = call ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  %unmarked.relocated = call ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(token %token, i32 1, i32 1)
  %same = icmp eq ptr addrspace(1) %marked.relocated, %unmarked.relocated
  %result = select i1 %same, ptr addrspace(1) %marked.relocated,
                            ptr addrspace(1) %unmarked.relocated
  ret ptr addrspace(1) %result
}

declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
    token, i32 immarg, i32 immarg)

!0 = !{}

; CHECK: LLVM ERROR: llvm.statepoint.fixed_stack_home value and a distinct
; CHECK-SAME: unmarked GC value lower to the same pre-call value
