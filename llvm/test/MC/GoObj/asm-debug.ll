; REQUIRES: x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t
; RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s

define goabi0 void @"test<ABI0>"() naked noinline !goobj.asm !0 {
  call void asm sideeffect "nop\0Aretq", "~{memory}"()
  unreachable
}
!0 = !{i32 1, i64 2, !1, !2, !3, !4, !3}
!1 = !{i32 0, i32 0, i32 0, i32 0, i32 10}
!2 = !{!5}
!3 = !{}
!4 = !{i32 5, i32 0, i32 1, !"input.s", !6}
!5 = !{i64 0, i32 -2, i32 10, !"input.s"}
!6 = !{!7, !8}
!7 = !{i64 0, i32 10, i32 1, !"input.s"}
!8 = !{i64 1, i32 11, i32 2, !"input.s"}
; CHECK-DAG: file 0: input.s
; CHECK-DAG: type=dwarf_info
; CHECK-DAG: type=dwarf_lines
; CHECK-DAG: type=106 add=0 target=test kind=R_DWTXTADDR_U4
; CHECK-DAG: type=1 add=0 target=test kind=R_ADDR
