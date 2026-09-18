; RUN: llc -mtriple=x86_64-unknown-linux-gnu -experimental-debug-variable-locations \
; RUN:   -verify-machineinstrs -stop-after=finalize-isel %s -o - | FileCheck %s --check-prefix=ISEL
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -experimental-debug-variable-locations \
; RUN:   -verify-machineinstrs -stop-after=livedebugvalues %s -o - | FileCheck %s --check-prefix=LIVE

; FinalizeISel expands statepoint frame indices into stack-map operands.
; Replacing the instruction must preserve references to its return-register
; definition, whose operand index moves past the expanded frame indices.
; This uses the ordinary C ABI and the standard statepoint GC strategy.

; ISEL-LABEL: name: with_stack_slot
; ISEL: debugValueSubstitutions:
; ISEL: { srcinst: 1, srcop: 20, dstinst: [[NEW:[0-9]+]], dstop: 22, subreg: 0 }
; ISEL: STATEPOINT {{.*}}implicit-def $rax, debug-instr-number [[NEW]]
; ISEL: DBG_INSTR_REF {{.*}}dbg-instr-ref(1, 20)

; LIVE-LABEL: name: with_stack_slot
; LIVE: DBG_INSTR_REF ![[VAR:[0-9]+]], {{.*}}dbg-instr-ref(1, 20)
; LIVE-NEXT: DBG_VALUE_LIST ![[VAR]], !DIExpression(DW_OP_LLVM_arg, 0), $rbx,
; LIVE: CALL64pcrel32 {{.*}}@observe
; LIVE: DBG_VALUE_LIST ![[VAR]], !DIExpression(DW_OP_LLVM_arg, 0), $rax,

declare i64 @produce()
declare void @observe(i64, ptr)
declare token @llvm.experimental.gc.statepoint.p0(i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare i64 @llvm.experimental.gc.result.i64(token)

define i64 @with_stack_slot() gc "statepoint-example" !dbg !4 {
entry:
  %slot = alloca i64, align 8
  store i64 0, ptr %slot
  %token = call token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 1, i32 0, ptr elementtype(i64 ()) @produce, i32 0, i32 0, i32 0, i32 0) [ "deopt"(ptr %slot) ], !dbg !6
  %value = call i64 @llvm.experimental.gc.result.i64(token %token), !dbg !6
  #dbg_value(i64 %value, !5, !DIExpression(), !6)
  call void @observe(i64 %value, ptr %slot), !dbg !7
  ret i64 %value, !dbg !7
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!8}
!0 = distinct !DICompileUnit(language: DW_LANG_C, file: !1, producer: "test", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "statepoint.c", directory: "/src")
!2 = !DIBasicType(name: "long", size: 64, encoding: DW_ATE_signed)
!3 = !DISubroutineType(types: !{})
!4 = distinct !DISubprogram(name: "with_stack_slot", scope: !1, file: !1, line: 1, type: !3, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!5 = !DILocalVariable(name: "value", scope: !4, file: !1, line: 2, type: !2)
!6 = !DILocation(line: 2, column: 1, scope: !4)
!7 = !DILocation(line: 3, column: 1, scope: !4)
!8 = !{i32 2, !"Debug Info Version", i32 3}
