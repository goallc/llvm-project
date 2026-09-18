; REQUIRES: x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -O2 -verify-machineinstrs \
; RUN:   -stop-after=x86-cf-opt -o - %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -O2 -verify-machineinstrs \
; RUN:   -o - %s | FileCheck %s --check-prefix=ASM

%slice = type { ptr, i64, i64 }
%scalar.result = type { i64, i64 }
%pointer.result = type { ptr addrspace(1), i64 }

declare goabiinternal void @safepoint()
declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
    token, i32 immarg, i32 immarg)

; Argument-copy elision maps the private carrier below to the incoming slice's
; fixed canonical register home. The home must remain allocated for the
; pre-frame morestack path, which saves the physical inputs itself, but the hot
; path should copy the original SSA pieces straight to the ABI0 outgoing area.
;
; MIR-LABEL: name: forwarded_incoming_slice_indirect
; MIR: fixedStack:
; MIR-NOT: MOV{{.*}} %fixed-stack
; MIR: ADJCALLSTACKDOWN64 24
; MIR-NOT: MOV64rm {{.*}}%fixed-stack
; MIR: STATEPOINT
; MIR: ADJCALLSTACKUP64 24
;
; ASM-LABEL: forwarded_incoming_slice_indirect:
; ASM: subq
; ASM-NOT: pushq
; ASM: callq
; ASM-NOT: addq
; ASM: callq
define goabiinternal void @forwarded_incoming_slice_indirect(
    %slice %incoming, ptr %callee)
    gc "statepoint-example" {
entry:
  %argument = alloca %slice, align 8
  store %slice %incoming, ptr %argument, align 8
  %call = call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 7, i32 0, ptr elementtype(void (ptr)) %callee,
          i32 1, i32 0,
          ptr byval(%slice) align 8 %argument,
          i32 0, i32 0)
      [ "gc-live"(ptr %argument) ]
  %after = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 8, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr %argument) ]
  ret void
}

; Function values can dispatch to different ABI0 assembly implementations, so
; the call target is deliberately indirect. The load after the second
; statepoint makes this unlike a disposable private byval source: the slice
; carrier and its stack-map-described address must survive for the next use.
;
; Keep ordinary stores to the outgoing area. Turning those stores into PUSHes
; would set hasPushSequences, disable X86's reserved call frame for the whole
; function, and reintroduce per-iteration SUB/PUSH/ADD adjustments.
;
; MIR-LABEL: name: indirect_slice_loop
; MIR-NOT: hasPushSequences: true
; MIR: stack:
; MIR: - { id: [[CARRIER:[0-9]+]], name: argument
; MIR: bb.1.loop:
; MIR: ADJCALLSTACKDOWN64
; MIR-NOT: PUSH64
; MIR: STATEPOINT {{.*}}%stack.[[CARRIER]].argument
; MIR: ADJCALLSTACKUP64
; MIR: STATEPOINT {{.*}}%stack.[[CARRIER]].argument
; MIR: {{.*}} %stack.[[CARRIER]].argument{{.*}}dereferenceable load
;
; The final frame reserves the maximum outgoing area once in the prologue.
; ASM-LABEL: indirect_slice_loop:
; ASM: subq
; ASM: [[LOOP:.LBB[0-9]+_[0-9]+]]:
; ASM-NOT: subq
; ASM-NOT: pushq
; ASM: callq
; ASM-NOT: addq
; ASM: callq
define goabiinternal i64 @indirect_slice_loop(
    ptr %callee, ptr %base, i64 %length, i64 %capacity, i64 %iterations)
    gc "statepoint-example" {
entry:
  %argument = alloca %slice, align 8
  br label %loop

loop:
  %index = phi i64 [ 0, %entry ], [ %next, %loop.cont ]
  store ptr %base, ptr %argument, align 8
  %argument.length = getelementptr inbounds i8, ptr %argument, i64 8
  store i64 %length, ptr %argument.length, align 8
  %argument.capacity = getelementptr inbounds i8, ptr %argument, i64 16
  store i64 %capacity, ptr %argument.capacity, align 8
  %call = call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void (ptr)) %callee,
          i32 1, i32 0,
          ptr byval(%slice) align 8 %argument,
          i32 0, i32 0)
      [ "gc-live"(ptr %argument) ]
  br label %call.cont

call.cont:
  %after = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 2, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr %argument) ]
  %retained.length = load i64, ptr %argument.length, align 8
  br label %loop.cont

loop.cont:
  %next = add nuw i64 %index, 1
  %more = icmp ult i64 %next, %iterations
  br i1 %more, label %loop, label %exit

exit:
  %answer = add i64 %next, %retained.length
  ret i64 %answer
}

