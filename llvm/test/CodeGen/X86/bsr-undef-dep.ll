; RUN: llc -mtriple=x86_64 -mattr=-lzcnt -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=BSR
; RUN: llc -mtriple=x86_64 -mattr=+lzcnt -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=LZCNT
; RUN: llc -mtriple=x86_64 -mcpu=znver4 -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=LZCNT
;
; The dependency-breaking pass must retain a defined fallback for zero inputs
; and must not introduce LZCNT when the target does not support it.

declare i64 @llvm.ctlz.i64(i64, i1 immarg)

define i64 @nonzero(i64 %x) {
; BSR-LABEL: nonzero:
; BSR-NOT: lzcnt
; BSR: bsrq
; BSR: retq
; LZCNT-LABEL: nonzero:
; LZCNT-NOT: bsr
; LZCNT: lzcntq
; LZCNT: retq
  %v = or i64 %x, 1
  %lz = call i64 @llvm.ctlz.i64(i64 %v, i1 false)
  ret i64 %lz
}

define i64 @zero_defined(i64 %x) {
; BSR-LABEL: zero_defined:
; BSR-NOT: lzcnt
; BSR: movl $127, %eax
; BSR-NEXT: bsrq %rdi, %rax
; BSR-NEXT: xorq $63, %rax
; BSR-NEXT: retq
; LZCNT-LABEL: zero_defined:
; LZCNT-NOT: bsr
; LZCNT: lzcntq
; LZCNT: retq
  %lz = call i64 @llvm.ctlz.i64(i64 %x, i1 false)
  ret i64 %lz
}

define i64 @zero_constant() {
; BSR-LABEL: zero_constant:
; BSR-NOT: bsr
; BSR: movl $64, %eax
; BSR-NEXT: retq
; LZCNT-LABEL: zero_constant:
; LZCNT-NOT: lzcnt
; LZCNT: movl $64, %eax
; LZCNT-NEXT: retq
  %lz = call i64 @llvm.ctlz.i64(i64 0, i1 false)
  ret i64 %lz
}
