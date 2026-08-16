; RUN: not --crash llc -mtriple=x86_64-unknown-linux-gnu -filetype=null < %s 2>&1 \
; RUN:   | FileCheck %s
; RUN: not --crash llc -mtriple=aarch64-unknown-linux-gnu -filetype=null < %s 2>&1 \
; RUN:   | FileCheck %s

; A direct Go ABI value has no stack fallback. The frontend must use a typed
; byval carrier once a whole logical argument no longer fits in registers.
define goabiinternal void @direct_register_overflow(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6,
    i64 %a7, i64 %a8, i64 %a9, i64 %a10, i64 %a11, i64 %a12, i64 %a13,
    i64 %a14, i64 %a15, i64 %a16) {
entry:
  ret void
}

; CHECK: LLVM ERROR: unable to allocate function argument #
