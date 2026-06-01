; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s --check-prefixes=CHECK,UNLINKABLE
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.pkg.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.pkg.o | FileCheck %s --check-prefixes=CHECK,LINKABLE

@g = global i64 42, align 8

declare void @ext()

define i64 @loadg() {
entry:
  %v = load i64, ptr @g, align 8
  ret i64 %v
}

define void @caller() {
entry:
  call void @ext()
  ret void
}

; UNLINKABLE: flags: 8
; LINKABLE: flags: 0
; CHECK: symdef-count: 5
; CHECK: symdef 0: .text abi=0 type=1 size=0
; CHECK-NEXT: symdef 1: loadg abi=0 type=1 size=8
; CHECK-NEXT: symdef 2: caller abi=0 type=1 size=8
; CHECK-NEXT: symdef 3: g abi=0 type=7 size=0
; CHECK-NEXT: symdef 4: .data abi=0 type=7 size=8
; CHECK: nonpkgdef-count: 0
; CHECK: nonpkgref-count: 1
; CHECK-NEXT: nonpkgref 0: ext abi=0 type=0 size=0
; CHECK: reloc 1.0: off=3 size=4 type=14 add=0 target=g
; CHECK: reloc 2.1: off=2 size=4 type=7 add=0 target=ext
