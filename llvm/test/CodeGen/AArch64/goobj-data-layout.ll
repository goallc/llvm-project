; RUN: llc -mtriple=aarch64-unknown-linux-goobj -stop-before=finalize-isel -o - %s | FileCheck %s

; CHECK: target datalayout = "{{.*}}-v128:64:64-{{.*}}-S128{{.*}}"
; CHECK: target triple = "aarch64-unknown-linux-goobj"

define void @f() {
  ret void
}
