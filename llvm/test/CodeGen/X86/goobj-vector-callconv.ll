; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s

declare goabi0 void @"runtime.morestack_noctxt<builtin.246><ABI0>"()

define goabiinternal <16 x i8> @vector_morestack_call(<16 x i8> %value) {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  ret <16 x i8> %value
}

; CHECK-LABEL: name: vector_morestack_call
; CHECK: MOVUPSmr $rsp, 1, $noreg, 8, $noreg, $xmm0
; CHECK: CALL64pcrel32 &"runtime.morestack_noctxt<builtin.246><ABI0>"
; CHECK: $xmm0 = MOVUPSrm $rsp, 1, $noreg, 8, $noreg
; CHECK: RET 0, $xmm0
