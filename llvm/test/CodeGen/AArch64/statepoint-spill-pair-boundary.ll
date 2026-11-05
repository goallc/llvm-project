; REQUIRES: aarch64-registered-target
; RUN: llc -disable-machine-cse -disable-lsr -verify-machineinstrs < %s | FileCheck %s
;
; A scalar register spill must not steal a statepoint spill's pair partner.
; Before the call, the scheduler places the stores in the order root0, scalar,
; root1. Greedy pairing used to make STP scalar, root1 plus STR root0, whereas
; the reloads make LDP root1, root0. The paired reload then crosses two stores.
; Prefer the GC spill pair and its reload at the same offset. Frame and ordinary
; memory pairs must still be formed, including a lone root with a scalar spill.
;
; CHECK-LABEL: _spill_boundary:
; CHECK: stp x29, x30, [sp, #64]
; CHECK-DAG: stp x1, x0, [x29, #-16]
; CHECK-DAG: stur x8, [x29, #-24]
; CHECK: blr
; CHECK: ldp x1, x0, [x29, #-16]
; CHECK: ldur {{x[0-9]+}}, [x29, #-24]

target triple = "aarch64-apple-darwin"

define goabiinternal void @spill_boundary(ptr addrspace(1) %b, ptr addrspace(1) %g, ptr %callee) "frame-pointer"="non-leaf" gc "statepoint-example" {
entry:
  br label %loop
loop:
  %bp = phi ptr addrspace(1) [ %b, %entry ], [ %br, %loop ]
  %gp = phi ptr addrspace(1) [ %g, %entry ], [ %gr, %loop ]
  %i = phi i64 [ 0, %entry ], [ %next, %loop ]
  %d = uitofp i64 %i to double
  %next = add nuw nsw i64 %i, 1
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 1, i32 0, ptr elementtype(void (ptr addrspace(1), double)) %callee, i32 2, i32 0, ptr addrspace(1) %gp, double %d, i32 0, i32 0) [ "gc-live"(ptr addrspace(1) %gp, ptr addrspace(1) %bp) ]
  %gr = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  %br = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 1, i32 1)
  %np = getelementptr i8, ptr addrspace(1) %br, i64 528
  %n = load i64, ptr addrspace(1) %np, align 8
  %more = icmp slt i64 %next, %n
  br i1 %more, label %loop, label %exit
exit:
  ret void
}

; CHECK-LABEL: _ordinary_pairs:
; CHECK: ldp [[A:x[0-9]+]], [[B:x[0-9]+]], [x0]
; CHECK: stp [[A]], [[B]], [x1]
; CHECK: ret
define void @ordinary_pairs(ptr %src, ptr %dst) {
  %a = load i64, ptr %src, align 8
  %src1 = getelementptr i64, ptr %src, i64 1
  %b = load i64, ptr %src1, align 8
  store i64 %a, ptr %dst, align 8
  %dst1 = getelementptr i64, ptr %dst, i64 1
  store i64 %b, ptr %dst1, align 8
  ret void
}

; A root without another root to pair with can still pair with a scalar spill.
; CHECK-LABEL: _isolated_root:
; CHECK: stp x1, x0, [sp, #16]
; CHECK: bl _safepoint
; CHECK: ldp x9, x8, [sp, #16]
declare goabiinternal void @safepoint()
define goabiinternal i64 @isolated_root(ptr addrspace(1) %p, i64 %i) "frame-pointer"="none" gc "statepoint-example" {
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 1, i32 0, ptr elementtype(void ()) @safepoint, i32 0, i32 0, i32 0, i32 0) [ "gc-live"(ptr addrspace(1) %p) ]
  %r = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  %v = load i64, ptr addrspace(1) %r, align 8
  %sum = add i64 %v, %i
  ret i64 %sum
}
