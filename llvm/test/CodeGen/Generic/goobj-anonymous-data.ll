; REQUIRES: x86-registered-target, aarch64-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S %s -o %t.opt.ll
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.opt.ll -o %t.x86.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.opt.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.opt.ll -o %t.arm64.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.opt.o | FileCheck %s

; Both indexed and non-package anonymous definitions retain their own data
; and relocation identities. An unmarked name must not be treated as anonymous.
@package_handle = internal constant [4 x i8] c"Read", section ".rodata", !goobj.symbol.anonymous !0, !goobj.symbol.index !1
@shared_handle = internal constant [5 x i8] c"Write", section ".rodata", !goobj.symbol.anonymous !0, !goobj.symbol.nonpackage !0
@.goallc.anon.7 = constant i8 42, section ".rodata"
@refs = global [2 x ptr] [ptr @package_handle, ptr @shared_handle], section ".data"
@llvm.compiler.used = appending global [3 x ptr] [ptr @source, ptr @package_handle, ptr @shared_handle], section "llvm.metadata"

define goabiinternal void @source() {
  ret void
}

!goobj.marker_relocs = !{!2, !3}
!0 = !{i1 true}
!1 = !{i32 0}
!2 = !{ptr @source, ptr @package_handle, i32 25, i64 0}
!3 = !{ptr @source, ptr @shared_handle, i32 25, i64 0}

; CHECK: symdef 0:  abi=0 type=3 size=4
; CHECK: symdef {{[0-9]+}}: .goallc.anon.7 abi=0 type=3 size=1
; CHECK: nonpkgdef [[SHARED:[0-9]+]]:  abi=0 type=3 size=5
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=25 add=0 target= kind=unknown pkg=self sym=0
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=25 add=0 target= kind=unknown pkg=none sym=[[SHARED]]
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=8 type=1 add=0 target= kind=R_ADDR pkg=self sym=0
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=8 size=8 type=1 add=0 target= kind=R_ADDR pkg=none sym=[[SHARED]]
