# REQUIRES: x86-registered-target
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t
# RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s

# CHECK: nonpkgdef-count: 4
# CHECK: nonpkgdef 0: caller abi=0 type=1 size=18
# CHECK: nonpkgdef 1: callee abi=0 type=1 size=1
# CHECK: nonpkgdef 2: ptr abi=0 type=7 size=16
# CHECK: nonpkgdef 3: data abi=0 type=7 size=8
# CHECK: nonpkgref-count: 2
# CHECK: nonpkgref 0: external.func abi=1 type=0 size=0
# CHECK: nonpkgref 1: external.data abi=0 type=0 size=0
# CHECK: reloc 0.0: off=1 size=4 type=7 add=0 target=callee
# CHECK: reloc 0.1: off=6 size=4 type=7 add=0 target=external.func
# CHECK: reloc 0.2: off=13 size=4 type=14 add=0 target=data
# CHECK: reloc 2.3: off=0 size=8 type=1 add=0 target=callee
# CHECK: reloc 2.4: off=8 size=8 type=1 add=8 target=external.data

.text
.globl caller
caller:
  callq callee
  callq external.func
  leaq data(%rip), %rax
  retq

.globl callee
callee:
  retq

.data
.globl ptr
ptr:
  .quad callee
  .quad external.data+8

.globl data
data:
  .quad 0
