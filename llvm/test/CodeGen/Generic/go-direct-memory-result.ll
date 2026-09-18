; RUN: not --crash llc -mtriple=x86_64-unknown-linux-gnu -filetype=null < %s 2>&1 \
; RUN:   | FileCheck %s
; RUN: not --crash llc -mtriple=aarch64-unknown-linux-gnu -filetype=null < %s 2>&1 \
; RUN:   | FileCheck %s

; An array with more than one element is memory-assigned by Go's whole-value
; ABI rule even when its flattened LLVM pieces would fit in registers. Reject
; the direct form instead of silently selecting a different ABI.
define goabiinternal [2 x i64] @direct_memory_result() {
entry:
  ret [2 x i64] zeroinitializer
}

; CHECK: LLVM ERROR: Go result 0 is memory-assigned but uses a direct LLVM return; use goret
