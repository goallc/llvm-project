; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.opt.o | FileCheck %s

%weak_offset.storage = type <{ i32 }>
%method_offsets.storage = type <{ i32, i32, i32, i32, i32, i32 }>

@target = constant i8 0, section ".rodata", align 1
@weak_offset = constant %weak_offset.storage <{ i32 ptrtoint (ptr @target to i32) }>, section ".rodata", align 4, !goobj.relocs !0, !goobj.weak_relocs !1, !goobj.symbol.flags !9
@method_name = constant i8 0, section ".rodata", align 1
@method_type = constant i8 0, section ".rodata", align 1
@method_offsets = constant %method_offsets.storage <{
  i32 ptrtoint (ptr @method_name to i32),
  i32 ptrtoint (ptr @method_type to i32),
  i32 ptrtoint (ptr @method_text to i32),
  i32 ptrtoint (ptr @method_text to i32),
  i32 ptrtoint (ptr @method_name to i32),
  i32 ptrtoint (ptr @method_type to i32)
}>, section ".rodata", align 4, !goobj.relocs !2, !goobj.symbol.flags !9

declare goabiinternal void @method_text()

!0 = !{!3}
!1 = !{i32 0}
!2 = !{!3, !4, !5, !6, !7, !8}
!3 = !{i32 0, i32 5}
!4 = !{i32 4, i32 26}
!5 = !{i32 8, i32 26}
!6 = !{i32 12, i32 26}
!7 = !{i32 16, i32 5}
!8 = !{i32 20, i32 5}
!9 = !{i32 64, i32 0}

; CHECK-DAG: symdef {{[0-9]+}}: weak_offset abi=0 type=3 size=4 align=4 flag=64 flag2=0
; CHECK-DAG: symdef {{[0-9]+}}: method_offsets abi=0 type=3 size=24 align=4 flag=64 flag2=0
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=4 type=32773 add=0 target=target
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=4 type=5 add=0 target=method_name
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=4 size=4 type=26 add=0 target=method_type
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=8 size=4 type=26 add=0 target=method_text
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=12 size=4 type=26 add=0 target=method_text
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=16 size=4 type=5 add=0 target=method_name
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=20 size=4 type=5 add=0 target=method_type
