; RUN: llc -filetype=obj %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: sed 's/!goobj.debug.funcs = !{!8, !9}/!goobj.debug.funcs = !{!9, !8}/' %s | llc -filetype=obj -o %t.reversed.o
; RUN: cmp %t.o %t.reversed.o
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

; Inline instances sharing one storage symbol must contribute all variables,
; regardless of the ordering of their metadata or allocated pointer addresses.
target triple = "x86_64-unknown-linux-goobj"

define goabiinternal i64 @"main.shared"(i64 %x) !dbg !10 {
  ret i64 %x, !dbg !24
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!5, !6}
!goobj.debug.config = !{!7}
!goobj.debug.funcs = !{!8, !9}
!goobj.debug.vars = !{!15, !25}
!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !1, producer: "Go compiler", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "shared.go", directory: "/tmp/goobj-debug")
!2 = !DIBasicType(name: "int", size: 64, encoding: DW_ATE_signed)
!3 = !DISubroutineType(types: !4)
!4 = !{!2, !2}
!5 = !{i32 2, !"Dwarf Version", i32 4}
!6 = !{i32 2, !"Debug Info Version", i32 3}
!7 = !{!"pcln-v1", !"dwarf-v1", !"dwarf4", !"main"}
!8 = !{!10, ptr @"main.shared"}
!9 = !{!20, ptr @"main.shared"}
!10 = distinct !DISubprogram(name: "main.shared", linkageName: "main.shared", file: !1, line: 3, type: !3, scopeLine: 3, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0, retainedNodes: !11)
!11 = !{!12}
!12 = !DILocalVariable(name: "from_first", scope: !10, file: !1, line: 3, type: !2)
!15 = !{!12, !"int", i32 0}
!20 = distinct !DISubprogram(name: "main.shared", linkageName: "main.shared", file: !1, line: 3, type: !3, scopeLine: 3, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0, retainedNodes: !21)
!21 = !{!22}
!22 = !DILocalVariable(name: "from_second", scope: !20, file: !1, line: 3, type: !2)
!24 = !DILocation(line: 4, scope: !10)
!25 = !{!22, !"int", i32 0}

; CHECK: data: {{.*}}66726f6d5f666972737400{{.*}}66726f6d5f7365636f6e6400
