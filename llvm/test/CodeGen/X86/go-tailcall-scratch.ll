; RUN: llc -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=x86_64-pc-windows-msvc -verify-machineinstrs < %s | FileCheck %s

target triple = "x86_64-unknown-linux-goobj"
@slot = external global ptr

; Nine integer parameters occupy every Go argument register; the closure
; context also occupies RDX. R12 and R13 remain available for the tail target.
; CHECK-LABEL: tail9:
; CHECK-NOT: push
; CHECK-NOT: (%rsp)
; CHECK: movq slot(%rip), %[[SCRATCH:r1[23]]]
; CHECK-NEXT: jmpq *%[[SCRATCH]]
define goabiinternal i64 @tail9(i64 %a, i64 %b, i64 %c, i64 %d, i64 %e, i64 %f, i64 %g, i64 %h, i64 %i, ptr nest %context) #0 {
  %target = load ptr, ptr @slot
  %r = musttail call goabiinternal i64 %target(i64 %a, i64 %b, i64 %c, i64 %d, i64 %e, i64 %f, i64 %g, i64 %h, i64 %i, ptr nest %context)
  ret i64 %r
}
attributes #0 = { "go-nosplit" }
