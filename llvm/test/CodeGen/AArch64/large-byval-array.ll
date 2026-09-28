; RUN: llc -mtriple=aarch64-unknown-linux-gnu -global-isel=0 -O0 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -global-isel=0 -O2 -verify-machineinstrs < %s | FileCheck %s

; Checking whether array members need consecutive registers must not allocate
; one type entry per byte of a large byval argument, even when it is unused.
define i32 @large_array(ptr byval([1073741808 x i8]) align 1 %arg) {
; CHECK-LABEL: large_array:
; CHECK: mov w{{[0-9]+}}, #1
; CHECK: ret
  ret i32 1
}

define i32 @nested_array(ptr byval([2 x [536870904 x i8]]) align 1 %arg) {
; CHECK-LABEL: nested_array:
; CHECK: mov w{{[0-9]+}}, #2
; CHECK: ret
  ret i32 2
}

define goabiinternal i64 @go_large_array(ptr byval([1073741808 x i8]) align 1 %arg) {
; CHECK-LABEL: go_large_array:
; CHECK: mov w{{[0-9]+}}, #3
; CHECK: ret
  ret i64 3
}
