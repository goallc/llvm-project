; RUN: opt -passes=sroa -S < %s | FileCheck %s

; SROA may rewrite a load to use the type and alignment of the promoted alloca.
; Preserve standard annotation metadata on the replacement instruction.
define i8 @volatile_slice_load(ptr %value) {
; CHECK-LABEL: define i8 @volatile_slice_load(
; CHECK: %[[SLOT:.*]] = alloca ptr, align 8
; CHECK: %[[RESULT:.*]] = load volatile i8, ptr %[[SLOT]], align 8, !annotation ![[ANNOT:[0-9]+]]
; CHECK: ret i8 %[[RESULT]]
entry:
  %slot = alloca ptr, align 8
  store ptr %value, ptr %slot, align 8
  %result = load volatile i8, ptr %slot, align 1, !annotation !0
  ret i8 %result
}

; CHECK: ![[ANNOT]] = !{!"test.annotation"}
!0 = !{!"test.annotation"}
