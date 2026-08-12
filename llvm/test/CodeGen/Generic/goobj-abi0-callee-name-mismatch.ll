; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj \
; RUN:   -o /dev/null %s 2>&1 | FileCheck %s
; RUN: not --crash llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj \
; RUN:   -o /dev/null %s 2>&1 | FileCheck %s

; A late stack-growth call resolves its ABI0 declaration by the frontend's IR
; storage suffix. Reject metadata that would make that declaration name a
; different linker-visible GoObj symbol.

declare !goobj.symbol.name !0 goabi0 void @runtime.morestack_noctxt.goallc.abi0()

define goabiinternal void @mismatched_morestack_name()
    "go-stack-growth-statepoint" {
entry:
  %frame = alloca [5000 x i8], align 8
  store volatile i8 1, ptr %frame, align 8
  ret void
}

; CHECK: LLVM ERROR: Go ABI0 storage name and GoObj symbol name metadata
; CHECK-SAME: disagree for runtime.morestack_noctxt

!0 = !{!"runtime.not_morestack"}

; REQUIRES: aarch64-registered-target, x86-registered-target
