; RUN: not llvm-as %s -o /dev/null 2>&1 | FileCheck %s

target datalayout = "e-p:32:32"

declare ptr @llvm.go.pointer.from.address.p0.i64(i64)

define ptr @wrong_address_width(i64 %address) {
  %pointer = call ptr @llvm.go.pointer.from.address.p0.i64(i64 %address)
  ret ptr %pointer
}

; CHECK: llvm.go.pointer.from.address operand must match the pointer width
