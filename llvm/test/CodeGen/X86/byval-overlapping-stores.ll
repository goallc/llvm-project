; RUN: llc -mtriple=x86_64-unknown-linux-gnu -disable-cgp -O2 -verify-machineinstrs -stop-after=finalize-isel < %s | FileCheck %s --check-prefixes=MIR,X86
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -disable-cgp -O2 -verify-machineinstrs -stop-after=finalize-isel < %s | FileCheck %s --check-prefixes=MIR,ARM

; Exercise DAG forwarding without IR preparation or dead-store elimination.
; The overlapping stores must stay ordered even when disjoint stores are
; available on separate memory chains. There must be no source reload.
declare void @consume24(ptr byval([24 x i8]) align 8)

; MIR-LABEL: name: wide_then_narrow
; MIR: stack: []
; MIR: body:
; X86: %[[BASE:[0-9]+]]:gr64 = COPY $rsp
; X86: MOV64mr %[[BASE]], 1, $noreg, 0, $noreg, %
; X86: MOV32mr %[[BASE]], 1, $noreg, 4, $noreg, %
; ARM: %[[BASE:[0-9]+]]:gpr64sp = COPY $sp
; ARM: STRXui %{{[0-9]+}}, %[[BASE]], 0
; ARM: STRWui %{{[0-9]+}}, %[[BASE]], 1
define void @wide_then_narrow(i64 %wide, i32 %narrow, i64 %a, i64 %b) {
entry:
  %slot = alloca [24 x i8], align 8
  %p8 = getelementptr i8, ptr %slot, i64 8
  store i64 %a, ptr %p8, align 8
  store i64 %wide, ptr %slot, align 8
  %p16 = getelementptr i8, ptr %slot, i64 16
  store i64 %b, ptr %p16, align 8
  %p4 = getelementptr i8, ptr %slot, i64 4
  store i32 %narrow, ptr %p4, align 4
  call void @consume24(ptr byval([24 x i8]) align 8 %slot)
  ret void
}

; MIR-LABEL: name: narrow_then_wide
; MIR: stack: []
; MIR: body:
; The fully overwritten narrow store may be eliminated after forwarding.
; X86: %[[BASE2:[0-9]+]]:gr64 = COPY $rsp
; X86: MOV64mr %[[BASE2]], 1, $noreg, 0, $noreg, %
; ARM: %[[BASE2:[0-9]+]]:gpr64sp = COPY $sp
; ARM: STRXui %{{[0-9]+}}, %[[BASE2]], 0
define void @narrow_then_wide(i64 %wide, i32 %narrow, i64 %a, i64 %b) {
entry:
  %slot = alloca [24 x i8], align 8
  %p4 = getelementptr i8, ptr %slot, i64 4
  store i32 %narrow, ptr %p4, align 4
  %p8 = getelementptr i8, ptr %slot, i64 8
  store i64 %a, ptr %p8, align 8
  store i64 %wide, ptr %slot, align 8
  %p16 = getelementptr i8, ptr %slot, i64 16
  store i64 %b, ptr %p16, align 8
  call void @consume24(ptr byval([24 x i8]) align 8 %slot)
  ret void
}
