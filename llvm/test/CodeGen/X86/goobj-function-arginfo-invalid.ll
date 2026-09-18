; RUN: split-file %s %t
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %t/arg-size.ll 2>&1 | FileCheck %s --check-prefix=ARG-SIZE
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %t/spill-offset.ll 2>&1 | FileCheck %s --check-prefix=SPILL-OFFSET
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %t/home-offset.ll 2>&1 | FileCheck %s --check-prefix=HOME-OFFSET

; ARG-SIZE: !goobj.func.arginfo argument size does not match lowered Go ABI layout
; SPILL-OFFSET: !goobj.func.arginfo spill area does not match lowered Go ABI layout
; HOME-OFFSET: !goobj.func.arginfo argument offset does not match lowered Go ABI home

;--- arg-size.ll
@arginfo = constant [1 x i8] c"\ff"

define goabiinternal void @arg_size(ptr %p) !goobj.func.arginfo !0 {
  ret void
}

!0 = !{ptr @arginfo, i64 16, i64 0, i64 0, i64 8}

;--- spill-offset.ll
@arginfo = constant [1 x i8] c"\ff"

define goabiinternal void @spill_offset(ptr %p) !goobj.func.arginfo !0 {
  ret void
}

!0 = !{ptr @arginfo, i64 8, i64 4, i64 0, i64 8}

;--- home-offset.ll
@arginfo = constant [1 x i8] c"\ff"

define goabiinternal void @home_offset(ptr %p, ptr %q) !goobj.func.arginfo !0 {
  ret void
}

!0 = !{ptr @arginfo, i64 16, i64 0, i64 0, i64 8, i64 4, i64 8}
