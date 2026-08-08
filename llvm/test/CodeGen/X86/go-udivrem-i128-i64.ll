; RUN: llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=x86_64-pc-windows-msvc -verify-machineinstrs < %s | FileCheck %s --check-prefix=WIN
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=MIR
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs | FileCheck %s --check-prefix=ASM

declare { i64, i64 } @llvm.x86.go.udivrem.i128.i64(i64, i64, i64)

define { i64, i64 } @udivrem128by64(i64 %high, i64 %low, i64 %divisor) {
; ASM-LABEL: udivrem128by64:
; ASM:       movq %rsi, %rax
; ASM:       movq %rdi, %rdx
; ASM:       divq %rcx
; ASM-NOT:   call
; ASM:       retq
;
; WIN-LABEL: udivrem128by64:
; WIN:       divq
; WIN-NOT:   call
; WIN:       retq
;
; MIR-LABEL: name: udivrem128by64
; MIR:       $rax = COPY
; MIR:       $rdx = COPY
; MIR:       DIV64r
; MIR-NOT:   CALL
  %result = call { i64, i64 } @llvm.x86.go.udivrem.i128.i64(
      i64 %high, i64 %low, i64 %divisor)
  ret { i64, i64 } %result
}
