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
; CHECK: symdef-count: 5
; CHECK: symdef 0: loadg abi=0 type=1 size=8
; CHECK-NEXT: symdef 1: caller abi=0 type=1 size=8
; CHECK-NEXT: symdef 2: g abi=0 type=7 size=8 align=8
; CHECK-NEXT: symdef 3:  abi=65535 type=3 size=28
; CHECK-NEXT: symdef 4:  abi=65535 type=3 size=28
; CHECK: hasheddef-count: 5
; CHECK: nonpkgdef-count: 0
; CHECK: nonpkgref-count: 1
; CHECK-NEXT: nonpkgref 0: ext abi=0 type=0 size=0
; CHECK: aux 0.0: type=funcinfo target= args=0 locals=0
; CHECK-NEXT: aux 0.1: type=funcdata target= data=0100000000000000
; CHECK-NEXT: aux 0.2: type=funcdata target= data=0100000000000000
; CHECK-NEXT: aux 0.3: type=pcsp target=
; CHECK-NEXT: aux 0.4: type=pcfile target=
; CHECK-NEXT: aux 0.5: type=pcline target=
; CHECK-NEXT: aux 0.6: type=pcdata target= pc=
; CHECK-NEXT: aux 0.7: type=pcdata target= pc=
; CHECK-NEXT: reloc 0.0: off=3 size=4 type=14 add=0 target=g
; CHECK-NEXT: aux 1.8: type=funcinfo target= args=0 locals=8
; CHECK-NEXT: aux 1.9: type=funcdata target= data=0100000000000000
; CHECK-NEXT: aux 1.10: type=funcdata target= data=0100000000000000
; CHECK-NEXT: aux 1.11: type=pcsp target=
; CHECK-NEXT: aux 1.12: type=pcfile target=
; CHECK-NEXT: aux 1.13: type=pcline target=
; CHECK-NEXT: aux 1.14: type=pcdata target= pc=
; CHECK-NEXT: aux 1.15: type=pcdata target= pc=
; CHECK-NEXT: reloc 1.1: off=2 size=4 type=7 add=0 target=ext
