; RUN: split-file %s %t
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/declaration.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=DECLARATION
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/duplicate.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=DUPLICATE
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/too-large.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=TOO-LARGE

;--- declaration.ll
declare !goobj.symbol.index !0 goabiinternal void @external()
!0 = !{i32 0}

; DECLARATION: LLVM ERROR: invalid !goobj.symbol.index attachment

;--- duplicate.ll
define goabiinternal void @first() !goobj.symbol.index !0 {
  ret void
}
define goabiinternal void @second() !goobj.symbol.index !0 {
  ret void
}
!0 = !{i32 0}

; DUPLICATE: LLVM ERROR: duplicate GoObj package symbol index

;--- too-large.ll
define goabiinternal void @f() !goobj.symbol.index !0 {
  ret void
}
!0 = !{i32 -1}

; TOO-LARGE: LLVM ERROR: GoObj package symbol index is too large
