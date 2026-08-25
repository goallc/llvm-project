; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=implicit-null-checks -o - %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=implicit-null-checks -o - %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs -o - %s | \
; RUN:   FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -verify-machineinstrs -o - %s | \
; RUN:   FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.x86.o %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o %t.a64.o %s

; GoObj enables ImplicitNullChecks by default, but only the producer-owned
; !{!"goallc"} marker opts a branch into Go's signal-based nil-check contract.
; The faulting access must stay in [0, runtime.minLegalPointer), and its debug
; location must identify the explicit nil check rather than the later load.

; MIR: [[CHECK_LOC:![0-9]+]] = !DILocation(line: 10,
; MIR-LABEL: name: fold_nonnegative
; MIR: FAULTING_OP
; MIR-SAME: debug-location [[CHECK_LOC]]
; ASM-LABEL: fold_nonnegative:
; ASM: Go implicit nil check
define goabiinternal i64 @fold_nonnegative(ptr %p) !dbg !4 {
entry:
  %isnil = icmp eq ptr %p, null
  br i1 %isnil, label %nil, label %notnil, !make.implicit !0, !dbg !7

nil:
  ret i64 0

notnil:
  %addr = getelementptr i8, ptr %p, i64 8, !dbg !8
  %value = load i64, ptr %addr, align 8, !dbg !8
  ret i64 %value
}

; A negative displacement from null wraps to a high address. Go would treat
; that signal as fatal rather than route it through panicmem.
; MIR-LABEL: name: keep_negative
; MIR-NOT: FAULTING_OP
define goabiinternal i64 @keep_negative(ptr %p) {
entry:
  %isnil = icmp eq ptr %p, null
  br i1 %isnil, label %nil, label %notnil, !make.implicit !0

nil:
  ret i64 0

notnil:
  %addr = getelementptr i8, ptr %p, i64 -8
  %value = load i64, ptr %addr, align 8
  ret i64 %value
}

; The first address not classified as a nil fault is also rejected.
; MIR-LABEL: name: keep_boundary
; MIR-NOT: FAULTING_OP
define goabiinternal i64 @keep_boundary(ptr %p) {
entry:
  %isnil = icmp eq ptr %p, null
  br i1 %isnil, label %nil, label %notnil, !make.implicit !0

nil:
  ret i64 0

notnil:
  %addr = getelementptr i8, ptr %p, i64 4096
  %value = load i64, ptr %addr, align 8
  ret i64 %value
}

; The generic empty marker must not opt GoObj into a contract that requires
; LLVM fault-map support.
; MIR-LABEL: name: keep_generic_marker
; MIR-NOT: FAULTING_OP
define goabiinternal i64 @keep_generic_marker(ptr %p) {
entry:
  %isnil = icmp eq ptr %p, null
  br i1 %isnil, label %nil, label %notnil, !make.implicit !1

nil:
  ret i64 0

notnil:
  %value = load i64, ptr %p, align 8
  ret i64 %value
}

!llvm.dbg.cu = !{!2}
!llvm.module.flags = !{!3}

!0 = !{!"goallc"}
!1 = !{}
!2 = distinct !DICompileUnit(language: DW_LANG_Go, file: !5, emissionKind: FullDebug)
!3 = !{i32 2, !"Debug Info Version", i32 3}
!4 = distinct !DISubprogram(name: "fold_nonnegative", scope: !5, file: !5, line: 1, type: !6, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !2)
!5 = !DIFile(filename: "nilcheck.go", directory: "/")
!6 = !DISubroutineType(types: !1)
!7 = !DILocation(line: 10, column: 2, scope: !4)
!8 = !DILocation(line: 20, column: 9, scope: !4)
