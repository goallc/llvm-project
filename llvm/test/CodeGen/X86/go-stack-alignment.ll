; REQUIRES: x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog -o - %s | FileCheck %s

declare goabiinternal void @sink(ptr)

define goabiinternal void @stack_slot(ptr %value) #0 {
; CHECK:       target datalayout = "{{.*}}-S64"
; CHECK-LABEL: name: stack_slot
; CHECK:       stackSize: 48
; CHECK:       maxAlignment: 8
; CHECK-NOT:   AND64
; CHECK:       $rsp = frame-setup SUB64ri32 $rsp, 40
; CHECK-NOT:   MOVAPSmr
; CHECK:       MOVUPSmr $rbp, 1, $noreg, -16, $noreg
; CHECK-SAME:  align 8
; CHECK:       MOVUPSmr $rbp, 1, $noreg, -32, $noreg
; CHECK-SAME:  align 8
; CHECK:       CALL64pcrel32 @sink
entry:
  %slot = alloca [4 x ptr], align 8
  call void @llvm.memset.inline.p0.i64(
      ptr align 8 %slot, i8 0, i64 32, i1 false)
  %last = getelementptr ptr, ptr %slot, i64 3
  store ptr %value, ptr %last, align 8
  call goabiinternal void @sink(ptr %slot)
  ret void
}

declare void @llvm.memset.inline.p0.i64(ptr, i8, i64, i1 immarg)

attributes #0 = { "frame-pointer"="non-leaf" "go-async-unsafe"
                  "go-stack-growth-statepoint" }
