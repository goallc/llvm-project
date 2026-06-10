; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

define goabi0cc void @abi0_func() {
entry:
  ret void
}

define gocc void @internal_func() {
entry:
  ret void
}

; CHECK: symdef-count: 3
; CHECK: symdef 0: .text abi=0 type=1 size=0
; CHECK-NEXT: symdef 1: abi0_func abi=0 type=1 size={{[0-9]+}}
; CHECK-NEXT: symdef 2: internal_func abi=1 type=1 size={{[0-9]+}}
