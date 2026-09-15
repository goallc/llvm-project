; RUN: llc -verify-machineinstrs < %s | FileCheck %s

target triple = "aarch64-unknown-linux-goobj"
@slot = external global ptr

; X0-X15 carry the integer parameters and X26 carries the closure context.
; The tail target must still fit in the permanent scratch registers X16/X17.
; CHECK-LABEL: tail16:
; CHECK-NOT: str
; CHECK-NOT: stp
; CHECK: adrp x[[SCRATCH:1[67]]], slot
; CHECK-NEXT: ldr x[[SCRATCH]], [x[[SCRATCH]], :lo12:slot]
; CHECK-NEXT: br x[[SCRATCH]]
define goabiinternal i64 @tail16(i64 %a, i64 %b, i64 %c, i64 %d, i64 %e, i64 %f, i64 %g, i64 %h, i64 %i, i64 %j, i64 %k, i64 %l, i64 %m, i64 %n, i64 %o, i64 %p, ptr nest %context) #0 {
  %target = load ptr, ptr @slot
  %r = musttail call goabiinternal i64 %target(i64 %a, i64 %b, i64 %c, i64 %d, i64 %e, i64 %f, i64 %g, i64 %h, i64 %i, i64 %j, i64 %k, i64 %l, i64 %m, i64 %n, i64 %o, i64 %p, ptr nest %context)
  ret i64 %r
}
attributes #0 = { "go-nosplit" }
