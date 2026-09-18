# REQUIRES: x86-registered-target, aarch64-registered-target
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t
# RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s

# RUN: llvm-mc -triple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm64
# RUN: %python %S/Inputs/dump-goobj.py %t.arm64 | FileCheck %s

# The addend compensates for R_PCREL's end-of-field PC, including when the
# subtraction base is an interior label rather than the source symbol start.
# CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=4 type=14 add=4 target=target
# CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=4 size=4 type=14 add=9 target=target
# CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=8 size=4 type=14 add=19 target=target
# CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=12 size=4 type=14 add=12 target=target
# CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=16 size=8 type=14 add=24 target=target

.text
.globl target
target:
  .byte 0
.Lcase:
  .byte 0
.section .rodata
.globl padding
padding:
  .quad 0
.globl table
table:
  .long target-table
.Lbase:
  .long .Lcase-table
  .long target-table+7
  .long target-.Lbase
  .quad target-table
