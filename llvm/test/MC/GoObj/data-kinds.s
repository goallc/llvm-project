# REQUIRES: x86-registered-target
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t
# RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s

# CHECK-DAG: nonpkgdef {{[0-9]+}}: noptrdata abi=0 type=5 size=8
# CHECK-DAG: nonpkgdef {{[0-9]+}}: data abi=0 type=7 size=8
# CHECK-DAG: nonpkgdef {{[0-9]+}}: bss abi=0 type=9 size=8
# CHECK-DAG: nonpkgdef {{[0-9]+}}: noptrbss abi=0 type=10 size=8

.section .noptrdata
.globl noptrdata
noptrdata:
  .quad 1

.data
.globl data
data:
  .quad 2

.bss
.globl bss
bss:
  .zero 8

.section .noptrbss
.globl noptrbss
noptrbss:
  .zero 8
