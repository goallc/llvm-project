; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: split-file %s %t
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs -filetype=obj %t/valid.ll -o %t.x86.o
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -verify-machineinstrs -filetype=obj %t/valid.ll -o %t.arm64.o
; RUN: llc -O0 -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs -filetype=obj %t/valid.ll -o %t.x86.o0.o
; RUN: llc -O0 -mtriple=aarch64-unknown-linux-goobj -verify-machineinstrs -filetype=obj %t/valid.ll -o %t.arm64.o0.o
; RUN: not --crash llc -mtriple=aarch64-unknown-linux-goobj %t/invalid-soft.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=SOFT
; RUN: not --crash llc -mtriple=aarch64-unknown-linux-goobj %t/invalid-hard.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=HARD
; SOFT: Go result 0 is memory-assigned but uses a direct LLVM return; use goret
; HARD: Go result 0 is register-assigned but uses goret

;--- valid.ll
%complex = type { double, double }

; The integer result still uses a register. Floating-point arguments and the
; complex result use their typed memory carriers in soft-float mode.
define goabiinternal i64 @makecomplex(ptr byval(double) align 8 %r, ptr byval(double) align 8 %i, ptr goret(%complex) "goretindex"="1" align 8 %out) "use-soft-float"="true" {
  %rv = load double, ptr %r, align 8
  %iv = load double, ptr %i, align 8
  %ip = getelementptr %complex, ptr %out, i32 0, i32 1
  store double %rv, ptr %out, align 8
  store double %iv, ptr %ip, align 8
  ret i64 42
}

; A direct call can obtain its ABI mode from the callee declaration.
define goabiinternal i64 @direct(ptr %r, ptr %i, ptr %dst) "frame-pointer"="non-leaf" {
  %v = call goabiinternal i64 @makecomplex(ptr byval(double) align 8 %r, ptr byval(double) align 8 %i, ptr goret(%complex) "goretindex"="1" align 8 %dst)
  ret i64 %v
}

; An indirect call must describe the ABI itself. It must not depend on the
; caller having a target-specific soft-float feature.
define goabiinternal i64 @indirect(ptr %fn, ptr %r, ptr %i, ptr %dst) "frame-pointer"="non-leaf" {
  %v = call goabiinternal i64 %fn(ptr byval(double) align 8 %r, ptr byval(double) align 8 %i, ptr goret(%complex) "goretindex"="1" align 8 %dst) "use-soft-float"="true"
  ret i64 %v
}

;--- invalid-soft.ll
define goabiinternal double @bad() "use-soft-float"="true" {
  ret double 1.0
}

;--- invalid-hard.ll
define goabiinternal void @bad(ptr goret(double) "goretindex"="0" %out) "use-soft-float"="false" {
  store double 1.0, ptr %out
  ret void
}
