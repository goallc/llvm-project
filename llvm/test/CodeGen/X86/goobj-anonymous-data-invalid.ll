; RUN: split-file %s %t
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/declaration.ll -o /dev/null 2>&1 | FileCheck %s
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/function.ll -o /dev/null 2>&1 | FileCheck %s
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/false.ll -o /dev/null 2>&1 | FileCheck %s

; CHECK: LLVM ERROR: invalid !goobj.symbol.anonymous attachment

;--- declaration.ll
@external = external global i8, !goobj.symbol.anonymous !0
!0 = !{i1 true}

;--- function.ll
define goabiinternal void @f() !goobj.symbol.anonymous !0 {
  ret void
}
!0 = !{i1 true}

;--- false.ll
@data = global i8 0, !goobj.symbol.anonymous !0
!0 = !{i1 false}
