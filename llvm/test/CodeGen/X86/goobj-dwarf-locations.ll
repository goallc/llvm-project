; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s --check-prefixes=COMMON,DWARF4
; RUN: sed 's/!"dwarf4"/!"dwarf5"/' %s | llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj -o %t.d5.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.d5.o | FileCheck %s --check-prefixes=COMMON,DWARF5
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s --check-prefix=ARM64

; Locations come from final stack slots and register histories, never source
; alloca offsets. Unsupported expressions must stay unavailable.
@"type:int" = external global i8

declare goabiinternal void @use(ptr)

define goabiinternal i64 @"main.stack"(i64 %x) !dbg !10 {
  %home = alloca i64, align 8
  #dbg_declare(ptr %home, !12, !DIExpression(), !13)
  store i64 %x, ptr %home, align 8, !dbg !13
  call goabiinternal void @use(ptr %home), !dbg !13
  %result = load i64, ptr %home, align 8, !dbg !13
  ret i64 %result, !dbg !13
}

define goabiinternal i64 @"main.register"(i64 %x) !dbg !20 {
  ; InstrRefBasedLDV uses this single-operand list for ordinary SSA values.
  #dbg_value(!DIArgList(i64 %x), !22, !DIExpression(DW_OP_LLVM_arg, 0), !23)
  %sum = add i64 %x, 1, !dbg !23
  #dbg_value(i64 42, !22, !DIExpression(), !24)
  ret i64 %sum, !dbg !24
}

define goabiinternal i64 @"main.unavailable"(i64 %x) !dbg !30 {
  #dbg_value(i64 poison, !32, !DIExpression(), !33)
  ret i64 %x, !dbg !33
}


define goabiinternal i64 @"main.heap"(ptr %p) !dbg !40 {
  %home = alloca ptr, align 8
  #dbg_declare(ptr %home, !42, !DIExpression(DW_OP_deref), !43)
  store ptr %p, ptr %home, align 8, !dbg !43
  call goabiinternal void @use(ptr %home), !dbg !43
  %address = load ptr, ptr %home, align 8, !dbg !43
  %value = load i64, ptr %address, align 8, !dbg !43
  ret i64 %value, !dbg !43
}

