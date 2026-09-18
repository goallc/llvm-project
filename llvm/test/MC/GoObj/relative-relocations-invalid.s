# REQUIRES: x86-registered-target, aarch64-registered-target
# RUN: not --crash llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t 2>&1 | FileCheck %s
# RUN: not --crash llvm-mc -triple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm64 2>&1 | FileCheck %s
# CHECK: GoObj relocation subtractor must belong to the source symbol of an absolute relocation

# Even in the same section, independently linked Go symbols can move apart.
.text
.globl target
target:
  .byte 0
.section .rodata
.globl other
other:
  .quad 0
.globl table
table:
  .long target-other
