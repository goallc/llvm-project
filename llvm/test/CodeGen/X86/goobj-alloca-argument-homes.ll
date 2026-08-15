; REQUIRES: x86-registered-target, aarch64-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=X86-MIR
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=A64-MIR

%aggregate = type { ptr, i64, ptr }
%stack_aggregate = type [2 x ptr]

declare goabiinternal void @safepoint()
declare void @llvm.lifetime.start.p0(i64 immarg, ptr captures(none))

; The alloca is the canonical home of a register argument. Its direct gc-live
; base makes its pointer contents active at the callsite, so bit zero belongs
; to ArgsPointerMaps rather than LocalsPointerMaps.
define goabiinternal ptr @active_scalar(ptr %value) gc "statepoint-example" {
entry:
  %home = alloca ptr, align 8
  call void @llvm.lifetime.start.p0(i64 8, ptr %home)
  store ptr %value, ptr %home, align 8
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "deopt"(i64 1195461697, i64 15, i64 1,
                  i64 1095520067, i64 11, ptr %home, i64 0, i64 8,
                  i64 8, i64 8, i64 1, i64 64, i64 1, i64 1,
                  i64 1095519299, i64 15),
        "gc-live"(ptr %home) ]
  %result = load ptr, ptr %home, align 8
  ret ptr %result
}

; X86-MIR-LABEL: name: active_scalar
; X86-MIR: fixedStack:
; X86-MIR-NEXT: - { id: 0, type: spill-slot, offset: 0, size: 8
; X86-MIR: MOV64mr %fixed-stack.0{{.*}}%ir.home
; X86-MIR: STATEPOINT{{.*}}%fixed-stack.0
; A64-MIR-LABEL: name: active_scalar
; A64-MIR: fixedStack:
; A64-MIR-NEXT: - { id: 0, type: spill-slot, offset: 8, size: 8
; A64-MIR: STRXui {{.*}}%fixed-stack.0{{.*}}%ir.home
; A64-MIR: STATEPOINT{{.*}}%fixed-stack.0

; The aggregate is split into multiple ABI pieces but has one complete home.
; Its alloca base is not directly live at the ordinary statepoint, so the
; function needs one StackObject at non-negative offset zero relative to argp.
define goabiinternal void @inactive_aggregate(%aggregate %value)
    gc "statepoint-example" {
entry:
  %home = alloca %aggregate, align 8
  call void @llvm.lifetime.start.p0(i64 24, ptr %home)
  store %aggregate %value, ptr %home, align 8
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 2, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "deopt"(i64 1195461697, i64 15, i64 1,
                  i64 1095520067, i64 11, ptr %home, i64 0, i64 24,
                  i64 8, i64 8, i64 3, i64 64, i64 1, i64 5,
                  i64 1095519299, i64 15) ]
  ret void
}

; X86-MIR-LABEL: name: inactive_aggregate
; X86-MIR: fixedStack:
; X86-MIR-NEXT: - { id: 0, type: spill-slot, offset: 0, size: 24
; X86-MIR: STATEPOINT{{.*}}%fixed-stack.0
; A64-MIR-LABEL: name: inactive_aggregate
; A64-MIR: fixedStack:
; A64-MIR-NEXT: - { id: 0, type: spill-slot, offset: 8, size: 24
; A64-MIR: STATEPOINT{{.*}}%fixed-stack.0

; An aggregate assigned wholly to the stack reuses its caller-populated slot;
; the lifetime marker must not make SelectionDAG allocate and copy a local.
define goabiinternal void @inactive_stack_aggregate(
    ptr preallocated(%stack_aggregate) align 8 %value.home)
    gc "statepoint-example" {
entry:
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 3, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "deopt"(i64 1195461697, i64 15, i64 1,
                  i64 1095520067, i64 11, ptr %value.home, i64 0, i64 16,
                  i64 8, i64 8, i64 2, i64 64, i64 1, i64 3,
                  i64 1095519299, i64 15) ]
  ret void
}

; X86-MIR-LABEL: name: inactive_stack_aggregate
; X86-MIR: fixedStack:
; X86-MIR: - { id: [[X86_STACK_HOME:[0-9]+]], type: default, offset: 0, size: 16
; X86-MIR: stack: []
; X86-MIR: STATEPOINT{{.*}}%fixed-stack.[[X86_STACK_HOME]]
; A64-MIR-LABEL: name: inactive_stack_aggregate
; A64-MIR: fixedStack:
; A64-MIR: - { id: [[A64_STACK_HOME:[0-9]+]], type: default, offset: 8, size: 16
; A64-MIR: stack: []
; A64-MIR: STATEPOINT{{.*}}%fixed-stack.[[A64_STACK_HOME]]

declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
