# REQUIRES: aarch64-registered-target
# RUN: llvm-mc -triple=aarch64-apple-darwin-goobj -filetype=obj %s -o %t
# RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s

# CHECK: header: go object darwin arm64
# CHECK: nonpkgdef 0: caller abi=0 type=1 size=80
# CHECK: nonpkgdef 1: callee abi=0 type=1 size=4
# CHECK: nonpkgdef 2: split_adrp abi=0 type=1 size=4
# CHECK: nonpkgdef 3: split_add abi=0 type=1 size=8
# CHECK: nonpkgdef 4: ptr abi=0 type=7 size=16
# CHECK: nonpkgdef 5: data abi=0 type=7 size=8
# CHECK: nonpkgref 0: external.func abi=1 type=0 size=0
# CHECK: nonpkgref 1: external.data abi=0 type=0 size=0
# CHECK: reloc 0.0: off=0 size=4 type=9 add=0 target=callee
# CHECK: reloc 0.1: off=4 size=4 type=9 add=0 target=external.func
# CHECK: reloc 0.2: off=8 size=8 type=3 add=0 target=data
# CHECK: reloc 0.3: off=16 size=8 type=37 add=0 target=data
# CHECK: reloc 0.4: off=24 size=8 type=38 add=0 target=data
# CHECK: reloc 0.5: off=32 size=8 type=39 add=0 target=data
# CHECK: reloc 0.6: off=40 size=8 type=40 add=0 target=data
# CHECK: reloc 0.7: off=48 size=4 type=36 add=0 target=data
# CHECK: reloc 0.8: off=52 size=4 type=36 add=0 target=external.data
# CHECK: reloc 0.9: off=56 size=4 type=36 add=0 target=data
# CHECK: reloc 0.10: off=64 size=4 type=36 add=0 target=data
# CHECK: reloc 0.11: off=68 size=4 type=36 add=0 target=data
# CHECK: reloc 0.12: off=72 size=4 type=36 add=0 target=data
# CHECK: reloc 2.13: off=0 size=4 type=36 add=0 target=data
# CHECK: reloc 3.14: off=0 size=4 type=36 add=0 target=data
# CHECK: reloc 4.15: off=0 size=8 type=1 add=0 target=callee
# CHECK: reloc 4.16: off=8 size=8 type=1 add=8 target=external.data

.text
.globl caller
caller:
  bl callee
  bl external.func
  adrp x0, data
  add x0, x0, :lo12:data
  adrp x1, data
  ldrb w1, [x1, :lo12:data]
  adrp x1, data
  ldrh w1, [x1, :lo12:data]
  adrp x1, data
  ldr w1, [x1, :lo12:data]
  adrp x1, data
  ldr x1, [x1, :lo12:data]
  # Different target symbols must not merge.
  adrp x2, data
  add x2, x2, :lo12:external.data
  # A gap between the instructions must not merge.
  adrp x3, data
  nop
  add x3, x3, :lo12:data
  # An ADRP followed by a different relocation kind must not merge.
  adrp x4, data
  adr x4, data
  ret

.globl callee
callee:
  ret

# Adjacent relocations in different source symbols must not merge.
.globl split_adrp
split_adrp:
  adrp x5, data

.globl split_add
split_add:
  add x5, x5, :lo12:data
  ret

.data
.globl ptr
ptr:
  .xword callee
  .xword external.data+8

.globl data
data:
  .xword 0
