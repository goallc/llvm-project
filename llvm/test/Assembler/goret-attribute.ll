; RUN: llvm-as < %s | llvm-dis | FileCheck %s

%stack.result = type { ptr, i64 }

; CHECK: define goabiinternal { i64, i64 } @roundtrip(
; CHECK-SAME: ptr goret(%stack.result) align 8 "goretindex"="1" %result1,
; CHECK-SAME: ptr goret(i32) align 4 "goretindex"="3" %result3)
define goabiinternal { i64, i64 } @roundtrip(
    ptr goret(%stack.result) "goretindex"="1" align 8 %result1,
    ptr goret(i32) "goretindex"="3" align 4 %result3) #0 {
  ret { i64, i64 } zeroinitializer
}

; CHECK: call goabiinternal { i64, i64 } @roundtrip(
; CHECK-SAME: ptr goret(%stack.result) align 8 "goretindex"="1" %result1,
; CHECK-SAME: ptr goret(i32) align 4 "goretindex"="3" %result3)
define goabiinternal void @roundtrip_callsite() {
entry:
  %result1 = alloca %stack.result, align 8
  %result3 = alloca i32, align 4
  %direct = call goabiinternal { i64, i64 } @roundtrip(
      ptr goret(%stack.result) "goretindex"="1" align 8 %result1,
      ptr goret(i32) "goretindex"="3" align 4 %result3) #0
  ret void
}

attributes #0 = { "go_results_tuple" }
