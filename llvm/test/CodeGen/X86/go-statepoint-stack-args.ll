; REQUIRES: x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s

%aggregate = type { ptr addrspace(1), i64, ptr addrspace(1) }

declare goabiinternal void @safepoint()

define goabiinternal ptr addrspace(1) @scalar_stack_arg(
    ptr addrspace(1) %p0,
    i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5,
    i64 %a6, i64 %a7, i64 %a8, i64 %a9, i64 %a10,
    i64 %a11, i64 %a12, i64 %a13, i64 %a14, i64 %a15,
    ptr addrspace(1) %p16) gc "statepoint-example" {
entry:
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %p16) ]
  %relocated = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token, i32 0, i32 0)
  ret ptr addrspace(1) %relocated
}

define goabiinternal ptr addrspace(1) @aggregate_stack_arg(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4,
    i64 %a5, i64 %a6, i64 %a7, i64 %a8, i64 %a9,
    i64 %a10, i64 %a11, i64 %a12, i64 %a13, i64 %a14,
    %aggregate %value) gc "statepoint-example" {
entry:
  %first = extractvalue %aggregate %value, 0
  %second = extractvalue %aggregate %value, 2
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 2, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %first, ptr addrspace(1) %second) ]
  %first.relocated = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token, i32 0, i32 0)
  %second.relocated = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token, i32 1, i32 1)
  %result = select i1 true, ptr addrspace(1) %first.relocated,
      ptr addrspace(1) %second.relocated
  ret ptr addrspace(1) %result
}

define goabiinternal ptr addrspace(1) @merged_stack_arg(
    ptr addrspace(1) %p0,
    i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5,
    i64 %a6, i64 %a7, i64 %a8, i64 %a9, i64 %a10,
    i64 %a11, i64 %a12, i64 %a13, i64 %a14, i64 %a15,
    ptr addrspace(1) %p16, i1 %condition) gc "statepoint-example" {
entry:
  %merged = select i1 %condition, ptr addrspace(1) %p0,
      ptr addrspace(1) %p16
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 3, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %merged) ]
  %relocated = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token, i32 0, i32 0)
  ret ptr addrspace(1) %relocated
}

declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
    token, i32 immarg, i32 immarg)

; CHECK-LABEL: name: scalar_stack_arg
; CHECK: fixedStack:
; CHECK: - { id: 0, type: default, offset: 56, size: 8,
; CHECK: isImmutable: false
; CHECK: stack:           []
; CHECK: STATEPOINT 1,
; CHECK-SAME: 2, 1, 1, 8, %fixed-stack.0, 0,
; CHECK-SAME: (volatile load store (s64) on %fixed-stack.0
; CHECK-NEXT: ADJCALLSTACKUP64
; CHECK-NEXT: [[SCALAR_RELOC:%[0-9]+]]:gr64 = MOV64rm %fixed-stack.0

; CHECK-LABEL: name: aggregate_stack_arg
; CHECK: stack:           []
; CHECK: STATEPOINT 2,
; CHECK-SAME: 2, 2, 1, 8, %fixed-stack.0, 0, 1, 8, %fixed-stack.2, 0,
; CHECK-SAME: (volatile load store (s64) on %fixed-stack.0{{[^)]*}}),
; CHECK-SAME: (volatile load store (s64) on %fixed-stack.2{{[^)]*}})
; CHECK-NEXT: ADJCALLSTACKUP64
; CHECK-NEXT: [[AGGREGATE_RELOC:%[0-9]+]]:gr64 = MOV64rm %fixed-stack.2

; CHECK-LABEL: name: merged_stack_arg
; CHECK: stack:
; CHECK-NEXT: - { id: 0, name: '', type: default, offset: 0, size: 8,
; CHECK: MOV64mr %stack.0,
; CHECK: STATEPOINT 3,
; CHECK-SAME: 2, 1, 1, 8, %stack.0, 0,
; CHECK-SAME: (volatile load store (s64) on %stack.0)
