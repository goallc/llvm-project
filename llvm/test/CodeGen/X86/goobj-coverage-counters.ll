; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

; The Go linker must identify and aggregate counters into runtime.covctrs.
; Ordinary no-pointer BSS must retain its distinct symbol kind.
@counter = global [4 x i32] zeroinitializer, section ".noptrbss.coverage_counter", align 4
@ordinary = global [4 x i32] zeroinitializer, section ".noptrbss", align 4

; CHECK-DAG: counter abi=0 type=23
; CHECK-DAG: ordinary abi=0 type=10
