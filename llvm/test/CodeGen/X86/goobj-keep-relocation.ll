; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

@target = constant i8 0, section ".rodata", align 1
@source = constant i8 0, section ".rodata", align 1, !goobj.keep !0

!0 = !{!"target"}

; CHECK: symdef {{[0-9]+}}: source abi=0 type=3 size=1
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=27 add=0 target=target
