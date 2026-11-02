; RUN: llc -mtriple=x86_64-pc-windows-goobj -O0 -verify-machineinstrs < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=x86_64-pc-windows-goobj -O2 -verify-machineinstrs < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=x86_64-pc-windows-gnu-goobj -relocation-model=pic -verify-machineinstrs < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=x86_64-pc-windows-goobj -filetype=obj -goobj-package-path=main -verify-machineinstrs %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s --check-prefix=OBJ
;
; Windows GoObj retains Go's ABI and object format. TLS recovery is a load of
; the runtime-selected TEB slot, then the Go TLS block, then g. Stack growth is
; handled by morestack, not the C ABI's __chkstk.

declare goabiinternal void @callee()
declare goabi0 void @"asmcallee<ABI0>"()

; ASM-LABEL: "abi0_to_internal<ABI0>":
; ASM: xorps %xmm15, %xmm15
; ASM-NEXT: movq runtime.tls_g(%rip), %r14
; ASM-NEXT: movq %gs:(%r14), %r14
; ASM-NEXT: movq (%r14), %r14
; ASM-NEXT: callq callee
define goabi0 void @"abi0_to_internal<ABI0>"() "go-nosplit" {
  call goabiinternal void @callee()
  ret void
}

; ASM-LABEL: "abi0_tail<ABI0>":
; ASM: movq runtime.tls_g(%rip), %r14
; ASM-NEXT: movq %gs:(%r14), %r14
; ASM-NEXT: movq (%r14), %r14
; ASM-NEXT: jmp callee
define goabi0 void @"abi0_tail<ABI0>"() "go-nosplit" {
  musttail call goabiinternal void @callee()
  ret void
}

; ASM-LABEL: restore_g:
; ASM: callq "asmcallee<ABI0>"
; ASM-NEXT: xorps %xmm15, %xmm15
; ASM-NEXT: movq runtime.tls_g(%rip), %r14
; ASM-NEXT: movq %gs:(%r14), %r14
; ASM-NEXT: movq (%r14), %r14
define goabiinternal void @restore_g() "go-nosplit" {
  call goabi0 void @"asmcallee<ABI0>"()
  ret void
}

; ASM-LABEL: large_frame:
; ASM-NOT: __chkstk
; ASM: callq "runtime.morestack_noctxt<ABI0>"
; ASM-NOT: __chkstk
; ASM: pushq %rbp
; ASM: movq %rsp, %rbp
; ASM-NOT: __chkstk
; ASM: subq $8192, %rsp
; ASM-NOT: __chkstk
define goabiinternal i8 @large_frame() "frame-pointer"="all" {
  %slot = alloca [8192 x i8], align 8
  %end = getelementptr [8192 x i8], ptr %slot, i64 0, i64 8191
  store volatile i8 42, ptr %end
  %v = load volatile i8, ptr %end
  ret i8 %v
}

; A conditional call must not shrink-wrap RBP setup into the slow path: the
; Windows GoObj unwind record describes a single entry prologue.
declare goabiinternal i64 @get_result()
; ASM-LABEL: conditional_frame:
; ASM: pushq %rbp
; ASM: movq %rsp, %rbp
; ASM: {{testq|cmpq}}
; ASM: callq get_result
define goabiinternal i64 @conditional_frame(i64 %x) "frame-pointer"="all" "go-nosplit" {
  %cond = icmp eq i64 %x, 0
  br i1 %cond, label %fast, label %slow
fast:
  ret i64 0
slow:
  %v = call goabiinternal i64 @get_result()
  %r = add i64 %v, 1
  ret i64 %r
}

; OBJ: runtime.tls_g abi=
; OBJ-NOT: runtime.tlsg
; OBJ-NOT: __chkstk

; The 29-byte prologue includes the finalized stack-split branch encodings.
; SET_FPREG ends at PC 29; PUSH_NONVOL(RBP) ends at PC 26.
; OBJ: type=seh_unwind target=go:sehuw.011D02051D031A5000000000 data=011d02051d031a5000000000
