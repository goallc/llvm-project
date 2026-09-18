; RUN: not llvm-as %s -o /dev/null 2>&1 | FileCheck %s

target datalayout = "e-p:32:32"

declare i64 @llvm.go.pointer.address.i64.p0(ptr)

define i64 @wrong_result_width(ptr %pointer) {
  %address = call i64 @llvm.go.pointer.address.i64.p0(ptr %pointer)
  ret i64 %address
}

; CHECK: llvm.go.pointer.address result must match the pointer width
