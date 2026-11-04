; REQUIRES: x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mcpu=x86-64 -O2 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mcpu=x86-64 -mattr=+ermsb -O2 -verify-machineinstrs < %s | FileCheck %s
;
; Go's fixed stack copies cross the normal eight-store limit at 129 bytes.
; Keep small always-inline copies as loads/stores without changing C functions,
; ordinary memcpy, size optimization, or the strategy above 256 bytes.

declare void @llvm.memcpy.inline.p0.p0.i64(ptr, ptr, i64 immarg, i1 immarg)
declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)

define goabiinternal void @copy_goabiinternal_128_align8_normal(ptr %dst, ptr %src) {
; CHECK-LABEL: copy_goabiinternal_128_align8_normal:
; CHECK-NOT: rep
; CHECK: mov{{[au]}}ps
; CHECK-NOT: rep
; CHECK: retq
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 8 %dst, ptr align 8 %src, i64 128, i1 false)
  ret void
}

define goabiinternal void @copy_goabiinternal_129_align1_normal(ptr %dst, ptr %src) {
; CHECK-LABEL: copy_goabiinternal_129_align1_normal:
; CHECK-NOT: rep
; CHECK: mov{{[au]}}ps
; CHECK-NOT: rep
; CHECK: retq
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 1 %dst, ptr align 1 %src, i64 129, i1 false)
  ret void
}

define goabiinternal void @copy_goabiinternal_136_align8_normal(ptr %dst, ptr %src) {
; CHECK-LABEL: copy_goabiinternal_136_align8_normal:
; CHECK-NOT: rep
; CHECK: mov{{[au]}}ps
; CHECK-NOT: rep
; CHECK: retq
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 8 %dst, ptr align 8 %src, i64 136, i1 false)
  ret void
}

define goabiinternal void @copy_goabiinternal_136_align16_normal(ptr %dst, ptr %src) {
; CHECK-LABEL: copy_goabiinternal_136_align16_normal:
; CHECK-NOT: rep
; CHECK: mov{{[au]}}ps
; CHECK-NOT: rep
; CHECK: retq
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 16 %dst, ptr align 16 %src, i64 136, i1 false)
  ret void
}

define goabiinternal void @copy_goabiinternal_255_align1_normal(ptr %dst, ptr %src) {
; CHECK-LABEL: copy_goabiinternal_255_align1_normal:
; CHECK-NOT: rep
; CHECK: mov{{[au]}}ps
; CHECK-NOT: rep
; CHECK: retq
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 1 %dst, ptr align 1 %src, i64 255, i1 false)
  ret void
}

define goabiinternal void @copy_goabiinternal_256_align8_normal(ptr %dst, ptr %src) {
; CHECK-LABEL: copy_goabiinternal_256_align8_normal:
; CHECK-NOT: rep
; CHECK: mov{{[au]}}ps
; CHECK-NOT: rep
; CHECK: retq
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 8 %dst, ptr align 8 %src, i64 256, i1 false)
  ret void
}

define goabi0 void @copy_goabi0_136_align8_normal(ptr byval(ptr) align 8 %dst.addr, ptr byval(ptr) align 8 %src.addr) {
; CHECK-LABEL: copy_goabi0_136_align8_normal:
; CHECK-NOT: rep
; CHECK: mov{{[au]}}ps
; CHECK-NOT: rep
; CHECK: retq
  %dst = load ptr, ptr %dst.addr, align 8
  %src = load ptr, ptr %src.addr, align 8
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 8 %dst, ptr align 8 %src, i64 136, i1 false)
  ret void
}

define goabiinternal void @copy_goabiinternal_257_align8_normal(ptr %dst, ptr %src) {
; CHECK-LABEL: copy_goabiinternal_257_align8_normal:
; CHECK: rep
; CHECK: retq
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 8 %dst, ptr align 8 %src, i64 257, i1 false)
  ret void
}

define  void @copy_c_136_align8_normal(ptr %dst, ptr %src) {
; CHECK-LABEL: copy_c_136_align8_normal:
; CHECK: rep
; CHECK: retq
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 8 %dst, ptr align 8 %src, i64 136, i1 false)
  ret void
}

define goabiinternal void @copy_goabiinternal_136_align8_optsize(ptr %dst, ptr %src) optsize {
; CHECK-LABEL: copy_goabiinternal_136_align8_optsize:
; CHECK: rep
; CHECK: retq
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 8 %dst, ptr align 8 %src, i64 136, i1 false)
  ret void
}