; A scalar aggregate result still needs its correctly sized ABI0 result slot.
; Keeping that goret carrier live across the following statepoint must not force
; a dynamic call frame either.
;
; MIR-LABEL: name: indirect_scalar_result_loop
; MIR-NOT: hasPushSequences: true
; MIR: bb.1.loop:
; MIR: ADJCALLSTACKDOWN64
; MIR-NOT: PUSH64
; MIR: STATEPOINT
; MIR: ADJCALLSTACKUP64
; MIR: STATEPOINT
;
; ASM-LABEL: indirect_scalar_result_loop:
; ASM: subq
; ASM: [[SCALAR_LOOP:.LBB[0-9]+_[0-9]+]]:
; ASM-NOT: subq
; ASM-NOT: pushq
; ASM: callq
; ASM-NOT: addq
; ASM: callq
define goabiinternal i64 @indirect_scalar_result_loop(
    ptr %callee, ptr %base, i64 %length, i64 %capacity, i64 %iterations)
    gc "statepoint-example" {
entry:
  %argument = alloca %slice, align 8
  %result = alloca %scalar.result, align 8
  br label %loop

loop:
  %index = phi i64 [ 0, %entry ], [ %next, %loop.cont ]
  store ptr %base, ptr %argument, align 8
  %argument.length = getelementptr inbounds i8, ptr %argument, i64 8
  store i64 %length, ptr %argument.length, align 8
  %argument.capacity = getelementptr inbounds i8, ptr %argument, i64 16
  store i64 %capacity, ptr %argument.capacity, align 8
  %call = call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 5, i32 0, ptr elementtype(void (ptr, ptr)) %callee,
          i32 2, i32 0,
          ptr byval(%slice) align 8 %argument,
          ptr goret(%scalar.result) align 8 "goretindex"="0" %result,
          i32 0, i32 0)
      [ "gc-live"(ptr %argument, ptr %result) ]
  br label %call.cont

call.cont:
  %low = load i64, ptr %result, align 8
  %result.high = getelementptr inbounds i8, ptr %result, i64 8
  %high = load i64, ptr %result.high, align 8
  %after = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 6, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr %argument, ptr %result) ]
  br label %loop.cont

loop.cont:
  %sum = add i64 %low, %high
  %next = add nuw i64 %index, 1
  %more = icmp ult i64 %next, %iterations
  br i1 %more, label %loop, label %exit

exit:
  %answer = phi i64 [ %sum, %loop.cont ]
  ret i64 %answer
}

; A pointer-bearing aggregate result uses the same fixed outgoing area while
; the pointer value itself remains an ordinary gc-live root and is consumed
; through gc.relocate at the following statepoint.
;
; MIR-LABEL: name: indirect_pointer_result_loop
; MIR-NOT: hasPushSequences: true
; MIR: bb.1.loop:
; MIR: ADJCALLSTACKDOWN64
; MIR-NOT: PUSH64
; MIR: STATEPOINT
; MIR: ADJCALLSTACKUP64
; MIR: STATEPOINT
;
; ASM-LABEL: indirect_pointer_result_loop:
; ASM: subq
; ASM: [[POINTER_LOOP:.LBB[0-9]+_[0-9]+]]:
; ASM-NOT: subq
; ASM-NOT: pushq
; ASM: callq
; ASM-NOT: addq
; ASM: callq
define goabiinternal ptr addrspace(1) @indirect_pointer_result_loop(
    ptr %callee, ptr %base, i64 %length, i64 %capacity, i64 %iterations)
    gc "statepoint-example" {
entry:
  %argument = alloca %slice, align 8
  %result = alloca %pointer.result, align 8
  br label %loop

loop:
  %index = phi i64 [ 0, %entry ], [ %next, %loop.cont ]
  store ptr %base, ptr %argument, align 8
  %argument.length = getelementptr inbounds i8, ptr %argument, i64 8
  store i64 %length, ptr %argument.length, align 8
  %argument.capacity = getelementptr inbounds i8, ptr %argument, i64 16
  store i64 %capacity, ptr %argument.capacity, align 8
  %call = call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 3, i32 0, ptr elementtype(void (ptr, ptr)) %callee,
          i32 2, i32 0,
          ptr byval(%slice) align 8 %argument,
          ptr goret(%pointer.result) align 8 "goretindex"="0" %result,
          i32 0, i32 0)
      [ "gc-live"(ptr %argument, ptr %result) ]
  br label %call.cont

call.cont:
  %pointer = load ptr addrspace(1), ptr %result, align 8
  %after = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 4, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %pointer, ptr %argument, ptr %result) ]
  br label %loop.cont

loop.cont:
  %relocated = call coldcc ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(
      token %after, i32 0, i32 0)
  %next = add nuw i64 %index, 1
  %more = icmp ult i64 %next, %iterations
  br i1 %more, label %loop, label %exit

exit:
  ret ptr addrspace(1) %relocated
}
