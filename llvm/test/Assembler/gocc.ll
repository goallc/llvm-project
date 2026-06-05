; RUN: llvm-as < %s | llvm-dis | FileCheck %s

declare gocc { i64, [2 x i64] } @tuple_decl(i64, i64, i64) #0

define gocc { i64, [2 x i64] } @tuple_call(i64 %a, i64 %b, i64 %c) #0 {
entry:
  %ret = call gocc { i64, [2 x i64] } @tuple_decl(i64 %a, i64 %b, i64 %c)
  ret { i64, [2 x i64] } %ret
}

; CHECK: declare gocc { i64, [2 x i64] } @tuple_decl(i64, i64, i64) #[[ATTR:[0-9]+]]
; CHECK: define gocc { i64, [2 x i64] } @tuple_call(i64 %a, i64 %b, i64 %c) #[[ATTR]] {
; CHECK: %ret = call gocc { i64, [2 x i64] } @tuple_decl(i64 %a, i64 %b, i64 %c)
; CHECK: attributes #[[ATTR]] = { "go_results_tuple" }

attributes #0 = { "go_results_tuple" }
