; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel -o - %s | FileCheck %s \
; RUN:     --check-prefixes=CHECK,X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel -o - %s | FileCheck %s \
; RUN:     --check-prefixes=CHECK,AARCH64

; A PHI made entirely from one fixed Go frame object and relocates of that
; object denotes the same frame index on every incoming edge. It must not
; become an ordinary Machine PHI whose address value can be spilled.

declare goabiinternal void @safepoint()

define goabiinternal void @fixed_frame_loop(i1 %take_call, i1 %again)
    gc "statepoint-example" {
; CHECK-LABEL: name: fixed_frame_loop
; CHECK-NOT: PHI
; CHECK: %stack.0.slot
; CHECK-NOT: PHI
entry:
  %slot = alloca i64, align 8, addrspace(1)
  br label %loop

loop:
  %current = phi ptr addrspace(1) [ %slot, %entry ], [ %next, %latch ]
  br i1 %take_call, label %call, label %latch

call:
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %slot) ]
  %relocated = call coldcc ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  br label %latch

latch:
  %next = phi ptr addrspace(1) [ %current, %loop ], [ %relocated, %call ]
  store i64 7, ptr addrspace(1) %next, align 8
  br i1 %again, label %loop, label %exit

exit:
  ret void
}

; Aggregate scalarization can put an exact frame address behind an
; extractvalue/insertvalue pair. Its relocate loop is the same frame-index
; identity and must receive the same PHI treatment.
define goabiinternal void @fixed_frame_aggregate_leaf_loop(i1 %again)
    gc "statepoint-example" {
; CHECK-LABEL: name: fixed_frame_aggregate_leaf_loop
; CHECK-NOT: PHI
; CHECK: %stack.0.aggregate.slot
; CHECK-NOT: PHI
entry:
  %aggregate.slot = alloca i64, align 8, addrspace(1)
  %address = getelementptr i8, ptr addrspace(1) %aggregate.slot, i64 0
  %aggregate.0 = insertvalue { ptr addrspace(1), i64 } poison,
      ptr addrspace(1) %address, 0
  %aggregate = insertvalue { ptr addrspace(1), i64 } %aggregate.0, i64 1, 1
  %leaf = extractvalue { ptr addrspace(1), i64 } %aggregate, 0
  br label %loop

loop:
  %current = phi ptr addrspace(1) [ %leaf, %entry ], [ %relocated, %cont ]
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 2, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %current) ]
  br label %cont

cont:
  %relocated = call coldcc ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  store i64 11, ptr addrspace(1) %current, align 8
  br i1 %again, label %loop, label %exit

exit:
  ret void
}

; A relocate of a fixed-frame PHI must keep the same frame-index identity for
; the next statepoint. Otherwise the relocate is exported to a virtual
; register and the next statepoint records an unnecessary spill slot.
define goabiinternal void @fixed_frame_relocate_chain(i1 %again)
    gc "statepoint-example" {
; CHECK-LABEL: name: fixed_frame_relocate_chain
; CHECK: stack:
; CHECK-NEXT: - { id: 0, name: chain.slot
; CHECK-NOT: id: 1
; CHECK: STATEPOINT 3
; CHECK-SAME: %stack.0.chain.slot
; CHECK-NOT: %stack.1
; CHECK: STATEPOINT 4
; CHECK-SAME: %stack.0.chain.slot
; CHECK-NOT: %stack.1
entry:
  %chain.slot = alloca i64, align 8, addrspace(1)
  br label %loop

loop:
  %current = phi ptr addrspace(1) [ %chain.slot, %entry ],
                                  [ %relocated.2, %loop ]
  %token.1 = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 3, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %current) ]
  %relocated.1 = call coldcc ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(token %token.1, i32 0, i32 0)
  %token.2 = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 4, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %relocated.1) ]
  %relocated.2 = call coldcc ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(token %token.2, i32 0, i32 0)
  store i64 13, ptr addrspace(1) %relocated.2, align 8
  br i1 %again, label %loop, label %exit

exit:
  ret void
}

; Different fixed objects do not form one frame-index equivalence class.
define goabiinternal void @different_fixed_frames(i1 %choose) {
; CHECK-LABEL: name: different_fixed_frames
; X86: %stack.0.left.slot
; X86: %stack.1.right.slot
; X86: PHI
; AARCH64: ADDXri %stack.1.right.slot
; AARCH64: ADDXri %stack.0.left.slot
; AARCH64: CSELXr
entry:
  %left.slot = alloca i64, align 8, addrspace(1)
  %right.slot = alloca i64, align 8, addrspace(1)
  br i1 %choose, label %left, label %right

left:
  br label %merge

right:
  br label %merge

merge:
  %selected = phi ptr addrspace(1) [ %left.slot, %left ],
                                           [ %right.slot, %right ]
  store i64 9, ptr addrspace(1) %selected, align 8
  ret void
}

declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
    token, i32 immarg, i32 immarg)
