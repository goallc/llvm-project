; RUN: split-file %s %t
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/fingerprint.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=FINGERPRINT
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/conflicting.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=CONFLICTING
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/definition.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=DEFINITION
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/duplicate-import.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=DUPLICATE-IMPORT

;--- fingerprint.ll
define goabiinternal void @f() {
  ret void
}
!goobj.imports = !{!0}
!0 = !{!"os", !"os", !"gggggggggggggggg"}

; FINGERPRINT: LLVM ERROR: invalid !goobj.imports fingerprint

;--- conflicting.ll
declare !goobj.import !0 !goobj.builtin !1 goabiinternal void @external()
define goabiinternal void @f() {
  call goabiinternal void @external()
  ret void
}
!0 = !{!"pkg", i32 1, i32 0}
!1 = !{i32 2}

; CONFLICTING: LLVM ERROR: invalid GoObj symbol reference attachment

;--- definition.ll
define goabiinternal void @f() !goobj.import !0 {
  ret void
}
!0 = !{!"pkg", i32 1, i32 0}

; DEFINITION: LLVM ERROR: invalid GoObj symbol reference attachment

;--- duplicate-import.ll
define goabiinternal void @f() {
  ret void
}
!goobj.imports = !{!0, !1}
!0 = !{!"os", !"os", !"0123456789abcdef"}
!1 = !{!"os", !"os", !"fedcba9876543210"}

; DUPLICATE-IMPORT: LLVM ERROR: duplicate !goobj.imports package
