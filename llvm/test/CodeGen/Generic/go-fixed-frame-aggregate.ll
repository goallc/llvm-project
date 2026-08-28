; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel -o - %s | FileCheck %s \
; RUN:     --check-prefixes=CHECK,X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel -o - %s | FileCheck %s \
; RUN:     --check-prefixes=CHECK,AARCH64

%aggregate = type { ptr, i64, i64 }

declare goabiinternal void @safepoint()
declare goabiinternal void @observe_aggregate(%aggregate)

; SelectionDAG scalarizes an aggregate PHI into one Machine PHI per leaf. The
; first leaf here is nevertheless the identity of %slot on every incoming
; edge. A call can move the Go stack, so its use after the statepoint must be
; selected from %slot's FrameIndex instead of the pointer Machine PHI.
define goabiinternal void @aggregate_fixed_frame_loop(i1 %again)
    gc "statepoint-example" {
; CHECK-LABEL: name: aggregate_fixed_frame_loop
; CHECK:       STATEPOINT 1,
; X86:        %[[FRAME:[0-9]+]]:gr64 = LEA64r %stack.0.slot
; X86-NEXT:   $rax = COPY %[[FRAME]]
; X86-NEXT:   $rbx = COPY
; X86-NEXT:   $rcx = COPY
; X86-NEXT:   CALL64pcrel32 @observe_aggregate
; AARCH64:    %[[FRAME:[0-9]+]]:gpr64sp = ADDXri %stack.0.slot
; AARCH64-NEXT: $x0 = COPY %[[FRAME]]
; AARCH64-NEXT: $x1 = COPY
; AARCH64-NEXT: $x2 = COPY
; AARCH64-NEXT: BL @observe_aggregate
entry:
  %slot = alloca i64, align 8
  %initial.0 = insertvalue %aggregate poison, ptr %slot, 0
  %initial.1 = insertvalue %aggregate %initial.0, i64 7, 1
  %initial = insertvalue %aggregate %initial.1, i64 9, 2
  br label %loop

loop:
  %current = phi %aggregate [ %initial, %entry ], [ %next, %cont ]
  call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
  br label %cont

cont:
  call goabiinternal void @observe_aggregate(%aggregate %current)
  %next = insertvalue %aggregate %current, ptr %slot, 0
  br i1 %again, label %loop, label %exit

exit:
  ret void
}

; A PHI with different frame bases is not one fixed-frame identity. Keep the
; ordinary SSA/vreg path for that leaf.
define goabiinternal void @aggregate_different_frames(i1 %choose)
    gc "statepoint-example" {
; CHECK-LABEL: name: aggregate_different_frames
; CHECK:       STATEPOINT 2,
; X86-NOT:     LEA64r %stack
; X86:         CALL64pcrel32 @observe_aggregate
; AARCH64-NOT: ADDXri %stack
; AARCH64:     BL @observe_aggregate
entry:
  %left.slot = alloca i64, align 8
  %right.slot = alloca i64, align 8
  %left.0 = insertvalue %aggregate poison, ptr %left.slot, 0
  %left.1 = insertvalue %aggregate %left.0, i64 1, 1
  %left = insertvalue %aggregate %left.1, i64 2, 2
  %right.0 = insertvalue %aggregate poison, ptr %right.slot, 0
  %right.1 = insertvalue %aggregate %right.0, i64 1, 1
  %right = insertvalue %aggregate %right.1, i64 2, 2
  br i1 %choose, label %take.left, label %take.right

take.left:
  br label %merge

take.right:
  br label %merge

merge:
  %selected = phi %aggregate [ %left, %take.left ],
                            [ %right, %take.right ]
  call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 2, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
  call goabiinternal void @observe_aggregate(%aggregate %selected)
  ret void
}

declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
