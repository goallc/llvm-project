# REQUIRES: aarch64-registered-target
# RUN: llvm-mc -triple=aarch64-unknown-linux-goobj -aarch64-goobj-composite-relocations -filetype=obj %s -o %t
# RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s

# The Go linker expects one GOT relocation over the ADRP/LDR pair.
# CHECK: reloc 0.0: off=0 size=8 type=34 add=0 target=data
# CHECK: reloc 0.1: off=8 size=8 type=40 add=0 target=data
# An adjacent pair using different address spaces must not merge.
# CHECK: reloc 0.2: off=16 size=4 type=34 add=0 target=data
# CHECK: reloc 0.3: off=20 size=4 type=36 add=0 target=data
# CHECK: reloc 0.4: off=24 size=4 type=36 add=0 target=data
# CHECK: reloc 0.5: off=28 size=4 type=34 add=0 target=data

.text
.globl caller
caller:
  adrp x0, :got:data
  ldr x0, [x0, :got_lo12:data]
  adrp x1, data
  ldr x1, [x1, :lo12:data]
  adrp x2, :got:data
  ldr x2, [x2, :lo12:data]
  adrp x3, data
  ldr x3, [x3, :got_lo12:data]
  ret
