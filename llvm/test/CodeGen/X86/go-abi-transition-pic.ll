; RUN: llc -mtriple=x86_64-linux-gnu -relocation-model=pic -O0 -verify-machineinstrs < %s | FileCheck %s --check-prefix=PIC
; RUN: llc -mtriple=x86_64-linux-gnu -relocation-model=pic -O2 -verify-machineinstrs < %s | FileCheck %s --check-prefix=PIC
; RUN: llc -mtriple=x86_64-linux-gnu -relocation-model=static -O2 -verify-machineinstrs < %s | FileCheck %s --check-prefix=STATIC
; RUN: llc -mtriple=x86_64-linux-goobj -relocation-model=pic -goobj-package-path=main -verify-machineinstrs -filetype=obj -o %t.o %s
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s --check-prefix=OBJ

; PIC ABI transitions must recover g through initial-exec TLS. R14 is reserved
; and can hold the offset before loading g, without clobbering arguments/results.
declare goabiinternal void @internal_callee()
declare goabi0 void @"abi0_callee<ABI0>"()

; PIC-LABEL: "abi0_to_internal<ABI0>":
; PIC: xorps %xmm15, %xmm15
; PIC-NEXT: movq runtime.tlsg@GOTTPOFF(%rip), %r14
; PIC-NEXT: movq %fs:(%r14), %r14
; PIC-NEXT: callq internal_callee
; STATIC-LABEL: "abi0_to_internal<ABI0>":
; STATIC: movq %fs:runtime.tlsg@TPOFF, %r14
define goabi0 void @"abi0_to_internal<ABI0>"() "go-nosplit" {
  call goabiinternal void @internal_callee()
  ret void
}

; PIC-LABEL: "abi0_tail_to_internal<ABI0>":
; PIC: movq runtime.tlsg@GOTTPOFF(%rip), %r14
; PIC-NEXT: movq %fs:(%r14), %r14
; PIC-NEXT: jmp internal_callee
; STATIC-LABEL: "abi0_tail_to_internal<ABI0>":
; STATIC: movq %fs:runtime.tlsg@TPOFF, %r14
define goabi0 void @"abi0_tail_to_internal<ABI0>"() "go-nosplit" {
  musttail call goabiinternal void @internal_callee()
  ret void
}

; PIC-LABEL: internal_to_abi0:
; PIC: callq "abi0_callee<ABI0>"
; PIC-NEXT: xorps %xmm15, %xmm15
; PIC-NEXT: movq runtime.tlsg@GOTTPOFF(%rip), %r14
; PIC-NEXT: movq %fs:(%r14), %r14
; STATIC-LABEL: internal_to_abi0:
; STATIC: movq %fs:runtime.tlsg@TPOFF, %r14
define goabiinternal void @internal_to_abi0() "go-nosplit" {
  call goabi0 void @"abi0_callee<ABI0>"()
  ret void
}

; Match native Go's symbol-free TLS relocations; the linker supplies runtime.tlsg.
; OBJ-NOT: nonpkgref {{[0-9]+}}: runtime.tlsg
; OBJ: reloc {{.*}} type=16 add=-4 {{.*}} pkg=0 sym=0
; OBJ: reloc {{.*}} type=16 add=-4 {{.*}} pkg=0 sym=0
; OBJ: reloc {{.*}} type=16 add=-4 {{.*}} pkg=0 sym=0
