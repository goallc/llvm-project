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
; CHECK: file-count: 1
; CHECK-NEXT: file 0: llvm-ir
; CHECK: symdef-count: 7
; CHECK: symdef 0: .text abi=0 type=1 size=0
; CHECK-NEXT: symdef 1: loadg abi=0 type=1 size=8
; CHECK-NEXT: symdef 2: caller abi=0 type=1 size=8
; CHECK-NEXT: symdef 3: g abi=0 type=7 size=0
; CHECK-NEXT: symdef 4: .data abi=0 type=7 size=8
; CHECK-NEXT: symdef 5:  abi=65535 type=3 size=28
; CHECK-NEXT: symdef 6:  abi=65535 type=3 size=28
; CHECK: nonpkgdef-count: 12
; CHECK: nonpkgref-count: 1
; CHECK-NEXT: nonpkgref 0: ext abi=0 type=0 size=0
; CHECK: aux 1.0: type=funcinfo target= args=0 locals=0
; CHECK-NEXT: aux 1.1: type=funcdata target= data=0100000000000000
; CHECK-NEXT: aux 1.2: type=funcdata target= data=0100000000000000
; CHECK-NEXT: aux 1.3: type=pcsp target=
; CHECK-NEXT: aux 1.4: type=pcfile target=
; CHECK-NEXT: aux 1.5: type=pcline target=
; CHECK-NEXT: aux 1.6: type=pcdata target= pc=
; CHECK-NEXT: reloc 1.0: off=3 size=4 type=14 add=0 target=g
; CHECK-NEXT: aux 2.7: type=funcinfo target= args=0 locals=8
; CHECK-NEXT: aux 2.8: type=funcdata target= data=0100000000000000
; CHECK-NEXT: aux 2.9: type=funcdata target= data=0100000000000000
; CHECK-NEXT: aux 2.10: type=pcsp target=
; CHECK-NEXT: aux 2.11: type=pcfile target=
; CHECK-NEXT: aux 2.12: type=pcline target=
; CHECK-NEXT: aux 2.13: type=pcdata target= pc=
; CHECK-NEXT: reloc 2.1: off=2 size=4 type=7 add=0 target=ext
