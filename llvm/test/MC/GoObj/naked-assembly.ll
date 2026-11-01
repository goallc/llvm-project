; REQUIRES: x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t
; RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s
;
; Assembly owns the frame: no synthesized empty stack maps or compiler frame
; facts may replace its explicit FUNCDATA and post-instruction SP transitions.
module asm ".goobj.assembly"
@args = external global i8

define goabi0 void @"test<ABI0>"() naked noinline {
  call void asm sideeffect "pushq %rbp\0A.Lpush:\0Amovq %rsp,%rbp\0A.Lcall:\0Acallq *%rax\0Apopq %rbp\0A.Lpop:\0Aretq\0A.goobj.asmfunc ${0:c}, 16, 8, 0, 4, 10\0A.goobj.asmpc ${0:c}, .Lpush, -3, 8\0A.goobj.asmpc ${0:c}, .Lpop, -3, 0\0A.goobj.asmpc ${0:c}, .Lpush, -2, 11, \22input.s\22\0A.goobj.asmpc ${0:c}, .Lpush, 0, -2\0A.goobj.asmpc ${0:c}, .Lpush, 0, -1\0A.goobj.asmpc ${0:c}, .Lcall, -5, 0\0A.goobj.asmfuncdata ${0:c}, 0, ${1:c}", "Ws,Ws,~{memory}"(ptr @"test<ABI0>", ptr @args)
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
; CHECK-NEXT: {{.*}}type=pcdata target= pc=[0-8:-1]
; CHECK-NEXT: {{.*}}type=funcdata target=args
; CHECK-NEXT: reloc {{.*}} off=4 size=0 type=10 add=0 target=:0 kind=R_CALLIND
