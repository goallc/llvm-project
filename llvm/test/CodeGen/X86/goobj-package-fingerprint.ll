; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s
; RUN: sed 's/0123456789abcdef/0123456789abcdeg/' %s | not llc -filetype=obj -o %t.bad.o 2>&1 | FileCheck %s --check-prefix=BAD
; RUN: sed 's/0123456789abcdef/0123456789abcd/' %s | not llc -filetype=obj -o %t.bad.o 2>&1 | FileCheck %s --check-prefix=BAD

; The linker object must carry the fingerprint of this package's export data,
; not just the fingerprints of its imports. Preserve byte order exactly.
target triple = "x86_64-unknown-linux-goobj"
define goabiinternal void @"p.F"() {
  ret void
}

!goobj.config = !{!0}
!0 = !{!"goallc.goobj", !"linux", !"amd64", !"go1.27", !"GOAMD64", !"v1", !"", !"p", !"0", !"0", !"0", !1, !"0123456789abcdef"}
!1 = !{}

; CHECK: fingerprint: 0123456789abcdef
; BAD: !goobj.config fingerprint must be 16 hexadecimal digits
