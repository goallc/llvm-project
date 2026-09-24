; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=example/pkg -filetype=obj < %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -goobj-package-path=example/pkg -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

@target1 = external global i8
@target2 = external global i8
@before = internal constant i64 42, section ".rodata", align 8
@.table = private unnamed_addr constant [2 x ptr] [ptr @target1, ptr @target2], section ".rodata", align 8
@after = internal constant i64 84, section ".rodata", align 8
@assembly_map = hidden constant i64 1, section ".rodata", !goobj.symbol.flags !0
@shared_local = weak hidden constant i64 2, section ".rodata", !goobj.symbol.flags !0
; STATIC and LOCAL are independent. In particular, writable static data must
; not acquire LOCAL, which prevents the Go linker from sharing it in plugins.
@static_data = internal global ptr @target1, section ".data", align 8
@static_local = internal global ptr @target2, section ".data", align 8, !goobj.symbol.flags !0
!0 = !{i32 2, i32 0}

define goabiinternal ptr @private_table_address() {
entry:
  ret ptr @.table
}

define goabiinternal double @constant_pool_load(double %x) {
entry:
  %sum = fadd double %x, 3.141592e+00
  ret double %sum
}

; CHECK-DAG: symdef [[POOL:[0-9]+]]: goallc.{{[0-9a-f]+}}.stmp_{{[0-9]+}} abi=65535 type=3 size=8 align={{[0-9]+}} flag=2 flag2=0
; CHECK-DAG: symdef [[TABLE:[0-9]+]]: goallc.{{[0-9a-f]+}}.stmp_{{[0-9]+}} abi=65535 type=3 size=16 align={{[0-9]+}} flag=2 flag2=0
; CHECK-DAG: symdef {{[0-9]+}}: before abi=65535 type=3
; CHECK-DAG: symdef {{[0-9]+}}: after abi=65535 type=3
; CHECK-DAG: symdef {{[0-9]+}}: assembly_map abi=0 type=3 size=8 align={{[0-9]+}} flag=2
; CHECK-DAG: symdef {{[0-9]+}}: shared_local abi=0 type=3 size=8 align={{[0-9]+}} flag=3
; CHECK-DAG: symdef [[STATIC:[0-9]+]]: static_data abi=65535 type=7 size=8 align=8 flag=0 flag2=0
; CHECK-DAG: symdef {{[0-9]+}}: static_local abi=65535 type=7 size=8 align=8 flag=2 flag2=0
; CHECK-DAG: reloc [[STATIC]].{{[0-9]+}}: off=0 size=8 type=1 add=0 target=target1
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size={{[0-9]+}} type={{[0-9]+}} add=0 target=goallc.{{[0-9a-f]+}}.stmp_{{[0-9]+}} kind=unknown pkg=self sym=[[POOL]]
; CHECK-DAG: reloc [[TABLE]].{{[0-9]+}}: off=0 size=8 type=1 add=0 target=target1
; CHECK-DAG: reloc [[TABLE]].{{[0-9]+}}: off=8 size=8 type=1 add=0 target=target2
