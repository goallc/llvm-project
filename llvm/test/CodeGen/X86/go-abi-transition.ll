; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 -verify-machineinstrs -o - %s | FileCheck %s --check-prefixes=ASM,ASM-O0
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O2 -verify-machineinstrs -o - %s | FileCheck %s --check-prefixes=ASM,ASM-O2
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main \
; RUN:   -verify-machineinstrs -filetype=obj -o %t.o %s
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | \
; RUN:   FileCheck %s --check-prefix=OBJ

declare goabiinternal void @internal_callee()
declare goabi0 void @"abi0_callee<ABI0>"()
declare goabi0 i64 @"abi0_result<ABI0>"()

define goabi0 void @"abi0_to_internal<ABI0>"() "go-nosplit" {
; ASM-LABEL: "abi0_to_internal<ABI0>":
; ASM-NOT: pushq %r14
; ASM-NOT: movaps %xmm15
; ASM: xorps %xmm15, %xmm15
; ASM-NEXT: movq %fs:runtime.tlsg@TPOFF, %r14
; ASM-NEXT: callq internal_callee
; ASM-NOT: movaps {{.*}}, %xmm15
; ASM-NOT: popq %r14
; ASM: retq
entry:
  call goabiinternal void @internal_callee()
  ret void
}

define goabiinternal void @internal_to_abi0() "go-nosplit" {
; ASM-LABEL: internal_to_abi0:
; ASM: callq "abi0_callee<ABI0>"
; ASM-NEXT: xorps %xmm15, %xmm15
; ASM-NEXT: movq %fs:runtime.tlsg@TPOFF, %r14
; ASM-NOT: movaps {{.*}}, %xmm15
; ASM-NOT: popq %r14
; ASM: retq
entry:
  call goabi0 void @"abi0_callee<ABI0>"()
  ret void
}

define goabiinternal void @internal_statepoint_to_abi0()
    "go-nosplit" gc "statepoint-example" {
; ASM-LABEL: internal_statepoint_to_abi0:
; ASM: callq "abi0_callee<ABI0>"
; A statepoint label records the return PC between the call and the repair.
; ASM: xorps %xmm15, %xmm15
; ASM-NEXT: movq %fs:runtime.tlsg@TPOFF, %r14
; ASM: retq
entry:
  call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 0, i32 0, ptr elementtype(void ()) @"abi0_callee<ABI0>",
          i32 0, i32 0, i32 0, i32 0)
  ret void
}

define goabiinternal i64 @internal_statepoint_result_from_abi0()
    "go-nosplit" gc "statepoint-example" {
; ABI0 returns through the caller frame. Complete that result load before the
; statepoint's final ABIInternal repair, without creating a chain/glue cycle.
; ASM-LABEL: internal_statepoint_result_from_abi0:
; ASM: callq "abi0_result<ABI0>"
; ASM-O0: movq %rsp, [[RESULT_BASE:%r[a-z0-9]+]]
; ASM-O0-NEXT: movq ([[RESULT_BASE]]), %rax
; ASM-O2: movq (%rsp), %rax
; ASM: xorps %xmm15, %xmm15
; ASM-NEXT: movq %fs:runtime.tlsg@TPOFF, %r14
; ASM: retq
entry:
  %token = call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 0, i32 0, ptr elementtype(i64 ()) @"abi0_result<ABI0>",
          i32 0, i32 0, i32 0, i32 0)
  %result = call i64 @llvm.experimental.gc.result.i64(token %token)
  ret i64 %result
}

define goabiinternal i8 @go_local_is_sp_relative() "go-nosplit"
    "frame-pointer"="non-leaf" {
; Go context restoration can restore SP while clearing BP. Keep local slots
; usable across that non-local resume while retaining the frame-pointer chain.
; ASM-LABEL: go_local_is_sp_relative:
; ASM: pushq %rbp
; ASM: movq %rsp, %rbp
; ASM: movb $7, {{[0-9]+}}(%rsp)
; ASM: callq internal_callee
; ASM: mov{{(b|zbl)}} {{[0-9]+}}(%rsp), %{{(al|eax)}}
; ASM: popq %rbp
; ASM: retq
entry:
  %local = alloca i8, align 1
  store volatile i8 7, ptr %local, align 1
  call goabiinternal void @internal_callee()
  %value = load volatile i8, ptr %local, align 1
  ret i8 %value
}

declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare i64 @llvm.experimental.gc.result.i64(token)

; Each repair has one symbol-free R_TLS_LE relocation, matching native x86 Go
; objects. Calls retain their ABI-specific named targets.
; OBJ-NOT: nonpkgref {{[0-9]+}}: runtime.tlsg
; OBJ: reloc {{.*}} type=15 {{.*}} kind=unknown pkg=0 sym=0
; OBJ: reloc {{.*}} kind=R_CALL
; OBJ: reloc {{.*}} kind=R_CALL
; OBJ: reloc {{.*}} type=15 {{.*}} kind=unknown pkg=0 sym=0
; OBJ: reloc {{.*}} kind=R_CALL
; OBJ: reloc {{.*}} type=15 {{.*}} kind=unknown pkg=0 sym=0
; OBJ: reloc {{.*}} kind=R_CALL
; OBJ: reloc {{.*}} type=15 {{.*}} kind=unknown pkg=0 sym=0
