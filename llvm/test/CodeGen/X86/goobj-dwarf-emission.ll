; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s --check-prefixes=COMMON,MIXED
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s --check-prefixes=COMMON,MIXED
; RUN: sed 's/FullDebug/LineTablesOnly/g' %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.min.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.min.o | FileCheck %s --check-prefixes=COMMON,MINIMAL --implicit-check-not=SDWARFABSFCN
; RUN: sed 's/FullDebug/LineTablesOnly/g' %s | llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o %t.min.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.min.arm64.o | FileCheck %s --check-prefixes=COMMON,MINIMAL --implicit-check-not=SDWARFABSFCN
; RUN: sed 's/!"dwarf5"/!"dwarf4"/; s/i32 5}/i32 4}/' %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.v4.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.v4.o | FileCheck %s --check-prefixes=COMMON,MIXED
; RUN: sed '/^!goobj.debug.vars =/d; s/!"pcln-v1", !"dwarf-v1", !"dwarf5", !"main"/!"pcln-v1"/' %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.pcln.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.pcln.o | FileCheck %s --check-prefix=PCLN --implicit-check-not=SDWARF --implicit-check-not=type=dwarf_

; RUN: sed 's/!"dwarf-v1", !"dwarf5", //' %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.native.x86.o
; RUN: cmp %t.x86.o %t.native.x86.o
; RUN: sed 's/!"dwarf-v1", !"dwarf5", //' %s | llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o %t.native.arm64.o
; RUN: cmp %t.arm64.o %t.native.arm64.o
; RUN: sed 's/!"dwarf-v1", !"dwarf5", //; s/i32 5}/i32 4}/' %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.native.v4.o
; RUN: cmp %t.v4.o %t.native.v4.o
; RUN: sed 's/!"dwarf-v1", !"dwarf5", //; s/!llvm.module.flags = !{!5, !6}/!llvm.module.flags = !{!6}/' %s | not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o /dev/null 2>&1 | FileCheck %s --check-prefix=VERSION
; VERSION: GoObj debug config requires Dwarf Version 4 or 5 and a package name

; LTO may combine FullDebug and LineTablesOnly CUs. The module config only
; selects the Go DWARF encoding. Like native Go -dwarf=false, a LineTablesOnly
; function needs a minimal DIE and line table, but no variables or inline DIEs.
; Runtime PC tables must survive all three emission modes.

@"main.full.global" = global i64 0, !dbg !50
@"main.minimal.global" = global i64 0, !dbg !52
@"type:int" = constant i8 0

define goabiinternal i64 @full(i64 %x) !dbg !10 {
  %v = add i64 %x, 1, !dbg !12
  ret i64 %v, !dbg !12
}

define goabiinternal i64 @minimal(i64 %x) !dbg !20 {
  %v = add i64 %x, 2, !dbg !22
  ret i64 %v, !dbg !22
}


!llvm.dbg.cu = !{!0, !1}
!llvm.module.flags = !{!5, !6}
!goobj.debug.config = !{!7}
!goobj.debug.funcs = !{!8, !9}
!goobj.debug.vars = !{!16, !26}
!goobj.gotype = !{!54, !55}

!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !2, producer: "Go compiler", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = distinct !DICompileUnit(language: DW_LANG_Go, file: !3, producer: "Go compiler", isOptimized: true, runtimeVersion: 0, emissionKind: LineTablesOnly)
!2 = !DIFile(filename: "full.go", directory: "/tmp/goobj-emission")
!3 = !DIFile(filename: "minimal.go", directory: "/tmp/goobj-emission")
!4 = !DISubroutineType(types: !17)
!5 = !{i32 2, !"Dwarf Version", i32 5}
!6 = !{i32 2, !"Debug Info Version", i32 3}
!7 = !{!"pcln-v1", !"dwarf-v1", !"dwarf5", !"main"}
!8 = !{!10, ptr @full}
!9 = !{!20, ptr @minimal}
!10 = distinct !DISubprogram(name: "full", linkageName: "full", file: !2, line: 10, type: !4, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0, retainedNodes: !14)
!12 = !DILocation(line: 11, scope: !10)
!14 = !{!15}
!15 = !DILocalVariable(name: "x", arg: 1, scope: !10, file: !2, line: 10, type: !18)
!16 = !{!15, !"int", i32 0}
!17 = !{!18, !18}
!18 = !DIBasicType(name: "int", size: 64, encoding: DW_ATE_signed)
!20 = distinct !DISubprogram(name: "minimal", linkageName: "minimal", file: !3, line: 20, type: !4, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !1, retainedNodes: !24)
!22 = !DILocation(line: 21, scope: !20)
!24 = !{!25}
!25 = !DILocalVariable(name: "x", arg: 1, scope: !20, file: !3, line: 20, type: !18)
!26 = !{!25, !"int", i32 0}
!50 = !DIGlobalVariableExpression(var: !51, expr: !DIExpression())
!51 = distinct !DIGlobalVariable(name: "main.full.global", linkageName: "main.full.global", scope: !0, file: !2, line: 2, type: !18, isLocal: false, isDefinition: true)
!52 = !DIGlobalVariableExpression(var: !53, expr: !DIExpression())
!53 = distinct !DIGlobalVariable(name: "main.minimal.global", linkageName: "main.minimal.global", scope: !1, file: !3, line: 2, type: !18, isLocal: false, isDefinition: true)
!54 = !{ptr @"main.full.global", ptr @"type:int"}
!55 = !{ptr @"main.minimal.global", ptr @"type:int"}

; COMMON: symdef [[FULL:[0-9]+]]: full abi=1
; COMMON: symdef [[MIN:[0-9]+]]: minimal abi=1
; COMMON: kind=SDWARFFCN
; COMMON: kind=SDWARFLINES
; COMMON: kind=SDWARFFCN
; COMMON: kind=SDWARFLINES
; COMMON-COUNT-2: kind=SDWARFVAR
; COMMON-NOT: kind=SDWARFVAR
; COMMON: aux [[FULL]].{{[0-9]+}}: type=dwarf_info {{.*}} sym=[[FULLINFO:[0-9]+]]
; COMMON: aux [[FULL]].{{[0-9]+}}: type=dwarf_lines
; COMMON: aux [[FULL]].{{[0-9]+}}: type=pcfile
; COMMON: aux [[FULL]].{{[0-9]+}}: type=pcline
; COMMON: aux [[MIN]].{{[0-9]+}}: type=dwarf_info {{.*}} sym=[[MININFO:[0-9]+]]
; COMMON: aux [[MIN]].{{[0-9]+}}: type=dwarf_lines
; COMMON: aux [[MIN]].{{[0-9]+}}: type=pcfile
; COMMON: aux [[MIN]].{{[0-9]+}}: type=pcline
; COMMON-NOT: reloc [[MININFO]].{{.*}}kind=R_USETYPE
; MIXED: reloc [[FULLINFO]].{{.*}}kind=R_USETYPE
; MIXED-NOT: reloc [[MININFO]].{{.*}}kind=R_USETYPE
; PCLN: type=pcfile
; PCLN: type=pcline
; PCLN: type=pcfile
; PCLN: type=pcline
; MINIMAL-NOT: reloc [[FULLINFO]].{{.*}}kind=R_USETYPE
