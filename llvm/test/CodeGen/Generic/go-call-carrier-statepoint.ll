; RUN: llc -mtriple=x86_64-unknown-linux-goobj -stop-after=finalize-isel -o - %s | FileCheck %s --check-prefixes=MIR,X86-MIR
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -stop-after=finalize-isel -o - %s | FileCheck %s --check-prefixes=MIR,AARCH64-MIR
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -stop-after=finalize-isel -o - %s | FileCheck %s --check-prefix=GENERIC
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -stop-after=finalize-isel -o - %s | FileCheck %s --check-prefix=GENERIC

%pair = type { ptr, i64 }

declare goabiinternal void @safepoint()
declare goabi0 void @roundtrip(
    ptr byval(%pair) align 8,
    ptr goret(%pair) align 8 "goretindex"="0")
declare goabi0 void @make_pointer(
    ptr goret(ptr addrspace(1)) align 8 "goretindex"="0")
declare goabi0 void @make_byte(
    ptr goret(i8) align 1 "goretindex"="0")
declare goabi0 void @consume(
    ptr byval(i64) align 8)
declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
    token, i32 immarg, i32 immarg)

; Both carriers are mentioned by an earlier statepoint solely to preserve
; their fixed-frame addresses. The byval source is otherwise a private
; initialization buffer, and the goret result has only bounded scalar loads.
; Go call lowering can therefore use the physical outgoing argument/result
; area directly without retaining either local FrameIndex.
;
; MIR-LABEL: name: forward_call_carriers
; MIR: stack:           []
; MIR: STATEPOINT {{.*}}@safepoint
; MIR: {{(MOV64mr|STRXui)}} {{.*}} :: (store (s64) into stack
; MIR: STATEPOINT {{.*}}@roundtrip
; MIR-COUNT-2: {{(MOV64rm|LDRXui)}} {{.*}} :: (load (s64) from stack
; MIR-NOT: %stack.
; MIR: RET
;
; On ordinary object formats, gc-live remains an explicit alloca contract.
; GENERIC-LABEL: name: forward_call_carriers
; GENERIC: stack:
; GENERIC-DAG: name: argument
; GENERIC-DAG: name: result
define goabiinternal i64 @forward_call_carriers(i64 %value)
    gc "statepoint-example" {
entry:
  %argument = alloca %pair, align 8
  %result = alloca %pair, align 8
  %before = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr %argument, ptr %result) ]
  store ptr null, ptr %argument, align 8
  %argument.value = getelementptr inbounds i8, ptr %argument, i64 8
  store i64 %value, ptr %argument.value, align 8
  %call = call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 2, i32 0, ptr elementtype(void (ptr, ptr)) @roundtrip,
          i32 2, i32 0,
          ptr byval(%pair) align 8 %argument,
          ptr goret(%pair) align 8 "goretindex"="0" %result,
          i32 0, i32 0)
      [ "gc-live"(ptr %argument, ptr %result) ]
  %result.pointer = load ptr, ptr %result, align 8
  %result.pointer.bits = ptrtoint ptr %result.pointer to i64
  %result.value.addr = getelementptr inbounds i8, ptr %result, i64 8
  %result.value = load i64, ptr %result.value.addr, align 8
  %sum = add i64 %result.pointer.bits, %result.value
  ret i64 %sum
}

; A projected pointer which reaches another statepoint cannot be introduced
; after statepoint liveness. Keep the goret home and use the ordinary IR root
; plus gc.relocate at the following call.
;
; MIR-LABEL: name: pointer_result_across_statepoint
; MIR: stack:
; MIR: name: result
; MIR: STATEPOINT {{.*}}@make_pointer
; MIR: STATEPOINT {{.*}}@safepoint
; MIR: RET
define goabiinternal ptr addrspace(1) @pointer_result_across_statepoint()
    gc "statepoint-example" {
entry:
  %result = alloca ptr addrspace(1), align 8
  %call = call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 3, i32 0, ptr elementtype(void (ptr)) @make_pointer,
          i32 1, i32 0,
          ptr goret(ptr addrspace(1)) align 8 "goretindex"="0" %result,
          i32 0, i32 0)
      [ "gc-live"(ptr %result) ]
  %pointer = load ptr addrspace(1), ptr %result, align 8
  %after = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 4, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %pointer) ]
  %relocated = call coldcc ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(
      token %after, i32 0, i32 0)
  ret ptr addrspace(1) %relocated
}

; Projection forwarding uses a virtual register directly and therefore only
; accepts value types which are already legal on the target. i8 is legal on
; X86, but AArch64 promotes it to a wider register type through the ordinary
; memory path. In particular, do not form an illegal CopyToReg after #110 makes
; an address-only gc-live use transparent to the carrier analysis.
;
; X86-MIR-LABEL: name: byte_result
; X86-MIR: stack:           []
; X86-MIR: STATEPOINT {{.*}}@make_byte
; X86-MIR: RET
; AARCH64-MIR-LABEL: name: byte_result
; AARCH64-MIR: stack:
; AARCH64-MIR: name: result
; AARCH64-MIR: STATEPOINT {{.*}}@make_byte
; AARCH64-MIR: RET
define goabiinternal i8 @byte_result()
    gc "statepoint-example" {
entry:
  %result = alloca i8, align 1
  %before = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 5, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr %result) ]
  %call = call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 6, i32 0, ptr elementtype(void (ptr)) @make_byte,
          i32 1, i32 0,
          ptr goret(i8) align 1 "goretindex"="0" %result,
          i32 0, i32 0)
      [ "gc-live"(ptr %result) ]
  %value = load i8, ptr %result, align 1
  ret i8 %value
}

; A deopt use can describe object contents or other externally observable
; storage. It is not an address-only gc-live use, so retain the local home.
;
; MIR-LABEL: name: deopt_byval_carrier
; MIR: stack:
; MIR: name: argument
; MIR: STATEPOINT {{.*}}@consume
; MIR: RET
define goabiinternal void @deopt_byval_carrier()
    gc "statepoint-example" {
entry:
  %argument = alloca i64, align 8
  store i64 42, ptr %argument, align 8
  %call = call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 5, i32 0, ptr elementtype(void (ptr)) @consume,
          i32 1, i32 0, ptr byval(i64) align 8 %argument,
          i32 0, i32 0)
      [ "deopt"(ptr %argument), "gc-live"(ptr %argument) ]
  ret void
}
