# REQUIRES: aarch64-registered-target
# RUN: llvm-mc -triple=aarch64-apple-darwin-goobj -filetype=obj %s -o %t
# RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s

# CHECK: header: go object darwin arm64
# CHECK: nonpkgdef 0: caller abi=0 type=1 size=20
# CHECK: nonpkgdef 1: callee abi=0 type=1 size=4
# CHECK: nonpkgdef 2: ptr abi=0 type=7 size=16
# CHECK: nonpkgdef 3: data abi=0 type=7 size=8
# CHECK: nonpkgref 0: external.func abi=0 type=0 size=0
# CHECK: nonpkgref 1: external.data abi=0 type=0 size=0
# CHECK: reloc 0.0: off=0 size=4 type=9 add=0 target=callee
# CHECK: reloc 0.1: off=4 size=4 type=9 add=0 target=external.func
# CHECK: reloc 0.2: off=8 size=4 type=36 add=0 target=data
# CHECK: reloc 0.3: off=12 size=4 type=36 add=0 target=data
# CHECK: reloc 2.4: off=0 size=8 type=1 add=0 target=callee
# CHECK: reloc 2.5: off=8 size=8 type=1 add=8 target=external.data

.text
.globl caller
caller:
  bl callee
  bl external.func
  adrp x0, data
  add x0, x0, :lo12:data
  ret

.globl callee
callee:
  ret

.data
.globl ptr
ptr:
  .xword callee
  .xword external.data+8

.globl data
data:
  .xword 0
