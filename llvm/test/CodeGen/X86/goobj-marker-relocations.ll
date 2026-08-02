; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.opt.o | FileCheck %s

@target = constant i8 0, section ".rodata", align 1
@init_source = global [8 x i8] zeroinitializer, section ".noptrdata", align 8
@init_target = external global i8
@llvm.compiler.used = appending global [4 x ptr] [ptr @source, ptr @target, ptr @init_source, ptr @init_target], section "llvm.metadata"

define goabiinternal void @source() {
  ret void
}

!goobj.marker_relocs = !{!0, !1, !2}
!0 = !{ptr @source, ptr @target, i32 23, i64 0}
!1 = !{ptr @source, ptr @target, i32 24, i64 96}
!2 = !{ptr @init_source, ptr @init_target, i32 102, i64 0}

; CHECK: symdef {{[0-9]+}}: source abi=1 type=1
; CHECK: symdef {{[0-9]+}}: init_source abi=0 type=5
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=23 add=0 target=target
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=24 add=96 target=target
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=102 add=0 target=init_target
