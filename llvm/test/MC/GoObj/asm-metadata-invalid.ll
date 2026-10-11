; REQUIRES: x86-registered-target
; RUN: sed 's/i32 65536/i32 0/' %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t 2>&1 | FileCheck %s --check-prefix=KIND
; RUN: sed 's/i32 65536/i32 -4/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t 2>&1 | FileCheck %s --check-prefix=KIND
; RUN: sed 's/i32 65536/i32 0/; s/i64 0/i64 3/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t 2>&1 | FileCheck %s --check-prefix=RANGE
; RUN: sed 's/i32 65536/i32 0/; s/i64 2/i64 3/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t 2>&1 | FileCheck %s --check-prefix=SIZE
; RUN: sed 's/i32 65536/i32 0/; s/i32 1, i64/i32 2, i64/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t 2>&1 | FileCheck %s --check-prefix=VERSION
; RUN: sed 's/i32 65536/i32 0/; s/!3, !4, !3/!3, !4, !5/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t 2>&1 | FileCheck %s --check-prefix=CALL
; KIND: invalid !goobj.asm PC event kind
; RANGE: !goobj.asm integer out of range
; SIZE: GoObj assembly function size differs from metadata
; VERSION: unsupported !goobj.asm version
; CALL: !goobj.asm call offset is outside function

define goabi0 void @"test<ABI0>"() naked noinline !goobj.asm !0 {
  call void asm sideeffect "nop\0Aretq", "~{memory}"()
  unreachable
}
!0 = !{i32 1, i64 2, !1, !2, !3, !4, !3}
!1 = !{i32 0, i32 0, i32 0, i32 0, i32 10}
!2 = !{!6}
!3 = !{}
!4 = !{}
!5 = !{i64 2}
!6 = !{i64 0, i32 65536, i32 0, !""}

; RUN: sed 's/i32 65536/i32 0/; s/!2, !3, !4/!2, !7, !4/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t 2>&1 | FileCheck %s --check-prefix=DUPLICATE
; RUN: sed 's/i32 65536/i32 0/; s/naked noinline/noinline/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t 2>&1 | FileCheck %s --check-prefix=NAKED
; RUN: sed 's/i32 65536/i32 0/; s/!1, !2, !3/!3, !2, !3/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t 2>&1 | FileCheck %s --check-prefix=TUPLE
; DUPLICATE: duplicate !goobj.asm FUNCDATA index
; NAKED: !goobj.asm requires a defined naked function
; TUPLE: invalid !goobj.asm tuple
@maps = external global i8
!7 = !{!8, !8}
!8 = !{i32 1, ptr @maps}
