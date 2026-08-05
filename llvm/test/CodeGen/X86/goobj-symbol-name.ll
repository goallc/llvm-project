; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

define goabi0 void @"same.goallc.abi0"() !goobj.symbol.name !0 {
entry:
  ret void
}

define goabiinternal void @same() {
entry:
  call goabi0 void @"same.goallc.abi0"()
  ret void
}

@external_c = global i8 0, !goobj.symbol.nonpackage !1
@external_c_ptr = global ptr @external_c

; CHECK: header: {{.*}}cgo_import_static{{.*}}external_c
; CHECK: symdef 0: same abi=0 type=1
; CHECK-NEXT: symdef 1: same abi=1 type=1
; CHECK-NEXT: symdef 2: external_c_ptr abi=0 type=7
; CHECK: nonpkgdef 0: external_c abi=0 type=9
; CHECK: target=same
; CHECK: target=external_c

!goobj.cgo = !{!2}
!0 = !{!"same"}
!1 = !{i1 true}
!2 = !{!"[[\22cgo_import_static\22,\22external_c\22]]"}
