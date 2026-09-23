; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.x86.o
; RUN: %python %S/Inputs/dump-goobj.py %t.x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

; A line-zero location has a known scope, unlike an absent debug location.
; Use the containing function declaration instead of inheriting the previous
; call's source location. Keep its scope when optimizations merge instructions
; from different source lines.
declare goabiinternal i64 @leaf()

define goabiinternal i64 @main.zero_line() "frame-pointer"="non-leaf" !dbg !10 {
  %a = call goabiinternal i64 @leaf(), !dbg !20
  %b = call goabiinternal i64 @leaf(), !dbg !21
  %sum = add i64 %a, %b, !dbg !22
  ret i64 %sum, !dbg !22
}

; The unlocated prologue belongs to the declaration, not line 17.
; CHECK: aux {{[0-9]+}}.{{[0-9]+}}: type=pcfile target= pc=[0-{{[0-9]+}}:0,{{[0-9]+}}-{{[0-9]+}}:1,
; CHECK: aux {{[0-9]+}}.{{[0-9]+}}: type=pcline target= pc=[0-{{[0-9]+}}:16,
; CHECK-SAME: :17
; CHECK-SAME: :16
; CHECK-SAME: :18

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!5, !6}
!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !1, producer: "goallc", isOptimized: true, runtimeVersion: 0, emissionKind: LineTablesOnly)
!1 = !DIFile(filename: "zero.go", directory: "/src")
!2 = !{}
!3 = !DISubroutineType(types: !2)
!5 = !{i32 7, !"Dwarf Version", i32 4}
!6 = !{i32 2, !"Debug Info Version", i32 3}
!10 = distinct !DISubprogram(name: "main.zero_line", linkageName: "main.zero_line", scope: !1, file: !1, line: 16, type: !3, scopeLine: 16, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!18 = !DIFile(filename: "included.go", directory: "/src")
!19 = !DILexicalBlockFile(scope: !10, file: !18, discriminator: 0)
!20 = !DILocation(line: 17, column: 2, scope: !19)
!21 = !DILocation(line: 0, scope: !10)
!22 = !DILocation(line: 18, column: 2, scope: !10)
