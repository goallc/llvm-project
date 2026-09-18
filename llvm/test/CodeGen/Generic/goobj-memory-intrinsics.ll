; RUN: llc -mtriple=x86_64-unknown-linux-goobj -O0 < %s | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -O2 < %s | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -O0 < %s | FileCheck %s --check-prefix=ARM64
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -O2 < %s | FileCheck %s --check-prefix=ARM64

; Large and dynamic operations must use Go helpers, with the target choosing
; whether small operations should be inlined. Go has no hosted C runtime.
; X86-LABEL: copy:
; X86: {{callq|jmp}} runtime.memmove
; ARM64-LABEL: copy:
; ARM64: {{bl|b}} runtime.memmove
define goabiinternal void @copy(ptr %dst, ptr %src, i64 %size) #0 {
  call void @llvm.memcpy.p0.p0.i64(ptr %dst, ptr %src, i64 %size, i1 false)
  ret void
}

; X86-LABEL: move:
; X86: {{callq|jmp}} runtime.memmove
; ARM64-LABEL: move:
; ARM64: {{bl|b}} runtime.memmove
define goabiinternal void @move(ptr %dst, ptr %src, i64 %size) #0 {
  call void @llvm.memmove.p0.p0.i64(ptr %dst, ptr %src, i64 %size, i1 false)
  ret void
}

; X86-LABEL: zero:
; X86: {{(callq|jmp) runtime.memclrNoHeapPointers|rep;stosb}}
; ARM64-LABEL: zero:
; ARM64: {{bl|b}} runtime.memclrNoHeapPointers
define goabiinternal void @zero(ptr %dst, i64 %size) #0 {
  call void @llvm.memset.p0.i64(ptr %dst, i8 0, i64 %size, i1 false)
  ret void
}

; At O0, even a small unaligned memmove may require a call on AArch64.
; X86-LABEL: small_move:
; X86-NOT: {{[[:space:]]}}memmove
; X86: ret
; ARM64-LABEL: small_move:
; ARM64-NOT: {{[[:space:]]}}memmove
; ARM64: ret
define goabiinternal void @small_move(ptr %dst, ptr %src) #0 {
  call void @llvm.memmove.p0.p0.i64(ptr %dst, ptr %src, i64 32, i1 false)
  ret void
}

; There is no general nonzero memset helper. Native expansion must handle both
; small and variable sizes without falling back to libc, including at O0.
; X86-LABEL: fill:
; X86-NOT: {{[[:space:]]}}memset
; X86: ret
; ARM64-LABEL: fill:
; ARM64-NOT: {{[[:space:]]}}memset
; ARM64: ret
define goabiinternal void @fill(ptr %dst, i8 %byte, i64 %size) #0 {
  call void @llvm.memset.p0.i64(ptr %dst, i8 %byte, i64 %size, i1 false)
  ret void
}

; X86-LABEL: small_fill:
; X86-NOT: {{[[:space:]]}}memset
; X86: ret
; ARM64-LABEL: small_fill:
; ARM64-NOT: {{[[:space:]]}}memset
; ARM64: ret
define goabiinternal void @small_fill(ptr %dst, i8 %byte) #0 {
  call void @llvm.memset.p0.i64(ptr %dst, i8 %byte, i64 32, i1 false)
  ret void
}

declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)
declare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1 immarg)
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1 immarg)

attributes #0 = { "frame-pointer"="non-leaf" }