define goabiinternal void @copy_goabiinternal_136_align8_minsize(ptr %dst, ptr %src) minsize {
; CHECK-LABEL: copy_goabiinternal_136_align8_minsize:
; CHECK: rep
; CHECK: retq
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 8 %dst, ptr align 8 %src, i64 136, i1 false)
  ret void
}

define goabiinternal void @copy_goabiinternal_136_align8_noimplicitfloat(ptr %dst, ptr %src) noimplicitfloat {
; CHECK-LABEL: copy_goabiinternal_136_align8_noimplicitfloat:
; CHECK: rep
; CHECK: retq
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 8 %dst, ptr align 8 %src, i64 136, i1 false)
  ret void
}

define goabiinternal void @copy_goabiinternal_136_align8_use_soft_float_true(ptr %dst, ptr %src) "use-soft-float"="true" {
; CHECK-LABEL: copy_goabiinternal_136_align8_use_soft_float_true:
; CHECK: rep
; CHECK: retq
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 8 %dst, ptr align 8 %src, i64 136, i1 false)
  ret void
}

declare goabiinternal void @consume136(ptr byval([136 x i8]) align 8)
define goabiinternal void @byval136(ptr %src) {
; CHECK-LABEL: byval136:
; CHECK-NOT: rep
; CHECK: movups
; CHECK-NOT: rep
; CHECK: callq consume136
; CHECK-NOT: rep
; CHECK: retq
  call goabiinternal void @consume136(ptr byval([136 x i8]) align 8 %src)
  ret void
}

declare void @consume_c136(ptr byval([136 x i8]) align 8)
define void @byval_c136(ptr %src) {
; CHECK-LABEL: byval_c136:
; CHECK: rep
; CHECK: callq consume_c136
; CHECK: retq
  call void @consume_c136(ptr byval([136 x i8]) align 8 %src)
  ret void
}

define goabiinternal void @ordinary_memcpy136(ptr %dst, ptr %src) {
; CHECK-LABEL: ordinary_memcpy136:
; CHECK-NOT: movups
; CHECK: callq memcpy
; CHECK: retq
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %dst, ptr align 8 %src, i64 136, i1 false)
  ret void
}

declare goabiinternal void @produce136(ptr goret([136 x i8]) align 8 "goretindex"="0")
define goabiinternal void @goret136(ptr %dst) {
; CHECK-LABEL: goret136:
; CHECK: callq produce136
; CHECK-NOT: rep
; CHECK: movups
; CHECK-NOT: rep
; CHECK: retq
  call goabiinternal void @produce136(ptr goret([136 x i8]) align 8 "goretindex"="0" %dst)
  ret void
}

; Keep target tuning that treats unaligned vectors as slow.
define goabiinternal void @slow_unaligned136(ptr %dst, ptr %src) "target-features"="+slow-unaligned-mem-16" {
; CHECK-LABEL: slow_unaligned136:
; CHECK: rep
; CHECK: retq
  call void @llvm.memcpy.inline.p0.p0.i64(ptr align 8 %dst, ptr align 8 %src, i64 136, i1 false)
  ret void
}

declare goabi0 void @consume_abi0_136(ptr byval([136 x i8]) align 8)
define goabiinternal void @byval_to_abi0_136(ptr %src) {
; CHECK-LABEL: byval_to_abi0_136:
; CHECK-NOT: rep
; CHECK: movups
; CHECK-NOT: rep
; CHECK: callq consume_abi0_136
; CHECK-NOT: rep
; CHECK: retq
  call goabi0 void @consume_abi0_136(ptr byval([136 x i8]) align 8 %src)
  ret void
}

; The policy follows the function being compiled, including calls across ABIs.
define void @c_caller_to_go136(ptr %src) {
; CHECK-LABEL: c_caller_to_go136:
; CHECK: rep
; CHECK: callq consume136
; CHECK: retq
  call goabiinternal void @consume136(ptr byval([136 x i8]) align 8 %src)
  ret void
}

define goabiinternal void @go_caller_to_c136(ptr %src) {
; CHECK-LABEL: go_caller_to_c136:
; CHECK-NOT: rep
; CHECK: movups
; CHECK-NOT: rep
; CHECK: callq consume_c136
; CHECK-NOT: rep
; CHECK: retq
  call void @consume_c136(ptr byval([136 x i8]) align 8 %src)
  ret void
}
