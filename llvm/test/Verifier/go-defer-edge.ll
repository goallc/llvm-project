; RUN: split-file %s %t
; RUN: opt -passes=verify %t/valid.ll -disable-output
; RUN: not opt -passes=verify %t/ordinary-call.ll -disable-output 2>&1 | FileCheck %s --check-prefix=ORDINARY
; RUN: not opt -passes=verify %t/no-indirect-dest.ll -disable-output 2>&1 | FileCheck %s --check-prefix=NO-DEST
; RUN: not opt -passes=verify %t/multiple-indirect-dests.ll -disable-output 2>&1 | FileCheck %s --check-prefix=MULTIPLE-DESTS
; RUN: not opt -passes=verify %t/same-dest.ll -disable-output 2>&1 | FileCheck %s --check-prefix=SAME-DEST

;--- valid.ll
declare void @llvm.go.defer.edge()

define void @valid() {
entry:
  callbr void @llvm.go.defer.edge() to label %normal [label %recover]

normal:
  ret void

recover:
  ret void
}

;--- ordinary-call.ll
; ORDINARY: llvm.go.defer.edge must be used with callbr
declare void @llvm.go.defer.edge()

define void @ordinary_call() {
entry:
  call void @llvm.go.defer.edge()
  ret void
}

;--- no-indirect-dest.ll
; NO-DEST: llvm.go.defer.edge callbr must have exactly one indirect destination
declare void @llvm.go.defer.edge()

define void @no_indirect_dest() {
entry:
  callbr void @llvm.go.defer.edge() to label %normal []

normal:
  ret void
}

;--- multiple-indirect-dests.ll
; MULTIPLE-DESTS: llvm.go.defer.edge callbr must have exactly one indirect destination
declare void @llvm.go.defer.edge()

define void @multiple_indirect_dests() {
entry:
  callbr void @llvm.go.defer.edge() to label %normal [label %recover1, label %recover2]

normal:
  ret void

recover1:
  ret void

recover2:
  ret void
}

;--- same-dest.ll
; SAME-DEST: llvm.go.defer.edge callbr destinations must be distinct
declare void @llvm.go.defer.edge()

define void @same_dest() {
entry:
  callbr void @llvm.go.defer.edge() to label %dest [label %dest]

dest:
  ret void
}
