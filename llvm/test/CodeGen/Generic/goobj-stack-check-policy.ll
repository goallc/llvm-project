; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=aarch64-apple-darwin-goobj < %s | \
; RUN:   FileCheck %s --check-prefix=A64-ASM
; RUN: llc -mtriple=x86_64-unknown-linux-goobj < %s | \
; RUN:   FileCheck %s --check-prefix=X86-ASM

declare goabiinternal void @callee()
declare goabiinternal void @runtime.panicdivide()

define goabiinternal void @zero_frame_leaf() "frame-pointer"="non-leaf" {
entry:
  ret void
}

define goabiinternal void @small_frame_leaf() "frame-pointer"="non-leaf" {
entry:
  %buf = alloca [64 x i8], align 8
  %slot = getelementptr inbounds [64 x i8], ptr %buf, i64 0, i64 63
  store volatile i8 1, ptr %slot, align 1
  ret void
}

define goabiinternal void @large_frame_leaf() "frame-pointer"="non-leaf" {
entry:
  %buf = alloca [256 x i8], align 8
  %slot = getelementptr inbounds [256 x i8], ptr %buf, i64 0, i64 255
  store volatile i8 1, ptr %slot, align 1
  ret void
}

define goabiinternal void @small_frame_non_leaf() "frame-pointer"="non-leaf" {
entry:
  call goabiinternal void @callee()
  ret void
}

define goabiinternal void @small_frame_x86_leaf_like_runtime_call()
    "frame-pointer"="non-leaf" {
entry:
  call goabiinternal void @runtime.panicdivide()
  ret void
}

define goabiinternal void @x86_leaf_like_runtime_call_at_limit()
    "frame-pointer"="non-leaf" {
entry:
  %buf = alloca [112 x i8], align 8
  %slot = getelementptr inbounds [112 x i8], ptr %buf, i64 0, i64 111
  store volatile i8 1, ptr %slot, align 1
  call goabiinternal void @runtime.panicdivide()
  ret void
}

define goabiinternal void @nosplit_large_non_leaf() "frame-pointer"="non-leaf"
    "go-nosplit" {
entry:
  %buf = alloca [256 x i8], align 8
  %slot = getelementptr inbounds [256 x i8], ptr %buf, i64 0, i64 255
  store volatile i8 1, ptr %slot, align 1
  call goabiinternal void @callee()
  ret void
}

; Entry maps remain present even when the native-Go leaf policy elides the
; stack-growth prologue.
; MIR-LABEL: name: zero_frame_leaf
; MIR: STACKMAP 5147419139155979380, 0
; MIR-NOT: runtime.morestack
; MIR-LABEL: name: small_frame_leaf
; MIR: STACKMAP 5147419139155979380, 0
; MIR-NOT: runtime.morestack

; A leaf frame at or above StackSmall and any non-leaf function still get a
; stack-growth edge by default.
; MIR-LABEL: name: large_frame_leaf
; MIR: runtime.morestack_noctxt
; MIR: STACKMAP 5147419139155979380, 0
; MIR-LABEL: name: small_frame_non_leaf
; MIR: runtime.morestack_noctxt
; MIR: STACKMAP 5147419139155979380, 0

; The explicit source policy remains the unconditional opt-out.
; MIR-LABEL: name: nosplit_large_non_leaf
; MIR: STACKMAP 5147419139155979380, 0
; MIR-NOT: runtime.morestack

; On AArch64 a zero-frame leaf starts directly with its original RET: no
; eight-instruction (32-byte) stack-growth sequence precedes it.
; A64-ASM-LABEL: zero_frame_leaf:
; A64-ASM-NOT: runtime.morestack
; A64-ASM: ret
; A64-ASM-LABEL: small_frame_leaf:
; A64-ASM-NOT: runtime.morestack
; A64-ASM: ret
; A64-ASM-LABEL: large_frame_leaf:
; A64-ASM: bl "runtime.morestack_noctxt<ABI0>"
; A64-ASM-LABEL: small_frame_non_leaf:
; A64-ASM: bl "runtime.morestack_noctxt<ABI0>"
; A64-ASM-LABEL: small_frame_x86_leaf_like_runtime_call:
; A64-ASM: bl "runtime.morestack_noctxt<ABI0>"
; A64-ASM-LABEL: x86_leaf_like_runtime_call_at_limit:
; A64-ASM: bl "runtime.morestack_noctxt<ABI0>"
; A64-ASM-LABEL: nosplit_large_non_leaf:
; A64-ASM-NOT: runtime.morestack
; A64-ASM: bl callee

; X86-ASM-LABEL: zero_frame_leaf:
; X86-ASM-NOT: runtime.morestack
; X86-ASM: retq
; X86-ASM-LABEL: small_frame_leaf:
; X86-ASM-NOT: runtime.morestack
; X86-ASM: retq
; X86-ASM-LABEL: large_frame_leaf:
; X86-ASM: callq "runtime.morestack_noctxt<ABI0>"
; X86-ASM-LABEL: small_frame_non_leaf:
; X86-ASM: callq "runtime.morestack_noctxt<ABI0>"
; X86-ASM-LABEL: small_frame_x86_leaf_like_runtime_call:
; X86-ASM-NOT: runtime.morestack
; X86-ASM: callq runtime.panicdivide
; X86-ASM-LABEL: x86_leaf_like_runtime_call_at_limit:
; X86-ASM: callq "runtime.morestack_noctxt<ABI0>"
; X86-ASM-LABEL: nosplit_large_non_leaf:
; X86-ASM-NOT: runtime.morestack
; X86-ASM: callq callee
