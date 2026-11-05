; REQUIRES: aarch64-registered-target
; RUN: llc -disable-machine-cse -disable-lsr -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -disable-machine-cse -disable-lsr -verify-machineinstrs -mattr=+disable-stp < %s | FileCheck %s --check-prefix=NO-STP
; RUN: llc -disable-machine-cse -disable-lsr -verify-machineinstrs -mattr=+disable-ldp < %s | FileCheck %s --check-prefix=NO-LDP
;
; Statepoint spills and reloads are independently scheduled. For odd-length
; contiguous runs, greedy scans can choose overlapping pair boundaries. Prefer
; disjoint pairs from the low-address end, using the same slots in each block.
; Even-length runs, different root orders, an adjacent scalar spill, and calls
; with only a subset of the roots must retain their legal pairing opportunities.
;
; NO-LDP-LABEL: _roots3:
; NO-LDP: bl _safepoint
; NO-LDP: ldr x8, [sp, #8]
; NO-LDP: ldr x9, [sp, #16]
; NO-LDP: ldr x10, [sp, #24]
;
; NO-STP-LABEL: _roots3:
; NO-STP: stp x29, x30, [sp, #32]
; NO-STP-NOT: stp
; NO-STP: bl _safepoint

target triple = "aarch64-apple-darwin"
; CHECK-LABEL: _roots3:
; CHECK-DAG: stp x0, x1, [sp, #8]
; CHECK-DAG: str x2, [sp, #24]
; CHECK: bl _safepoint
; CHECK: ldp x8, x9, [sp, #8]
; CHECK: ldr x10, [sp, #24]
define goabiinternal i64 @roots3(ptr addrspace(1) %p0, ptr addrspace(1) %p1, ptr addrspace(1) %p2) "frame-pointer"="none" gc "statepoint-example" {
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 1, i32 0, ptr elementtype(void ()) @safepoint, i32 0, i32 0, i32 0, i32 0) [ "gc-live"(ptr addrspace(1) %p0, ptr addrspace(1) %p1, ptr addrspace(1) %p2) ]
  %r0 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  %v0 = load i64, ptr addrspace(1) %r0, align 8
  %r1 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 1, i32 1)
  %v1 = load i64, ptr addrspace(1) %r1, align 8
  %r2 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 2, i32 2)
  %v2 = load i64, ptr addrspace(1) %r2, align 8
  %sum1 = add i64 %v0, %v1
  %sum2 = add i64 %sum1, %v2
  ret i64 %sum2
}
; CHECK-LABEL: _roots4:
; CHECK-DAG: stp x2, x3, [sp, #32]
; CHECK-DAG: stp x0, x1, [sp, #16]
; CHECK: bl _safepoint
; CHECK: ldp x8, x9, [sp, #16]
; CHECK: ldp x10, x11, [sp, #32]
define goabiinternal i64 @roots4(ptr addrspace(1) %p0, ptr addrspace(1) %p1, ptr addrspace(1) %p2, ptr addrspace(1) %p3) "frame-pointer"="none" gc "statepoint-example" {
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 1, i32 0, ptr elementtype(void ()) @safepoint, i32 0, i32 0, i32 0, i32 0) [ "gc-live"(ptr addrspace(1) %p0, ptr addrspace(1) %p1, ptr addrspace(1) %p2, ptr addrspace(1) %p3) ]
  %r0 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  %v0 = load i64, ptr addrspace(1) %r0, align 8
  %r1 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 1, i32 1)
  %v1 = load i64, ptr addrspace(1) %r1, align 8
  %r2 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 2, i32 2)
  %v2 = load i64, ptr addrspace(1) %r2, align 8
  %r3 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 3, i32 3)
  %v3 = load i64, ptr addrspace(1) %r3, align 8
  %sum1 = add i64 %v0, %v1
  %sum2 = add i64 %sum1, %v2
  %sum3 = add i64 %sum2, %v3
  ret i64 %sum3
}
; CHECK-LABEL: _roots5:
; CHECK-DAG: stp x2, x3, [sp, #24]
; CHECK-DAG: stp x0, x1, [sp, #8]
; CHECK-DAG: str x4, [sp, #40]
; CHECK: bl _safepoint
; CHECK: ldp x8, x9, [sp, #8]
; CHECK: ldp x10, x11, [sp, #24]
define goabiinternal i64 @roots5(ptr addrspace(1) %p0, ptr addrspace(1) %p1, ptr addrspace(1) %p2, ptr addrspace(1) %p3, ptr addrspace(1) %p4) "frame-pointer"="none" gc "statepoint-example" {
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 1, i32 0, ptr elementtype(void ()) @safepoint, i32 0, i32 0, i32 0, i32 0) [ "gc-live"(ptr addrspace(1) %p0, ptr addrspace(1) %p1, ptr addrspace(1) %p2, ptr addrspace(1) %p3, ptr addrspace(1) %p4) ]
  %r0 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  %v0 = load i64, ptr addrspace(1) %r0, align 8
  %r1 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 1, i32 1)
  %v1 = load i64, ptr addrspace(1) %r1, align 8
  %r2 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 2, i32 2)
  %v2 = load i64, ptr addrspace(1) %r2, align 8
  %r3 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 3, i32 3)
  %v3 = load i64, ptr addrspace(1) %r3, align 8
  %r4 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 4, i32 4)
  %v4 = load i64, ptr addrspace(1) %r4, align 8
  %sum1 = add i64 %v0, %v1
  %sum2 = add i64 %sum1, %v2
  %sum3 = add i64 %sum2, %v3
  %sum4 = add i64 %sum3, %v4
  ret i64 %sum4
}
declare goabiinternal void @safepoint()

; CHECK-LABEL: _roots3_branch:
; CHECK-DAG: stp x0, x1, [sp, #8]
; CHECK-DAG: str x2, [sp, #24]
; CHECK: bl _safepoint_cond
; CHECK: tbz
; CHECK: ldp x8, x9, [sp, #8]
; CHECK: ldr x10, [sp, #24]
define goabiinternal i64 @roots3_branch(ptr addrspace(1) %p0, ptr addrspace(1) %p1, ptr addrspace(1) %p2) "frame-pointer"="none" gc "statepoint-example" {
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 1, i32 0, ptr elementtype(i1 ()) @safepoint_cond, i32 0, i32 0, i32 0, i32 0) [ "gc-live"(ptr addrspace(1) %p0, ptr addrspace(1) %p1, ptr addrspace(1) %p2) ]
  %ok = call i1 @llvm.experimental.gc.result.i1(token %token)
  br i1 %ok, label %success, label %failure
success:
  %r0 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  %v0 = load i64, ptr addrspace(1) %r0, align 8
  %r1 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 1, i32 1)
  %v1 = load i64, ptr addrspace(1) %r1, align 8
  %r2 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 2, i32 2)
  %v2 = load i64, ptr addrspace(1) %r2, align 8
  %sum1 = add i64 %v0, %v1
  %sum2 = add i64 %sum1, %v2
  ret i64 %sum2
failure:
  ret i64 0
}
declare goabiinternal i1 @safepoint_cond()

; CHECK-LABEL: _roots3_scalar:
; CHECK-DAG: stp x0, x1, [sp, #24]
; CHECK-DAG: str x2, [sp, #40]
; CHECK: bl _safepoint
; CHECK: ldp x8, x9, [sp, #24]
; CHECK: ldr x10, [sp, #40]
define goabiinternal i64 @roots3_scalar(ptr addrspace(1) %p0, ptr addrspace(1) %p1, ptr addrspace(1) %p2, i64 %scalar) "frame-pointer"="none" gc "statepoint-example" {
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 1, i32 0, ptr elementtype(void ()) @safepoint, i32 0, i32 0, i32 0, i32 0) [ "gc-live"(ptr addrspace(1) %p0, ptr addrspace(1) %p1, ptr addrspace(1) %p2, i64 %scalar) ]
  %r0 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  %v0 = load i64, ptr addrspace(1) %r0, align 8
  %r1 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 1, i32 1)
  %v1 = load i64, ptr addrspace(1) %r1, align 8
  %r2 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 2, i32 2)
  %v2 = load i64, ptr addrspace(1) %r2, align 8
  %sum1 = add i64 %v0, %v1
  %sum2 = add i64 %sum1, %v2
  %total = add i64 %sum2, %scalar
  ret i64 %total
}

; CHECK-LABEL: _roots3_load_reverse:
; CHECK-DAG: stp x2, x1, [sp, #8]
; CHECK-DAG: str x0, [sp, #24]
; CHECK: bl _safepoint
; CHECK: ldp x8, x9, [sp, #8]
define goabiinternal i64 @roots3_load_reverse(ptr addrspace(1) %p0, ptr addrspace(1) %p1, ptr addrspace(1) %p2) "frame-pointer"="none" gc "statepoint-example" {
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 1, i32 0, ptr elementtype(void ()) @safepoint, i32 0, i32 0, i32 0, i32 0) [ "gc-live"(ptr addrspace(1) %p0, ptr addrspace(1) %p1, ptr addrspace(1) %p2) ]
  %r2 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 2, i32 2)
  %v2 = load volatile i64, ptr addrspace(1) %r2, align 8
  %r1 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 1, i32 1)
  %v1 = load volatile i64, ptr addrspace(1) %r1, align 8
  %r0 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  %v0 = load volatile i64, ptr addrspace(1) %r0, align 8
  %sum1 = add i64 %v0, %v1
  %sum2 = add i64 %sum1, %v2
  ret i64 %sum2
}

; The first call has only the upper pair live. Do not suppress that pair or
; merge the later store across the call to obtain the globally preferred pair.
; CHECK-LABEL: _roots3_subset:
; CHECK: stp x1, x2, [sp, #16]
; CHECK: bl _make_root
; CHECK: str x0, [sp, #8]
; CHECK: bl _safepoint
; CHECK: ldp x8, x9, [sp, #8]
define goabiinternal i64 @roots3_subset(ptr addrspace(1) %p0, ptr addrspace(1) %p1, ptr addrspace(1) %p2) "frame-pointer"="none" gc "statepoint-example" {
  %first = call goabiinternal token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 2, i32 0, ptr elementtype(ptr addrspace(1) ()) @make_root, i32 0, i32 0, i32 0, i32 0) [ "gc-live"(ptr addrspace(1) %p1, ptr addrspace(1) %p2) ]
  %new = call ptr addrspace(1) @llvm.experimental.gc.result.p1(token %first)
  %q1 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %first, i32 0, i32 0)
  %q2 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %first, i32 1, i32 1)
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...) @llvm.experimental.gc.statepoint.p0(i64 1, i32 0, ptr elementtype(void ()) @safepoint, i32 0, i32 0, i32 0, i32 0) [ "gc-live"(ptr addrspace(1) %new, ptr addrspace(1) %q1, ptr addrspace(1) %q2) ]
  %r0 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 0, i32 0)
  %v0 = load i64, ptr addrspace(1) %r0, align 8
  %r1 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 1, i32 1)
  %v1 = load i64, ptr addrspace(1) %r1, align 8
  %r2 = call coldcc ptr addrspace(1) @llvm.experimental.gc.relocate.p1(token %token, i32 2, i32 2)
  %v2 = load i64, ptr addrspace(1) %r2, align 8
  %sum1 = add i64 %v0, %v1
  %sum2 = add i64 %sum1, %v2
  ret i64 %sum2
}
declare goabiinternal ptr addrspace(1) @make_root()
