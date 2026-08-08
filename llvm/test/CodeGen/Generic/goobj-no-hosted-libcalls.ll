; RUN: llc -mtriple=x86_64-unknown-linux-gnu -o - %s | FileCheck %s --check-prefix=ELF
; RUN: not llc -mtriple=x86_64-unknown-linux-goobj -o /dev/null %s 2>&1 | FileCheck %s --check-prefix=GOOBJ
; RUN: not llc -mtriple=aarch64-unknown-linux-goobj -o /dev/null %s 2>&1 | FileCheck %s --check-prefix=GOOBJ

; ELF: callq __udivti3
; GOOBJ: LLVM ERROR: no runtime library implementation is available for this operation

define i128 @udiv_i128(i128 %dividend, i128 %divisor) {
  %quotient = udiv i128 %dividend, %divisor
  ret i128 %quotient
}
