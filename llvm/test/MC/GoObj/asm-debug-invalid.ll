; REQUIRES: x86-registered-target
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t 2>&1 | FileCheck %s --check-prefix=VERSION
; RUN: sed 's/i32 3, i32 0/i32 5, i32 0/; s/i32 10, i32 1/i32 10, i32 4/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t 2>&1 | FileCheck %s --check-prefix=FLAGS
; RUN: sed 's/i32 3, i32 0/i32 5, i32 0/; s/!7, !8/!8, !7/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t 2>&1 | FileCheck %s --check-prefix=ORDER
; VERSION: invalid !goobj.asm DWARF version
; FLAGS: !goobj.asm integer out of range
; ORDER: !goobj.asm debug rows are not ordered

define goabi0 void @"test<ABI0>"() naked noinline !goobj.asm !0 {
  call void asm sideeffect "nop\0Aretq", "~{memory}"()
  unreachable
}
!0 = !{i32 1, i64 2, !1, !2, !3, !4, !3}
!1 = !{i32 0, i32 0, i32 0, i32 0, i32 10}
!2 = !{!5}
!3 = !{}
!4 = !{i32 3, i32 0, i32 1, !"input.s", !6}
!5 = !{i64 0, i32 -2, i32 10, !"input.s"}
!6 = !{!7, !8}
!7 = !{i64 0, i32 10, i32 1, !"input.s"}
!8 = !{i64 1, i32 11, i32 2, !"input.s"}
