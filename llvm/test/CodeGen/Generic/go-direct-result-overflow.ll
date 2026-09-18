; RUN: not --crash llc -mtriple=x86_64-unknown-linux-gnu -filetype=null < %s 2>&1 \
; RUN:   | FileCheck %s --check-prefix=X86
; RUN: not --crash llc -mtriple=aarch64-unknown-linux-gnu -filetype=null < %s 2>&1 \
; RUN:   | FileCheck %s --check-prefix=AARCH64

; A direct Go ABI result has no stack fallback. The frontend must retain only
; the register-assigned results in the LLVM return value and use goret
; carriers for whole logical results assigned to memory.
define goabiinternal [17 x i64] @direct_result_overflow() {
entry:
  ret [17 x i64] zeroinitializer
}

; X86: LLVM ERROR: X86 Go direct return exceeds the register ABI; use goret
; AARCH64: LLVM ERROR: AArch64 Go direct return exceeds the register ABI; use goret
