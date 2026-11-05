; RUN: llc -mtriple=aarch64-apple-darwin-goobj -O2 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -O2 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -O2 -verify-machineinstrs -filetype=obj -o /dev/null < %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -O2 -verify-machineinstrs -filetype=obj -o /dev/null < %s
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -O0 -verify-machineinstrs -filetype=obj -o /dev/null < %s
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -O2 -verify-machineinstrs -filetype=obj -o %t.o < %s
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s --check-prefix=OBJ
;
; The production GoObj path keeps ordinary small expansion and uses a
; compact loop for medium objects. Offsets must not lose stack provenance.
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1 immarg)
declare goabiinternal void @observe(ptr)

define goabiinternal void @clear_768_offset_0() {
; CHECK-LABEL: clear_768_offset_0:
; CHECK-NOT: runtime.memclrNoHeapPointers
; CHECK: stp xzr, xzr, [x{{[0-9]+}}], #16
; CHECK: b.ne
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
; CHECK: stp xzr, xzr, [x{{[0-9]+}}], #16
; CHECK: b.ne
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
; CHECK: stp xzr, xzr, [x{{[0-9]+}}], #16
; CHECK: b.ne
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
; CHECK: stp xzr, xzr, [x{{[0-9]+}}], #16
; CHECK: b.ne
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
; CHECK-NOT: runtime.memclrNoHeapPointers
; CHECK: stp xzr, xzr, [x{{[0-9]+}}], #16
; CHECK: b.ne
; CHECK-NOT: runtime.memclrNoHeapPointers
; CHECK: bl observe
  %a = alloca [1041 x i8], align 16
  %p = getelementptr i8, ptr %a, i64 0
  call void @llvm.memset.p0.i64(ptr align 16 %p, i8 0, i64 1025, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @clear_4096_offset_0() {
; CHECK-LABEL: clear_4096_offset_0:
; CHECK-NOT: runtime.memclrNoHeapPointers
; CHECK: stp xzr, xzr, [x{{[0-9]+}}], #16
; CHECK: b.ne
; CHECK-NOT: runtime.memclrNoHeapPointers
; CHECK: bl observe
  %a = alloca [4112 x i8], align 16
  %p = getelementptr i8, ptr %a, i64 0
  call void @llvm.memset.p0.i64(ptr align 16 %p, i8 0, i64 4096, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

; The loop and its exit must stay within the allocated frame's PCSP interval.
; A larger clear increases frame size, not the number of clearing stores.
; OBJ: symdef 0: clear_768_offset_0 abi=1 type=1 size=100
; OBJ: symdef 5: clear_4096_offset_0 abi=1 type=1 size=116
; OBJ: aux 0.0: type=funcinfo target= args=0 locals=824
; OBJ: aux 0.3: type=pcsp target= pc=[0-10:0,10-24:832,24-25:0]
; OBJ: reloc 0.1: off=80 size=4 type=9 add=0 target=observe
; OBJ: aux 5.40: type=funcinfo target= args=0 locals=4152
; OBJ: aux 5.43: type=pcsp target= pc=[0-13:0,13-28:4160,28-29:0]
; OBJ: reloc 5.11: off=92 size=4 type=9 add=0 target=observe

; Keep the first size beyond the loop policy on the runtime path.
define goabiinternal void @clear_4097_offset_1() {
; CHECK-LABEL: clear_4097_offset_1:
; CHECK: bl runtime.memclrNoHeapPointers
; CHECK: bl observe
  %a = alloca [4112 x i8], align 16
  %p = getelementptr i8, ptr %a, i64 1
  call void @llvm.memset.p0.i64(ptr align 1 %p, i8 0, i64 4097, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}
