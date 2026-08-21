; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 -verify-machineinstrs -o - %s | FileCheck %s --check-prefixes=ASM,ASM-O0
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O2 -verify-machineinstrs -o - %s | FileCheck %s --check-prefixes=ASM,ASM-O2
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 -verify-machineinstrs \
; RUN:   -stop-before=x86-go-abi -o - %s | FileCheck %s --check-prefix=PRE
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 -verify-machineinstrs \
; RUN:   -stop-after=x86-go-abi -o - %s | FileCheck %s --check-prefix=LATE
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main \
; RUN:   -verify-machineinstrs -filetype=obj -o %t.o %s
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | \
; RUN:   FileCheck %s --check-prefix=OBJ

declare goabiinternal void @internal_callee()
declare goabi0 void @"abi0_callee<ABI0>"()
declare goabi0 void @"abi0_result<ABI0>"(
    ptr goret(i64) align 8 "goretindex"="0")
declare i64 @llvm.read_register.i64(metadata)

define goabi0 void @"abi0_to_internal<ABI0>"() "go-nosplit" {
; PRE-LABEL: name: 'abi0_to_internal<ABI0>'
; PRE-NOT: XORPSrr
; PRE: CALL64pcrel32 {{.*}}@internal_callee
; LATE-LABEL: name: 'abi0_to_internal<ABI0>'
; LATE: $xmm15 = XORPSrr
; LATE-NEXT: $r14 = MOV64rm {{.*}}runtime.tlsg
; LATE-NEXT: CALL64pcrel32 {{.*}}@internal_callee
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
; LATE-LABEL: name: internal_to_abi0
; LATE: CALL64pcrel32 {{.*}}@"abi0_callee<ABI0>"
; LATE-NEXT: $xmm15 = XORPSrr
; LATE-NEXT: $r14 = MOV64rm {{.*}}runtime.tlsg
; ASM-LABEL: internal_to_abi0:
; ASM-NOT: pushq %r14
; ASM-NOT: movaps %xmm15,
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

define goabiinternal i64 @internal_snapshot_g_across_abi0() "go-nosplit" {
; ABI0 may change R14. Preserve the value observed before the call separately
; while the late repair reloads the current g into R14 after the call.
; PRE-LABEL: name: internal_snapshot_g_across_abi0
; PRE: CALL64pcrel32 {{.*}}@"abi0_callee<ABI0>", csr_64_goabi0{{.*}}implicit-def $r14, implicit-def $xmm15
; ASM-LABEL: internal_snapshot_g_across_abi0:
; ASM-O0: movq %r14, %rax
; ASM-O0-NEXT: movq %rax, [[OLDG:[0-9]*]](%rsp)
; ASM-O2: movq %r14, [[OLDG:%r[a-z0-9]+]]
; ASM: callq "abi0_callee<ABI0>"
; ASM-NEXT: xorps %xmm15, %xmm15
; ASM-NEXT: movq %fs:runtime.tlsg@TPOFF, %r14
; ASM-O0: movq [[OLDG]](%rsp), %rax
; ASM-O2: movq [[OLDG]], %rax
; ASM: retq
entry:
  %oldg = call i64 @llvm.read_register.i64(metadata !0)
  call goabi0 void @"abi0_callee<ABI0>"()
  ret i64 %oldg
}

define goabiinternal void @internal_statepoint_to_abi0()
    "go-nosplit" gc "statepoint-example" {
; ASM-LABEL: internal_statepoint_to_abi0:
; ASM-NOT: pushq %r14
; ASM-NOT: movaps %xmm15,
; ASM: callq "abi0_callee<ABI0>"
; A statepoint label records the return PC between the call and the repair.
; ASM: xorps %xmm15, %xmm15
; ASM-NEXT: movq %fs:runtime.tlsg@TPOFF, %r14
; ASM-NOT: movaps {{.*}}, %xmm15
; ASM-NOT: popq %r14
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
; The late machine pass repairs the reserved state immediately after the
; statepoint call. The ABI0 result remains in the caller frame and is loaded
; afterwards.
; ASM-LABEL: internal_statepoint_result_from_abi0:
; ASM: callq "abi0_result<ABI0>"
; ASM: xorps %xmm15, %xmm15
; ASM-NEXT: movq %fs:runtime.tlsg@TPOFF, %r14
; ASM-O0-NEXT: movq %rsp, [[RESULT_BASE:%r[a-z0-9]+]]
; ASM-O0-NEXT: movq ([[RESULT_BASE]]), %rax
; ASM-O2-NEXT: movq (%rsp), %rax
; ASM: retq
entry:
  %result.addr = alloca i64, align 8
  %token = call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 0, i32 0,
          ptr elementtype(void (ptr)) @"abi0_result<ABI0>",
          i32 1, i32 0,
          ptr goret(i64) align 8 "goretindex"="0" %result.addr,
          i32 0, i32 0)
  %result = load i64, ptr %result.addr, align 8
  ret i64 %result
}

define goabiinternal i64 @internal_statepoint_snapshot_g_across_abi0()
    "go-nosplit" gc "statepoint-example" {
; PRE-LABEL: name: internal_statepoint_snapshot_g_across_abi0
; PRE: STATEPOINT {{.*}}@"abi0_callee<ABI0>"{{.*}}csr_64_goabi0{{.*}}implicit-def $r14, implicit-def $xmm15
; ASM-LABEL: internal_statepoint_snapshot_g_across_abi0:
; ASM-O0: movq %r14, %rax
; ASM-O0-NEXT: movq %rax, [[SP_OLDG:[0-9]*]](%rsp)
; ASM-O2: movq %r14, [[SP_OLDG:%r[a-z0-9]+]]
; ASM: callq "abi0_callee<ABI0>"
; ASM: xorps %xmm15, %xmm15
; ASM-NEXT: movq %fs:runtime.tlsg@TPOFF, %r14
; ASM-O0: movq [[SP_OLDG]](%rsp), %rax
; ASM-O2: movq [[SP_OLDG]], %rax
; ASM: retq
entry:
  %oldg = call i64 @llvm.read_register.i64(metadata !0)
  call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 0, i32 0, ptr elementtype(void ()) @"abi0_callee<ABI0>",
          i32 0, i32 0, i32 0, i32 0)
  ret i64 %oldg
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

!0 = !{!"r14"}

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
