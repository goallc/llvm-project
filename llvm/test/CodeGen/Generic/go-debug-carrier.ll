; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O2 -verify-machineinstrs -filetype=obj < %s -o %t.x86_64.o
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O2 -verify-machineinstrs -stop-after=finalize-isel < %s | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O2 -verify-machineinstrs -filetype=obj < %s -o %t.aarch64.o
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O2 -verify-machineinstrs -stop-after=finalize-isel < %s | FileCheck %s

; RUN: llvm-dwarfdump --verify %t.x86_64.o
; RUN: llvm-dwarfdump --verify %t.aarch64.o

; Debug addresses are observable even though metadata is absent from uses().
; Retain their homes, including when only a derived address has debug users.
%pair = type { i64, i64 }
declare goabi0 void @sink(ptr byval(%pair) align 8)
declare goabi0 void @source(ptr goret(%pair) align 8 "goretindex"="0")
declare token @llvm.experimental.gc.statepoint.p0(i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)

; CHECK-LABEL: name: byval_root
; CHECK: stack:
; CHECK-NEXT: - { id: 0, name: home, type: default, offset: 0, size: 16
; CHECK: debug-info-variable: '!{{[0-9]+}}', debug-info-expression: '!DIExpression()'
define goabiinternal i64 @byval_root() gc "statepoint-example" !dbg !10 {
entry:
  %home = alloca %pair, align 8
  %field = getelementptr inbounds %pair, ptr %home, i32 0, i32 1
  #dbg_declare(ptr %home, !11, !DIExpression(), !12)
  store %pair { i64 13, i64 17 }, ptr %home, align 8, !dbg !12
  call goabi0 void @sink(ptr byval(%pair) align 8 %home), !dbg !12
  ret i64 0, !dbg !12
}

; CHECK-LABEL: name: byval_gep
; CHECK: stack:
; CHECK-NEXT: - { id: 0, name: home, type: default, offset: 0, size: 16
; CHECK: debug-info-variable: '!{{[0-9]+}}', debug-info-expression: '!DIExpression(DW_OP_plus_uconst, 8)'
define goabiinternal i64 @byval_gep() gc "statepoint-example" !dbg !13 {
entry:
  %home = alloca %pair, align 8
  %field = getelementptr inbounds %pair, ptr %home, i32 0, i32 1
  #dbg_declare(ptr %field, !14, !DIExpression(), !15)
  store %pair { i64 13, i64 17 }, ptr %home, align 8, !dbg !15
  call goabi0 void @sink(ptr byval(%pair) align 8 %home), !dbg !15
  ret i64 0, !dbg !15
}

; CHECK-LABEL: name: goret_root
; CHECK: stack:
; CHECK-NEXT: - { id: 0, name: home, type: default, offset: 0, size: 16
; CHECK: debug-info-variable: '!{{[0-9]+}}', debug-info-expression: '!DIExpression()'
define goabiinternal i64 @goret_root() gc "statepoint-example" !dbg !16 {
entry:
  %home = alloca %pair, align 8
  %field = getelementptr inbounds %pair, ptr %home, i32 0, i32 1
  #dbg_declare(ptr %home, !17, !DIExpression(), !18)
  %token = call goabi0 token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(
      i64 1, i32 0, ptr elementtype(void (ptr)) @source, i32 1, i32 0,
      ptr goret(%pair) align 8 "goretindex"="0" %home, i32 0, i32 0), !dbg !18
  %value = load i64, ptr %field, align 8, !dbg !18
  ret i64 %value, !dbg !18
}

; CHECK-LABEL: name: goret_gep
; CHECK: stack:
; CHECK-NEXT: - { id: 0, name: home, type: default, offset: 0, size: 16
; CHECK: debug-info-variable: '!{{[0-9]+}}', debug-info-expression: '!DIExpression(DW_OP_plus_uconst, 8)'
define goabiinternal i64 @goret_gep() gc "statepoint-example" !dbg !19 {
entry:
  %home = alloca %pair, align 8
  %field = getelementptr inbounds %pair, ptr %home, i32 0, i32 1
  #dbg_declare(ptr %field, !20, !DIExpression(), !21)
  %token = call goabi0 token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(
      i64 1, i32 0, ptr elementtype(void (ptr)) @source, i32 1, i32 0,
      ptr goret(%pair) align 8 "goretindex"="0" %home, i32 0, i32 0), !dbg !21
  %value = load i64, ptr %field, align 8, !dbg !21
  ret i64 %value, !dbg !21
}

; CHECK-LABEL: name: byval_value
; CHECK: stack:
; CHECK-NEXT: - { id: 0, name: home, type: default, offset: 0, size: 16
; CHECK: DBG_VALUE %stack.0.home, $noreg, !{{[0-9]+}}, !DIExpression(DW_OP_deref)
define goabiinternal i64 @byval_value() gc "statepoint-example" !dbg !22 {
entry:
  %home = alloca %pair, align 8
  %field = getelementptr inbounds %pair, ptr %home, i32 0, i32 1
  #dbg_value(ptr %home, !23, !DIExpression(DW_OP_deref), !24)
  store %pair { i64 13, i64 17 }, ptr %home, align 8, !dbg !24
  call goabi0 void @sink(ptr byval(%pair) align 8 %home), !dbg !24
  ret i64 0, !dbg !24
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!8, !9}
!0 = distinct !DICompileUnit(language: DW_LANG_Go, file: !1, producer: "Go", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "test.go", directory: "/")
!2 = !DISubroutineType(types: !5)
!4 = !DIBasicType(name: "int", size: 64, encoding: DW_ATE_signed)
!5 = !{}
!8 = !{i32 2, !"Debug Info Version", i32 3}
!9 = !{i32 2, !"Dwarf Version", i32 4}
!10 = distinct !DISubprogram(name: "byval_root", scope: !1, file: !1, line: 1, type: !2, scopeLine: 1, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!11 = !DILocalVariable(name: "value", scope: !10, file: !1, line: 2, type: !4)
!12 = !DILocation(line: 2, column: 1, scope: !10)
!13 = distinct !DISubprogram(name: "byval_gep", scope: !1, file: !1, line: 1, type: !2, scopeLine: 1, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!14 = !DILocalVariable(name: "value", scope: !13, file: !1, line: 2, type: !4)
!15 = !DILocation(line: 2, column: 1, scope: !13)
!16 = distinct !DISubprogram(name: "goret_root", scope: !1, file: !1, line: 1, type: !2, scopeLine: 1, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!17 = !DILocalVariable(name: "value", scope: !16, file: !1, line: 2, type: !4)
!18 = !DILocation(line: 2, column: 1, scope: !16)
!19 = distinct !DISubprogram(name: "goret_gep", scope: !1, file: !1, line: 1, type: !2, scopeLine: 1, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!20 = !DILocalVariable(name: "value", scope: !19, file: !1, line: 2, type: !4)
!21 = !DILocation(line: 2, column: 1, scope: !19)

!22 = distinct !DISubprogram(name: "byval_value", scope: !1, file: !1, line: 1, type: !2, scopeLine: 1, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!23 = !DILocalVariable(name: "value", scope: !22, file: !1, line: 2, type: !4)
!24 = !DILocation(line: 2, column: 1, scope: !22)
