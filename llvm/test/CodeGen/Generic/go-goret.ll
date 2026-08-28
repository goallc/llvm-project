; RUN: llc -mtriple=x86_64-unknown-linux-gnu -o - %s | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -o - %s | FileCheck %s --check-prefix=AARCH64
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -stop-after=finalize-isel -o - %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -stop-after=finalize-isel -o - %s | FileCheck %s --check-prefix=MIR

%large = type [4 x i64]
%memory.result = type [2 x i64]
%stack.arg = type { i64, i64, i64 }
%zero.array.result = type { i64, [3 x {}], double }
%slice.result = type { ptr, i64, i64 }
%large.projection = type { ptr, i64, i64, i64, i64, i64, i64, i64, i64 }

declare goabiinternal void @write_statepoint_result(
    ptr goret(%memory.result) align 8 "goretindex"="0")
declare goabi0 void @write_statepoint_slice(
    ptr goret(%slice.result) align 8 "goretindex"="0")
declare goabi0 void @write_large_projection(
    ptr goret(%large.projection) align 8 "goretindex"="0")
declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)

define goabiinternal { i64, double } @mixed_results(
    i64 %arg,
    ptr goret(%large) align 8 "goretindex"="1" %memory.result) #0 {
; X86-LABEL: mixed_results:
; X86: movq $42, 8(%rsp)
; X86: retq
; AARCH64-LABEL: mixed_results:
; AARCH64: str {{x[0-9]+}}, [sp, #8]
; AARCH64: ret
entry:
  store i64 42, ptr %memory.result, align 8
  %direct0 = insertvalue { i64, double } poison, i64 %arg, 0
  %direct1 = insertvalue { i64, double } %direct0, double 1.000000e+00, 1
  ret { i64, double } %direct1
}

define goabiinternal i64 @call_mixed_results(i64 %arg) {
; X86-LABEL: call_mixed_results:
; X86: callq mixed_results
; AARCH64-LABEL: call_mixed_results:
; AARCH64: bl mixed_results
entry:
  %memory.result = alloca %large, align 8
  %direct = call goabiinternal { i64, double } @mixed_results(
      i64 %arg,
      ptr goret(%large) align 8 "goretindex"="1" %memory.result) #0
  %direct0 = extractvalue { i64, double } %direct, 0
  %memory0 = load i64, ptr %memory.result, align 8
  %sum = add i64 %direct0, %memory0
  ret i64 %sum
}

