; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O2 -verify-machineinstrs < %s | FileCheck %s --check-prefixes=CHECK,UNALIGNED
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -mattr=+strict-align -O2 -verify-machineinstrs < %s | FileCheck %s --check-prefixes=CHECK,STRICT
;
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -mattr=-fp-armv8 -O2 -verify-machineinstrs < %s | FileCheck %s --check-prefixes=CHECK,UNALIGNED
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -mattr=+mops -O2 -verify-machineinstrs < %s | FileCheck %s --check-prefix=MOPS
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O2 -verify-machineinstrs -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O2 -verify-machineinstrs -filetype=obj -o /dev/null < %s
;
; Keep ordinary small zero fills, and lower medium Go stack clears to compact
; machine-CFG loops rather than generic runtime calls or unbounded expansion.
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1 immarg)
declare goabiinternal void @observe(ptr)
declare void @observe_c(ptr)

define goabiinternal void @stack_191() {
; UNALIGNED-LABEL: stack_191:
; UNALIGNED-NOT: bl memset
; UNALIGNED-NOT: bl bzero
; UNALIGNED-NOT: b.ne
; UNALIGNED: bl observe
; STRICT-LABEL: stack_191:
; STRICT: bl {{memset|bzero}}
; STRICT: bl observe
  %a = alloca [191 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 191, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

; The normal small-memset expansion still runs first. Its target-specific
; store budget, rather than a new hard byte threshold, determines when this
; fallback is reached.
define goabiinternal void @stack_192() {
; UNALIGNED-LABEL: stack_192:
; UNALIGNED-NOT: b.ne
; UNALIGNED: bl observe
; STRICT-LABEL: stack_192:
; STRICT: stp xzr, xzr, [x{{[0-9]+}}], #16
; STRICT: b.ne
; STRICT: bl observe
  %a = alloca [192 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 192, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_257() {
; CHECK-LABEL: stack_257:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [257 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 257, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_511() {
; CHECK-LABEL: stack_511:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [511 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 511, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_512() {
; CHECK-LABEL: stack_512:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [512 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 512, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_767() {
; CHECK-LABEL: stack_767:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp xzr, xzr, [x{{[0-9]+}}], #16
; CHECK: b.ne
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [767 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 767, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

; Target MOPS lowering keeps its existing priority.
define goabiinternal void @stack_768() {
; MOPS-LABEL: stack_768:
; MOPS: setp
; MOPS-NEXT: setm
; MOPS-NEXT: sete
; MOPS-NOT: b.ne
; MOPS: bl observe
; CHECK-LABEL: stack_768:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp xzr, xzr, [x{{[0-9]+}}], #16
; CHECK: b.ne
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
; MIR-LABEL: name: stack_768
; MIR: noPhis: false
; MIR: bb.1
; MIR: successors: %bb.1
; MIR: PHI
; MIR: PHI
; MIR-NOT: PHI
; MIR-NOT: LDR
; MIR-NOT: LDP
; MIR: STPXpost {{.*}}$xzr, $xzr{{.*}} :: (store (s6144) into %ir.a
; MIR: STPXpost {{.*}}$xzr, $xzr
; MIR: STPXpost {{.*}}$xzr, $xzr
; MIR: STPXpost {{.*}}$xzr, $xzr
; MIR: SUBSXri {{.*}}, 64, 0
; MIR: Bcc 1, %bb.1
; MIR: bb.2
  %a = alloca [768 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 768, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_769() {
; CHECK-LABEL: stack_769:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp xzr, xzr, [x{{[0-9]+}}], #16
; CHECK: b.ne
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [769 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 769, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_1024() {
; CHECK-LABEL: stack_1024:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp xzr, xzr, [x{{[0-9]+}}], #16
; CHECK: b.ne
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [1024 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 1024, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_1025() {
; CHECK-LABEL: stack_1025:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp xzr, xzr, [x{{[0-9]+}}], #16
; CHECK: b.ne
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [1025 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 1025, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @stack_4096() {
; CHECK-LABEL: stack_4096:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: stp xzr, xzr, [x{{[0-9]+}}], #16
; CHECK: b.ne
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [4096 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 4096, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @heap(ptr %p) {
; CHECK-LABEL: heap:
; CHECK: bl {{memset|bzero}}
  call void @llvm.memset.p0.i64(ptr align 16 %p, i8 0, i64 768, i1 false)
  call goabiinternal void @observe(ptr %p)
  ret void
}

define goabiinternal void @dynamic(i64 %n) {
; CHECK-LABEL: dynamic:
; CHECK: bl {{memset|bzero}}
  %a = alloca [1024 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 %n, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @nonzero() {
; CHECK-LABEL: nonzero:
; CHECK: bl {{memset|bzero}}
  %a = alloca [768 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 7, i64 768, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define void @c_stack() {
; CHECK-LABEL: c_stack:
; CHECK: bl {{memset|bzero}}
  %a = alloca [768 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 768, i1 false)
  call void @observe_c(ptr %a)
  ret void
}

; The policy does not override a size-optimized function or volatile memset.
define goabiinternal void @size_optimized() optsize {
; CHECK-LABEL: size_optimized:
; CHECK: bl {{memset|bzero}}
  %a = alloca [768 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 768, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @volatile_stack() {
; CHECK-LABEL: volatile_stack:
; CHECK: bl {{memset|bzero}}
  %a = alloca [768 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 768, i1 true)
  call goabiinternal void @observe(ptr %a)
  ret void
}

; Keep the normal store-type selection when vector registers are forbidden.
define goabiinternal void @no_float() noimplicitfloat {
; CHECK-LABEL: no_float:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK-NOT: movi
; CHECK: stp xzr, xzr
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [768 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 768, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

; Byte alignment uses integer pairs on ordinary targets and a compact byte
; store loop on strict-alignment targets. Neither path may overrun the object.
define goabiinternal void @unaligned_stack() {
; CHECK-LABEL: unaligned_stack:
; UNALIGNED-NOT: bl memset
; UNALIGNED: stp
; UNALIGNED-NOT: bl memset
; STRICT-NOT: bl memset
; STRICT: strb wzr, [x{{[0-9]+}}], #1
; STRICT: b.ne
; STRICT-NOT: bl memset
; CHECK: bl observe
  %a = alloca [784 x i8], align 16
  %p = getelementptr i8, ptr %a, i64 1
  call void @llvm.memset.p0.i64(ptr align 1 %p, i8 0, i64 768, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

; No source operand or vector registers are necessary near the size cap.
; Three bytes following the loop exercise the ordinary exact tail lowering.
define goabiinternal void @medium_tail() noimplicitfloat {
; CHECK-LABEL: medium_tail:
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK-NOT: movi
; CHECK: stp xzr, xzr, [x{{[0-9]+}}], #16
; CHECK: b.ne
; CHECK: strb wzr
; CHECK: strh wzr
; CHECK-NOT: bl memset
; CHECK-NOT: bl bzero
; CHECK: bl observe
  %a = alloca [4035 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %a, i8 0, i64 4035, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

; Strict-alignment scalar loops must use only accesses allowed by the pointer.
define goabiinternal void @align2_tail() {
; STRICT-LABEL: align2_tail:
; STRICT: strh wzr, [x{{[0-9]+}}], #2
; STRICT: b.ne
; STRICT: strb wzr
; STRICT-NOT: bl memset
; STRICT: bl observe
  %a = alloca [1026 x i8], align 8
  %p = getelementptr i8, ptr %a, i64 2
  call void @llvm.memset.p0.i64(ptr align 2 %p, i8 0, i64 1023, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @align4_tail() {
; STRICT-LABEL: align4_tail:
; STRICT: str wzr, [x{{[0-9]+}}], #4
; STRICT: b.ne
; STRICT-DAG: strh wzr, [x{{[0-9]+}}, #12]
; STRICT-DAG: strb wzr, [x{{[0-9]+}}, #14]
; STRICT-NOT: bl memset
; STRICT: bl observe
  %a = alloca [1028 x i8], align 8
  %p = getelementptr i8, ptr %a, i64 4
  call void @llvm.memset.p0.i64(ptr align 4 %p, i8 0, i64 1023, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

; Larger clears retain the runtime's bulk clearing path.
define goabiinternal void @stack_4097() {
; CHECK-LABEL: stack_4097:
; CHECK: bl {{memset|bzero}}
; CHECK: bl observe
  %a = alloca [4097 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 4097, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}

define goabiinternal void @large_tail() {
; CHECK-LABEL: large_tail:
; CHECK: bl {{memset|bzero}}
; CHECK: bl observe
  %a = alloca [2097155 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %a, i8 0, i64 2097155, i1 false)
  call goabiinternal void @observe(ptr %a)
  ret void
}
