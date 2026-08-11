; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.opt.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o %t.arm64.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.opt.o | FileCheck %s

define goabiinternal void @third() !goobj.symbol.index !1 {
  ret void
}

define goabiinternal void @unindexed() {
  ret void
}

define goabiinternal void @first() !goobj.symbol.index !0 {
  ret void
}

!0 = !{i32 0}
!1 = !{i32 2}

; CHECK: symdef 0: first abi=1 type=1
; CHECK-NEXT: symdef 1:  abi=0 type=3 size=0 align=0 flag=0 flag2=0
; CHECK-NEXT: symdef 2: third abi=1 type=1
; CHECK-NEXT: symdef 3: unindexed abi=1 type=1
