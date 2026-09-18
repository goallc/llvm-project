; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

module asm ".goobj.cgo \22[[\\\22cgo_import_static\\\22,\\\22external_c\\\22]]\22"

define goabi0 void @"same<ABI0>"() {
entry:
  ret void
}

define goabiinternal void @same() {
entry:
  call goabi0 void @"same<ABI0>"()
  ret void
}

define goabi0 void @"suffix_only<ABI0>"() {
entry:
  ret void
}

declare goabi0 void @"external_abi0<ABI0>"()
declare goabiinternal void @external_internal()

@abi0_function_ptr = global ptr @"external_abi0<ABI0>"
@internal_function_ptr = global ptr @external_internal
@external_c = global i8 0, !goobj.symbol.nonpackage !1
@external_c_ptr = global ptr @external_c

; CHECK: header: {{.*}}cgo_import_static{{.*}}external_c
; CHECK: symdef 0: same abi=0 type=1
; CHECK-NEXT: symdef 1: same abi=1 type=1
; CHECK-NEXT: symdef 2: suffix_only abi=0 type=1
; CHECK-NEXT: symdef 3: abi0_function_ptr abi=0 type=7
; CHECK-NEXT: symdef 4: internal_function_ptr abi=0 type=7
; CHECK-NEXT: symdef 5: external_c_ptr abi=0 type=7
; CHECK: nonpkgdef 0: external_c abi=0 type=9
; CHECK: nonpkgref {{[0-9]+}}: external_abi0 abi=0 type=0
; CHECK: nonpkgref {{[0-9]+}}: external_internal abi=1 type=0
; CHECK: target=same
; CHECK: target=external_abi0
; CHECK: target=external_internal
; CHECK: target=external_c

!1 = !{i1 true}
