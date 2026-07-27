; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

@target = constant i8 0, section ".rodata", align 1
@weak_offset = constant <{ i32 }> <{ i32 ptrtoint (ptr @target to i32) }>, section ".rodata", align 4, !goobj.relocs !0

!0 = !{!1}
!1 = !{i32 0, i32 32773}

; CHECK: symdef {{[0-9]+}}: weak_offset abi=0 type=3 size=4
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=4 type=32773 add=0 target=target
