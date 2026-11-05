; RUN: llc -mtriple=x86_64-unknown-linux-gnu < %s | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -disable-lsr < %s | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -mattr=+ccmp < %s | FileCheck %s --check-prefix=CCMP
; Fixed-bound early-exit scans reduced from Go ethereum/bitutil.

; CHECK-LABEL: scan_byte:
; CHECK:       {{test|cmp}}{{b|q}}
; CHECK-NEXT:  j{{e|ne}}
; CHECK-NOT:   orb
; CHECK:       {{test|cmp}}{{b|q}}
; CHECK-NOT:   set
; CHECK-NOT:   orb
; CHECK:       j{{e|ne}}
; CHECK:       retq
; CCMP-LABEL: scan_byte:
; CCMP:       ctest
; CCMP:       retq
define i1 @scan_byte(ptr %p) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %next, %loop ]
  %a = getelementptr i8, ptr %p, i64 %i
  %v = load i8, ptr %a, align 1
  %data = icmp ne i8 %v, 0
  %next = add nuw nsw i64 %i, 1
  %bound = icmp eq i64 %next, 4096
  %cond = select i1 %data, i1 true, i1 %bound
  br i1 %cond, label %exit, label %loop, !prof !0
exit:
  %result = icmp ne i8 %v, 0
  ret i1 %result
}

; CHECK-LABEL: scan_word:
; CHECK:       {{test|cmp}}{{b|q}}
; CHECK-NEXT:  j{{e|ne}}
; CHECK-NOT:   orb
; CHECK:       {{test|cmp}}{{b|q}}
; CHECK-NOT:   set
; CHECK-NOT:   orb
; CHECK:       j{{e|ne}}
; CHECK:       retq
; CCMP-LABEL: scan_word:
; CCMP:       ctest
; CCMP:       retq
define i1 @scan_word(ptr %p) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %next, %loop ]
  %a = getelementptr i64, ptr %p, i64 %i
  %v = load i64, ptr %a, align 1
  %data = icmp ne i64 %v, 0
  %next = add nuw nsw i64 %i, 1
  %bound = icmp eq i64 %next, 4096
  %cond = select i1 %data, i1 true, i1 %bound
  br i1 %cond, label %exit, label %loop, !prof !0
exit:
  %result = icmp ne i64 %v, 0
  ret i1 %result
}

; CHECK-LABEL: scan_byte_swapped:
; CHECK:       {{test|cmp}}{{b|q}}
; CHECK-NEXT:  j{{e|ne}}
; CHECK-NOT:   orb
; CHECK:       {{test|cmp}}{{b|q}}
; CHECK-NOT:   set
; CHECK-NOT:   orb
; CHECK:       j{{e|ne}}
; CHECK:       retq
; CCMP-LABEL: scan_byte_swapped:
; CCMP:       ctest
; CCMP:       retq
define i1 @scan_byte_swapped(ptr %p) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %next, %loop ]
  %a = getelementptr i8, ptr %p, i64 %i
  %v = load i8, ptr %a, align 1
  %data = icmp ne i8 %v, 0
  %next = add nuw nsw i64 %i, 1
  %bound = icmp eq i64 %next, 4096
  %cond = select i1 %bound, i1 true, i1 %data
  br i1 %cond, label %exit, label %loop, !prof !0
exit:
  %result = icmp ne i8 %v, 0
  ret i1 %result
}

; CHECK-LABEL: scan_byte_and:
; CHECK:       {{test|cmp}}{{b|q}}
; CHECK-NEXT:  j{{e|ne}}
; CHECK-NOT:   orb
; CHECK:       {{test|cmp}}{{b|q}}
; CHECK-NOT:   set
; CHECK-NOT:   orb
; CHECK:       j{{e|ne}}
; CHECK:       retq
; CCMP-LABEL: scan_byte_and:
; CCMP:       ctest
; CCMP:       retq
define i1 @scan_byte_and(ptr %p) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %next, %loop ]
  %a = getelementptr i8, ptr %p, i64 %i
  %v = load i8, ptr %a, align 1
  %data = icmp eq i8 %v, 0
  %next = add nuw nsw i64 %i, 1
  %bound = icmp ne i64 %next, 4096
  %cond = select i1 %data, i1 %bound, i1 false
  br i1 %cond, label %loop, label %exit, !prof !0
exit:
  %result = icmp ne i8 %v, 0
  ret i1 %result
}

; Non-loop mixed predicates retain the existing cost model.
; CHECK-LABEL: acyclic:
; CHECK: set
; CHECK: set
; CHECK: orb
; CHECK: retq
define i1 @acyclic(i8 %a, i64 %b) {
  %x = icmp ne i8 %a, 0
  %y = icmp eq i64 %b, 4096
  %r = or i1 %x, %y
  ret i1 %r
}

; A merged data-dependent early exit need not have a strongly biased profile.
!0 = !{!"branch_weights", i32 256127, i32 255873}

; An acyclic branch with the same mixed predicates still uses SETCC+OR.
; CHECK-LABEL: acyclic_branch:
; CHECK:       setne
; CHECK:       sete
; CHECK:       orb
; CHECK:       j{{e|ne}}
define i32 @acyclic_branch(i8 %a, i64 %b) {
  %x = icmp ne i8 %a, 0
  %y = icmp eq i64 %b, 4096
  %r = select i1 %x, i1 true, i1 %y
  br i1 %r, label %yes, label %no, !prof !0
yes:
  %v1 = tail call i32 @yes()
  ret i32 %v1
no:
  %v2 = tail call i32 @no()
  ret i32 %v2
}
declare i32 @yes()
declare i32 @no()
