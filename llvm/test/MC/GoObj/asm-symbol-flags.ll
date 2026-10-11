; REQUIRES: x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t
; RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s
;
; STATIC identity and LOCAL semantics are independent in Go assembly. Exact
; frontend flags suppress linkage-derived flags, but can explicitly set LOCAL.
!goobj.assembly = !{!2}
!2 = !{i32 1}
@constant = hidden constant i64 42, !goobj.symbol.flags.exact !0

define internal goabi0 void @"local<ABI0>"() naked noinline !goobj.symbol.flags.exact !1 !goobj.asm !3 {
  call void asm sideeffect "retq", "~{memory}"()
  unreachable
}
!0 = !{i8 2, i8 0}
!1 = !{i8 0, i8 0}
; CHECK-DAG: constant abi=0 type=3 size=8 align={{[0-9]+}} flag=2 flag2=0
; CHECK-DAG: local abi=65535 type=1 size=1 align={{[0-9]+}} flag=0 flag2=0

!3 = !{i32 1, i64 1, !4, !5, !5, !5, !5}
!4 = !{i32 0, i32 0, i32 0, i32 0, i32 1}
!5 = !{}
