; RUN: llc -mtriple=x86_64-unknown-linux-gnu -o - %s | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -o - %s | FileCheck %s --check-prefix=AARCH64

%large = type [4 x i64]
%memory.result = type [2 x i64]
%stack.arg = type { i64, i64, i64 }

declare goabiinternal void @write_statepoint_result(
    ptr goret(%memory.result) align 8 "goretindex"="0")
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

attributes #0 = { "go_results_tuple" }
