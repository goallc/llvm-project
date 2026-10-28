; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: split-file %s %t
; RUN: llvm-link %t/weak.ll %t/strong.ll -o %t.forward.bc
; RUN: llvm-link %t/strong.ll %t/weak.ll -o %t.reverse.bc
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.forward.bc -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.reverse.bc -o %t.a64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.a64.o | FileCheck %s
; RUN: opt -passes='default<O2>' %t.forward.bc -o %t.opt.bc
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.opt.bc -o %t.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.opt.o | FileCheck %s
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/declaration.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=DECLARATION
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/invalid.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=INVALID

; The type belongs to the prevailing definition, not to the first input.
; CHECK: aux {{[0-9]+}}.{{[0-9]+}}: type=gotype target=type.strong
; CHECK-NOT: type=gotype target=type.weak
; DECLARATION: invalid !goobj.gotype attachment
; INVALID: invalid !goobj.gotype attachment

;--- weak.ll
@shared = weak global i64 1, section ".data", !goobj.gotype !0
@type.weak = external global i8
!0 = !{ptr @type.weak}
@llvm.compiler.used = appending global [2 x ptr] [ptr @shared, ptr @type.weak], section "llvm.metadata"

;--- strong.ll
@shared = global i64 2, section ".data", !goobj.gotype !0
@type.strong = external global i8
!0 = !{ptr @type.strong}
@llvm.compiler.used = appending global [2 x ptr] [ptr @shared, ptr @type.strong], section "llvm.metadata"

;--- declaration.ll
@shared = external global i64, !goobj.gotype !0
@type = external global i8
!0 = !{ptr @type}

;--- invalid.ll
@shared = global i64 0, !goobj.gotype !0
!0 = !{}
