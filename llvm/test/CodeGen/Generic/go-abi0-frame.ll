; REQUIRES: x86-registered-target, aarch64-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O0 -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=A64
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 < %s | \
; RUN:   FileCheck %s --check-prefix=X86-ASM
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O0 < %s | \
; RUN:   FileCheck %s --check-prefix=A64-ASM

declare ptr @llvm.go.abi0.frame()

@frame_sink = external global ptr

; The intrinsic denotes one mutable, aliased object spanning the two arguments
; and one result slot. It deliberately overlaps the per-value fixed objects.
define goabi0 void @abi0_frame(ptr byval(i64) align 8 %a,
                              ptr byval(i64) align 8 %b,
                              ptr goret(ptr) align 8 "goretindex"="0" %result) noinline {
entry:
  %frame = call ptr @llvm.go.abi0.frame()
  store ptr %frame, ptr %result, align 8
  ret void
}

; X86-LABEL: name: abi0_frame
; X86: fixedStack:
; X86: type: default, offset: 0, size: 24
; X86-NEXT: isImmutable: false, isAliased: true
; X86: LEA64r %fixed-stack.{{[0-9]+}}
; A64-LABEL: name: abi0_frame
; A64: fixedStack:
; A64: type: default, offset: 8, size: 24
; A64-NEXT: isImmutable: false, isAliased: true
; A64: ADDXri %fixed-stack.{{[0-9]+}}
; X86-ASM-LABEL: abi0_frame:
; X86-ASM: leaq 24(%rsp), [[RESULT:%r[a-z0-9]+]]
; X86-ASM-NEXT: leaq 8(%rsp), [[FRAME:%r[a-z0-9]+]]
; X86-ASM-NEXT: movq [[FRAME]], ([[RESULT]])
; A64-ASM-LABEL: abi0_frame:
; A64-ASM: add x8, sp, #8
; A64-ASM-NEXT: str x8, [sp, #24]

; Zero-sized Go arguments and results remain part of the logical ABI layout,
; but consume no registers or stack bytes. The intrinsic still denotes the
; present frame base, represented by a zero-sized fixed address anchor.
define goabi0 void @abi0_zero_arg([0 x i8] %arg) noinline {
entry:
  %frame = call ptr @llvm.go.abi0.frame()
  store volatile ptr %frame, ptr @frame_sink
  ret void
}

define goabi0 [0 x i8] @abi0_zero_result() noinline {
entry:
  %frame = call ptr @llvm.go.abi0.frame()
  store volatile ptr %frame, ptr @frame_sink
  ret [0 x i8] zeroinitializer
}

; X86-LABEL: name: abi0_zero_arg
; X86: fixedStack:
; X86: type: default, offset: 0, size: 0
; X86-NEXT: isImmutable: false, isAliased: true
; X86: LEA64r %fixed-stack.{{[0-9]+}}
; X86-LABEL: name: abi0_zero_result
; X86: fixedStack:
; X86: type: default, offset: 0, size: 0
; X86-NEXT: isImmutable: false, isAliased: true
; X86: LEA64r %fixed-stack.{{[0-9]+}}
; A64-LABEL: name: abi0_zero_arg
; A64: fixedStack:
; A64: type: default, offset: 8, size: 0
; A64-NEXT: isImmutable: false, isAliased: true
; A64: ADDXri %fixed-stack.{{[0-9]+}}
; A64-LABEL: name: abi0_zero_result
; A64: fixedStack:
; A64: type: default, offset: 8, size: 0
; A64-NEXT: isImmutable: false, isAliased: true
; A64: ADDXri %fixed-stack.{{[0-9]+}}
; X86-ASM-LABEL: abi0_zero_arg:
; X86-ASM: leaq 8(%rsp), [[X86_ZERO_ARG:%r[a-z0-9]+]]
; X86-ASM: movq [[X86_ZERO_ARG]], ({{%r[a-z0-9]+}})
; X86-ASM-LABEL: abi0_zero_result:
; X86-ASM: leaq 8(%rsp), [[X86_ZERO_RESULT:%r[a-z0-9]+]]
; X86-ASM: movq [[X86_ZERO_RESULT]], ({{%r[a-z0-9]+}})
; A64-ASM-LABEL: abi0_zero_arg:
; A64-ASM: add [[A64_ZERO_ARG:x[0-9]+]], sp, #8
; A64-ASM: str [[A64_ZERO_ARG]], [{{x[0-9]+}}]
; A64-ASM-LABEL: abi0_zero_result:
; A64-ASM: add [[A64_ZERO_RESULT:x[0-9]+]], sp, #8
; A64-ASM: str [[A64_ZERO_RESULT]], [{{x[0-9]+}}]
