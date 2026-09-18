; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

define goabi0 void @"abi0_func<ABI0>"() {
entry:
  ret void
}

define goabiinternal void @internal_func() {
entry:
  ret void
}

; CHECK: symdef-count: 4
; CHECK: symdef 0: abi0_func abi=0 type=1 size={{[0-9]+}}
; CHECK-NEXT: symdef 1: internal_func abi=1 type=1 size={{[0-9]+}}
; CHECK-NEXT: symdef 2:  abi=0 type=3 size={{[0-9]+}}
; CHECK-NEXT: symdef 3:  abi=0 type=3 size={{[0-9]+}}
; Both definitions are zero-frame leaves, so native-Go stack-check policy does
; not introduce an otherwise unrelated runtime reference.
; CHECK-NOT: runtime.morestack
