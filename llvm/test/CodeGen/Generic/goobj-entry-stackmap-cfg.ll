; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -goobj-package-path=main -filetype=obj %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -goobj-package-path=main -filetype=obj %s -o %t.a64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.a64.o | FileCheck %s

; A normal statepoint selects a live frame map. When physical block placement
; later reaches a CFG path at the entry SP depth, PCDATA_StackMapIndex must
; return to Go's entry value (-1), which runtime getStackMap normalizes to
; function-level ArgsPointerMaps bitmap 0, without identifying morestack by
; name.

; CHECK: type=pcdata target= pc=[0-{{[0-9]+}}:-1,{{[0-9]+}}-{{[0-9]+}}:1,{{[0-9]+}}-{{[0-9]+}}:-1]

declare goabiinternal void @callee()

define goabiinternal ptr addrspace(1)
    @entry_map_cfg(ptr addrspace(1) %pointer) "frame-pointer"="non-leaf"
    gc "statepoint-example" {
entry:
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void ()) @callee,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %pointer) ]
  %relocated = call coldcc ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  ret ptr addrspace(1) %relocated
}

declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
    token, i32 immarg, i32 immarg)
