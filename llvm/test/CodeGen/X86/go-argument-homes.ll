; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O0 < %s | \
; RUN:   FileCheck %s --check-prefix=ASM

%pair = type { i64, i64 }

; Exhaust X86's integer register budget so the pair arrives in one typed stack
; home. The preallocated carrier is the home itself; no frontend alloca or copy
; exists.
define goabiinternal ptr @x86_stack_pair_home(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4,
    i64 %a5, i64 %a6, i64 %a7, i64 %a8,
    ptr preallocated(%pair) align 8 %value.home) {
entry:
  ret ptr %value.home
}

; MIR-LABEL: name: x86_stack_pair_home
; MIR: fixedStack:
; MIR-NEXT: - { id: 0, type: default, offset: 0, size: 16
; MIR-NEXT: isImmutable: false, isAliased: true
; MIR-NOT: MOV64mr %fixed-stack.0
; MIR: LEA64r %fixed-stack.0
; ASM-LABEL: x86_stack_pair_home:
; ASM: leaq 8(%rsp), %rax
