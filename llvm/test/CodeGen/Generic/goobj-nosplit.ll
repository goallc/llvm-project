; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s --check-prefixes=CHECK,A64
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s

declare goabiinternal void @callee(ptr)
declare goabi0 void @callee.abi0(ptr)

define goabiinternal void @nosplit(ptr %pointer) "go-nosplit"
    "go-stack-growth-statepoint" {
entry:
  %slot = alloca ptr, align 8
  store volatile ptr %pointer, ptr %slot, align 8
  call goabiinternal void @callee(ptr %pointer)
  ret void
}

define goabiinternal void @split(ptr %pointer)
    "go-stack-growth-statepoint" {
entry:
  %slot = alloca ptr, align 8
  store volatile ptr %pointer, ptr %slot, align 8
  call goabiinternal void @callee(ptr %pointer)
  ret void
}

define goabiinternal void @nosplit_abi0_call(ptr %pointer) "go-nosplit"
    "go-stack-growth-statepoint" {
entry:
  %closure = alloca [3 x ptr], align 8
  %code = getelementptr [3 x ptr], ptr %closure, i64 0, i64 0
  %context = getelementptr [3 x ptr], ptr %closure, i64 0, i64 1
  store volatile ptr @callee, ptr %code, align 8
  store volatile ptr %pointer, ptr %context, align 8
  call goabi0 void @callee.abi0(ptr %closure)
  ret void
}

; CHECK-LABEL: name: nosplit
; CHECK: STACKMAP
; CHECK-NOT: runtime.morestack
; CHECK-LABEL: name: split
; CHECK: runtime.morestack_noctxt

; A64-LABEL: name: nosplit_abi0_call
; A64: stackSize: 48
; A64: maxCallFrameSize: 16
