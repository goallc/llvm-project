; RUN: opt -module-summary %s -o %t.bc
; RUN: llvm-dis %t.bc -o - | FileCheck %s

declare void @llvm.go.defer.edge()

define i32 @defer_edge() {
entry:
  callbr void @llvm.go.defer.edge() to label %normal [label %recovered]
normal:
  ret i32 0
recovered:
  ret i32 1
}

; CHECK-LABEL: define i32 @defer_edge()
; CHECK: callbr void @llvm.go.defer.edge()
; CHECK: ^{{[0-9]+}} = gv: (name: "defer_edge", summaries: (function:
