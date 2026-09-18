; RUN: llc -mtriple=x86_64-linux-goobj -O0 -verify-machineinstrs -stop-after=prolog-epilog %s -o - | FileCheck %s --check-prefixes=CHECK,STATIC
; RUN: llc -mtriple=x86_64-linux-goobj -O2 -verify-machineinstrs -stop-after=prolog-epilog %s -o - | FileCheck %s --check-prefixes=CHECK,STATIC
; RUN: llc -mtriple=x86_64-linux-goobj -O2 -relocation-model=pic -verify-machineinstrs -stop-after=prolog-epilog %s -o - | FileCheck %s --check-prefixes=CHECK,PIC

; An ABI0 entry (or its ABI0 maymorestack hook) can leave R14 unset.
; Reload g in the check block, which is also the morestack retry target.
; CHECK-LABEL: name: 'abi0_stack_check<ABI0>'
; CHECK: CALL64pcrel32 &"hook<ABI0>"
; CHECK: bb.[[CHECKBB:[0-9]+]]:
; STATIC: $r14 = MOV64rm $noreg, 1, $noreg, target-flags(x86-tpoff) &runtime.tlsg, $fs
; PIC: $r14 = MOV64rm $rip, 1, $noreg, target-flags(x86-gottpoff) &runtime.tlsg, $noreg
; PIC-NEXT: $r14 = MOV64rm killed $r14, 1, $noreg, 0, $fs
; CHECK: CMP64rm $r12, $r14, 1, $noreg, 16, $noreg
; CHECK: CALL64pcrel32 &"runtime.morestack_noctxt<ABI0>"
; CHECK: JMP_1 %bb.[[CHECKBB]]
define goabi0 void @"abi0_stack_check<ABI0>"()
    "go-maymorestack"="hook<ABI0>" {
  %buf = alloca [4096 x i8], align 8
  %last = getelementptr [4096 x i8], ptr %buf, i64 0, i64 4095
  store volatile i8 1, ptr %last
  ret void
}

; NOSPLIT entries must not acquire a stack check or a TLS load.
; CHECK-LABEL: name: 'abi0_nosplit<ABI0>'
; CHECK-NOT: &runtime.tlsg
; CHECK-NOT: CMP64rm
; CHECK: RET
define goabi0 void @"abi0_nosplit<ABI0>"() "go-nosplit" {
  ret void
}
