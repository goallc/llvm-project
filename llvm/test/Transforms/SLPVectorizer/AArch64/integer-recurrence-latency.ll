; RUN: opt -passes=slp-vectorizer -S -mcpu=generic < %s | FileCheck %s
; RUN: opt -passes=slp-vectorizer -S -mcpu=apple-m4 < %s | FileCheck %s
;
; Packing independent recurrence states reduces instruction count but puts all
; lanes on the longer vector rotate dependency chain (SHL + USRA on AArch64).
; Keep the scalar chains while still vectorizing independent rounds and integer
; recurrences whose latency does not increase.
;
target triple = "aarch64-unknown-linux-gnu"

declare i32 @llvm.fshl.i32(i32, i32, i32)

; CHECK-LABEL: define void @hash_rounds(
; CHECK: loop:
; CHECK-COUNT-4: = phi i32
; CHECK-NOT: phi <
; CHECK-NOT: call <4 x i32> @llvm.fshl
; CHECK: ret void
define void @hash_rounds(ptr noalias readonly %p, i64 %n, ptr noalias %out) {
entry:
  br label %loop
loop:
  %idx = phi i64 [0, %entry], [%next, %loop]
  %a0 = phi i32 [1, %entry], [%r0, %loop]
  %a1 = phi i32 [2, %entry], [%r1, %loop]
  %a2 = phi i32 [3, %entry], [%r2, %loop]
  %a3 = phi i32 [4, %entry], [%r3, %loop]
  %ix0 = add i64 %idx, 0
  %p0 = getelementptr i32, ptr %p, i64 %ix0
  %x0 = load i32, ptr %p0, align 4
  %m0 = mul i32 %x0, -2048144777
  %v0 = add i32 %m0, %a0
  %rot0 = call i32 @llvm.fshl.i32(i32 %v0, i32 %v0, i32 13)
  %r0 = mul i32 %rot0, -1640531535
  %ix1 = add i64 %idx, 1
  %p1 = getelementptr i32, ptr %p, i64 %ix1
  %x1 = load i32, ptr %p1, align 4
  %m1 = mul i32 %x1, -2048144777
  %v1 = add i32 %m1, %a1
  %rot1 = call i32 @llvm.fshl.i32(i32 %v1, i32 %v1, i32 13)
  %r1 = mul i32 %rot1, -1640531535
  %ix2 = add i64 %idx, 2
  %p2 = getelementptr i32, ptr %p, i64 %ix2
  %x2 = load i32, ptr %p2, align 4
  %m2 = mul i32 %x2, -2048144777
  %v2 = add i32 %m2, %a2
  %rot2 = call i32 @llvm.fshl.i32(i32 %v2, i32 %v2, i32 13)
  %r2 = mul i32 %rot2, -1640531535
  %ix3 = add i64 %idx, 3
  %p3 = getelementptr i32, ptr %p, i64 %ix3
  %x3 = load i32, ptr %p3, align 4
  %m3 = mul i32 %x3, -2048144777
  %v3 = add i32 %m3, %a3
  %rot3 = call i32 @llvm.fshl.i32(i32 %v3, i32 %v3, i32 13)
  %r3 = mul i32 %rot3, -1640531535
  %next = add i64 %idx, 4
  %done = icmp eq i64 %next, %n
  br i1 %done, label %exit, label %loop
exit:
  %o0 = getelementptr i32, ptr %out, i64 0
  store i32 %r0, ptr %o0, align 4
  %o1 = getelementptr i32, ptr %out, i64 1
  store i32 %r1, ptr %o1, align 4
  %o2 = getelementptr i32, ptr %out, i64 2
  store i32 %r2, ptr %o2, align 4
  %o3 = getelementptr i32, ptr %out, i64 3
  store i32 %r3, ptr %o3, align 4
  ret void
}

; CHECK-LABEL: define void @independent_rounds(
; CHECK: call <4 x i32> @llvm.fshl.v4i32
; CHECK: store <4 x i32>
; CHECK: ret void
define void @independent_rounds(ptr noalias readonly %p, ptr noalias readonly %states, ptr noalias %out) {
entry:
  %sp0 = getelementptr i32, ptr %states, i64 0
  %a0 = load i32, ptr %sp0, align 4
  %p0 = getelementptr i32, ptr %p, i64 0
  %x0 = load i32, ptr %p0, align 4
  %m0 = mul i32 %x0, -2048144777
  %v0 = add i32 %m0, %a0
  %rot0 = call i32 @llvm.fshl.i32(i32 %v0, i32 %v0, i32 13)
  %r0 = mul i32 %rot0, -1640531535
  %o0 = getelementptr i32, ptr %out, i64 0
  store i32 %r0, ptr %o0, align 4
  %sp1 = getelementptr i32, ptr %states, i64 1
  %a1 = load i32, ptr %sp1, align 4
  %p1 = getelementptr i32, ptr %p, i64 1
  %x1 = load i32, ptr %p1, align 4
  %m1 = mul i32 %x1, -2048144777
  %v1 = add i32 %m1, %a1
  %rot1 = call i32 @llvm.fshl.i32(i32 %v1, i32 %v1, i32 13)
  %r1 = mul i32 %rot1, -1640531535
  %o1 = getelementptr i32, ptr %out, i64 1
  store i32 %r1, ptr %o1, align 4
  %sp2 = getelementptr i32, ptr %states, i64 2
  %a2 = load i32, ptr %sp2, align 4
  %p2 = getelementptr i32, ptr %p, i64 2
  %x2 = load i32, ptr %p2, align 4
  %m2 = mul i32 %x2, -2048144777
  %v2 = add i32 %m2, %a2
  %rot2 = call i32 @llvm.fshl.i32(i32 %v2, i32 %v2, i32 13)
  %r2 = mul i32 %rot2, -1640531535
  %o2 = getelementptr i32, ptr %out, i64 2
  store i32 %r2, ptr %o2, align 4
  %sp3 = getelementptr i32, ptr %states, i64 3
  %a3 = load i32, ptr %sp3, align 4
  %p3 = getelementptr i32, ptr %p, i64 3
  %x3 = load i32, ptr %p3, align 4
  %m3 = mul i32 %x3, -2048144777
  %v3 = add i32 %m3, %a3
  %rot3 = call i32 @llvm.fshl.i32(i32 %v3, i32 %v3, i32 13)
  %r3 = mul i32 %rot3, -1640531535
  %o3 = getelementptr i32, ptr %out, i64 3
  store i32 %r3, ptr %o3, align 4
  ret void
}

; CHECK-LABEL: define void @add_states(
; CHECK: phi <4 x i32>
; CHECK: add <4 x i32>
; CHECK: ret void
define void @add_states(ptr noalias readonly %p, i64 %n, ptr noalias %out) {
entry:
  br label %loop
loop:
  %idx = phi i64 [0, %entry], [%next, %loop]
  %a0 = phi i32 [1, %entry], [%r0, %loop]
  %a1 = phi i32 [2, %entry], [%r1, %loop]
  %a2 = phi i32 [3, %entry], [%r2, %loop]
  %a3 = phi i32 [4, %entry], [%r3, %loop]
  %ix0 = add i64 %idx, 0
  %p0 = getelementptr i32, ptr %p, i64 %ix0
  %x0 = load i32, ptr %p0, align 4
  %r0 = add i32 %x0, %a0
  %ix1 = add i64 %idx, 1
  %p1 = getelementptr i32, ptr %p, i64 %ix1
  %x1 = load i32, ptr %p1, align 4
  %r1 = add i32 %x1, %a1
  %ix2 = add i64 %idx, 2
  %p2 = getelementptr i32, ptr %p, i64 %ix2
  %x2 = load i32, ptr %p2, align 4
  %r2 = add i32 %x2, %a2
  %ix3 = add i64 %idx, 3
  %p3 = getelementptr i32, ptr %p, i64 %ix3
  %x3 = load i32, ptr %p3, align 4
  %r3 = add i32 %x3, %a3
  %next = add i64 %idx, 4
  %done = icmp eq i64 %next, %n
  br i1 %done, label %exit, label %loop
exit:
  %o0 = getelementptr i32, ptr %out, i64 0
  store i32 %r0, ptr %o0, align 4
  %o1 = getelementptr i32, ptr %out, i64 1
  store i32 %r1, ptr %o1, align 4
  %o2 = getelementptr i32, ptr %out, i64 2
  store i32 %r2, ptr %o2, align 4
  %o3 = getelementptr i32, ptr %out, i64 3
  store i32 %r3, ptr %o3, align 4
  ret void
}

declare i32 @llvm.fshr.i32(i32, i32, i32)

; CHECK-LABEL: define void @rotate_right_states(
; CHECK-COUNT-4: = phi i32
; CHECK-NOT: phi <
; CHECK-NOT: call <4 x i32> @llvm.fshr
; CHECK: ret void
define void @rotate_right_states(ptr noalias readonly %p, i64 %n, ptr noalias %out) {
entry:
  br label %loop
loop:
  %idx = phi i64 [0, %entry], [%next, %loop]
  %a0 = phi i32 [1, %entry], [%r0, %loop]
  %a1 = phi i32 [2, %entry], [%r1, %loop]
  %a2 = phi i32 [3, %entry], [%r2, %loop]
  %a3 = phi i32 [4, %entry], [%r3, %loop]
  %ix0 = add i64 %idx, 0
  %p0 = getelementptr i32, ptr %p, i64 %ix0
  %x0 = load i32, ptr %p0, align 4
  %m0 = mul i32 %x0, -2048144777
  %v0 = add i32 %m0, %a0
  %rot0 = call i32 @llvm.fshr.i32(i32 %v0, i32 %v0, i32 13)
  %r0 = mul i32 %rot0, -1640531535
  %ix1 = add i64 %idx, 1
  %p1 = getelementptr i32, ptr %p, i64 %ix1
  %x1 = load i32, ptr %p1, align 4
  %m1 = mul i32 %x1, -2048144777
  %v1 = add i32 %m1, %a1
  %rot1 = call i32 @llvm.fshr.i32(i32 %v1, i32 %v1, i32 13)
  %r1 = mul i32 %rot1, -1640531535
  %ix2 = add i64 %idx, 2
  %p2 = getelementptr i32, ptr %p, i64 %ix2
  %x2 = load i32, ptr %p2, align 4
  %m2 = mul i32 %x2, -2048144777
  %v2 = add i32 %m2, %a2
  %rot2 = call i32 @llvm.fshr.i32(i32 %v2, i32 %v2, i32 13)
  %r2 = mul i32 %rot2, -1640531535
  %ix3 = add i64 %idx, 3
  %p3 = getelementptr i32, ptr %p, i64 %ix3
  %x3 = load i32, ptr %p3, align 4
  %m3 = mul i32 %x3, -2048144777
  %v3 = add i32 %m3, %a3
  %rot3 = call i32 @llvm.fshr.i32(i32 %v3, i32 %v3, i32 13)
  %r3 = mul i32 %rot3, -1640531535
  %next = add i64 %idx, 4
  %done = icmp eq i64 %next, %n
  br i1 %done, label %exit, label %loop
exit:
  %o0 = getelementptr i32, ptr %out, i64 0
  store i32 %r0, ptr %o0, align 4
  %o1 = getelementptr i32, ptr %out, i64 1
  store i32 %r1, ptr %o1, align 4
  %o2 = getelementptr i32, ptr %out, i64 2
  store i32 %r2, ptr %o2, align 4
  %o3 = getelementptr i32, ptr %out, i64 3
  store i32 %r3, ptr %o3, align 4
  ret void
}
