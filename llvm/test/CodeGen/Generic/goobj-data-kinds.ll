; REQUIRES: aarch64-registered-target
; REQUIRES: x86-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.amd64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.amd64.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=aarch64-apple-darwin-goobj -filetype=obj -o %t.arm64.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.opt.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.amd64.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.amd64.opt.o | FileCheck %s
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -filetype=asm < %s | FileCheck %s --check-prefix=ASM

@rodata = constant i64 1, section ".rodata", align 8
@noptrdata = global i64 2, section ".noptrdata", align 8
@data = global ptr @noptrdata, section ".data", align 8
@bss = global ptr null, section ".bss", align 8
@noptrbss = global i64 0, section ".noptrbss", align 8

; CHECK-DAG: symdef {{[0-9]+}}: rodata abi=0 type=3 size=8 align=8
; CHECK-DAG: symdef {{[0-9]+}}: noptrdata abi=0 type=5 size=8 align=8
; CHECK-DAG: symdef {{[0-9]+}}: data abi=0 type=7 size=8 align=8
; CHECK-DAG: symdef {{[0-9]+}}: bss abi=0 type=9 size=8 align=8
; CHECK-DAG: symdef {{[0-9]+}}: noptrbss abi=0 type=10 size=8 align=8
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=8 type=1 add=0 target=noptrdata
; ASM: .section .noptrbss,"aw",@nobits
