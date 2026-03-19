; RUN: llvm-as < %s | llvm-dis | FileCheck %s

; CHECK: declare gocc i64 @go_decl(i64)
declare gocc i64 @go_decl(i64)

; CHECK: define gocc i64 @go_def(i64 %x)
define gocc i64 @go_def(i64 %x) {
  ret i64 %x
}
