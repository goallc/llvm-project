; RUN: opt -passes=rpo-function-attrs -debug-pass-manager -disable-output %s 2>&1 | FileCheck %s --check-prefix=ANALYSIS
; RUN: opt -passes=rpo-function-attrs -S %s | FileCheck %s
;
; Public functions, unused internal definitions, and private definitions cannot
; enter the RPO attribute worklist, even when they form a shared reference graph.
; ANALYSIS: Running pass: ReversePostOrderFunctionAttrsPass
; ANALYSIS-NOT: Running analysis: LazyCallGraphAnalysis
; ANALYSIS: Running pass: VerifierPass

@refs = global [2 x ptr] [ptr @public, ptr @private_func]
declare void @external()

; CHECK-LABEL: define void @public()
define void @public() {
  call void @external()
  ret void
}

; CHECK-LABEL: define internal void @unused()
define internal void @unused() {
  ret void
}

; CHECK-LABEL: define private void @private_func()
define private void @private_func() {
  ret void
}
