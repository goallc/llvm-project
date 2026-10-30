; RUN: llc -filetype=obj %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: sed 's/!goobj.debug.funcs = !{!8, !9}/!goobj.debug.funcs = !{!9, !8}/' %s | llc -filetype=obj -o %t.reversed.o
; RUN: cmp %t.o %t.reversed.o
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

; RUN: sed 's/!goobj.debug.funcs = !{!8, !9}/!goobj.debug.funcs = !{!9}/' %s | llc -filetype=obj -o %t.abstract-only.o
; RUN: cmp %t.o %t.abstract-only.o
; RUN: sed 's/!goobj.debug.funcs = !{!8, !9}/!goobj.debug.funcs = !{!9}/' %s | llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o %t.arm64-abstract-only.o
; RUN: cmp %t.arm64.o %t.arm64-abstract-only.o
; RUN: sed '/^!goobj.debug.funcs =/d' %s | not --crash llc -filetype=obj -o /dev/null 2>&1 | FileCheck %s --check-prefix=MISSING
; MISSING: LLVM ERROR: GoObj inline subprogram has no exact symbol: main.abstract

; Inline instances sharing one storage symbol must contribute all variables,
; regardless of the ordering of their metadata or allocated pointer addresses.
target triple = "x86_64-unknown-linux-goobj"

define goabiinternal i64 @"main.shared"(i64 %x) !dbg !10 {
  #dbg_value(i64 %x, !22, !DIExpression(), !26)
  ret i64 %x, !dbg !24
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!5, !6}
!goobj.debug.funcs = !{!8, !9}
!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !27, producer: "Go compiler", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug, imports: !30)
!1 = !DIFile(filename: "shared.go", directory: "/tmp/goobj-debug")
!2 = !DIBasicType(name: "int", size: 64, encoding: DW_ATE_signed)
!3 = !DISubroutineType(types: !4)
!4 = !{!2, !2}
!5 = !{i32 2, !"Dwarf Version", i32 4}
!6 = !{i32 2, !"Debug Info Version", i32 3}
!8 = !{!10, ptr @"main.shared"}
!9 = !{!20, ptr @"main.shared"}
!10 = distinct !DISubprogram(name: "main.shared", linkageName: "main.shared", file: !1, line: 3, type: !3, scopeLine: 3, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0, retainedNodes: !11)
!11 = !{!12}
!12 = !DILocalVariable(name: "from_first", scope: !10, file: !1, line: 3, type: !2)
!20 = distinct !DISubprogram(name: "main.shared", linkageName: "main.abstract", file: !1, line: 3, type: !3, scopeLine: 3, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0, retainedNodes: !21)
!21 = !{!22}
!22 = !DILocalVariable(name: "from_second", scope: !20, file: !1, line: 3, type: !2)
!24 = !DILocation(line: 4, scope: !10)
!26 = !DILocation(line: 4, scope: !20, inlinedAt: !24)

; CHECK: data: {{.*}}66726f6d5f666972737400{{.*}}66726f6d5f7365636f6e6400



!27 = !DIFile(filename: "main", directory: "")
!28 = !DIModule(scope: null, name: "main", file: !27)
!29 = !DIImportedEntity(tag: DW_TAG_imported_module, scope: !0, entity: !28)
!30 = !{!29}
