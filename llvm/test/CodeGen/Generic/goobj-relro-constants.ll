; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -relocation-model=pic -goobj-package-path=example/pkg -filetype=obj < %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -relocation-model=pic -goobj-package-path=example/pkg -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

; Private constants without an explicit section may be placed in .data.rel.ro
; by PIC lowering. Both these and explicitly sectioned RELRO globals must be
; read-only Go symbols, with their relocations preserved. Mutable pointer data
; must retain SDATA classification.
@target = external global i8
@table = private unnamed_addr constant [2 x ptr] [ptr @target, ptr @target]
@relro = constant ptr @target, section ".data.rel.ro", align 8
@relro_local = constant ptr @target, section ".data.rel.ro.local", align 8
@mutable = global ptr @target, section ".data", align 8

define goabiinternal ptr @table_address() {
  ret ptr @table
}

; CHECK-DAG: symdef [[TABLE:[0-9]+]]: goallc.{{[0-9a-f]+}}.stmp_{{[0-9]+}} abi=65535 type=3 size=16
; CHECK-DAG: symdef [[RELRO:[0-9]+]]: relro abi=0 type=3 size=8 align=8
; CHECK-DAG: symdef [[LOCAL:[0-9]+]]: relro_local abi=0 type=3 size=8 align=8
; CHECK-DAG: symdef [[MUTABLE:[0-9]+]]: mutable abi=0 type=7 size=8 align=8
; CHECK-DAG: reloc [[TABLE]].{{[0-9]+}}: off=0 size=8 type=1 add=0 target=target
; CHECK-DAG: reloc [[TABLE]].{{[0-9]+}}: off=8 size=8 type=1 add=0 target=target
; CHECK-DAG: reloc [[RELRO]].{{[0-9]+}}: off=0 size=8 type=1 add=0 target=target
; CHECK-DAG: reloc [[LOCAL]].{{[0-9]+}}: off=0 size=8 type=1 add=0 target=target
; CHECK-DAG: reloc [[MUTABLE]].{{[0-9]+}}: off=0 size=8 type=1 add=0 target=target
