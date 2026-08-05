; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

define goabiinternal void @normal() {
  ret void
}

define goabiinternal void @wrapper() !goobj.func.info !0 {
  ret void
}

!0 = !{i8 23, i8 1}

; CHECK: symdef 0: normal
; CHECK: symdef 1: wrapper
; CHECK: aux 0.0: type=funcinfo target= args=0 locals={{[0-9]+}} funcid=0 funcflag=0
; CHECK: aux 1.8: type=funcinfo target= args=0 locals={{[0-9]+}} funcid=23 funcflag=1
