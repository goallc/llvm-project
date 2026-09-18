; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm.o | FileCheck %s
; REQUIRES: x86-registered-target, aarch64-registered-target

; A reference to one private constant must not retain another constant's
; relocation targets. Zero-sized objects still need a directly indexed symbol.
@first = private constant [2 x ptr] [ptr @a, ptr null], section ".rodata", align 8
@second = private constant [3 x ptr] [ptr @b, ptr null, ptr null], section ".rodata", align 8
@empty = private constant [0 x i8] zeroinitializer, section ".rodata", align 1

declare goabiinternal void @a()
declare goabiinternal void @b()

; Also keep machine constant-pool objects addressable alongside private IR
; globals, even though they are not GlobalVariables.
define goabiinternal double @with_constant_pool(double %x) {
  %r = fadd double %x, 0x400921FB54442D18
  ret double %r
}

define goabiinternal ptr @get_first() {
  ret ptr @first
}
define goabiinternal ptr @get_second() {
  ret ptr @second
}
define goabiinternal ptr @get_empty() {
  ret ptr @empty
}

; CHECK: symdef [[FIRST:[0-9]+]]: [[FIRSTNAME:goallc\.[0-9a-f]+\.stmp_[0-9]+]] abi=65535 type=3 size=16 align=8 flag=2 flag2=0
; CHECK: symdef [[SECOND:[0-9]+]]: [[SECONDNAME:goallc\.[0-9a-f]+\.stmp_[0-9]+]] abi=65535 type=3 size=24 align=8 flag=2 flag2=0
; CHECK: symdef [[EMPTY:[0-9]+]]: [[EMPTYNAME:goallc\.[0-9a-f]+\.stmp_[0-9]+]] abi=65535 type=3 size=0 align=1 flag=2 flag2=0
; CHECK-DAG: target=[[FIRSTNAME]]
; CHECK-DAG: target=[[SECONDNAME]]
; CHECK-DAG: target=[[EMPTYNAME]]
; CHECK-DAG: reloc [[FIRST]].{{[0-9]+}}: off=0 size=8 type=1 add=0 target=a
; CHECK-DAG: reloc [[SECOND]].{{[0-9]+}}: off=0 size=8 type=1 add=0 target=b
