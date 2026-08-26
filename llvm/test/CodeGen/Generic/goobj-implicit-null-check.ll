; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=implicit-null-checks -o - %s | \
; RUN:   FileCheck %s --check-prefixes=MIR,X86-MIR
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=implicit-null-checks -o - %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs -o - %s | \
; RUN:   FileCheck %s --check-prefixes=ASM,X86-ASM
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -verify-machineinstrs -o - %s | \
; RUN:   FileCheck %s --check-prefixes=ASM,AARCH64-ASM
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.x86.o %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o %t.a64.o %s
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | \
; RUN:   FileCheck %s --check-prefix=X86-OBJ
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.a64.o | \
; RUN:   FileCheck %s --check-prefix=AARCH64-OBJ

; GoObj enables ImplicitNullChecks by default, but only the producer-owned
; !{!"goallc"} marker opts a branch into Go's signal-based nil-check contract.
; The faulting access must stay in [0, runtime.minLegalPointer), and its debug
; location must identify the explicit nil check rather than the later load.

declare goabi0 void @"consume_byval<ABI0>"(ptr byval(i64) align 8)
declare goabiinternal void @observe(ptr)
declare goabiinternal void @runtime.deferreturn()
declare goabiinternal void @runtime.panicmem()
declare void @llvm.go.defer.edge()
declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)

; MIR: [[CHECK_LOC:![0-9]+]] = !DILocation(line: 10,
; MIR-LABEL: name: fold_nonnegative
; MIR-NOT: FAULTING_OP
; MIR: debug-location [[CHECK_LOC]] :: (load (s64) from %ir.addr)
; ASM-LABEL: fold_nonnegative:
; ASM-NOT: runtime.panicmem
; Removing the shrink-wrapped panic path before frame lowering must not leave
; its 16-byte frame size on this leaf function's Go metadata.
; AARCH64-OBJ: symdef [[FOLD:[0-9]+]]: fold_nonnegative {{.*}}flag=8
; AARCH64-OBJ: aux [[FOLD]].{{[0-9]+}}: type=funcinfo {{.*}}locals=0
; AARCH64-OBJ: aux [[FOLD]].{{[0-9]+}}: type=pcsp {{.*}}pc=[0-{{[0-9]+}}:0]
; X86-OBJ: symdef [[FOLD:[0-9]+]]: fold_nonnegative {{.*}}flag=24
; X86-OBJ: aux [[FOLD]].{{[0-9]+}}: type=funcinfo {{.*}}locals=0
; X86-OBJ: aux [[FOLD]].{{[0-9]+}}: type=pcsp {{.*}}pc=[0-{{[0-9]+}}:0]
define goabiinternal i64 @fold_nonnegative(ptr %p) #0 !dbg !4 {
entry:
  %isnil = icmp eq ptr %p, null
  br i1 %isnil, label %nil, label %notnil, !make.implicit !0, !dbg !7

nil:
  call goabiinternal void @runtime.panicmem(), !dbg !7
  unreachable

notnil:
  %addr = getelementptr i8, ptr %p, i64 8, !dbg !8
  %value = load i64, ptr %addr, align 8, !dbg !8
  ret i64 %value
}

; The frontend panic call is a statepoint before Machine CodeGen. Once its
; implicit nil check folds, Machine CFG reachability cleanup must remove that
; dead path without losing the function entry stack map.
; ASM-LABEL: fold_statepoint_panic:
; ASM-NOT: runtime.panicmem
define goabiinternal i64 @fold_statepoint_panic(ptr %p) #0
    gc "statepoint-example" {
entry:
  %isnil = icmp eq ptr %p, null
  br i1 %isnil, label %nil, label %notnil, !make.implicit !0

nil:
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void ()) @runtime.panicmem,
          i32 0, i32 0, i32 0, i32 0)
  unreachable

notnil:
  %value = load i64, ptr %p, align 8
  ret i64 %value
}

; A defer callbr indirect destination has no physical branch, but it is a
; required Machine CFG recovery entry. Removing the folded nil path with the
; standard reachability pass must preserve this target.
; MIR-LABEL: name: preserve_defer_callbr_target
; MIR-NOT: FAULTING_OP
; MIR: recover (inlineasm-br-indirect-target)
; MIR: runtime.deferreturn
; ASM-LABEL: preserve_defer_callbr_target:
; ASM-NOT: runtime.panicmem
; ASM: runtime.deferreturn
define goabiinternal i64 @preserve_defer_callbr_target(ptr %p) #0 {
entry:
  callbr void @llvm.go.defer.edge()
      to label %check [label %recover]

check:
  %isnil = icmp eq ptr %p, null
  br i1 %isnil, label %nil, label %notnil, !make.implicit !0

