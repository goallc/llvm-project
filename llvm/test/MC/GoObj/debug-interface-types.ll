; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.x86.o
; RUN: %python %S/Inputs/dump-goobj.py %t.x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

; Concrete interface types need DWARF even without a named variable of that
; type. Keep their existing runtime type identity on the function's info
; carrier; itab references are not themselves runtime type descriptors.
@"type:[]main.T" = external global i8
@"go:itab.main.T,main.I" = external global i8

define goabiinternal void @main.main() !dbg !10 !goobj.marker_relocs !14 {
  ret void, !dbg !11
}

; CHECK: symdef [[INFO:[0-9]+]]: {{.*}}kind=SDWARFFCN
; CHECK: reloc [[INFO]].{{[0-9]+}}: off=0 size=0 type=22 add=0 target=type:[]main.T kind=R_USETYPE
; CHECK-NOT: kind=R_USETYPE

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!5, !6}
!goobj.debug.funcs = !{!8}
!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !15, producer: "goallc", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug, imports: !18)
!1 = !DIFile(filename: "types.go", directory: "/src")
!2 = !{}
!3 = !DISubroutineType(types: !2)
!5 = !{i32 7, !"Dwarf Version", i32 4}
!6 = !{i32 2, !"Debug Info Version", i32 3}
!8 = !{!10, ptr @main.main}
!10 = distinct !DISubprogram(name: "main.main", linkageName: "main.main", scope: !1, file: !1, line: 3, type: !3, scopeLine: 3, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!11 = !DILocation(line: 4, column: 2, scope: !10)
!12 = !{ptr @"type:[]main.T", i32 23, i64 0}
!13 = !{ptr @"go:itab.main.T,main.I", i32 23, i64 0}

!14 = !{!12, !13}

!15 = !DIFile(filename: "main", directory: "")
!16 = !DIModule(scope: null, name: "main", file: !15)
!17 = !DIImportedEntity(tag: DW_TAG_imported_module, scope: !0, entity: !16)
!18 = !{!17}
