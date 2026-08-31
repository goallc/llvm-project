; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.dwarf4.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.dwarf4.o | FileCheck %s --check-prefixes=COMMON,DWARF4
; RUN: opt -passes='default<O2>' < %s | llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj -o %t.o2.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o2.o | FileCheck %s --check-prefixes=COMMON,DWARF4
; RUN: sed 's/!"dwarf4"/!"dwarf5"/' %s | llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj -o %t.dwarf5.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.dwarf5.o | FileCheck %s --check-prefixes=COMMON,DWARF5
; RUN: sed '/^!goobj.gotype =/d' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj -o /dev/null 2>&1 | FileCheck %s --check-prefix=MISSING-GOTYPE

; The frontend sends source semantics in standard LLVM DI metadata plus exact
; GoObj identity/configuration metadata. The GoObj backend must retain its
; existing PCDATA output and add linker-native DWARF carrier symbols; ordinary
; LLVM .debug_* sections must not leak into the Go object.

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-goobj"

@"main.global" = global i64 0, !dbg !40, !dbg !42
@"type:int" = constant [1 x i8] zeroinitializer, section ".rodata"
@"main.pointer" = global ptr null, !dbg !45
@"type:unsafe.Pointer<builtin.287>" = external global i8
@llvm.compiler.used = appending global [1 x ptr] [ptr @"type:unsafe.Pointer<builtin.287>"], section "llvm.metadata"
@"main..dict.testfn[main.CustomInt]" = constant [8 x i8] zeroinitializer

define goabiinternal i64 @"main.inline"(i64 %x) !dbg !20 {
entry:
  %sum = add i64 %x, 1, !dbg !24
  ret i64 %sum, !dbg !24
}

define goabiinternal i64 @"main.debug"(i64 %x) !dbg !10 {
entry:
  %sum = add i64 %x, 1, !dbg !31
  ret i64 %sum, !dbg !32
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!5, !6}
!goobj.debug.config = !{!7}
!goobj.debug.funcs = !{!8, !9}
!goobj.debug.vars = !{!15, !25}
!goobj.gotype = !{!44, !49}

!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !1, producer: "Go compiler", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "debug.go", directory: "/tmp/goobj-debug")
!2 = !DIBasicType(name: "int", size: 64, encoding: DW_ATE_signed)
!3 = !DISubroutineType(types: !4)
!4 = !{!2, !2}
!5 = !{i32 2, !"Dwarf Version", i32 4}
!6 = !{i32 2, !"Debug Info Version", i32 3}
!7 = !{!"pcln-v1", !"dwarf-v1", !"dwarf4", !"main"}
!8 = !{!10, ptr @"main.debug"}
!9 = !{!20, ptr @"main.inline"}

!10 = distinct !DISubprogram(name: "main.debug", linkageName: "main.debug", file: !1, line: 7, type: !3, scopeLine: 7, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0, retainedNodes: !11)
!11 = !{!12}
!12 = !DILocalVariable(name: "x", arg: 1, scope: !10, file: !1, line: 7, type: !2)
!15 = !{!12, !"int", i32 0, i32 1}

!20 = distinct !DISubprogram(name: "main.inline", linkageName: "main.inline", file: !1, line: 3, type: !3, scopeLine: 3, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0, retainedNodes: !21)
!21 = !{!22}
!22 = !DILocalVariable(name: "x", arg: 1, scope: !20, file: !1, line: 3, type: !2)
!24 = !DILocation(line: 4, column: 2, scope: !20)
!25 = !{!22, !"int", i32 0, i32 0}

!31 = !DILocation(line: 8, column: 9, scope: !10)
!32 = !DILocation(line: 9, column: 2, scope: !10)
!40 = !DIGlobalVariableExpression(var: !41, expr: !DIExpression())
!41 = distinct !DIGlobalVariable(name: "main.global", linkageName: "main.global", scope: !0, file: !1, line: 2, type: !2, isLocal: false, isDefinition: true)
!42 = !DIGlobalVariableExpression(var: !43, expr: !DIExpression())
!43 = distinct !DIGlobalVariable(name: "main.global.alias", linkageName: "main.global", scope: !0, file: !1, line: 2, type: !2, isLocal: false, isDefinition: true)
!44 = !{ptr @"main.global", ptr @"type:int"}
!45 = !DIGlobalVariableExpression(var: !46, expr: !DIExpression())
!46 = distinct !DIGlobalVariable(name: "main.pointer", linkageName: "main.pointer", scope: !0, file: !1, line: 3, type: !47, isLocal: false, isDefinition: true)
!47 = !DIBasicType(name: "unsafe.Pointer", size: 64, encoding: DW_ATE_address)
!49 = !{ptr @"main.pointer", ptr @"type:unsafe.Pointer<builtin.287>"}

; COMMON: symdef {{[0-9]+}}: main.inline abi=1 type=1 {{.*}} kind=STEXT
; COMMON: symdef {{[0-9]+}}: main.debug abi=1 type=1 {{.*}} kind=STEXT
; COMMON: main.global {{.*}} kind=SBSS
; COMMON: main.pointer {{.*}} kind=SBSS
; COMMON: main..dict.testfn{{.*}}flag2=4{{.*}}kind=SRODATA
; COMMON: kind=SDWARFFCN
; COMMON: kind=SDWARFLINES
; COMMON: go:cuinfo.packagename.main {{.*}} kind=SDWARFCUINFO
; COMMON-COUNT-2: kind=SDWARFVAR
; COMMON-NOT: kind=SDWARFVAR
; COMMON: type=dwarf_info target=
; COMMON: type=dwarf_lines target=
; COMMON: type=pcfile target=
; COMMON: type=pcline target=
; DWARF4: kind=R_ADDR
; DWARF4-NOT: kind=R_DWTXTADDR_U4
; DWARF5: kind=R_DWTXTADDR_U4
; COMMON: target=type:int kind=R_USETYPE
; COMMON-COUNT-2: target=main.global kind=R_ADDR
; COMMON: target=go:info.int kind=R_DWARFSECREF
; COMMON: target=builtin:287 kind=R_USETYPE
; COMMON: target=main.pointer kind=R_ADDR
; COMMON: target=go:info.unsafe.Pointer kind=R_DWARFSECREF
; COMMON-NOT: .debug_
; MISSING-GOTYPE: LLVM ERROR: GoObj DWARF global main.global has no !goobj.gotype target
