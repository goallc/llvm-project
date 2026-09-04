; RUN: opt -passes="ipsccp<func-spec>" -funcspec-min-function-size=3 -S < %s | FileCheck %s

define i64 @caller(i64 %x, i1 %flag) {
entry:
  br i1 %flag, label %plus, label %minus

plus:
  %plus.result = call i64 @compute(i64 %x, ptr @plus.one)
  br label %merge

minus:
  %minus.result = call i64 @compute(i64 %x, ptr @minus.one)
  br label %merge

merge:
  %result = phi i64 [ %plus.result, %plus ], [ %minus.result, %minus ]
  ret i64 %result
}

; Neither frontend-definition metadata attachment is valid on optimizer-created
; specializations. In particular, later argument elimination may change their
; signatures, making an inherited semantic argument description stale.
; CHECK-LABEL: define internal i64 @compute.specialized.1(i64 %x, ptr %binop) {
; CHECK-LABEL: define internal i64 @compute.specialized.2(i64 %x, ptr %binop) {
define internal i64 @compute(i64 %x, ptr %binop) !goobj.symbol.index !0 !goobj.func.arginfo !1 {
entry:
  %result = call i64 %binop(i64 %x)
  ret i64 %result
}

define internal i64 @plus.one(i64 %x) {
entry:
  %result = add i64 %x, 1
  ret i64 %result
}

define internal i64 @minus.one(i64 %x) {
entry:
  %result = sub i64 %x, 1
  ret i64 %result
}

!0 = !{i32 6}
!1 = !{ptr @compute, i64 16, i64 0, i64 0, i64 8, i64 8, i64 8}
