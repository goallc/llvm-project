; RUN: llc < %s -mtriple=x86_64-unknown-linux-gnu | FileCheck %s
; RUN: opt < %s -passes='default<O2>' -S | FileCheck %s --check-prefix=OPT

; These intrinsics represent instructions already protected by Go's runtime
; CPU-feature checks when the configured GOAMD64 level does not guarantee the
; instruction. The surrounding functions deliberately have no target feature
; attributes.

define double @floor(double %x) {
; CHECK-LABEL: floor:
; CHECK:       roundsd $1, %xmm0, %xmm0
; CHECK-NEXT:  retq
  %result = call double @llvm.x86.go.sse41.round.f64(double %x, i32 1)
  ret double %result
}

define double @ceil(double %x) {
; CHECK-LABEL: ceil:
; CHECK:       roundsd $2, %xmm0, %xmm0
; CHECK-NEXT:  retq
  %result = call double @llvm.x86.go.sse41.round.f64(double %x, i32 2)
  ret double %result
}

define double @trunc(double %x) {
; CHECK-LABEL: trunc:
; CHECK:       roundsd $3, %xmm0, %xmm0
; CHECK-NEXT:  retq
  %result = call double @llvm.x86.go.sse41.round.f64(double %x, i32 3)
  ret double %result
}

define double @roundeven(double %x) {
; CHECK-LABEL: roundeven:
; CHECK:       roundsd $0, %xmm0, %xmm0
; CHECK-NEXT:  retq
  %result = call double @llvm.x86.go.sse41.round.f64(double %x, i32 0)
  ret double %result
}

define double @fma(double %x, double %y, double %z) {
; CHECK-LABEL: fma:
; CHECK:       vfmadd213sd %xmm2, %xmm1, %xmm0
; CHECK-NEXT:  retq
  %result = call double @llvm.x86.go.fma.f64(double %x, double %y, double %z)
  ret double %result
}

; The guarded intrinsics are intentionally not speculatable: optimization must
; not move the feature instruction above the runtime feature branch.
define double @guarded_round(double %x, i1 %has_sse41) {
; OPT-LABEL: define double @guarded_round(
; OPT:       br i1 %has_sse41, label %round, label %exit
; OPT:       round:
; OPT-NEXT:  %result = tail call double @llvm.x86.go.sse41.round.f64(double %x, i32 3)
; OPT-NEXT:  br label %exit
entry:
  br i1 %has_sse41, label %round, label %exit

round:
  %result = call double @llvm.x86.go.sse41.round.f64(double %x, i32 3)
  br label %exit

exit:
  %value = phi double [ %result, %round ], [ %x, %entry ]
  ret double %value
}

define double @guarded_fma(double %x, double %y, double %z, i1 %has_fma) {
; OPT-LABEL: define double @guarded_fma(
; OPT:       br i1 %has_fma, label %fma, label %exit
; OPT:       fma:
; OPT-NEXT:  %result = tail call double @llvm.x86.go.fma.f64(double %x, double %y, double %z)
; OPT-NEXT:  br label %exit
entry:
  br i1 %has_fma, label %fma, label %exit

fma:
  %result = call double @llvm.x86.go.fma.f64(double %x, double %y, double %z)
  br label %exit

exit:
  %value = phi double [ %result, %fma ], [ %z, %entry ]
  ret double %value
}

declare double @llvm.x86.go.sse41.round.f64(double, i32 immarg)
declare double @llvm.x86.go.fma.f64(double, double, double)
