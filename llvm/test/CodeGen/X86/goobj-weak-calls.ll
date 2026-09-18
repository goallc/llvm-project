; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s --check-prefix=X86
; RUN: opt -passes='default<O2>' -S %s -o %t.opt.ll
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.opt.ll -o %t.x86.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.opt.o | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %s -o %t.arm.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm.o | FileCheck %s --check-prefix=ARM
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.opt.ll -o %t.arm.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm.opt.o | FileCheck %s --check-prefix=ARM
; REQUIRES: x86-registered-target, aarch64-registered-target

; Weakness applies only to the annotated direct call edge. Taking the same
; callee's address and calling it from another function remain strong. Metadata
; alone must not synthesize a relocation or an undefined reference.
@address = global ptr @callee, section ".data", align 8
@llvm.compiler.used = appending global [5 x ptr] [ptr @weak_caller, ptr @strong_caller, ptr @callee, ptr @uncalled, ptr @address], section "llvm.metadata"

declare goabiinternal void @callee()
declare goabiinternal void @other()
declare goabiinternal void @uncalled()

define goabiinternal ptr @weak_caller() "frame-pointer"="all" {
  call goabiinternal void @callee()
  call goabiinternal void @other()
  ret ptr @callee
}

define goabiinternal void @strong_caller() "frame-pointer"="all" {
  call goabiinternal void @callee()
  call goabiinternal void @other()
  ret void
}

!goobj.weak_calls = !{!0, !1}
!0 = !{ptr @weak_caller, ptr @callee}
!1 = !{ptr @weak_caller, ptr @uncalled}

; X86-NOT: target=uncalled
; X86: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}type=32775 add=0 target=callee
; X86: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}type=7 add=0 target=other
; X86: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}type={{1|14}} add=0 target=callee
; X86: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}type=7 add=0 target=callee
; X86: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}type=7 add=0 target=other
; X86: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}type=1 add=0 target=callee
; X86-NOT: target=uncalled
; ARM-NOT: target=uncalled
; ARM: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}type=32777 add=0 target=callee
; ARM: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}type=9 add=0 target=other
; ARM-COUNT-2: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}type=36 add=0 target=callee
; ARM: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}type=9 add=0 target=callee
; ARM: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}type=9 add=0 target=other
; ARM: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}type=1 add=0 target=callee
; ARM-NOT: target=uncalled
