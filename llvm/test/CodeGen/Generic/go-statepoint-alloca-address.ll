; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog -o - %s | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog -o - %s | FileCheck %s --check-prefix=AARCH64

; A Go stack alloca in gc-live describes a frame address, not a scalar pointer
; which needs a spill slot. With a gc.relocate, the relocate must recompute the
; FrameIndex address after the statepoint so it observes a possibly grown
; stack. Without a gc.relocate, a later direct use of the original alloca must
; likewise select the original FrameIndex instead of a cached pre-call address.

declare goabiinternal void @safepoint()
declare goabiinternal void @observe(ptr addrspace(1))

define goabiinternal void @first_class_alloca_address()
 gc "statepoint-example" {
; X86-LABEL: name: first_class_alloca_address
; X86:       STATEPOINT 1,
; X86-NEXT:  $rax = LEA64r
; X86-NEXT:  CALL64pcrel32 @observe
; X86-NOT:   MOV64m
;
; AARCH64-LABEL: name: first_class_alloca_address
; AARCH64:       STATEPOINT 1,
; AARCH64-NEXT:  $x0 = ADDXri $sp,
; AARCH64-NEXT:  BL @observe
; AARCH64-NOT:   LDRXui
; AARCH64-NOT:   STRXui
entry:
  %slot = alloca ptr, align 8, addrspace(1)
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0,
          ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %slot) ]
  %relocated = call coldcc ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  %address = getelementptr inbounds i8, ptr addrspace(1) %relocated, i64 0
  call goabiinternal void @observe(ptr addrspace(1) %address)
  ret void
}

define goabiinternal void @first_class_alloca_address_without_relocate()
 gc "statepoint-example" {
; X86-LABEL: name: first_class_alloca_address_without_relocate
; X86:       STATEPOINT 2,
; X86-NEXT:  $rax = LEA64r
; X86-NEXT:  CALL64pcrel32 @observe
; X86-NOT:   MOV64m
;
; AARCH64-LABEL: name: first_class_alloca_address_without_relocate
; AARCH64:       STATEPOINT 2,
; AARCH64-NEXT:  $x0 = ADDXri $sp,
; AARCH64-NEXT:  BL @observe
; AARCH64-NOT:   LDRXui
; AARCH64-NOT:   STRXui
entry:
  %slot = alloca ptr, align 8, addrspace(1)
  call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 2, i32 0,
          ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %slot) ]
  %address = getelementptr inbounds i8, ptr addrspace(1) %slot, i64 0
  call goabiinternal void @observe(ptr addrspace(1) %address)
  ret void
}

declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
    token, i32 immarg, i32 immarg)
