; RUN: split-file %s %t
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/declaration.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=DECLARATION
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/data.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=DATA
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/malformed.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=MALFORMED
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/conflicting.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=CONFLICTING

;--- declaration.ll
declare goabiinternal void @"source<goallc.fmv.baseline>"()
define goabiinternal void @caller() {
  call goabiinternal void @"source<goallc.fmv.baseline>"()
  ret void
}

; DECLARATION: LLVM ERROR: Go FMV suffix requires a defined function symbol

;--- data.ll
@"source<goallc.fmv.baseline>" = global i8 0

; DATA: LLVM ERROR: Go FMV suffix requires a function symbol

;--- malformed.ll
define goabiinternal void @"source<goallc.fmv.>"() {
  ret void
}

; MALFORMED: LLVM ERROR: invalid Go FMV implementation symbol name

;--- conflicting.ll
define goabiinternal void @"source<linkname><goallc.fmv.baseline>"() {
  ret void
}

; CONFLICTING: LLVM ERROR: conflicting Go FMV implementation symbol identity
