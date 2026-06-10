; RUN: llvm-as < %s | llvm-dis | FileCheck %s

declare goabiinternal { i64, [2 x i64] } @tuple_decl(i64, i64, i64) #0
declare goabi0 i64 @abi0_decl(i64, i64)

define goabiinternal { i64, [2 x i64] } @tuple_call(i64 %a, i64 %b, i64 %c) #0 {
entry:
  %ret = call goabiinternal { i64, [2 x i64] } @tuple_decl(i64 %a, i64 %b, i64 %c)
  ret { i64, [2 x i64] } %ret
}

define goabi0 i64 @abi0_call(i64 %a, i64 %b) {
entry:
  %ret = call goabi0 i64 @abi0_decl(i64 %a, i64 %b)
  ret i64 %ret
}

; CHECK: declare goabiinternal { i64, [2 x i64] } @tuple_decl(i64, i64, i64) #[[ATTR:[0-9]+]]
; CHECK: declare goabi0 i64 @abi0_decl(i64, i64)
; CHECK: define goabiinternal { i64, [2 x i64] } @tuple_call(i64 %a, i64 %b, i64 %c) #[[ATTR]] {
; CHECK: %ret = call goabiinternal { i64, [2 x i64] } @tuple_decl(i64 %a, i64 %b, i64 %c)
; CHECK: define goabi0 i64 @abi0_call(i64 %a, i64 %b) {
; CHECK: %ret = call goabi0 i64 @abi0_decl(i64 %a, i64 %b)
; CHECK: attributes #[[ATTR]] = { "go_results_tuple" }

attributes #0 = { "go_results_tuple" }
