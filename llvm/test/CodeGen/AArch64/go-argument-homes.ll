; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O0 -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O0 < %s | \
; RUN:   FileCheck %s --check-prefix=ASM

%pair = type { i64, i64 }

; Exhaust AArch64's integer register budget so the pair arrives in one typed
; stack home at the target's Go stack bias. The carrier is bound directly to
; that home and needs no frontend alloca or copy.
define goabiinternal ptr @aarch64_stack_pair_home(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4,
    i64 %a5, i64 %a6, i64 %a7, i64 %a8, i64 %a9,
    i64 %a10, i64 %a11, i64 %a12, i64 %a13, i64 %a14,
    ptr byval(%pair) align 8 %value.home) {
entry:
  ret ptr %value.home
}

; MIR-LABEL: name: aarch64_stack_pair_home
; MIR: fixedStack:
; MIR-NEXT: - { id: 0, type: default, offset: 8, size: 16
; MIR-NEXT: isImmutable: false, isAliased: true
; MIR-NOT: STRXui {{.*}}%fixed-stack.0
; MIR: ADDXri %fixed-stack.0
; ASM-LABEL: aarch64_stack_pair_home:
; ASM: add x0, sp, #8
