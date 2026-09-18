; REQUIRES: x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -mattr=+retpoline-indirect-calls,+retpoline-indirect-branches -verify-machineinstrs < %s | FileCheck %s --implicit-check-not='callq *' --implicit-check-not='jmpq *' --implicit-check-not='__llvm_retpoline'
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -mattr=+retpoline-indirect-calls,+retpoline-indirect-branches -O0 -verify-machineinstrs < %s | FileCheck %s --implicit-check-not='callq *' --implicit-check-not='jmpq *' --implicit-check-not='__llvm_retpoline'
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -mattr=+retpoline-indirect-calls,+retpoline-indirect-branches -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s --check-prefix=OBJ

; R11 is a Go argument, RDX carries the closure. Neither may be overwritten
; with the target. Ordinary calls reuse LLVM's thunk lowering with R12.
; CHECK-LABEL: ordinary:
; CHECK: movl $9, %r11d
; CHECK: callq "runtime.retpolineR12<ABI0>"
define goabiinternal void @ordinary(ptr %fp, ptr %ctx) "go-nosplit" {
  call goabiinternal void %fp(ptr nest %ctx, i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7, i64 8, i64 9)
  ret void
}

; Subregister arguments also occupy R11; checking only the full register
; would silently corrupt the ninth byte argument.
; CHECK-LABEL: ordinary_bytes:
; CHECK: callq "runtime.retpolineR12<ABI0>"
define goabiinternal void @ordinary_bytes(ptr %fp) "go-nosplit" {
  call goabiinternal void %fp(i8 1, i8 2, i8 3, i8 4, i8 5, i8 6, i8 7, i8 8, i8 9)
  ret void
}

; Statepoints choose the thunk for the existing physical target register.
; CHECK-LABEL: safepoint:
; CHECK: movl $9, %r11d
; CHECK: callq "runtime.retpoline{{[A-Z0-9]+}}<ABI0>"
define goabiinternal void @safepoint(ptr %fp, ptr %ctx) "go-nosplit" gc "statepoint-example" {
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
    @llvm.experimental.gc.statepoint.p0(i64 0, i32 0, ptr elementtype(void (ptr, i64, i64, i64, i64, i64, i64, i64, i64, i64)) %fp, i32 10, i32 0,
      ptr nest %ctx, i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7, i64 8, i64 9, i32 0, i32 0)
  ret void
}

declare token @llvm.experimental.gc.statepoint.p0(i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)

; CHECK-LABEL: tail:
; CHECK: jmp "runtime.retpolineR12<ABI0>"
define goabiinternal i64 @tail(ptr nest %ctx, i64 %a, i64 %b, i64 %c, i64 %d, i64 %e, i64 %f, i64 %g, i64 %h, i64 %i) "go-nosplit" {
  %fp = load ptr, ptr %ctx
  %r = musttail call goabiinternal i64 %fp(ptr nest %ctx, i64 %a, i64 %b, i64 %c, i64 %d, i64 %e, i64 %f, i64 %g, i64 %h, i64 %i)
  ret i64 %r
}

; Runtime entry points use ABI0 symbol identity even though the trampoline
; preserves Go ABIInternal arguments; it does not interpret those arguments.
; OBJ: nonpkgref {{.*}}runtime.retpolineR12 abi=0
; OBJ: target=runtime.retpolineR12 kind=R_CALL
