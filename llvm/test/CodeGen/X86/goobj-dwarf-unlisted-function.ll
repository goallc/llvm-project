; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s
; RUN: sed 's/!"dwarf4"/!"dwarf5"/' %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.v5.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.v5.o | FileCheck %s
; RUN: sed 's/!"dwarf4"/!"dwarf5"/' %s | llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o %t.arm64v5.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64v5.o | FileCheck %s

; Optimizers can clone a function and its DISubprogram without adding entries
; to the frontend's named metadata. The clone keeps the source linkage name,
; but its DWARF carrier must belong to the actual emitted storage symbol.
define goabiinternal i64 @original(i64 %x) !dbg !10 {
  ret i64 %x, !dbg !11
}

define internal goabiinternal i64 @original.specialized.1(i64 %x) !dbg !20 {
  %result = add i64 %x, 1, !dbg !21
  ret i64 %result, !dbg !21
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!5, !6}
!goobj.debug.config = !{!7}
!goobj.debug.funcs = !{!8}
!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !1, producer: "Go compiler", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "specialized.go", directory: "/tmp/goobj-debug")
!2 = !DIBasicType(name: "int", size: 64, encoding: DW_ATE_signed)
!3 = !DISubroutineType(types: !4)
!4 = !{!2, !2}
!5 = !{i32 2, !"Dwarf Version", i32 4}
!6 = !{i32 2, !"Debug Info Version", i32 3}
!7 = !{!"pcln-v1", !"dwarf-v1", !"dwarf4", !"main"}
!8 = !{!10, ptr @original}
!10 = distinct !DISubprogram(name: "original", linkageName: "original", file: !1, line: 3, type: !3, scopeLine: 3, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!11 = !DILocation(line: 4, scope: !10)
!20 = distinct !DISubprogram(name: "original", linkageName: "original", file: !1, line: 3, type: !3, scopeLine: 3, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!21 = !DILocation(line: 4, scope: !20)

; CHECK: symdef [[ORIGINAL:[0-9]+]]: original abi=
; CHECK: symdef [[CLONE:[0-9]+]]: original.specialized.1 abi=
; CHECK: aux [[ORIGINAL]].{{[0-9]+}}: type=dwarf_info target=
; CHECK: aux [[CLONE]].{{[0-9]+}}: type=dwarf_info target=
