# REQUIRES: x86-registered-target
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t
# RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s

# CHECK: header: go object linux amd64 go1.26.3 GOAMD64=v1 X:regabiwrappers,regabiargs,dwarf5,greenteagc,randomizedheapbase64\n!\n
# CHECK-NEXT: magic-offset: 111
# CHECK-NEXT: flags: 4
# CHECK: symdef-bytes: 0
# CHECK: nonpkgdef-bytes: 63
# CHECK: nonpkgdef-count: 3
# CHECK: nonpkgdef 0: foo abi=0 type=1 size=2
# CHECK: nonpkgdef 1: bar abi=0 type=7 size=3
# CHECK: nonpkgdef 2: baz abi=0 type=9 size=4
# CHECK: data: 9090010203

.text
.globl foo
foo:
  nop
  nop

.data
.globl bar
bar:
  .byte 1, 2, 3

.bss
.globl baz
baz:
  .zero 4
