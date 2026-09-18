; REQUIRES: aarch64-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs \
; RUN:   -stop-before=prolog-epilog < %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs < %s \
; RUN:   | FileCheck %s --check-prefix=ASM

declare goabiinternal void @safepoint()

define goabiinternal void @illegal_vector_spill(ptr %in, ptr %out)
    "frame-pointer"="non-leaf" gc "statepoint-example" {
entry:
  %value = load <4 x ptr addrspace(1)>, ptr %in, align 8
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(<4 x ptr addrspace(1)> %value) ]
  %relocated = call coldcc <4 x ptr addrspace(1)>
      @llvm.experimental.gc.relocate.v4p1(token %token, i32 0, i32 0)
  store <4 x ptr addrspace(1)> %relocated, ptr %out, align 8
  ret void
}

define goabiinternal void @pointer_spill(ptr addrspace(1) %value, ptr %out)
    "frame-pointer"="non-leaf" gc "statepoint-example" {
entry:
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 2, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %value) ]
  %relocated = call coldcc ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  store ptr addrspace(1) %relocated, ptr %out, align 8
  ret void
}

declare token @llvm.experimental.gc.statepoint.p0(
    i64, i32, ptr, i32, i32, ...)
declare <4 x ptr addrspace(1)> @llvm.experimental.gc.relocate.v4p1(
    token, i32, i32)
declare ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token, i32, i32)

; MIR-LABEL: name: illegal_vector_spill
; MIR: maxAlignment:    16
; MIR: size: 32, alignment: 16
; MIR-LABEL: name: pointer_spill
; MIR: stack:
; MIR-NEXT: {{ *}}- { id: 0, name: '', type: default, offset: 0, size: 8, alignment: 8,

; ASM-LABEL: illegal_vector_spill:
; ASM-NOT: and	sp
; ASM: bl safepoint
; ASM: ret
; ASM-LABEL: pointer_spill:
; ASM-NOT: and	sp
; ASM: bl safepoint
; ASM: ret
