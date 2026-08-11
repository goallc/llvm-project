; RUN: llc < %s -mtriple=x86_64-unknown-linux-gnu | FileCheck %s
; RUN: opt < %s -passes='default<O2>' -S | FileCheck %s --check-prefix=OPT

; This intrinsic represents an instruction already protected by Go's runtime
; FMA feature check when GOAMD64 does not guarantee FMA.

define double @fma(double %x, double %y, double %z) {
; CHECK-LABEL: fma:
; CHECK:       vfmadd213sd %xmm2, %xmm1, %xmm0
; CHECK-NEXT:  retq
  %result = call double @llvm.x86.go.fma.f64(double %x, double %y, double %z)
  ret double %result
}

; GOAMD64=v3 maps to x86-64-v3, whose guaranteed set includes FMA.
define double @v3_fma(double %x, double %y, double %z) #0 {
; CHECK-LABEL: v3_fma:
; CHECK:       vfmadd213sd %xmm2, %xmm1, %xmm0
; CHECK-NEXT:  retq
  %result = call double @llvm.fma.f64(double %x, double %y, double %z)
  ret double %result
}

; The guarded intrinsic is intentionally not speculatable: optimization must
; not move the feature instruction above the runtime feature branch.
define double @guarded_fma(double %x, double %y, double %z, i1 %has_fma) {
; CHECK-LABEL: guarded_fma:
; CHECK:       testb $1, %dil
; CHECK-NEXT:  je [[EXIT:.LBB[0-9]+_[0-9]+]]
; CHECK:       vfmadd231sd %xmm0, %xmm1, %xmm2
; CHECK-NEXT:  [[EXIT]]:
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

declare double @llvm.x86.go.fma.f64(double, double, double)
declare double @llvm.fma.f64(double, double, double)

attributes #0 = { "target-cpu"="x86-64-v3" }
