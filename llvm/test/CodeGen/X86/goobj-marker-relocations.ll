; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

@target = constant i8 0, section ".rodata", align 1

define goabiinternal void @source() !goobj.marker_relocs !0 {
  ret void
}

!0 = !{!1, !2}
!1 = !{i32 23, i64 0, !"target"}
!2 = !{i32 24, i64 96, !"target"}

; CHECK: symdef {{[0-9]+}}: source abi=1 type=1
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=23 add=0 target=target
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=24 add=96 target=target
