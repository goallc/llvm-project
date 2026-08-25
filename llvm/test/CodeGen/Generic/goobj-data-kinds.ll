; REQUIRES: aarch64-registered-target
; REQUIRES: x86-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.amd64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.amd64.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=aarch64-apple-darwin-goobj -filetype=obj -o %t.arm64.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.opt.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.amd64.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.amd64.opt.o | FileCheck %s
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -filetype=asm < %s | FileCheck %s --check-prefix=ASM

@rodata = constant i64 1, section ".rodata", align 8
@noptrdata = global i64 2, section ".noptrdata", align 8
@data = global ptr @noptrdata, section ".data", align 8
@bss = global ptr null, section ".bss", align 8
@noptrbss = global i64 0, section ".noptrbss", align 8

@fips_rodata = constant i64 3, section ".rodata.fips", align 8
@fips_noptrdata = global i64 4, section ".noptrdata.fips", align 8
@fips_data = global i64 5, section ".data.fips", align 8

@before = internal constant i64 6, section ".rodata", align 8
@.switch.table = private unnamed_addr constant [4 x i64] [i64 11, i64 22, i64 33, i64 44], section ".rodata", align 8
@after = internal constant i64 7, section ".rodata", align 8

define goabiinternal i64 @fips_text(i64 %index) section ".text.fips" {
entry:
  %slot = getelementptr inbounds [4 x i64], ptr @.switch.table, i64 0, i64 %index
  %value = load i64, ptr %slot, align 8
  ret i64 %value
}

define goabiinternal void @ordinary_text() {
entry:
  ret void
}

; CHECK-DAG: symdef {{[0-9]+}}: rodata abi=0 type=3 size=8 align=8
; CHECK-DAG: symdef {{[0-9]+}}: noptrdata abi=0 type=5 size=8 align=8
; CHECK-DAG: symdef {{[0-9]+}}: data abi=0 type=7 size=8 align=8
; CHECK-DAG: symdef {{[0-9]+}}: bss abi=0 type=9 size=8 align=8
; CHECK-DAG: symdef {{[0-9]+}}: noptrbss abi=0 type=10 size=8 align=8
; CHECK-DAG: symdef {{[0-9]+}}: fips_text abi=1 type=2
; CHECK-DAG: symdef {{[0-9]+}}: fips_rodata abi=0 type=4 size=8 align=8
; CHECK-DAG: symdef {{[0-9]+}}: fips_noptrdata abi=0 type=6 size=8 align=8
; CHECK-DAG: symdef {{[0-9]+}}: fips_data abi=0 type=8 size=8 align=8
; CHECK-DAG: symdef {{[0-9]+}}: ordinary_text abi=1 type=1
; CHECK-DAG: symdef [[TABLE:[0-9]+]]: goallc.{{[0-9a-f]+}}.stmp_{{[0-9]+}} abi=65535 type=4 size=32 align={{[0-9]+}} flag=2 flag2=0
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size={{[0-9]+}} type={{[0-9]+}} add=0 target=goallc.{{[0-9a-f]+}}.stmp_{{[0-9]+}} kind=unknown pkg=self sym=[[TABLE]]
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=8 type=1 add=0 target=noptrdata
; ASM: .section .noptrbss,"aw",@nobits

!goobj.static_rodata_type = !{!0}
!0 = !{i8 4}
