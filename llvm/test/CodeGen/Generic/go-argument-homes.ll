; REQUIRES: x86-registered-target, aarch64-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O0 -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=A64
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 < %s | \
; RUN:   FileCheck %s --check-prefix=X86-ASM
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O0 < %s | \
; RUN:   FileCheck %s --check-prefix=A64-ASM

%padded = type { i8, i64 }
%pair = type { i64, i64 }

; A register argument's canonical alloca is remapped to its ABI spill home and
; the IR store initializes that home.
define goabiinternal ptr @reg_scalar_home(i64 %value) {
entry:
  %home = alloca i64, align 8
  store i64 %value, ptr %home, align 8
  ret ptr %home
}

; X86-LABEL: name: reg_scalar_home
; X86: fixedStack:
; X86-NEXT: - { id: 0, type: spill-slot, offset: 0, size: 8
; X86: MOV64mr %fixed-stack.0{{.*}}%ir.home
; X86: LEA64r %fixed-stack.0
; A64-LABEL: name: reg_scalar_home
; A64: fixedStack:
; A64-NEXT: - { id: 0, type: spill-slot, offset: 8, size: 8
; A64: STRXui {{.*}}%fixed-stack.0{{.*}}%ir.home
; A64: ADDXri %fixed-stack.0
; X86-ASM-LABEL: reg_scalar_home:
; X86-ASM: movq %rax, 8(%rsp)
; X86-ASM-NEXT: leaq 8(%rsp), %rax
; A64-ASM-LABEL: reg_scalar_home:
; A64-ASM: str x0, [sp, #8]
; A64-ASM-NEXT: add x0, sp, #8

; A split, padded register argument has one logical home, not one fixed object
; per ABI piece.
define goabiinternal ptr @reg_padded_home(%padded %value) {
entry:
  %home = alloca %padded, align 8
  store %padded %value, ptr %home, align 8
  ret ptr %home
}

; X86-LABEL: name: reg_padded_home
; X86: fixedStack:
; X86-NEXT: - { id: 0, type: spill-slot, offset: 0, size: 16
; X86: MOV8mr %fixed-stack.0{{.*}}%ir.home
; X86: MOV64mr %fixed-stack.0{{.*}}8{{.*}}%ir.home + 8
; X86: LEA64r %fixed-stack.0
; A64-LABEL: name: reg_padded_home
; A64: fixedStack:
; A64-NEXT: - { id: 0, type: spill-slot, offset: 8, size: 16
; A64-DAG: STRBBui {{.*}}%fixed-stack.0{{.*}}%ir.home
; A64-DAG: STRXui {{.*}}%fixed-stack.0{{.*}}1{{.*}}%ir.home + 8
; A64: ADDXri %fixed-stack.0
; X86-ASM-LABEL: reg_padded_home:
; X86-ASM-DAG: movb %al, 8(%rsp)
; X86-ASM-DAG: movq %rbx, 16(%rsp)
; X86-ASM: leaq 8(%rsp), %rax
; A64-ASM-LABEL: reg_padded_home:
; A64-ASM-DAG: strb w0, [sp, #8]
; A64-ASM-DAG: str x1, [sp, #16]
; A64-ASM: add x0, sp, #8

; Exhaust X86's integer register budget so the pair arrives in one stack home.
define goabiinternal ptr @x86_stack_pair_home(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4,
    i64 %a5, i64 %a6, i64 %a7, i64 %a8, %pair %value) {
entry:
  %home = alloca %pair, align 8
  store %pair %value, ptr %home, align 8
  ret ptr %home
}

; X86-LABEL: name: x86_stack_pair_home
; X86: fixedStack:
; X86-NEXT: - { id: 0, type: default, offset: 0, size: 16
; X86-NEXT: isImmutable: false, isAliased: true
; X86: MOV64rm %fixed-stack.0
; X86: MOV64rm %fixed-stack.0{{.*}}8
; X86-NOT: MOV64mr %fixed-stack.0
; X86: LEA64r %fixed-stack.0
; X86-ASM-LABEL: x86_stack_pair_home:
; X86-ASM-DAG: movq 8(%rsp), %rax
; X86-ASM-DAG: movq 16(%rsp), %rax
; X86-ASM: leaq 8(%rsp), %rax

; Exhaust AArch64's integer register budget so the pair arrives in one stack
; home at the target's Go stack bias.
define goabiinternal ptr @aarch64_stack_pair_home(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4,
    i64 %a5, i64 %a6, i64 %a7, i64 %a8, i64 %a9,
    i64 %a10, i64 %a11, i64 %a12, i64 %a13, i64 %a14,
    %pair %value) {
entry:
  %home = alloca %pair, align 8
  store %pair %value, ptr %home, align 8
  ret ptr %home
}

; A64-LABEL: name: aarch64_stack_pair_home
; A64: fixedStack:
; A64-NEXT: - { id: 0, type: default, offset: 8, size: 16
; A64-NEXT: isImmutable: false, isAliased: true
; A64-NOT: STRXui {{.*}}%fixed-stack.0
; A64: ADDXri %fixed-stack.0
; A64-ASM-LABEL: aarch64_stack_pair_home:
; A64-ASM: add x0, sp, #8
