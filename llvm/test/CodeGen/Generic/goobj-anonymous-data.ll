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

; Private data uses existing static carriers, including when the only reference
; is a Go linker marker, keep edge, or gotype auxiliary (no ordinary MC fixup).
; Indexed and non-package definitions must retain separate extents and indexes.
@package_handle = private constant [4 x i8] c"Read", section ".rodata", !goobj.symbol.index !1
@shared_handle = private constant [5 x i8] c"Write", section ".rodata", !goobj.symbol.nonpackage !0
@address_handle = private constant [6 x i8] c"Public", section ".rodata"
@keep_handle = private constant [7 x i8] c"KeepMe!", section ".rodata"
@type_handle = private constant [8 x i8] c"TypeData", section ".rodata"
@.goallc.anon.7 = constant i8 42, section ".rodata"
@refs = global ptr @address_handle, section ".data"
@llvm.compiler.used = appending global [5 x ptr] [ptr @source, ptr @package_handle, ptr @shared_handle, ptr @keep_handle, ptr @type_handle], section "llvm.metadata"

define goabiinternal void @source() {
  ret void
}

!goobj.marker_relocs = !{!2, !3}
!goobj.keep = !{!4}
!goobj.gotype = !{!5}
!0 = !{i1 true}
!1 = !{i32 0}
!2 = !{ptr @source, ptr @package_handle, i32 25, i64 0}
!3 = !{ptr @source, ptr @shared_handle, i32 25, i64 0}
!4 = !{ptr @source, ptr @keep_handle}
!5 = !{ptr @refs, ptr @type_handle}

; CHECK-DAG: symdef 0: [[PACKAGE:goallc\.[a-f0-9]+\.stmp_[0-9]+]] abi=65535 type=3 size=4
; CHECK-DAG: symdef [[ADDR:[0-9]+]]: [[ADDRESS:goallc\.[a-f0-9]+\.stmp_[0-9]+]] abi=65535 type=3 size=6
; CHECK-DAG: symdef [[KEEP:[0-9]+]]: [[KEEPNAME:goallc\.[a-f0-9]+\.stmp_[0-9]+]] abi=65535 type=3 size=7
; CHECK-DAG: symdef [[TYPE:[0-9]+]]: [[TYPENAME:goallc\.[a-f0-9]+\.stmp_[0-9]+]] abi=65535 type=3 size=8
; CHECK-DAG: symdef {{[0-9]+}}: .goallc.anon.7 abi=0 type=3 size=1
; CHECK: nonpkgdef [[SHARED:[0-9]+]]: [[SHAREDNAME:goallc\.[a-f0-9]+\.stmp_[0-9]+]] abi=65535 type=3 size=5
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=25 add=0 target=[[PACKAGE]] kind=unknown pkg=self sym=0
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=25 add=0 target=[[SHAREDNAME]] kind=unknown pkg=none sym=[[SHARED]]
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=27 add=0 target=[[KEEPNAME]] kind=unknown pkg=self sym=[[KEEP]]
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=8 type=1 add=0 target=[[ADDRESS]] kind=R_ADDR pkg=self sym=[[ADDR]]
; CHECK-DAG: aux {{[0-9]+}}.{{[0-9]+}}: type=gotype target=[[TYPENAME]] pkg=self sym=[[TYPE]]
