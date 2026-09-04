; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.opt.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

@content = weak constant [3 x i8] c"abc", section ".rodata", align 1, !goobj.content_hash !0
@llvm.compiler.used = appending global [2 x ptr] [ptr @content, ptr @"example.com/generic.func1#QUJDREVGR0g=#"], section "llvm.metadata"

define goabiinternal void @"example.com/generic.func1#QUJDREVGR0g=#"() !goobj.content_addressable !1 {
entry:
  ret void
}

!0 = !{!"0123456789abcdef"}
!1 = !{i1 true}

; CHECK-DAG: hasheddef [[CONTENT:[0-9]+]]: content abi=0 type=3 size=3 align=1 flag=1 flag2=0
; CHECK-DAG: hasheddef [[FUNCTION:[0-9]+]]: example.com/generic.func1 abi=1 type=1 size={{[1-9][0-9]*}} align=0 flag={{[0-9]+}} flag2=0
; CHECK-DAG: hash [[CONTENT]]: 30313233343536373839616263646566
; CHECK-DAG: hash [[FUNCTION]]: {{[0-9a-f]+}}
; CHECK-NOT: example.com/generic.func1#QUJDREVGR0g=#