define goabiinternal i64 @"main.pieces"(i64 %x, i64 %y) !dbg !50 {
  #dbg_value(i64 %x, !52, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !53)
  #dbg_value(i64 %y, !52, !DIExpression(DW_OP_LLVM_fragment, 64, 64), !53)
  %sum = add i64 %x, %y, !dbg !53
  #dbg_value(i64 poison, !52, !DIExpression(DW_OP_LLVM_fragment, 0, 64), !54)
  ret i64 %sum, !dbg !54
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!5, !6}
!goobj.debug.config = !{!7}
!goobj.debug.funcs = !{!8, !9, !14, !44, !55}
!goobj.debug.vars = !{!15, !25, !35, !45, !56}
!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !1, producer: "Go compiler", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "locations.go", directory: "/tmp")
!2 = !DIBasicType(name: "int", size: 64, encoding: DW_ATE_signed)
!3 = !DISubroutineType(types: !4)
!4 = !{!2, !2}
!5 = !{i32 2, !"Dwarf Version", i32 4}
!6 = !{i32 2, !"Debug Info Version", i32 3}
!7 = !{!"pcln-v1", !"dwarf-v1", !"dwarf4", !"main"}
!8 = !{!10, ptr @"main.stack"}
!9 = !{!20, ptr @"main.register"}
!14 = !{!30, ptr @"main.unavailable"}
!10 = distinct !DISubprogram(name: "main.stack", linkageName: "main.stack", file: !1, line: 1, type: !3, scopeLine: 1, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!12 = !DILocalVariable(name: "x", arg: 1, scope: !10, file: !1, line: 1, type: !2)
!13 = !DILocation(line: 2, column: 1, scope: !10)
!15 = !{!12, !"int", i32 0}
!20 = distinct !DISubprogram(name: "main.register", linkageName: "main.register", file: !1, line: 4, type: !3, scopeLine: 4, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!22 = !DILocalVariable(name: "x", arg: 1, scope: !20, file: !1, line: 4, type: !2)
!23 = !DILocation(line: 5, column: 1, scope: !20)
!24 = !DILocation(line: 6, column: 1, scope: !20)
!25 = !{!22, !"int", i32 0}
!30 = distinct !DISubprogram(name: "main.unavailable", linkageName: "main.unavailable", file: !1, line: 8, type: !3, scopeLine: 8, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!32 = !DILocalVariable(name: "x", arg: 1, scope: !30, file: !1, line: 8, type: !2)
!33 = !DILocation(line: 9, column: 1, scope: !30)
!35 = !{!32, !"int", i32 0}


!40 = distinct !DISubprogram(name: "main.heap", linkageName: "main.heap", file: !1, line: 11, type: !3, scopeLine: 11, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!42 = !DILocalVariable(name: "heap", arg: 1, scope: !40, file: !1, line: 11, type: !2)
!43 = !DILocation(line: 12, column: 1, scope: !40)
!44 = !{!40, ptr @"main.heap"}
!45 = !{!42, !"int", i32 0}
!50 = distinct !DISubprogram(name: "main.pieces", linkageName: "main.pieces", file: !1, line: 14, type: !3, scopeLine: 14, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!52 = !DILocalVariable(name: "pair", scope: !50, file: !1, line: 14, type: !57)
!53 = !DILocation(line: 15, column: 1, scope: !50)
!54 = !DILocation(line: 16, column: 1, scope: !50)
!55 = !{!50, ptr @"main.pieces"}
!56 = !{!52, !"pair", i32 0}
!57 = !DICompositeType(tag: DW_TAG_structure_type, name: "pair", file: !1, size: 128, elements: !58)
!58 = !{}

; COMMON: kind=SDWARFLOC
; COMMON: kind=SDWARFLOC
; COMMON: kind=SDWARFLOC
; COMMON: kind=SDWARFLOC
; The stack argument copy uses its caller-provided home: CFA+0 on X86,
; CFA+8 on AArch64. Register x is RAX until PC 3, then the constant 42.
; DWARF4: aux 0.{{[0-9]+}}: type=dwarf_loc target= data=000000000000000000000000000000000200910000000000000000000000000000000000
; DWARF5: aux 0.{{[0-9]+}}: type=dwarf_loc target= data=010000000004071d02910000
; DWARF4: aux 1.{{[0-9]+}}: type=dwarf_loc target= data=00000000000000000000000000000000010050000000000000000000000000000000000300112a9f00000000000000000000000000000000
; DWARF5: aux 1.{{[0-9]+}}: type=dwarf_loc target= data=0100000000040003015004030403112a9f00
; COMMON: aux 2.{{[0-9]+}}: type=dwarf_info
; COMMON-NOT: type=dwarf_loc
; The heap variable dereferences its pointer home; the fragmented pair keeps
; its second piece after the first piece becomes unavailable.
; COMMON: aux 3.{{[0-9]+}}: type=dwarf_info
; DWARF4: aux 3.{{[0-9]+}}: type=dwarf_loc target= data=00000000000000000000000000000000030091000600000000000000000000000000000000
; DWARF5: aux 3.{{[0-9]+}}: type=dwarf_loc target= data=01000000000407200391000600
; DWARF4: aux 4.{{[0-9]+}}: type=dwarf_loc target= data=000000000000000000000000000000000600509308539308000000000000000000000000000000000500930853930800000000000000000000000000000000
; DWARF5: aux 4.{{[0-9]+}}: type=dwarf_loc target= data=01000000000400030650930853930804030405930853930800
; DWARF4: type=98 add=7 target=main.stack
; DWARF4: type=98 add=29 target=main.stack
; DWARF4: type=98 add=0 target=main.register
; DWARF4: type=98 add=3 target=main.register
; DWARF4: type=98 add=3 target=main.register
; DWARF4: type=98 add=4 target=main.register
; ARM64: aux 0.{{[0-9]+}}: type=dwarf_loc target= data=000000000000000000000000000000000200910800000000000000000000000000000000
; ARM64: aux 1.{{[0-9]+}}: type=dwarf_loc target= data=000000000000000000000000000000000300112a9f00000000000000000000000000000000
; ARM64: aux 2.{{[0-9]+}}: type=dwarf_info
; ARM64-NOT: type=dwarf_loc
; ARM64: aux 3.{{[0-9]+}}: type=dwarf_info
; ARM64: aux 3.{{[0-9]+}}: type=dwarf_loc target= data=00000000000000000000000000000000030091080600000000000000000000000000000000
; ARM64: aux 4.{{[0-9]+}}: type=dwarf_loc target= data=000000000000000000000000000000000500930851930800000000000000000000000000000000
