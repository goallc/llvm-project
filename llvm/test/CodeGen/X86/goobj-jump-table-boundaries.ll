; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -aarch64-min-jump-table-entries=4 -filetype=obj %s -o %t.arm.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm.o | FileCheck %s --check-prefix=ARM
; REQUIRES: x86-registered-target, aarch64-registered-target

; Each function's jump table must be an independent Go symbol. A section-wide
; carrier would make reaching one table retain the other function through its
; block-address relocations.
declare goabiinternal void @callee0()
declare goabiinternal void @callee1()
declare goabiinternal void @callee2()
declare goabiinternal void @callee3()
declare goabiinternal void @callee4()
declare goabiinternal void @callee5()

define goabiinternal void @first(i64 %index) "frame-pointer"="all" {
entry:
  switch i64 %index, label %exit [
    i64 0, label %case0
    i64 1, label %case1
    i64 2, label %case2
    i64 3, label %case3
    i64 4, label %case4
    i64 5, label %case5
  ]
case0:
  call goabiinternal void @callee0()
  br label %exit
case1:
  call goabiinternal void @callee1()
  br label %exit
case2:
  call goabiinternal void @callee2()
  br label %exit
case3:
  call goabiinternal void @callee3()
  br label %exit
case4:
  call goabiinternal void @callee4()
  br label %exit
case5:
  call goabiinternal void @callee5()
  br label %exit
exit:
  ret void
}

define goabiinternal void @second(i64 %index) "frame-pointer"="all" {
entry:
  switch i64 %index, label %exit [
    i64 0, label %case0
    i64 1, label %case1
    i64 2, label %case2
    i64 3, label %case3
    i64 4, label %case4
    i64 5, label %case5
  ]
case0:
  call goabiinternal void @callee0()
  br label %exit
case1:
  call goabiinternal void @callee1()
  br label %exit
case2:
  call goabiinternal void @callee2()
  br label %exit
case3:
  call goabiinternal void @callee3()
  br label %exit
case4:
  call goabiinternal void @callee4()
  br label %exit
case5:
  call goabiinternal void @callee5()
  br label %exit
exit:
  ret void
}

; X86: symdef [[FIRST:[0-9]+]]: [[FIRSTNAME:goallc\.[0-9a-f]+\.stmp_[0-9]+]] abi=65535 type=3 size=48 align=8 flag=2 flag2=0
; X86: symdef [[SECOND:[0-9]+]]: [[SECONDNAME:goallc\.[0-9a-f]+\.stmp_[0-9]+]] abi=65535 type=3 size=48 align=8 flag=2 flag2=0
; X86-DAG: target=[[FIRSTNAME]]
; X86-DAG: target=[[SECONDNAME]]
; X86-DAG: reloc [[FIRST]].{{[0-9]+}}: {{.*}}target=first
; X86-DAG: reloc [[SECOND]].{{[0-9]+}}: {{.*}}target=second
; ARM: symdef {{[0-9]+}}: goallc.{{[0-9a-f]+}}.stmp_{{[0-9]+}} abi=65535 type=3 size={{6|12|24}} align={{1|2|4}} flag=2 flag2=0
; ARM: symdef {{[0-9]+}}: goallc.{{[0-9a-f]+}}.stmp_{{[0-9]+}} abi=65535 type=3 size={{6|12|24}} align={{1|2|4}} flag=2 flag2=0
