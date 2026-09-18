; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o /dev/null %s 2>&1 | FileCheck %s
; RUN: not --crash llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o /dev/null %s 2>&1 | FileCheck %s

; A variable-sized alloca changes SP after the Go stack-growth check and cannot
; be described by the current GoObj frame and stack-map metadata. Reject it
; deterministically on both supported Go targets.

define goabiinternal void @dynamic_alloca(i64 %size) {
entry:
  %buf = alloca i8, i64 %size, align 16
  store volatile i8 1, ptr %buf, align 1
  ret void
}

; CHECK: LLVM ERROR: GoObj stack growth does not support dynamic allocas
