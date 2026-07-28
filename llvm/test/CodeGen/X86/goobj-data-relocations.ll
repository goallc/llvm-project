; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

%go.descriptor.weak_offset = type <{ i32 }>

@target = constant i8 0, section ".rodata", align 1
@weak_offset = constant %go.descriptor.weak_offset <{ i32 ptrtoint (ptr @target to i32) }>, section ".rodata", align 4, !goobj.weak_relocs !0

!0 = !{i32 0}

; CHECK: symdef {{[0-9]+}}: weak_offset abi=0 type=3 size=4
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=4 type=32773 add=0 target=target
