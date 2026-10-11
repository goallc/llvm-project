; REQUIRES: x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t
; RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s --check-prefix=VALID
; RUN: sed 's/!{!0, !0}/!{}/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t 2>&1 | FileCheck %s --check-prefix=EMPTY
; RUN: sed 's/i32 1/i32 2/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t 2>&1 | FileCheck %s --check-prefix=VERSION
; RUN: sed 's/i32 1/i64 1/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t 2>&1 | FileCheck %s --check-prefix=WIDTH
; VALID: flags: 4
; EMPTY: missing !goobj.assembly version
; VERSION: unsupported !goobj.assembly version
; WIDTH: invalid !goobj.asm integer width

; Repeated records from module linking agree on the protocol version. The
; marker must also work for an assembly object with data and no functions.
!goobj.assembly = !{!0, !0}
!0 = !{i32 1}
@data = global i64 42
