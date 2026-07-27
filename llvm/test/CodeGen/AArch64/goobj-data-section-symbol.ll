; RUN: llc -mtriple=aarch64-apple-darwin-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

@inter = external global i8
@type = external global i8
@method = external global i8
@external_gotype = external global i8

@gotype = constant i8 0, section ".rodata", align 1
@cache0 = global <{ ptr, ptr, [8 x i8] }> zeroinitializer, section ".data", align 16, !goobj.gotype !5
@cache1 = global <{ ptr, ptr, [8 x i8] }> zeroinitializer, section ".data", align 16, !goobj.gotype !6

@itab = constant <{ ptr, ptr, i32, [4 x i8], i64 }> <{
  ptr @inter,
  ptr @type,
  i32 123,
  [4 x i8] zeroinitializer,
  i64 ptrtoint (ptr @method to i64)
}>, section ".rodata", align 8, !goobj.symbol.flags !0, !goobj.relocs !1

!0 = !{i32 1, i32 2}
!1 = !{!2, !3, !4}
!2 = !{i32 0, i32 1}
!3 = !{i32 8, i32 1}
!4 = !{i32 24, i32 32769}
!5 = !{!"gotype"}
!6 = !{!"external_gotype"}

; CHECK-DAG: symdef {{[0-9]+}}: cache0 abi=0 type=7 size=24 align=16
; CHECK-DAG: symdef {{[0-9]+}}: cache1 abi=0 type=7 size=24 align=16
; CHECK-DAG: symdef {{[0-9]+}}: itab abi=0 type=3 size=32 align=8
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=8 type=1 add=0 target=inter
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=8 size=8 type=1 add=0 target=type
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=24 size=8 type=32769 add=0 target=method
; CHECK: aux {{[0-9]+}}.{{[0-9]+}}: type=gotype target=gotype
; CHECK: aux {{[0-9]+}}.{{[0-9]+}}: type=gotype target=external_gotype
