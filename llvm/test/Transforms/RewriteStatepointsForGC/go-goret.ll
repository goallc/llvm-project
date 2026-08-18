; RUN: opt -passes=rewrite-statepoints-for-gc -S %s | FileCheck %s
; RUN: opt -passes=rewrite-statepoints-for-gc -S %s \
; RUN:   | llc -mtriple=x86_64-unknown-linux-gnu -verify-machineinstrs -o /dev/null
; RUN: opt -passes=rewrite-statepoints-for-gc -S %s \
; RUN:   | llc -mtriple=aarch64-unknown-linux-gnu -verify-machineinstrs -o /dev/null

%result = type { [64 x i64] }

declare goabiinternal void @write_result(
    ptr goret(%result) align 8 "goretindex"="0")

define i64 @caller() gc "statepoint-example" {
; CHECK-LABEL: define i64 @caller()
; CHECK: call goabiinternal token {{.*}} @llvm.experimental.gc.statepoint.p0(
; CHECK-SAME: ptr goret(%result) align 8 "goretindex"="0" %memory.result,
entry:
  %memory.result = alloca %result, align 8
  call goabiinternal void @write_result(
      ptr goret(%result) align 8 "goretindex"="0" %memory.result)
  %value = load i64, ptr %memory.result, align 8
  ret i64 %value
}
