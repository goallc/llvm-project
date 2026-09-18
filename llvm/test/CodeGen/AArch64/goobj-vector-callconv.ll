; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s

declare goabi0 void @"runtime.morestack_noctxt<builtin.246><ABI0>"()

define goabiinternal <16 x i8> @vector_morestack_call(<16 x i8> %value)
    "frame-pointer"="non-leaf" {
entry:
  %buf = alloca [8192 x i8], align 16
  %slot = getelementptr inbounds [8192 x i8], ptr %buf, i64 0, i64 8191
  store volatile i8 1, ptr %slot, align 1
  ret <16 x i8> %value
}

; The Go home starts at entry SP+8 and is deliberately only 8-byte aligned.
; Materialize that address before the 128-bit spill/reload.
; CHECK-LABEL: name: vector_morestack_call
; CHECK: $x27 = ADDXri $sp, 8, 0
; CHECK-NEXT: STRQui $q0, $x27, 0
; CHECK: BL &"runtime.morestack_noctxt<builtin.246><ABI0>"
; CHECK: $x27 = ADDXri $sp, 8, 0
; CHECK-NEXT: $q0 = LDRQui $x27, 0
; CHECK: RET_ReallyLR implicit $q0
