; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.x86.o
; RUN: %python %S/Inputs/dump-goobj.py %t.x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

; Concrete interface types need DWARF even without a named variable of that
; type. Keep their existing runtime type identity on the function's info
; carrier; itab references are not themselves runtime type descriptors.
@"type:[]main.T" = external global i8
@"go:itab.main.T,main.I" = external global i8

define goabiinternal void @main.main() !dbg !10 {
  ret void, !dbg !11
}

; CHECK: symdef [[INFO:[0-9]+]]: {{.*}}kind=SDWARFFCN
; CHECK: reloc [[INFO]].{{[0-9]+}}: off=0 size=0 type=22 add=0 target=type:[]main.T kind=R_USETYPE
; CHECK-NOT: kind=R_USETYPE

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!5, !6}
!goobj.debug.config = !{!7}
!goobj.debug.funcs = !{!8}
!goobj.marker_relocs = !{!12, !13}
!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !1, producer: "goallc", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "types.go", directory: "/src")
!2 = !{}
!3 = !DISubroutineType(types: !2)
!5 = !{i32 7, !"Dwarf Version", i32 4}
!6 = !{i32 2, !"Debug Info Version", i32 3}
!7 = !{!"pcln-v1", !"dwarf-v1", !"dwarf4", !"main"}
!8 = !{!10, ptr @main.main}
!10 = distinct !DISubprogram(name: "main.main", linkageName: "main.main", scope: !1, file: !1, line: 3, type: !3, scopeLine: 3, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!11 = !DILocation(line: 4, column: 2, scope: !10)
!12 = !{ptr @main.main, ptr @"type:[]main.T", i32 23, i64 0}
!13 = !{ptr @main.main, ptr @"go:itab.main.T,main.I", i32 23, i64 0}
