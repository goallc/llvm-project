; RUN: llc -mtriple=x86_64-unknown-linux-gnu -experimental-debug-variable-locations \
; RUN:   -verify-machineinstrs -stop-after=livedebugvalues %s -o - | FileCheck %s
;
; Statepoint spill slots are not register-allocation spill slots. Track the
; variable in the GC slot even after its original return register is clobbered.
;
; CHECK-LABEL: name: with_gc_spill
; CHECK: DBG_VALUE_LIST ![[VAR:[0-9]+]], !DIExpression(DW_OP_LLVM_arg, 0), $rax,
; CHECK: MOV64mr $rsp, 1, $noreg, [[OFF:[0-9]+]], $noreg, {{.*}}$rax
; CHECK-NEXT: DBG_VALUE_LIST ![[VAR]], !DIExpression(DW_OP_LLVM_arg, 0, DW_OP_plus_uconst, [[OFF]], DW_OP_deref), $rsp,
; CHECK: STATEPOINT {{.*}}@safepoint
; CHECK-NOT: DBG_VALUE_LIST ![[VAR]]
; CHECK: CALL64pcrel32 {{.*}}@observe

declare ptr addrspace(1) @produce()
declare void @safepoint()
declare void @observe(ptr addrspace(1))
declare token @llvm.experimental.gc.statepoint.p0(i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare ptr addrspace(1) @llvm.experimental.gc.result.p1(token)
declare ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token, i32 immarg, i32 immarg)

define ptr addrspace(1) @with_gc_spill() gc "statepoint-example" !dbg !4 {
entry:
  %token = call token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 1, i32 0, ptr elementtype(ptr addrspace(1) ()) @produce, i32 0, i32 0, i32 0, i32 0), !dbg !6
  %value = call ptr addrspace(1) @llvm.experimental.gc.result.p1(token %token), !dbg !6
  #dbg_value(ptr addrspace(1) %value, !5, !DIExpression(), !6)
  %next = call token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 2, i32 0, ptr elementtype(void ()) @safepoint, i32 0, i32 0, i32 0, i32 0) [ "gc-live"(ptr addrspace(1) %value) ], !dbg !7
  %relocated = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %next, i32 0, i32 0), !dbg !7
  call void @observe(ptr addrspace(1) %relocated), !dbg !7
  ret ptr addrspace(1) %relocated, !dbg !7
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!8}
!0 = distinct !DICompileUnit(language: DW_LANG_C, file: !1, producer: "test", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "statepoint.c", directory: "/src")
!2 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!3 = !DISubroutineType(types: !{})
!4 = distinct !DISubprogram(name: "with_gc_spill", scope: !1, file: !1, line: 1, type: !3, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!5 = !DILocalVariable(name: "value", scope: !4, file: !1, line: 2, type: !2)
!6 = !DILocation(line: 2, column: 1, scope: !4)
!7 = !DILocation(line: 3, column: 1, scope: !4)
!8 = !{i32 2, !"Debug Info Version", i32 3}
