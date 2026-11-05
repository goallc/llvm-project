; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O2 -verify-machineinstrs -stop-after=codegenprepare < %s | FileCheck %s --check-prefix=IR
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O2 -verify-machineinstrs -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -max-store-memcpy=1024 -O2 -verify-machineinstrs -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=MIR

; Ordinary C byval calls use the same ownership and initialization proof as
; Go's pre-GC preparation. None of these tests depend on a Go calling convention.
; Inline large AArch64 fallback copies to keep this test independent of library
; call expansion inside an already-open byval call sequence.

declare void @consume(ptr byval([32 x i8]) align 8)
declare void @consume320(ptr byval([320 x i8]) align 8)
declare void @consume4096(ptr byval([4096 x i8]) align 8)
declare void @observe(ptr)
declare void @other()
declare void @panic() noreturn
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1 immarg)
declare void @llvm.lifetime.start.p0(ptr)
declare void @llvm.lifetime.end.p0(ptr)
@escaped = external global ptr

; No memset is necessary. Sink only the private writes, retaining the loaded
; SSA snapshot even though its source memory is overwritten before the call.
; IR-LABEL: define void @no_fill_nil_edge(
; IR: %snapshot = load i64, ptr %source
; IR: store i64 99, ptr %source
; IR-NOT: store i64 %snapshot
; IR: br i1 %nil
; IR: store i64 %snapshot
; IR: call void @consume
; MIR-LABEL: name: no_fill_nil_edge
; MIR: stack: []
; MIR: body:
define void @no_fill_nil_edge(i1 %nil, ptr %source, ptr %pointer) {
entry:
  %slot = alloca [32 x i8], align 8
  %snapshot = load i64, ptr %source
  store i64 %snapshot, ptr %slot, align 8
  %p8 = getelementptr i8, ptr %slot, i64 8
  store ptr %pointer, ptr %p8, align 8
  %p16 = getelementptr i8, ptr %slot, i64 16
  store i64 17, ptr %p16, align 8
  %p24 = getelementptr i8, ptr %slot, i64 24
  store i64 23, ptr %p24, align 8
  store i64 99, ptr %source
  br i1 %nil, label %bad, label %call
bad:
  call void @panic()
  unreachable
call:
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  ret void
}

; Multiple partial fills, including nonzero bytes, need not start at offset 0.
; IR-LABEL: define void @partial_fills(
; IR-NOT: @llvm.memset
; IR: store <8 x i8> splat (i8 7)
; IR: store <8 x i8> splat (i8 1)
; IR: store i8 1
; IR: store <4 x i8> splat (i8 1)
; IR: store <2 x i8> splat (i8 1)
; IR: store i8 %byte
; IR: store ptr %pointer
; IR: call void @consume
; MIR-LABEL: name: partial_fills
; MIR: stack: []
; MIR: body:
define void @partial_fills(i8 %byte, ptr %pointer) {
entry:
  %slot = alloca [32 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 7, i64 16, i1 false)
  %p8 = getelementptr i8, ptr %slot, i64 8
  call void @llvm.memset.p0.i64(ptr align 8 %p8, i8 1, i64 16, i1 false)
  %p17 = getelementptr i8, ptr %slot, i64 17
  store i8 %byte, ptr %p17
  %p24 = getelementptr i8, ptr %slot, i64 24
  store ptr %pointer, ptr %p24, align 8
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  ret void
}

; The original SSA byte value also supports a nonconstant fill.
; IR-LABEL: define void @dynamic_fill(
; IR-NOT: @llvm.memset
; IR: insertelement
; IR: shufflevector
; IR: store <16 x i8>
; IR: store <8 x i8>
; IR: store ptr %pointer
; IR: call void @consume
; MIR-LABEL: name: dynamic_fill
; MIR: stack: []
; MIR: body:
define void @dynamic_fill(i8 %byte, ptr %pointer) {
entry:
  %slot = alloca [32 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 %byte, i64 32, i1 false)
  %p24 = getelementptr i8, ptr %slot, i64 24
  store ptr %pointer, ptr %p24, align 8
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  ret void
}

; Keep partially overwritten typed stores in their memory order. There is no
; byte reconstruction of a scalar or pointer value in IR.
; IR-LABEL: define void @partial_scalar_overlap(
; IR-NOT: @llvm.memset
; IR: store <16 x i8> zeroinitializer
; IR: store i64 %wide
; IR: store i32 %narrow
; IR: store ptr %pointer
; IR: call void @consume
; MIR-LABEL: name: partial_scalar_overlap
; MIR: stack: []
; MIR: body:
define void @partial_scalar_overlap(i64 %wide, i32 %narrow, ptr %pointer) {
entry:
  %slot = alloca [32 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 0, i64 32, i1 false)
  store i64 %wide, ptr %slot, align 8
  %p4 = getelementptr i8, ptr %slot, i64 4
  store i32 %narrow, ptr %p4, align 4
  %p24 = getelementptr i8, ptr %slot, i64 24
  store ptr %pointer, ptr %p24, align 8
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  ret void
}

; A control-flow merge is safe when all initializers dominate the call and
; neither path observes the object or calls another function.
; MIR-LABEL: name: diamond
; MIR: stack: []
; MIR: body:
define void @diamond(i1 %choose, i8 %byte, ptr %out) {
entry:
  %slot = alloca [32 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 0, i64 32, i1 false)
  store i8 %byte, ptr %slot
  br i1 %choose, label %left, label %right
left:
  store volatile i8 1, ptr %out
  br label %merge
right:
  store volatile i8 2, ptr %out
  br label %merge
merge:
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  ret void
}

; The former 256-byte cutoff was a pattern restriction, not a semantic limit.
; MIR-LABEL: name: larger_fill
; MIR: stack: []
; MIR: body:
define void @larger_fill(i8 %byte) {
entry:
  %slot = alloca [320 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 0, i64 320, i1 false)
  store i8 %byte, ptr %slot
  call void @consume320(ptr byval([320 x i8]) align 8 %slot)
  ret void
}

; A large sparse carrier has no fill expansion cost. Unwritten bytes remain
; unspecified, just as in the original byval copy.
; MIR-LABEL: name: large_sparse
; MIR: stack: []
; MIR: body:
define void @large_sparse(i64 %a, i64 %b, i1 %nil) {
entry:
  %slot = alloca [4096 x i8], align 8
  store i64 %a, ptr %slot, align 8
  %last = getelementptr i8, ptr %slot, i64 4088
  store i64 %b, ptr %last, align 8
  br i1 %nil, label %bad, label %call
bad:
  call void @panic()
  unreachable
call:
  call void @consume4096(ptr byval([4096 x i8]) align 8 %slot)
  ret void
}

; Conditional writes need a reaching-definition merge, which this preparation
; does not synthesize. Other rejection cases retain both source and copy.
; MIR-LABEL: name: conditional_write
; MIR: stack:
; MIR: name: slot
; MIR: body:
define void @conditional_write(i1 %choose, i8 %byte) {
entry:
  %slot = alloca [32 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 0, i64 32, i1 false)
  br i1 %choose, label %write, label %call
write:
  store i8 %byte, ptr %slot
  br label %call
call:
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  ret void
}

; MIR-LABEL: name: call_on_one_path
; MIR: stack:
; MIR: name: slot
; MIR: body:
define void @call_on_one_path(i1 %choose, i8 %byte) {
entry:
  %slot = alloca [32 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 0, i64 32, i1 false)
  store i8 %byte, ptr %slot
  br i1 %choose, label %side, label %call
side:
  call void @other()
  br label %call
call:
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  ret void
}

; MIR-LABEL: name: loop_before_call
; MIR: stack:
; MIR: name: slot
; MIR: body:
define void @loop_before_call(ptr %condition, i8 %byte) {
entry:
  %slot = alloca [32 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 0, i64 32, i1 false)
  store i8 %byte, ptr %slot
  br label %loop
loop:
  %again = load volatile i1, ptr %condition
  br i1 %again, label %loop, label %call
call:
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  ret void
}

; MIR-LABEL: name: escaped_address
; MIR: stack:
; MIR: name: slot
; MIR: body:
define void @escaped_address(i8 %byte) {
entry:
  %slot = alloca [32 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 0, i64 32, i1 false)
  store i8 %byte, ptr %slot
  store ptr %slot, ptr @escaped
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  ret void
}

; MIR-LABEL: name: observed_address
; MIR: stack:
; MIR: name: slot
; MIR: body:
define void @observed_address(i8 %byte) {
entry:
  %slot = alloca [32 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 0, i64 32, i1 false)
  store i8 %byte, ptr %slot
  call void @observe(ptr %slot)
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  ret void
}

; MIR-LABEL: name: multiple_uses
; MIR: stack:
; MIR: name: slot
; MIR: body:
define void @multiple_uses(i8 %byte) {
entry:
  %slot = alloca [32 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 0, i64 32, i1 false)
  store i8 %byte, ptr %slot
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  ret void
}

; IR-LABEL: define void @dynamic_length(
; IR: call void @llvm.memset.p0.i64
; MIR-LABEL: name: dynamic_length
; MIR: stack:
; MIR: name: slot
; MIR: body:
define void @dynamic_length(i64 %length) {
entry:
  %slot = alloca [32 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 0, i64 %length, i1 false)
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  ret void
}

; Bound store expansion even though the byval object's size is unrestricted.
; IR-LABEL: define void @expansion_budget(
; IR: call void @llvm.memset.p0.i64
; MIR-LABEL: name: expansion_budget
; MIR: stack:
; MIR: name: slot
; MIR: body:
define void @expansion_budget() {
entry:
  %slot = alloca [4096 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 0, i64 4096, i1 false)
  call void @consume4096(ptr byval([4096 x i8]) align 8 %slot)
  ret void
}

; CodeGenPrepare must not change pointer lifetimes after a GC client has had
; its opportunity to classify roots. That client uses the shared helper early.
; IR-LABEL: define void @gc_client(
; IR: call void @llvm.memset.p0.i64
; MIR-LABEL: name: gc_client
; MIR: stack:
; MIR: name: slot
; MIR: body:
define void @gc_client(i8 %byte) gc "statepoint-example" {
entry:
  %slot = alloca [32 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %slot, i8 0, i64 32, i1 false)
  store i8 %byte, ptr %slot
  call void @consume(ptr byval([32 x i8]) align 8 %slot)
  ret void
}