nil:
  call goabiinternal void @runtime.panicmem()
  unreachable

notnil:
  %value = load i64, ptr %p, align 8
  ret i64 %value

recover:
  call goabiinternal void @runtime.deferreturn()
  ret i64 0
}

; If the panic handler itself is a defer callbr indirect destination, the
; standard reachability pass preserves it through the callbr Machine CFG edge.
; MIR-LABEL: name: preserve_defer_callbr_panic_target
; MIR-NOT: FAULTING_OP
; MIR: nil (inlineasm-br-indirect-target)
; MIR: runtime.panicmem
; ASM-LABEL: preserve_defer_callbr_panic_target:
; ASM: runtime.panicmem
define goabiinternal i64 @preserve_defer_callbr_panic_target(ptr %p) #0 {
entry:
  callbr void @llvm.go.defer.edge()
      to label %check [label %nil]

check:
  %isnil = icmp eq ptr %p, null
  br i1 %isnil, label %nil, label %notnil, !make.implicit !0

nil:
  call goabiinternal void @runtime.panicmem()
  unreachable

notnil:
  %value = load i64, ptr %p, align 8
  ret i64 %value
}

; A byval argument is expanded to a memcpy during call lowering. Preserve the
; source IR pointer on that memcpy's load so alias analysis can prove that the
; load may move above an unrelated stack store.
; ASM-LABEL: fold_byval_after_store:
; AARCH64-ASM: runtime.panicmem
; X86-MIR-LABEL: name: fold_byval_after_store
; X86-MIR-NOT: FAULTING_OP
; X86-MIR: MOV64rm {{.*}}from %ir.p
; X86-ASM-NOT: runtime.panicmem
define goabiinternal void @fold_byval_after_store(ptr %p) #0 {
entry:
  %slot = alloca i64, align 8
  %isnil = icmp eq ptr %p, null
  br i1 %isnil, label %nil, label %notnil, !make.implicit !0

nil:
  call goabiinternal void @runtime.panicmem()
  unreachable

notnil:
  store i64 1, ptr %slot, align 8
  call goabi0 void @"consume_byval<ABI0>"(ptr byval(i64) align 8 %p)
  call goabiinternal void @observe(ptr %slot)
  ret void
}

; A negative displacement from null wraps to a high address. Go would treat
; that signal as fatal rather than route it through panicmem.
; X86-ASM-LABEL: keep_negative:
; MIR-LABEL: name: keep_negative
; MIR-NOT: FAULTING_OP
define goabiinternal i64 @keep_negative(ptr %p) {
entry:
  %isnil = icmp eq ptr %p, null
  br i1 %isnil, label %nil, label %notnil, !make.implicit !0

nil:
  ret i64 0

notnil:
  %addr = getelementptr i8, ptr %p, i64 -8
  %value = load i64, ptr %addr, align 8
  ret i64 %value
}

; The first address not classified as a nil fault is also rejected.
; MIR-LABEL: name: keep_boundary
; MIR-NOT: FAULTING_OP
define goabiinternal i64 @keep_boundary(ptr %p) {
entry:
  %isnil = icmp eq ptr %p, null
  br i1 %isnil, label %nil, label %notnil, !make.implicit !0

nil:
  ret i64 0

notnil:
  %addr = getelementptr i8, ptr %p, i64 4096
  %value = load i64, ptr %addr, align 8
  ret i64 %value
}

; The generic empty marker must not opt GoObj into a contract that requires
; LLVM fault-map support.
; MIR-LABEL: name: keep_generic_marker
; MIR-NOT: FAULTING_OP
define goabiinternal i64 @keep_generic_marker(ptr %p) {
entry:
  %isnil = icmp eq ptr %p, null
  br i1 %isnil, label %nil, label %notnil, !make.implicit !1

nil:
  ret i64 0

notnil:
  %value = load i64, ptr %p, align 8
  ret i64 %value
}

!llvm.dbg.cu = !{!2}
!llvm.module.flags = !{!3}

!0 = !{!"goallc"}
!1 = !{}
attributes #0 = { "frame-pointer"="non-leaf" }
!2 = distinct !DICompileUnit(language: DW_LANG_Go, file: !5, emissionKind: FullDebug)
!3 = !{i32 2, !"Debug Info Version", i32 3}
!4 = distinct !DISubprogram(name: "fold_nonnegative", scope: !5, file: !5, line: 1, type: !6, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !2)
!5 = !DIFile(filename: "nilcheck.go", directory: "/")
!6 = !DISubroutineType(types: !1)
!7 = !DILocation(line: 10, column: 2, scope: !4)
!8 = !DILocation(line: 20, column: 9, scope: !4)
