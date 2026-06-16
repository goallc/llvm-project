; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

; The fixed alloca forces a frame larger than Go StackBig, which requires the
; Go stack-growth slow path. The argument is register-passed, so the generated
; slow path must also preserve ABIInternal register arguments across morestack.

define goabiinternal i64 @big_frame(i64 %x) {
entry:
  %buf = alloca [5000 x i8], align 16
  %p0 = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 0
  %p1 = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 7, ptr %p0, align 16
  store volatile i8 11, ptr %p1, align 1
  %v0 = load volatile i8, ptr %p0, align 16
  %v1 = load volatile i8, ptr %p1, align 1
  %a = zext i8 %v0 to i64
  %b = zext i8 %v1 to i64
  %sum0 = add i64 %a, %b
  %sum1 = add i64 %sum0, %x
  ret i64 %sum1
}

; CHECK: symdef {{[0-9]+}}: big_frame abi=1 type=1 size={{[0-9]+}}
; CHECK: nonpkgref {{[0-9]+}}: runtime.morestack_noctxt abi=0 type=0 size=0
; CHECK: aux {{[0-9]+}}.{{[0-9]+}}: type=funcinfo target= args={{[1-9][0-9]*}} locals={{[1-9][0-9][0-9][0-9][0-9]*}}
; CHECK: aux {{[0-9]+}}.{{[0-9]+}}: type=funcdata target= data=0100000000000000
; CHECK: aux {{[0-9]+}}.{{[0-9]+}}: type=funcdata target= data=0100000000000000
; CHECK: aux {{[0-9]+}}.{{[0-9]+}}: type=pcdata target= pc=[0-
; CHECK-SAME: :0
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size=4 type=7 add=0 target=runtime.morestack_noctxt
