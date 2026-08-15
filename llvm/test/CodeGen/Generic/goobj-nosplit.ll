; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s --check-prefixes=CHECK,A64
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -filetype=obj -o %t.a64.o %s
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.x86.o %s

declare goabiinternal void @callee(ptr)
declare token @llvm.call.preallocated.setup(i32)
declare ptr @llvm.call.preallocated.arg(token, i32)
declare goabi0 void @"callee.abi0<ABI0>"(
    ptr preallocated(ptr) align 8)

define goabiinternal void @nosplit(ptr %pointer) "go-nosplit" {
entry:
  %slot = alloca ptr, align 8
  store volatile ptr %pointer, ptr %slot, align 8
  call goabiinternal void @callee(ptr %pointer)
  ret void
}

define goabiinternal void @split(ptr %pointer) {
entry:
  %slot = alloca ptr, align 8
  store volatile ptr %pointer, ptr %slot, align 8
  call goabiinternal void @callee(ptr %pointer)
  ret void
}

define goabiinternal void @nosplit_abi0_call(ptr %pointer) "go-nosplit" {
entry:
  %closure = alloca [3 x ptr], align 8
  %code = getelementptr [3 x ptr], ptr %closure, i64 0, i64 0
  %context = getelementptr [3 x ptr], ptr %closure, i64 0, i64 1
  store volatile ptr @callee, ptr %code, align 8
  store volatile ptr %pointer, ptr %context, align 8
  %setup = call token @llvm.call.preallocated.setup(i32 1)
  %argument = call ptr @llvm.call.preallocated.arg(token %setup, i32 0)
      preallocated(ptr)
  store ptr %closure, ptr %argument, align 8
  call goabi0 void @"callee.abi0<ABI0>"(
      ptr preallocated(ptr) align 8 %argument)
      ["preallocated"(token %setup)]
  ret void
}

; CHECK-LABEL: name: nosplit
; CHECK: STACKMAP 5147419139155979380, 0
; CHECK-NOT: STATEPOINT
; CHECK-NOT: runtime.morestack
; CHECK-LABEL: name: split
; CHECK-DAG: STACKMAP 5147419139155979380, 0
; CHECK-DAG: runtime.morestack_noctxt

; A64-LABEL: name: nosplit_abi0_call
; A64: stackSize: 48
; A64: maxCallFrameSize: 16
