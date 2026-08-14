; RUN: split-file %s %t
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/fingerprint.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=FINGERPRINT
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/conflicting.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=CONFLICTING
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/import-builtin.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=IMPORT-BUILTIN
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/definition.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=DEFINITION
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/duplicate-import.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=DUPLICATE-IMPORT
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/obsolete-builtin.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=OBSOLETE-BUILTIN
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/builtin-definition.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=BUILTIN-DEFINITION
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/builtin-index.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=BUILTIN-INDEX
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/builtin-linkname.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=BUILTIN-LINKNAME

;--- fingerprint.ll
define goabiinternal void @f() {
  ret void
}
!goobj.imports = !{!0}
!0 = !{!"os", !"os", !"gggggggggggggggg"}

; FINGERPRINT: LLVM ERROR: invalid !goobj.imports fingerprint

;--- conflicting.ll
declare !goobj.import !0 goabiinternal void @"external<linkname>"()
define goabiinternal void @f() {
  call goabiinternal void @"external<linkname>"()
  ret void
}
!0 = !{!"pkg", i32 1, i32 0}

; CONFLICTING: LLVM ERROR: invalid GoObj symbol reference attachment

;--- import-builtin.ll
declare !goobj.import !0 goabiinternal void @"runtime.external<builtin.1>"()
define goabiinternal void @f() {
  call goabiinternal void @"runtime.external<builtin.1>"()
  ret void
}
!0 = !{!"runtime", i32 1, i32 0}

; IMPORT-BUILTIN: LLVM ERROR: invalid GoObj symbol reference attachment

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

;--- obsolete-builtin.ll
@source = global ptr @"type:string", !goobj.builtin !0
@"type:string" = external global i8
!0 = !{i32 7}

; OBSOLETE-BUILTIN: LLVM ERROR: !goobj.builtin is obsolete; encode the builtin index in the symbol name

;--- builtin-definition.ll
define goabiinternal void @"runtime.bad<linkname>"() {
  ret void
}

; BUILTIN-DEFINITION: LLVM ERROR: Go builtin and linkname suffixes require an undefined symbol

;--- builtin-index.ll
declare goabiinternal void @"runtime.bad<builtin.x>"()
define goabiinternal void @f() {
  call goabiinternal void @"runtime.bad<builtin.x>"()
  ret void
}

; BUILTIN-INDEX: LLVM ERROR: invalid Go builtin symbol index

;--- builtin-linkname.ll
declare goabiinternal void @"runtime.bad<builtin.1><linkname>"()
define goabiinternal void @f() {
  call goabiinternal void @"runtime.bad<builtin.1><linkname>"()
  ret void
}

; BUILTIN-LINKNAME: LLVM ERROR: conflicting Go builtin and linkname symbol identity
