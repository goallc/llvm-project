; RUN: llc -mtriple=aarch64-apple-darwin-goobj -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s

@prefix = internal constant [3 x i8] c"pad", section ".rodata", align 1
@.empty = private unnamed_addr constant [0 x i8] zeroinitializer, align 4
@after = internal constant i64 42, section ".rodata", align 8
@zero = global [0 x i8] zeroinitializer, section ".noptrbss", align 1
@refs = global [2 x ptr] [ptr @.empty, ptr @zero], section ".data", align 8

; CHECK-DAG: symdef [[ZERO:[0-9]+]]: zero abi=0 type=10 size=0 align=1
; CHECK-DAG: hasheddef [[EMPTY:[0-9]+]]: .L.empty abi=0 type=3 size=0 align=4 flag=3 flag2=0
; CHECK-DAG: hash [[EMPTY]]: 96eeff563b3135e3f77964e8c062328f
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=8 type=1 add=0 target=.L.empty
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=8 size=8 type=1 add=0 target=zero
