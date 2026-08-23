; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

@data = constant i8 0, section ".rodata", !goobj.symbol.flags !0

define goabiinternal void @reflect_func() !goobj.symbol.flags !1 {
  ret void
}

!0 = !{i32 4, i32 1}
!1 = !{i32 32, i32 16}

; CHECK-DAG: symdef {{[0-9]+}}: data abi=0 type=3 size=1 align={{[0-9]+}} flag=4 flag2=1
; The backend adds the Go leaf bit (8) after machine lowering.
; CHECK-DAG: symdef {{[0-9]+}}: reflect_func abi=1 type=1 size={{[0-9]+}} align={{[0-9]+}} flag=40 flag2=16
