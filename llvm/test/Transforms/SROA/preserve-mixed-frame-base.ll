; RUN: opt -S -passes=sroa < %s | FileCheck %s --check-prefixes=CHECK,SROA
; RUN: opt -S -passes='default<O2>' < %s | FileCheck %s --check-prefixes=CHECK,O2
;
; Scalar replacement must not multiply relocation bases after unfolding GEPs
; through a frame/object merge when the collector requests a shared base.
; The hint is target-independent and does not require a loaded GC strategy.
target datalayout = "e-p:64:64-i64:64-n8:16:32:64-S128"

declare void @safepoint()

; CHECK-LABEL: define {{.*}}@mixed_phi(
; CHECK: %local = alloca { i64, ptr, i64, ptr }
; CHECK-NOT: alloca
; CHECK: %base = phi ptr [ %local, %default ], [ %config, %entry ]
; CHECK-NOT: phi
; CHECK: call void @safepoint()
; CHECK: %a = getelementptr i8, ptr %base, i64 8
; CHECK: %x = load ptr, ptr %a
; CHECK: call void @safepoint()
; CHECK: %b = getelementptr i8, ptr %base, i64 24
; CHECK: %y = load ptr, ptr %b
; CHECK: ret i1

define i1 @mixed_phi(ptr %config) #0 {
entry:
  %local = alloca {i64, ptr, i64, ptr}, align 8
  %nil = icmp eq ptr %config, null
  br i1 %nil, label %default, label %merge
default:
  store {i64, ptr, i64, ptr} zeroinitializer, ptr %local
  br label %merge
merge:
  %base = phi ptr [%local, %default], [%config, %entry]
  call void @safepoint()
  %a = getelementptr i8, ptr %base, i64 8
  %x = load ptr, ptr %a
  call void @safepoint()
  %b = getelementptr i8, ptr %base, i64 24
  %y = load ptr, ptr %b
  %eq = icmp eq ptr %x, %y
  ret i1 %eq
}

; CHECK-LABEL: define {{.*}}@mixed_select(
; CHECK: %local = alloca { i64, ptr, i64, ptr }
; CHECK-NOT: alloca
; CHECK: %base = select i1 %choose, ptr %local, ptr %config
; CHECK-NOT: select
; CHECK: call void @safepoint()
; CHECK: %a = getelementptr i8, ptr %base, i64 8
; CHECK: %x = load ptr, ptr %a
; CHECK: call void @safepoint()
; CHECK: %b = getelementptr i8, ptr %base, i64 24
; CHECK: %y = load ptr, ptr %b
; CHECK: ret i1

define i1 @mixed_select(ptr %config, i1 %choose) #0 {
entry:
  %local = alloca {i64, ptr, i64, ptr}, align 8
  store {i64, ptr, i64, ptr} zeroinitializer, ptr %local
  %base = select i1 %choose, ptr %local, ptr %config
  call void @safepoint()
  %a = getelementptr i8, ptr %base, i64 8
  %x = load ptr, ptr %a
  call void @safepoint()
  %b = getelementptr i8, ptr %base, i64 24
  %y = load ptr, ptr %b
  %eq = icmp eq ptr %x, %y
  ret i1 %eq
}

