; REQUIRES: aarch64-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s

declare goabiinternal void @"runtime.GC"()

define goabiinternal void @subword_homes(i8 %a, i16 %b)
    "frame-pointer"="non-leaf" {
entry:
  call goabiinternal void @"runtime.GC"()
  ret void
}

define goabiinternal i64 @large_home_offset(
    ptr preallocated([4096 x i64]) align 8 %stackarg, i64 %regarg)
    "frame-pointer"="non-leaf" {
entry:
  call goabiinternal void @"runtime.GC"()
  ret i64 %regarg
}

define goabiinternal i64 @large_home_boundary(
    ptr preallocated([4094 x i64]) align 8 %stackarg, i64 %regarg)
    "frame-pointer"="non-leaf" {
entry:
  call goabiinternal void @"runtime.GC"()
  ret i64 %regarg
}

; CHECK-LABEL: name: subword_homes
; CHECK: fixedStack:
; CHECK-DAG: offset: 10, size: 2
; CHECK-DAG: offset: 8, size: 1
; CHECK: STRBBui $w0, $sp, 8
; CHECK-NEXT: STRHHui $w1, $sp, 5
; CHECK: BL &"runtime.morestack_noctxt<ABI0>"
; CHECK: $w0 = LDRBBui $sp, 8
; CHECK-NEXT: $w1 = LDRHHui $sp, 5

; CHECK-LABEL: name: large_home_offset
; CHECK: offset: 32776, size: 8
; CHECK: $x27 = ADDXri $sp, 16, 0
; CHECK-NEXT: STRXui $x0, $x27, 4095
; CHECK: BL &"runtime.morestack_noctxt<ABI0>"
; CHECK: $x27 = ADDXri $sp, 16, 0
; CHECK-NEXT: $x0 = LDRXui $x27, 4095

; CHECK-LABEL: name: large_home_boundary
; CHECK: offset: 32760, size: 8
; CHECK: STRXui $x0, $sp, 4095
; CHECK: BL &"runtime.morestack_noctxt<ABI0>"
; CHECK: $x0 = LDRXui $sp, 4095
