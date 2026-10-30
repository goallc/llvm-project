; RUN: split-file %s %t
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/data.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=SOURCE
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/declaration.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=SOURCE
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/target.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=TARGET
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/legacy.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=LEGACY
; SOURCE: LLVM ERROR: !goobj.weak_calls requires a function definition
; TARGET: LLVM ERROR: !goobj.weak_calls requires function targets
; LEGACY: LLVM ERROR: GoObj weak calls require definition attachments

;--- data.ll
@data = global i8 0, !goobj.weak_calls !0
declare goabiinternal void @callee()
!0 = !{ptr @callee}

;--- declaration.ll
declare !goobj.weak_calls !0 goabiinternal void @caller()
declare goabiinternal void @callee()
!0 = !{ptr @callee}

;--- target.ll
@data = external global i8
define goabiinternal void @caller() !goobj.weak_calls !0 { ret void }
!0 = !{ptr @data}

;--- legacy.ll
define goabiinternal void @caller() { ret void }
declare goabiinternal void @callee()
!goobj.weak_calls = !{!0}
!0 = !{ptr @caller, ptr @callee}
