; RUN: split-file %s %t
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/keep-decl.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=KEEP-DECL
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/marker-decl.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=MARKER-DECL
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/keep-target.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=KEEP-TARGET
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/marker-shape.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=MARKER-SHAPE
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/legacy.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=LEGACY
; KEEP-DECL: LLVM ERROR: !goobj.keep requires a definition
; MARKER-DECL: LLVM ERROR: !goobj.marker_relocs requires a definition
; KEEP-TARGET: LLVM ERROR: expected !goobj.keep symbol operands to be LLVM global references
; MARKER-SHAPE: LLVM ERROR: expected !goobj.marker_relocs entries to have three operands
; LEGACY: LLVM ERROR: GoObj keep/marker relations require definition attachments

;--- keep-decl.ll
@source = external global i8, !goobj.keep !0
@target = external global i8
!0 = !{ptr @target}
;--- marker-decl.ll
@source = external global i8, !goobj.marker_relocs !0
@target = external global i8
!0 = !{!1}
!1 = !{ptr @target, i32 23, i64 0}
;--- keep-target.ll
@source = global i8 0, !goobj.keep !0
!0 = !{i32 0}
;--- marker-shape.ll
@source = global i8 0, !goobj.marker_relocs !0
@target = external global i8
!0 = !{!1}
!1 = !{ptr @source, ptr @target, i32 23, i64 0}
;--- legacy.ll
@source = global i8 0
@target = external global i8
!goobj.keep = !{!0}
!0 = !{ptr @source, ptr @target}
