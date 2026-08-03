; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.opt.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

@content = weak constant [3 x i8] c"abc", section ".rodata", align 1, !goobj.content_hash !0
@llvm.compiler.used = appending global [1 x ptr] [ptr @content], section "llvm.metadata"

!0 = !{!"0123456789abcdef"}

; CHECK: hasheddef 0: content abi=0 type=3 size=3 align=1 flag=1 flag2=0
; CHECK: hash 0: 30313233343536373839616263646566
