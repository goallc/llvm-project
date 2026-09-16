; RUN: opt -passes=instcombine -S < %s | FileCheck %s
;
; A byval copy of a non-escaping, directly accessed scalar does not invalidate
; its existing value description. Escaped or indirectly modified storage must
; still use the address description. This is independent of the target ABI.

target datalayout = "e-p:64:64-i64:64-n8:16:32:64-S128"
@escaped = global ptr null

declare void @copy(ptr byval(i64) align 8)
declare void @modify(ptr)

; CHECK-LABEL: define void @local_copy(
; CHECK: #dbg_value(i64 7,
; CHECK-NOT: #dbg_value(ptr
; CHECK: call void @copy(
; CHECK-NOT: #dbg_value(ptr
; CHECK: ret void
define void @local_copy() !dbg !5 {
  %home = alloca i64, align 8
  #dbg_declare(ptr %home, !6, !DIExpression(), !7)
  store i64 7, ptr %home, align 8
  call void @copy(ptr byval(i64) align 8 %home)
  ret void
}

; CHECK-LABEL: define void @escaped_copy(
; CHECK: #dbg_value(ptr %home, {{.*}}!DIExpression(DW_OP_deref)
; CHECK-NEXT: call void @copy(
define void @escaped_copy() !dbg !8 {
  %home = alloca i64, align 8
  #dbg_declare(ptr %home, !9, !DIExpression(), !10)
  store i64 7, ptr %home, align 8
  store ptr %home, ptr @escaped
  call void @copy(ptr byval(i64) align 8 %home)
  ret void
}

; CHECK-LABEL: define void @derived_write(
; CHECK: #dbg_value(ptr %home, {{.*}}!DIExpression(DW_OP_deref)
; CHECK-NEXT: call void @copy(
define void @derived_write(i8 %x) !dbg !11 {
  %home = alloca i64, align 8
  #dbg_declare(ptr %home, !12, !DIExpression(), !13)
  store i64 7, ptr %home, align 8
  %part = getelementptr i8, ptr %home, i64 1
  store i8 %x, ptr %part
  call void @copy(ptr byval(i64) align 8 %home)
  ret void
}

; CHECK-LABEL: define void @ordinary_call(
; CHECK: #dbg_value(ptr %home, {{.*}}!DIExpression(DW_OP_deref)
; CHECK-NEXT: call void @modify(
define void @ordinary_call() !dbg !14 {
  %home = alloca i64, align 8
  #dbg_declare(ptr %home, !15, !DIExpression(), !16)
  store i64 7, ptr %home, align 8
  call void @modify(ptr %home)
  ret void
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!3}
!0 = distinct !DICompileUnit(language: DW_LANG_C99, file: !1, producer: "test", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "test.c", directory: "/")
!2 = !DISubroutineType(types: !{})
!3 = !{i32 2, !"Debug Info Version", i32 3}
!4 = !DIBasicType(name: "long", size: 64, encoding: DW_ATE_signed)
!5 = distinct !DISubprogram(name: "local_copy", scope: !1, file: !1, line: 1, type: !2, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!6 = !DILocalVariable(name: "value", scope: !5, file: !1, line: 2, type: !4)
!7 = !DILocation(line: 2, column: 1, scope: !5)
!8 = distinct !DISubprogram(name: "escaped_copy", scope: !1, file: !1, line: 1, type: !2, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!9 = !DILocalVariable(name: "value", scope: !8, file: !1, line: 2, type: !4)
!10 = !DILocation(line: 2, column: 1, scope: !8)
!11 = distinct !DISubprogram(name: "derived_write", scope: !1, file: !1, line: 1, type: !2, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!12 = !DILocalVariable(name: "value", scope: !11, file: !1, line: 2, type: !4)
!13 = !DILocation(line: 2, column: 1, scope: !11)
!14 = distinct !DISubprogram(name: "ordinary_call", scope: !1, file: !1, line: 1, type: !2, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!15 = !DILocalVariable(name: "value", scope: !14, file: !1, line: 2, type: !4)
!16 = !DILocation(line: 2, column: 1, scope: !14)
