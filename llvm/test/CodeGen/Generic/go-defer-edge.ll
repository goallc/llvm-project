; RUN: opt -passes='default<O2>' -S %s | FileCheck %s --check-prefix=OPT
; RUN: llc -O0 -fast-isel=0 -verify-machineinstrs -mtriple=aarch64-unknown-linux-gnu %s -o - | FileCheck %s --check-prefix=AARCH64
; RUN: llc -O0 -fast-isel=0 -verify-machineinstrs -mtriple=x86_64-unknown-linux-gnu %s -o - | FileCheck %s --check-prefix=X86
; RUN: llc -O0 -fast-isel=0 -mtriple=aarch64-unknown-linux-gnu -stop-after=finalize-isel %s -o - | FileCheck %s --check-prefix=SDAG
; RUN: llc -O0 -global-isel=1 -mtriple=aarch64-unknown-linux-gnu -stop-after=irtranslator %s -o - | FileCheck %s --check-prefix=GISEL

declare void @llvm.go.defer.edge()
declare void @runtime.deferreturn()

define void @go_defer_edge() {
; OPT-LABEL: define void @go_defer_edge()
; OPT: callbr void @llvm.go.defer.edge()
; OPT-NEXT: to label %{{.*}} [label %recover]
; OPT: recover:
; OPT: call void @runtime.deferreturn()
;
; AARCH64-LABEL: go_defer_edge:
; AARCH64-NOT: llvm.go.defer.edge
; AARCH64: ret
; AARCH64: runtime.deferreturn
; AARCH64: ret
;
; X86-LABEL: go_defer_edge:
; X86-NOT: llvm.go.defer.edge
; X86: retq
; X86: runtime.deferreturn
; X86: retq
;
; SDAG-LABEL: name: go_defer_edge
; SDAG-NOT: llvm.go.defer.edge
; SDAG: bb.{{[0-9]+}}.entry:
; SDAG: successors: %bb.{{[0-9]+}}{{.*}}%bb.{{[0-9]+}}
; SDAG: bb.{{[0-9]+}}.recover (inlineasm-br-indirect-target)
;
; GISEL-LABEL: name: go_defer_edge
; GISEL-NOT: G_INTRINSIC intrinsic(@llvm.go.defer.edge)
; GISEL: bb.{{[0-9]+}}.entry:
; GISEL: successors: %bb.{{[0-9]+}}{{.*}}%bb.{{[0-9]+}}
; GISEL: bb.{{[0-9]+}}.recover (inlineasm-br-indirect-target)
entry:
  callbr void @llvm.go.defer.edge() to label %normal [label %recover]

normal:
  ret void

recover:
  call void @runtime.deferreturn()
  ret void
}
