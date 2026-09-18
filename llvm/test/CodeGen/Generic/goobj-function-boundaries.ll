; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -O0 -filetype=obj %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s -DRET_SIZE=1
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -O2 -filetype=obj %s -o %t.x86.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.opt.o | FileCheck %s -DRET_SIZE=1
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -O0 -filetype=obj %s -o %t.arm.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm.o | FileCheck %s -DRET_SIZE=4
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -O2 -filetype=obj %s -o %t.arm.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm.opt.o | FileCheck %s -DRET_SIZE=4

; Each body contains only a return. Function alignment must not become part
; of the preceding Go symbol's payload, whether it is strong, Dupok, or
; content-addressable. The same body at the end of the section has no padding.
; CHECK-DAG: : ordinary abi=1 type=1 size=[[RET_SIZE]] align=
; CHECK-DAG: : duplicate abi=1 type=1 size=[[RET_SIZE]] align=
; CHECK-DAG: : content abi=1 type=1 size=[[RET_SIZE]] align=
; CHECK-DAG: : aligned abi=1 type=1 size=[[RET_SIZE]] align=
; CHECK-DAG: : last abi=1 type=1 size=[[RET_SIZE]] align=

define goabiinternal void @ordinary() "go-nosplit" {
  ret void
}

define linkonce_odr goabiinternal void @duplicate() align 32 "go-nosplit" {
  ret void
}

define goabiinternal void @content() align 64 "go-nosplit" !goobj.content_addressable !0 {
  ret void
}

define goabiinternal void @aligned() align 64 "go-nosplit" {
  ret void
}

define linkonce_odr goabiinternal void @last() "go-nosplit" {
  ret void
}

!0 = !{i1 true}
