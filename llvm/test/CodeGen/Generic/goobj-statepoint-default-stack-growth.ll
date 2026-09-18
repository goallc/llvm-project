; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog -o - %s | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog -o - %s | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.x86.o %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o %t.a64.o %s

; GoObj Go functions use stack growth by default. An ordinary statepoint does
; not need a second frontend attribute to make the target synthesize the late
; ABI0 morestack call and the function-level entry-args stack map.

declare goabiinternal void @callee()

define goabiinternal void @default_stack_growth() "frame-pointer"="non-leaf"
    gc "statepoint-example" {
entry:
  call goabiinternal token (i64, i32, ptr, i32, i32, ...)
    @llvm.experimental.gc.statepoint.p0(
      i64 0, i32 0, ptr elementtype(void ()) @callee, i32 0, i32 0,
      i32 0, i32 0)
  ret void
}

declare token @llvm.experimental.gc.statepoint.p0(
  i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)

; CHECK-LABEL: name: default_stack_growth
; CHECK-DAG: STACKMAP 5147419139155979380, 0
; CHECK-DAG: runtime.morestack_noctxt<ABI0>
; CHECK-DAG: STATEPOINT 0, 0, 0, @callee
