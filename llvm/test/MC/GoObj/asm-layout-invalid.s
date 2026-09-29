# REQUIRES: x86-registered-target
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -defsym EXPECTED=1 -filetype=obj %s -o %t
# RUN: not --crash llvm-mc -defsym EXPECTED=2 -triple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t 2>&1 | FileCheck %s
# CHECK: GoObj assembly interior address changed during encoding
.goobj.assembly
.text
.globl test
test:
  nop
.Linterior:
  ret
.goobj.asmfunc test, 0, 0, 0, 4, 1
.goobj.asmpc test, .Linterior, -4, EXPECTED
