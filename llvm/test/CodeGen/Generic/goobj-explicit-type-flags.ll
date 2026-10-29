; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S %s -o %t.opt.ll
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.opt.ll -o %t.opt.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.opt.x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.opt.ll -o %t.opt.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.opt.arm64.o | FileCheck %s

; LLVM identified struct names do not carry Go object semantics. Explicit
; flags work equally on anonymous storage and do not depend on type spelling.
%go.descriptor.unflagged = type { i8 }
%go.itab.unflagged = type { i8 }
@ordinary_descriptor = constant %go.descriptor.unflagged { i8 1 }, section ".rodata", align 1
@ordinary_itab = constant %go.itab.unflagged { i8 2 }, section ".rodata", align 1
@descriptor = weak constant { i8 } { i8 3 }, section ".rodata", align 1, !goobj.symbol.flags !0
@itab = weak constant { i8 } { i8 4 }, section ".rodata", align 1, !goobj.symbol.flags !1
!0 = !{i8 64, i8 0}
!1 = !{i8 0, i8 2}

; CHECK-DAG: ordinary_descriptor abi=0 type=3 size=1 align=1 flag=0 flag2=0
; CHECK-DAG: ordinary_itab abi=0 type=3 size=1 align=1 flag=0 flag2=0
; CHECK-DAG: descriptor abi=0 type=3 size=1 align=1 flag=65 flag2=0
; CHECK-DAG: itab abi=0 type=3 size=1 align=1 flag=1 flag2=2
