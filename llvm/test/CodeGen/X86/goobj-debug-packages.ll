; RUN: split-file %s %t
; RUN: llvm-link %t/a.ll %t/b.ll %t/empty.ll -o %t/linked.bc
; RUN: opt -passes='default<O2>' %t/linked.bc -o %t/opt.bc
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/opt.bc -o %t/x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t/x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t/opt.bc -o %t/arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t/arm64.o | FileCheck %s
; RUN: sed 's/name: "emptyname"/name: "conflict"/; s@empty/package@example.com/with.dot@' %t/empty.ll > %t/conflict.ll
; RUN: llvm-link %t/a.ll %t/conflict.ll -o %t/conflict.bc
; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t/conflict.bc -o /dev/null 2>&1 | FileCheck %s --check-prefix=CONFLICT
;
; Native CU/module relationships preserve every source package through linking
; and optimization, including empty packages and LineTablesOnly CUs. A module
; imported from another source file is not the current package's definition.
; Package carrier prefixes use Go's escaped import path, not the module name.
; CHECK: go:cuinfo.packagename.empty/package {{.*}}kind=SDWARFCUINFO
; CHECK: go:cuinfo.packagename.example.com/with%2edot {{.*}}kind=SDWARFCUINFO
; CHECK: go:cuinfo.packagename.other/package {{.*}}kind=SDWARFCUINFO
; CHECK-NOT: go:cuinfo.packagename.
; CHECK: data: {{.*}}656d7074796e616d65736f757263656e616d656f746865726e616d65
; CONFLICT: conflicting GoObj source module names

;--- a.ll
!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!8, !9}
!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !1, producer: "Go compiler", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug, imports: !2)
!1 = !DIFile(filename: "example.com/with.dot", directory: "")
!2 = !{!3, !5}
!3 = !DIImportedEntity(tag: DW_TAG_imported_module, scope: !0, entity: !4)
!4 = !DIModule(scope: null, name: "sourcename", file: !1)
!5 = !DIImportedEntity(tag: DW_TAG_imported_module, scope: !0, entity: !6)
!6 = !DIModule(scope: null, name: "external", file: !7, isDecl: true)
!7 = !DIFile(filename: "external/package", directory: "")
!8 = !{i32 2, !"Dwarf Version", i32 5}
!9 = !{i32 2, !"Debug Info Version", i32 3}
define goabiinternal i64 @a(i64 %x) !dbg !10 {
  ret i64 %x, !dbg !11
}
!10 = distinct !DISubprogram(name: "a", linkageName: "a", scope: !4, file: !12, line: 1, type: !13, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!11 = !DILocation(line: 1, scope: !10)
!12 = !DIFile(filename: "a.go", directory: "/tmp/native-debug")
!13 = !DISubroutineType(types: !14)
!14 = !{}

;--- b.ll
!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!8, !9}
!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !1, producer: "Go compiler", isOptimized: true, runtimeVersion: 0, emissionKind: LineTablesOnly, imports: !2)
!1 = !DIFile(filename: "other/package", directory: "")
!2 = !{!3, !5}
!3 = !DIImportedEntity(tag: DW_TAG_imported_module, scope: !0, entity: !4)
!4 = !DIModule(scope: null, name: "othername", file: !1)
!5 = !DIImportedEntity(tag: DW_TAG_imported_module, scope: !0, entity: !6)
!6 = !DIModule(scope: null, name: "external", file: !7, isDecl: true)
!7 = !DIFile(filename: "external/package", directory: "")
!8 = !{i32 2, !"Dwarf Version", i32 5}
!9 = !{i32 2, !"Debug Info Version", i32 3}
define goabiinternal i64 @b(i64 %x) !dbg !10 {
  ret i64 %x, !dbg !11
}
!10 = distinct !DISubprogram(name: "b", linkageName: "b", scope: !4, file: !12, line: 1, type: !13, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!11 = !DILocation(line: 1, scope: !10)
!12 = !DIFile(filename: "b.go", directory: "/tmp/native-debug")
!13 = !DISubroutineType(types: !14)
!14 = !{}

;--- empty.ll
!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!8, !9}
!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !1, producer: "Go compiler", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug, imports: !2)
!1 = !DIFile(filename: "empty/package", directory: "")
!2 = !{!3, !5}
!3 = !DIImportedEntity(tag: DW_TAG_imported_module, scope: !0, entity: !4)
!4 = !DIModule(scope: null, name: "emptyname", file: !1)
!5 = !DIImportedEntity(tag: DW_TAG_imported_module, scope: !0, entity: !6)
!6 = !DIModule(scope: null, name: "external", file: !7, isDecl: true)
!7 = !DIFile(filename: "external/package", directory: "")
!8 = !{i32 2, !"Dwarf Version", i32 5}
!9 = !{i32 2, !"Debug Info Version", i32 3}
