; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -verify-machineinstrs %s -o - | FileCheck %s --check-prefix=ARM
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s --check-prefixes=OBJ,X86-OBJ
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm.o | FileCheck %s --check-prefixes=OBJ,ARM-OBJ
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -O0 -verify-machineinstrs -filetype=obj %s -o /dev/null
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -O0 -verify-machineinstrs -filetype=obj %s -o /dev/null
; REQUIRES: x86-registered-target, aarch64-registered-target

declare goabiinternal void @use(i64, double, ptr)
declare goabi0 void @"use0<ABI0>"()

; Save live integer/FP arguments and the closure context before the hook.
; The normal stack check follows it, and morestack retries that check only.
define goabiinternal void @with_args(i64 %n, double %f, ptr nest %ctxt) #0 {
  call goabiinternal void @use(i64 %n, double %f, ptr %ctxt)
  ret void
}

; X86-LABEL: with_args:
; X86: movq %rax, 8(%rsp)
; X86: movsd %xmm0, 16(%rsp)
; X86: pushq %rdx
; X86: callq hook
; X86: popq %rdx
; X86: [[XCHECK:\.LBB[0-9_]+]]:
; X86: movq 8(%rsp), %rax
; X86: movsd 16(%rsp), %xmm0
; X86: cmpq
; X86: callq "runtime.morestack<ABI0>"
; X86: jmp [[XCHECK]]

; ARM-LABEL: with_args:
; ARM: str x0, [sp, #8]
; ARM: str d0, [sp, #16]
; ARM: str x30, [sp, #-32]!
; ARM: stur x29, [sp, #-8]
; ARM: sub x29, sp, #8
; ARM: str x26, [sp, #8]
; ARM: bl hook
; ARM: ldr x26, [sp, #8]
; ARM: ldur x29, [sp, #-8]
; ARM: ldr x30, [sp], #32
; ARM: [[ACHECK:\.LBB[0-9_]+]]:
; ARM: ldr x0, [sp, #8]
; ARM: ldr d0, [sp, #16]
; ARM: ldr x17, [x28, #16]
; ARM: bl "runtime.morestack<ABI0>"
; ARM: b [[ACHECK]]

define goabi0 void @"abi0<ABI0>"() #1 {
  call goabi0 void @"use0<ABI0>"()
  ret void
}
; X86-LABEL: "abi0<ABI0>":
; X86: callq "hook<ABI0>"
; ARM-LABEL: "abi0<ABI0>":
; ARM: bl "hook<ABI0>"

define goabiinternal void @explicit_nosplit(i64 %n, double %f, ptr %p) #2 {
  call goabiinternal void @use(i64 %n, double %f, ptr %p)
  ret void
}
; X86-LABEL: explicit_nosplit:
; X86-NOT: hook
; X86: retq
; ARM-LABEL: explicit_nosplit:
; ARM-NOT: hook
; ARM: ret

define goabiinternal i64 @small_leaf(i64 %n) #0 {
  ret i64 %n
}
; X86-LABEL: small_leaf:
; X86-NOT: hook
; X86: retq
; ARM-LABEL: small_leaf:
; ARM-NOT: hook
; ARM: ret

attributes #0 = { "frame-pointer"="all" "go-maymorestack"="hook" }
attributes #1 = { "frame-pointer"="all" "go-maymorestack"="hook<ABI0>" }
attributes #2 = { "frame-pointer"="all" "go-maymorestack"="hook" "go-nosplit" }

; The hook's ABI and temporary stack depth are part of the emitted contract,
; even though the ordinary function frame has not been allocated yet.
; OBJ-DAG: nonpkgref [[INTERNAL:[0-9]+]]: hook abi=1
; OBJ-DAG: nonpkgref [[ABI0:[0-9]+]]: hook abi=0
; X86-OBJ: aux 0.{{[0-9]+}}: type=pcsp target= pc=[0-{{[0-9]+}}:0,{{[0-9]+}}-{{[0-9]+}}:8,{{[0-9]+}}-{{[0-9]+}}:0,
; ARM-OBJ: aux 0.{{[0-9]+}}: type=pcsp target= pc=[0-{{[0-9]+}}:0,{{[0-9]+}}-{{[0-9]+}}:32,{{[0-9]+}}-{{[0-9]+}}:0,
; OBJ: reloc 0.{{[0-9]+}}: {{.*}}target=hook {{.*}}pkg=none sym=[[INTERNAL]]
; OBJ: reloc 1.{{[0-9]+}}: {{.*}}target=hook {{.*}}pkg=none sym=[[ABI0]]
