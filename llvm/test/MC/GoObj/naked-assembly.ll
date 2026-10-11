; REQUIRES: x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t
; RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s
;
; Assembly owns the frame: no synthesized empty stack maps or compiler frame
; facts may replace its explicit FUNCDATA and post-instruction SP transitions.
!goobj.assembly = !{!0}
!0 = !{i32 1}
@args = external global i8

define goabi0 void @"test<ABI0>"() naked noinline !goobj.asm !1 {
  call void asm sideeffect "pushq %rbp\0Amovq %rsp,%rbp\0Acallq *%rax\0Apopq %rbp\0Aretq", "Ws,~{memory}"(ptr @args)
  unreachable
}

; CHECK: flags: 4
; CHECK: file 0: input.s
; CHECK: nonpkgdef 0: test abi=0 type=1 size=8 align=0 flag=0
; CHECK: nonpkgref 0: args abi=0
; CHECK: type=funcinfo target= args=16 locals=8 funcid=0 funcflag=4 startline=10 files=[0]
; CHECK-NEXT: {{.*}}type=pcsp target= pc=[0-1:0,1-7:8,7-8:0]
; CHECK-NEXT: {{.*}}type=pcfile target= pc=[0-1:-1,1-8:0]
; CHECK-NEXT: {{.*}}type=pcline target= pc=[0-1:-1,1-8:11]
; CHECK-NEXT: {{.*}}type=pcinline target= pc=[0-8:-1]
; CHECK-NEXT: {{.*}}type=pcdata target= pc=[0-8:-1]
; CHECK-NEXT: {{.*}}type=funcdata target=args
; CHECK-NEXT: reloc {{.*}} off=4 size=0 type=10 add=0 target=:0 kind=R_CALLIND

!1 = !{i32 1, i64 8, !2, !3, !9, !12, !11}
!2 = !{i32 16, i32 8, i32 0, i32 4, i32 10}
!3 = !{!4, !5, !6, !7, !8}
!4 = !{i64 1, i32 -3, i32 8, !""}
!5 = !{i64 7, i32 -3, i32 0, !""}
!6 = !{i64 1, i32 -2, i32 11, !"input.s"}
!7 = !{i64 1, i32 0, i32 -2, !""}
!8 = !{i64 1, i32 0, i32 -1, !""}
!9 = !{!10}
!10 = !{i32 0, ptr @args}
!11 = !{i64 4}
!12 = !{}
