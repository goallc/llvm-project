; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

define goabi0 void @abi0_func() {
entry:
  ret void
}

define goabiinternal void @internal_func() {
entry:
  ret void
}

; CHECK: symdef-count: 5
; CHECK: symdef 0: .text abi=0 type=1 size=0
; CHECK-NEXT: symdef 1: abi0_func abi=0 type=1 size={{[0-9]+}}
; CHECK-NEXT: symdef 2: internal_func abi=1 type=1 size={{[0-9]+}}
; CHECK-NEXT: symdef 3:  abi=65535 type=3 size={{[0-9]+}}
; CHECK-NEXT: symdef 4:  abi=65535 type=3 size={{[0-9]+}}
; CHECK: nonpkgref {{[0-9]+}}: runtime.morestack_noctxt abi=0 type=0 size=0
