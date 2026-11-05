; RUN: llc -mtriple=aarch64-apple-darwin-goobj -O2 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -O2 -verify-machineinstrs < %s | FileCheck %s
;
; The production GoObj path uses the same bounded expansion and retains the
; runtime fallback outside its budget. Offsets must not lose stack provenance.
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1 immarg)
declare goabiinternal void @observe(ptr)

define goabiinternal void @clear_768_offset_0() {
; CHECK-LABEL: clear_768_offset_0:
; CHECK-NOT: runtime.memclrNoHeapPointers
; CHECK: stp
; CHECK-NOT: runtime.memclrNoHeapPointers
; CHECK: bl observe
  %a = alloca [784 x i8], align 16
  %p = getelementptr i8, ptr %a, i64 0
  call void @llvm.memset.p0.i64(ptr align 16 %p, i8 0, i64 768, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @clear_767_offset_1() {
; CHECK-LABEL: clear_767_offset_1:
; CHECK-NOT: runtime.memclrNoHeapPointers
; CHECK: stp
; CHECK-NOT: runtime.memclrNoHeapPointers
; CHECK: bl observe
  %a = alloca [784 x i8], align 16
  %p = getelementptr i8, ptr %a, i64 1
  call void @llvm.memset.p0.i64(ptr align 1 %p, i8 0, i64 767, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @clear_769_offset_15() {
; CHECK-LABEL: clear_769_offset_15:
; CHECK-NOT: runtime.memclrNoHeapPointers
; CHECK: stp
; CHECK-NOT: runtime.memclrNoHeapPointers
; CHECK: bl observe
  %a = alloca [800 x i8], align 16
  %p = getelementptr i8, ptr %a, i64 15
  call void @llvm.memset.p0.i64(ptr align 1 %p, i8 0, i64 769, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @clear_1024_offset_8() {
; CHECK-LABEL: clear_1024_offset_8:
; CHECK-NOT: runtime.memclrNoHeapPointers
; CHECK: stp
; CHECK-NOT: runtime.memclrNoHeapPointers
; CHECK: bl observe
  %a = alloca [1048 x i8], align 16
  %p = getelementptr i8, ptr %a, i64 8
  call void @llvm.memset.p0.i64(ptr align 8 %p, i8 0, i64 1024, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @clear_1025_offset_0() {
; CHECK-LABEL: clear_1025_offset_0:
; CHECK: bl runtime.memclrNoHeapPointers
; CHECK: bl observe
  %a = alloca [1041 x i8], align 16
  %p = getelementptr i8, ptr %a, i64 0
  call void @llvm.memset.p0.i64(ptr align 16 %p, i8 0, i64 1025, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @clear_4096_offset_0() {
; CHECK-LABEL: clear_4096_offset_0:
; CHECK: bl runtime.memclrNoHeapPointers
; CHECK: bl observe
  %a = alloca [4112 x i8], align 16
  %p = getelementptr i8, ptr %a, i64 0
  call void @llvm.memset.p0.i64(ptr align 16 %p, i8 0, i64 4096, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}
