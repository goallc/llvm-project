; RUN: opt -S -passes='default<O2>' %s | FileCheck %s --check-prefix=OPT
; RUN: opt -S -passes=rewrite-statepoints-for-gc %s | FileCheck %s --check-prefix=STATEPOINT
; RUN: llc -mtriple=arm64-apple-macosx -verify-machineinstrs -stop-before=aarch64-expand-pseudo -o - %s | FileCheck %s --check-prefix=PSEUDO
; RUN: llc -mtriple=arm64-apple-macosx -verify-machineinstrs -o - %s | FileCheck %s --check-prefix=ASM
; RUN: llc -O0 -mtriple=arm64-apple-macosx -verify-machineinstrs -o - %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -goobj-package-path=main \
; RUN:   -verify-machineinstrs -filetype=obj -o %t.o %s
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | \
; RUN:   FileCheck %s --check-prefix=OBJ

declare ptr @llvm.go.gc.write.barrier(i32 immarg)
declare goabiinternal void @"runtime.gcWriteBarrier1<builtin.234>"()
declare goabiinternal void @"runtime.gcWriteBarrier8<builtin.241>"()

define goabiinternal ptr @acquire_one() gc "statepoint-example" {
; OPT-LABEL: define goabiinternal ptr @acquire_one()
; OPT: call ptr @llvm.go.gc.write.barrier(i32 1)
;
; STATEPOINT-LABEL: define goabiinternal ptr @acquire_one()
; STATEPOINT: call ptr @llvm.go.gc.write.barrier(i32 1)
; STATEPOINT-NOT: gc.statepoint
;
; PSEUDO-LABEL: name: acquire_one
; PSEUDO: GO_GC_WRITE_BARRIER 1
; PSEUDO-SAME: implicit-def $x25
; PSEUDO-SAME: implicit-def {{(dead )?}}$x27
; PSEUDO-SAME: implicit $sp
;
; ASM-LABEL: _acquire_one:
; ASM: bl _runtime.gcWriteBarrier1
; ASM-NEXT: mov x0, x25
  %buf = call ptr @llvm.go.gc.write.barrier(i32 1)
  ret ptr %buf
}

define goabiinternal ptr @acquire_eight() gc "statepoint-example" {
; PSEUDO-LABEL: name: acquire_eight
; PSEUDO: GO_GC_WRITE_BARRIER 8
;
; ASM-LABEL: _acquire_eight:
; ASM: bl _runtime.gcWriteBarrier8
; ASM-NEXT: mov x0, x25
  %buf = call ptr @llvm.go.gc.write.barrier(i32 8)
  ret ptr %buf
}

define goabiinternal void @store_one(ptr %value) gc "statepoint-example" {
; PSEUDO-LABEL: name: store_one
; PSEUDO: GO_GC_WRITE_BARRIER 1
;
; ASM-LABEL: _store_one:
; ASM: bl _runtime.gcWriteBarrier1
; ASM-NEXT: str x0, [x25]
  %buf = call ptr @llvm.go.gc.write.barrier(i32 1)
  store ptr %value, ptr %buf
  ret void
}

; OBJ-NOT: nonpkgref {{[0-9]+}}: runtime.gcWriteBarrier
; OBJ: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size=4 type=9 add=0 target=builtin:234 {{.*}}pkg=builtin sym=234
; OBJ: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size=4 type=9 add=0 target=builtin:241 {{.*}}pkg=builtin sym=241
