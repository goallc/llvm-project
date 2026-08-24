; RUN: llc -mtriple=x86_64-unknown-linux-goobj -stop-before=finalize-isel -o - %s | FileCheck %s

; CHECK: target datalayout = "{{.*}}-v128:64:64-{{.*}}-S64"
; CHECK: target triple = "x86_64-unknown-linux-goobj"

define void @f() {
  ret void
}
