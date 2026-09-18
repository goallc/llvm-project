; RUN: split-file %s %t
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/function-count.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=COUNT
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/global-range.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=RANGE

;--- function-count.ll
define goabiinternal void @f() !goobj.symbol.flags !0 {
  ret void
}
!0 = !{i32 32}

; COUNT: LLVM ERROR: expected !goobj.symbol.flags to have two operands

;--- global-range.ll
@data = constant i8 0, !goobj.symbol.flags !0
!0 = !{i32 256, i32 0}

; RANGE: LLVM ERROR: expected !goobj.symbol.flags operands to be i8
