; RUN: split-file %s %t
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj \
; RUN:   -o /dev/null %t/unsuffixed.ll 2>&1 | FileCheck %s --check-prefix=MISMATCH
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj \
; RUN:   -o /dev/null %t/internal-suffix.ll 2>&1 | FileCheck %s --check-prefix=MISMATCH
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj \
; RUN:   -o /dev/null %t/obsolete-metadata.ll 2>&1 | FileCheck %s --check-prefix=METADATA

; MISMATCH: LLVM ERROR: Go ABI0 calling convention and <ABI0> symbol suffix disagree
; METADATA: LLVM ERROR: !goobj.symbol.name is obsolete; encode ABI0 in the symbol name

;--- unsuffixed.ll
define goabi0 void @missing_suffix() {
  ret void
}

;--- internal-suffix.ll
define goabiinternal void @"wrong_suffix<ABI0>"() {
  ret void
}

;--- obsolete-metadata.ll
define goabiinternal void @obsolete_metadata() !goobj.symbol.name !0 {
  ret void
}

!0 = !{!"other_name"}

; REQUIRES: x86-registered-target
