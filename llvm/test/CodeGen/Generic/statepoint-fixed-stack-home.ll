; REQUIRES: aarch64-registered-target
; REQUIRES: x86-registered-target
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=AARCH64-MIR
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=X86-MIR
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -verify-machineinstrs < %s \
; RUN:   | FileCheck %s --check-prefix=AARCH64-ASM
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs < %s \
; RUN:   | FileCheck %s --check-prefix=X86-ASM

%roots = type { i64, ptr addrspace(1), ptr addrspace(1) }
%pair = type { ptr addrspace(1), ptr addrspace(1) }

declare void @safepoint()
declare void @mutate(ptr)

define %pair @two_subslots(ptr addrspace(1) %p, ptr addrspace(1) %q)
    gc "statepoint-example" {
entry:
  %roots = alloca %roots, align 8
  %p.addr = getelementptr inbounds %roots, ptr %roots, i32 0, i32 1
  %q.addr = getelementptr inbounds %roots, ptr %roots, i32 0, i32 2
  store ptr addrspace(1) %p, ptr %p.addr, align 8
  store ptr addrspace(1) %q, ptr %q.addr, align 8
  %p.live = load volatile ptr addrspace(1), ptr %p.addr, align 8,
      !llvm.statepoint.fixed_stack_home !0
  %q.live = load volatile ptr addrspace(1), ptr %q.addr, align 8,
      !llvm.statepoint.fixed_stack_home !0
  %token = call token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %p.live,
                  ptr addrspace(1) %q.live) ]
  %p.relocated = call ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  %q.relocated = call ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(token %token, i32 1, i32 1)
  store ptr addrspace(1) %p.relocated, ptr %p.addr, align 8
  store ptr addrspace(1) %q.relocated, ptr %q.addr, align 8
  %result.0 = insertvalue %pair poison, ptr addrspace(1) %p.relocated, 0
  %result.1 = insertvalue %pair %result.0, ptr addrspace(1) %q.relocated, 1
  ret %pair %result.1
}

; The call receives the field address and may replace its pointer value. The
; relocate must reload that post-call value from the exact home; lowering must
; not spill the stale pre-call load to another slot or back over the field.
define ptr addrspace(1) @callee_mutates_home(ptr addrspace(1) %p)
    gc "statepoint-example" {
entry:
  %roots = alloca %roots, align 8
  %p.addr = getelementptr inbounds %roots, ptr %roots, i32 0, i32 1
  store ptr addrspace(1) %p, ptr %p.addr, align 8
  %p.live = load volatile ptr addrspace(1), ptr %p.addr, align 8,
      !llvm.statepoint.fixed_stack_home !0
  %token = call token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 2, i32 0, ptr elementtype(void (ptr)) @mutate,
          i32 1, i32 0, ptr %p.addr, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %p.live) ]
  %p.relocated = call ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  ret ptr addrspace(1) %p.relocated
}

declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
    token, i32 immarg, i32 immarg)

!0 = !{}

; AARCH64-MIR-LABEL: name: two_subslots
; AARCH64-MIR: stack:
; AARCH64-MIR: - { id: 0, name: roots, type: default, offset: 0, size: 24,
; AARCH64-MIR-NOT: id: 1
; AARCH64-MIR: STATEPOINT 1,
; AARCH64-MIR-SAME: 2, 2, 1, 8, %stack.0{{[^, ]*}}, 16,
; AARCH64-MIR-SAME: 1, 8, %stack.0{{[^, ]*}}, 8,
; AARCH64-MIR-SAME: (volatile load store (s64) on %stack.0{{[^ ]*}} + 16),
; AARCH64-MIR-SAME: (volatile load store (s64) on %stack.0{{[^ ]*}} + 8)
; AARCH64-MIR-DAG: LDRXui %stack.0{{[^, ]*}}, 1
; AARCH64-MIR-DAG: LDRXui %stack.0{{[^, ]*}}, 2

; X86-MIR-LABEL: name: two_subslots
; X86-MIR: stack:
; X86-MIR: - { id: 0, name: roots, type: default, offset: 0, size: 24,
; X86-MIR-NOT: id: 1
; X86-MIR: STATEPOINT 1,
; X86-MIR-SAME: 2, 2, 1, 8, %stack.0{{[^, ]*}}, 16,
; X86-MIR-SAME: 1, 8, %stack.0{{[^, ]*}}, 8,
; X86-MIR-SAME: (volatile load store (s64) on %stack.0{{[^ ]*}} + 16),
; X86-MIR-SAME: (volatile load store (s64) on %stack.0{{[^ ]*}} + 8)
; X86-MIR-DAG: MOV64rm %stack.0{{[^, ]*}}, 1, $noreg, 8,
; X86-MIR-DAG: MOV64rm %stack.0{{[^, ]*}}, 1, $noreg, 16,

; AARCH64-ASM-LABEL: callee_mutates_home:
; AARCH64-ASM: str x0, [sp, #[[AARCH64_HOME:[0-9]+]]]
; AARCH64-ASM: bl mutate
; AARCH64-ASM: ldr x0, [sp, #[[AARCH64_HOME]]]

; X86-ASM-LABEL: callee_mutates_home:
; X86-ASM: movq %rdi, [[X86_HOME:[0-9]+]](%rsp)
; X86-ASM: callq mutate@PLT
; X86-ASM: movq [[X86_HOME]](%rsp), %rax
