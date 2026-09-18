; RUN: llc -mtriple=aarch64-unknown-linux-goobj -O0 -fast-isel -verify-machineinstrs -stop-after=finalize-isel < %s | FileCheck %s --check-prefixes=CHECK,O0
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -O2 -verify-machineinstrs -stop-after=finalize-isel < %s | FileCheck %s --check-prefixes=CHECK,O2

; The load/store blocks end in branches so FastISel can handle them without
; encountering a Go return or statepoint first. It must not reuse an address
; exported by formal-argument lowering: grow may have copied the Go stack.
declare goabiinternal void @grow()
declare token @llvm.experimental.gc.statepoint.p0(i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)

define goabiinternal i64 @read_byval(ptr byval([2 x i64]) align 8 %arg) gc "statepoint-example" {
entry:
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 1, i32 0, ptr elementtype(void ()) @grow, i32 0, i32 0, i32 0, i32 0)
  br label %read
read:
  %field = getelementptr i64, ptr %arg, i64 1
  %value = load volatile i64, ptr %field, align 8
  br label %exit
exit:
  ret i64 %value
}
; CHECK-LABEL: name: read_byval
; CHECK: STATEPOINT
; O0: bb.1.read:
; O0: [[BASE:%[0-9]+]]:gpr64sp = ADDXri %fixed-stack.{{[0-9]+}}, 0, 0
; O0: [[FIELD:%[0-9]+]]:gpr64sp = ADDXri killed [[BASE]], 8, 0
; O0: LDRXui [[FIELD]], 0
; O2: LDRXui %fixed-stack.{{[0-9]+}}, 1

define goabiinternal void @write_goret(ptr goret([2 x i64]) align 8 "goretindex"="0" %result) gc "statepoint-example" {
entry:
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 1, i32 0, ptr elementtype(void ()) @grow, i32 0, i32 0, i32 0, i32 0)
  br label %write
write:
  %field = getelementptr i64, ptr %result, i64 1
  store volatile i64 42, ptr %field, align 8
  br label %exit
exit:
  ret void
}
; CHECK-LABEL: name: write_goret
; CHECK: STATEPOINT
; O0: bb.1.write:
; O0: [[BASE:%[0-9]+]]:gpr64sp = ADDXri %fixed-stack.{{[0-9]+}}, 0, 0
; O0: [[FIELD:%[0-9]+]]:gpr64sp = ADDXri killed [[BASE]], 8, 0
; O0: STRXui {{.*}}, [[FIELD]], 0
; O2: STRXui {{.*}}, %fixed-stack.{{[0-9]+}}, 1