; Without the hint SROA continues to unfold and split this exact shape.
; CHECK-LABEL: define {{.*}}@unhinted(
; CHECK: %local.sroa.1 = alloca ptr
; CHECK: %local.sroa.4 = alloca ptr
; CHECK: %base.sroa.phi = phi ptr
; CHECK: %base.sroa.phi2 = phi ptr
; CHECK: ret i1

define i1 @unhinted(ptr %config) {
entry:
  %local = alloca {i64, ptr, i64, ptr}, align 8
  %nil = icmp eq ptr %config, null
  br i1 %nil, label %default, label %merge
default:
  store {i64, ptr, i64, ptr} zeroinitializer, ptr %local
  br label %merge
merge:
  %base = phi ptr [%local, %default], [%config, %entry]
  call void @safepoint()
  %a = getelementptr i8, ptr %base, i64 8
  %x = load ptr, ptr %a
  call void @safepoint()
  %b = getelementptr i8, ptr %base, i64 24
  %y = load ptr, ptr %b
  %eq = icmp eq ptr %x, %y
  ret i1 %eq
}

; A collector hint must not turn off ordinary SROA or mem2reg.
; CHECK-LABEL: define {{.*}}@promote(
; CHECK-NOT: alloca
; CHECK: ret ptr %p

define ptr @promote(ptr %p) #0 {
  %local = alloca {ptr, i64}, align 8
  %a = getelementptr {ptr, i64}, ptr %local, i32 0, i32 0
  %b = getelementptr {ptr, i64}, ptr %local, i32 0, i32 1
  store ptr %p, ptr %a
  store i64 42, ptr %b
  %x = load ptr, ptr %a
  ret ptr %x
}

; Two distinct frame objects retain distinct addresses, even when a third
; incoming value is an ordinary object. No object identity is coalesced.
; CHECK-LABEL: define {{.*}}@two_frames(
; CHECK: %first = alloca { ptr, ptr }
; CHECK: %second = alloca { ptr, ptr }
; SROA: %base = phi ptr [ %first, %left ], [ %second, %right ], [ %config, %entry ]
; O2: %[[STACK:.*]] = phi ptr [ %second, %right ], [ %first, %entry ]
; O2: %base = phi ptr [ %config, %entry ], [ %[[STACK]], %merge.sink.split ]
; CHECK: call void @safepoint()
; CHECK: %field = getelementptr i8, ptr %base, i64 8
; CHECK: load ptr, ptr %field

define ptr @two_frames(ptr %config, i2 %which, ptr %p, ptr %q) #0 {
entry:
  %first = alloca {ptr, ptr}, align 8
  %second = alloca {ptr, ptr}, align 8
  switch i2 %which, label %merge [i2 0, label %left i2 1, label %right]
left:
  %a = getelementptr i8, ptr %first, i64 8
  store ptr %p, ptr %a
  br label %merge
right:
  %b = getelementptr i8, ptr %second, i64 8
  store ptr %q, ptr %b
  br label %merge
merge:
  %base = phi ptr [%first, %left], [%second, %right], [%config, %entry]
  call void @safepoint()
  %field = getelementptr i8, ptr %base, i64 8
  %r = load ptr, ptr %field
  ret ptr %r
}

; The hint must not inhibit promotion in a function without safepoints.
; CHECK-LABEL: define {{.*}}@call_free(
; CHECK-NOT: alloca
; CHECK-NOT: phi ptr
; CHECK: ret i64

define i64 @call_free(ptr dereferenceable(16) %config, i1 %choose) #0 {
entry:
  %local = alloca {i64, i64}, align 8
  store {i64, i64} {i64 11, i64 13}, ptr %local
  %base = select i1 %choose, ptr %local, ptr %config
  %a = getelementptr i8, ptr %base, i64 0
  %x = load i64, ptr %a
  %b = getelementptr i8, ptr %base, i64 8
  %y = load i64, ptr %b
  %sum = add i64 %x, %y
  ret i64 %sum
}

declare void @gc_leaf() "gc-leaf-function"

; An ordinary call with the explicit GC-leaf contract has the same property.
; CHECK-LABEL: define {{.*}}@leaf_call(
; CHECK-NOT: alloca
; CHECK: call void @gc_leaf()
; CHECK-NOT: phi ptr
; CHECK: ret i64

define i64 @leaf_call(ptr dereferenceable(16) %config, i1 %choose) #0 {
entry:
  %local = alloca {i64, i64}, align 8
  store {i64, i64} {i64 11, i64 13}, ptr %local
  %base = select i1 %choose, ptr %local, ptr %config
  call void @gc_leaf()
  %a = getelementptr i8, ptr %base, i64 0
  %x = load i64, ptr %a
  %b = getelementptr i8, ptr %base, i64 8
  %y = load i64, ptr %b
  %sum = add i64 %x, %y
  ret i64 %sum
}

attributes #0 = { "gc-preserve-frame-base" }