; A multi-element array is memory-assigned even when its elements have zero
; size. Keep the first logical result in memory and the second in a register.
define goabiinternal i64 @zero_array_memory_result(
    i64 %direct,
    ptr goret(%zero.array.result) align 8 "goretindex"="0" %memory.result) {
; X86-LABEL: zero_array_memory_result:
; X86: movq $42, 8(%rsp)
; X86: retq
; AARCH64-LABEL: zero_array_memory_result:
; AARCH64: str {{x[0-9]+}}, [sp, #8]
; AARCH64: ret
entry:
  store i64 42, ptr %memory.result, align 8
  ret i64 %direct
}

define goabiinternal i64 @call_zero_array_memory_result(i64 %arg) {
; X86-LABEL: call_zero_array_memory_result:
; X86: callq zero_array_memory_result
; AARCH64-LABEL: call_zero_array_memory_result:
; AARCH64: bl zero_array_memory_result
entry:
  %memory.result = alloca %zero.array.result, align 8
  %direct = call goabiinternal i64 @zero_array_memory_result(
      i64 %arg,
      ptr goret(%zero.array.result) align 8 "goretindex"="0" %memory.result)
  ret i64 %direct
}

define goabiinternal void @result_after_byval(
    ptr byval(%stack.arg) align 8 %arg,
    ptr goret(%memory.result) align 8 "goretindex"="0" %memory.result) {
; The 24-byte typed stack input precedes the aligned result area. The X86
; return address and the AArch64 Go stack bias both make the callee-visible
; result address sp+32.
; X86-LABEL: result_after_byval:
; X86: movq $7, 32(%rsp)
; X86: retq
; AARCH64-LABEL: result_after_byval:
; AARCH64: str {{x[0-9]+}}, [sp, #32]
; AARCH64: ret
entry:
  store i64 7, ptr %memory.result, align 8
  ret void
}

define goabiinternal i64 @statepoint_goret() gc "statepoint-example" {
; X86-LABEL: statepoint_goret:
; X86: callq write_statepoint_result
; AARCH64-LABEL: statepoint_goret:
; AARCH64: bl write_statepoint_result
entry:
  %memory.result = alloca %memory.result, align 8
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0,
          ptr elementtype(void (ptr)) @write_statepoint_result,
          i32 1, i32 0,
          ptr goret(%memory.result) align 8 "goretindex"="0" %memory.result,
          i32 0, i32 0)
  %value = load i64, ptr %memory.result, align 8
  ret i64 %value
}

; A bounded set of scalar loads from a pure goret carrier is read directly
; from the outgoing ABI0 result area. No local result FrameIndex remains.
; MIR-LABEL: name: statepoint_slice_projection
; MIR-NOT: name: memory.result
; MIR: stack: []
; MIR: STATEPOINT {{.*}}@write_statepoint_slice
; MIR-COUNT-3: {{(MOV64rm|LDRXui)}} {{.*}} :: (load (s64) from stack
; MIR: RET
define goabiinternal %slice.result @statepoint_slice_projection()
    gc "statepoint-example" {
entry:
  %memory.result = alloca %slice.result, align 8
  %token = call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 2, i32 0,
          ptr elementtype(void (ptr)) @write_statepoint_slice,
          i32 1, i32 0,
          ptr goret(%slice.result) align 8 "goretindex"="0" %memory.result,
          i32 0, i32 0)
  %base = load ptr, ptr %memory.result, align 8
  %len.addr = getelementptr inbounds i8, ptr %memory.result, i64 8
  %len = load i64, ptr %len.addr, align 8
  %cap.addr = getelementptr inbounds i8, ptr %memory.result, i64 16
  %cap = load i64, ptr %cap.addr, align 8
  %ret0 = insertvalue %slice.result poison, ptr %base, 0
  %ret1 = insertvalue %slice.result %ret0, i64 %len, 1
  %ret2 = insertvalue %slice.result %ret1, i64 %cap, 2
  ret %slice.result %ret2
}

; More than eight projections deliberately remains on the memory path so a
; large aggregate never becomes a complex SelectionDAG SSA result.
; MIR-LABEL: name: statepoint_large_projection_fallback
; MIR: name: memory.result
; MIR: STATEPOINT {{.*}}@write_large_projection
; MIR: {{(MOV64rm|LDRXui)}} %stack.{{[0-9]+}}.memory.result
; MIR: RET
define goabiinternal i64 @statepoint_large_projection_fallback()
    gc "statepoint-example" {
entry:
  %memory.result = alloca %large.projection, align 8
  %token = call goabi0 token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 3, i32 0,
          ptr elementtype(void (ptr)) @write_large_projection,
          i32 1, i32 0,
          ptr goret(%large.projection) align 8 "goretindex"="0" %memory.result,
          i32 0, i32 0)
  %v0.ptr = load ptr, ptr %memory.result, align 8
  %v0 = ptrtoint ptr %v0.ptr to i64
  %p1 = getelementptr inbounds i8, ptr %memory.result, i64 8
  %v1 = load i64, ptr %p1, align 8
  %s1 = add i64 %v0, %v1
  %p2 = getelementptr inbounds i8, ptr %memory.result, i64 16
  %v2 = load i64, ptr %p2, align 8
  %s2 = add i64 %s1, %v2
  %p3 = getelementptr inbounds i8, ptr %memory.result, i64 24
  %v3 = load i64, ptr %p3, align 8
  %s3 = add i64 %s2, %v3
  %p4 = getelementptr inbounds i8, ptr %memory.result, i64 32
  %v4 = load i64, ptr %p4, align 8
  %s4 = add i64 %s3, %v4
  %p5 = getelementptr inbounds i8, ptr %memory.result, i64 40
  %v5 = load i64, ptr %p5, align 8
  %s5 = add i64 %s4, %v5
  %p6 = getelementptr inbounds i8, ptr %memory.result, i64 48
  %v6 = load i64, ptr %p6, align 8
  %s6 = add i64 %s5, %v6
  %p7 = getelementptr inbounds i8, ptr %memory.result, i64 56
  %v7 = load i64, ptr %p7, align 8
  %s7 = add i64 %s6, %v7
  %p8 = getelementptr inbounds i8, ptr %memory.result, i64 64
  %v8 = load i64, ptr %p8, align 8
  %s8 = add i64 %s7, %v8
  ret i64 %s8
}

attributes #0 = { "go_results_tuple" }
