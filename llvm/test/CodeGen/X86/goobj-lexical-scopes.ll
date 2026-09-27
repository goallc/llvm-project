; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s
; RUN: sed 's/!"dwarf5"/!"dwarf4"/' %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.d4.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.d4.o | FileCheck %s
; RUN: sed 's/!"dwarf5"/!"dwarf4"/' %s | llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o %t.arm64.d4.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.d4.o | FileCheck %s
; RUN: sed 's/line: 3/line: 2/g' %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.same-line.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.same-line.x86.o | FileCheck %s --check-prefix=SAME-LINE
; RUN: sed 's/line: 3/line: 2/g' %s | llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o %t.same-line.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.same-line.arm64.o | FileCheck %s --check-prefix=SAME-LINE
; RUN: sed -e 's/line: 3/line: 2/g' -e 's/!"dwarf5"/!"dwarf4"/' %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.same-line.d4.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.same-line.d4.o | FileCheck %s --check-prefix=SAME-LINE
; RUN: sed -e 's/line: 3/line: 2/g' -e 's/!"dwarf5"/!"dwarf4"/' %s | llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o %t.same-line.arm64.d4.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.same-line.arm64.d4.o | FileCheck %s --check-prefix=SAME-LINE

; The two i variables have the same name and type, but different lexical
; parents. The address ranges come from LLVM's final LexicalScopes analysis.
@"type:int" = external global i8
declare goabiinternal void @use(i64)

define goabiinternal void @nested(i64 %x) #0 !dbg !10 {
  call goabiinternal void @use(i64 %x), !dbg !20
  call goabiinternal void @use(i64 %x), !dbg !21
  call goabiinternal void @use(i64 %x), !dbg !20
  ret void, !dbg !22
}

attributes #0 = { "frame-pointer"="all" }

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!5, !6}
!goobj.debug.config = !{!7}
!goobj.debug.funcs = !{!8}
!goobj.debug.vars = !{!30, !31, !32}
!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !1, producer: "Go compiler", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "scope.go", directory: "/tmp/goobj-debug")
!2 = !DIBasicType(name: "int", size: 64, encoding: DW_ATE_signed)
!3 = !DISubroutineType(types: !4)
!4 = !{null, !2}
!5 = !{i32 2, !"Dwarf Version", i32 5}
!6 = !{i32 2, !"Debug Info Version", i32 3}
!7 = !{!"pcln-v1", !"dwarf-v1", !"dwarf5", !"main"}
!8 = !{!10, ptr @nested}
!10 = distinct !DISubprogram(name: "nested", linkageName: "nested", file: !1, line: 1, type: !3, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !11)
!11 = !{!12, !15, !16}
!12 = !DILocalVariable(name: "x", arg: 1, scope: !10, file: !1, line: 1, type: !2)
!13 = distinct !DILexicalBlock(scope: !10, file: !1, line: 2)
!14 = distinct !DILexicalBlock(scope: !13, file: !1, line: 3)
!15 = !DILocalVariable(name: "i", scope: !13, file: !1, line: 2, type: !2)
!16 = !DILocalVariable(name: "i", scope: !14, file: !1, line: 3, type: !2)
!20 = !DILocation(line: 2, scope: !13)
!21 = !DILocation(line: 3, scope: !14)
!22 = !DILocation(line: 4, scope: !10)
!30 = !{!12, !"int", i32 0}
!31 = !{!15, !"int", i32 0}
!32 = !{!16, !"int", i32 0}

; x is a root formal (2e), followed by two nested lexical blocks (0c),
; each containing its own i (28 6900), then three end-of-children markers.
; CHECK: type=dwarf_info target= data={{[0-9a-f]+}}2e7800000100000000000c000000002869000200000000000c00000000286900030000000000000000
; CHECK: type=dwarf_ranges target=

; Declarations on the same line must also retain both variables and their
; distinct scopes. Deduplicating by name/type/line loses one of the i DIEs.
; SAME-LINE: type=dwarf_info target= data={{[0-9a-f]+}}2e7800000100000000000c000000002869000200000000000c00000000286900020000000000000000
