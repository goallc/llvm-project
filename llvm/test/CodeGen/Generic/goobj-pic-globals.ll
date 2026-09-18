; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: llc -verify-machineinstrs -mtriple=x86_64-unknown-linux-goobj -relocation-model=pic < %s | FileCheck %s --check-prefix=X86
; RUN: llc -verify-machineinstrs -mtriple=aarch64-unknown-linux-goobj -relocation-model=pic < %s | FileCheck %s --check-prefix=ARM64
; RUN: llc -verify-machineinstrs -O0 -mtriple=x86_64-unknown-linux-goobj -relocation-model=pic < %s | FileCheck %s --check-prefix=X86
; RUN: llc -verify-machineinstrs -O0 -mtriple=aarch64-unknown-linux-goobj -relocation-model=pic < %s | FileCheck %s --check-prefix=ARM64
; RUN: llc -verify-machineinstrs -mtriple=x86_64-unknown-linux-goobj -relocation-model=static < %s | FileCheck %s --check-prefix=X86-STATIC
; RUN: llc -verify-machineinstrs -mtriple=x86_64-unknown-linux-goobj -relocation-model=pic -filetype=obj < %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s --check-prefix=X86-OBJ
; RUN: llc -verify-machineinstrs -mtriple=aarch64-unknown-linux-goobj -relocation-model=pic -aarch64-goobj-composite-relocations -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s --check-prefix=ARM64-OBJ
; RUN: sed '/^!goobj.dynlink =/d' %s | llc -verify-machineinstrs -mtriple=x86_64-unknown-linux-goobj -relocation-model=pic | FileCheck %s --check-prefix=X86-LOCAL
; RUN: sed '/^!goobj.dynlink =/d' %s | llc -verify-machineinstrs -mtriple=aarch64-apple-darwin-goobj -relocation-model=pic | FileCheck %s --check-prefix=ARM64-LOCAL

; PIC references to preemptible declarations and definitions must use the GOT.
; Explicit dso_local and static code retain direct accesses.
; Without dynamic Go linking, PIC code also retains direct accesses.
; X86-OBJ: reloc 0.0: off=3 size=4 type=29 add=0 target=external
; X86-OBJ: reloc 1.1: off=3 size=4 type=29 add=0 target=defined
; X86-OBJ: reloc 2.2: off=3 size=4 type=14 add=0 target=local
; ARM64-OBJ: reloc 0.0: off=0 size=8 type=34 add=0 target=external
; ARM64-OBJ: reloc 1.1: off=0 size=8 type=34 add=0 target=defined
; ARM64-OBJ: reloc 2.2: off=0 size=8 type=3 add=0 target=local

@external = external global i64
@defined = global i64 42
@local = dso_local global i64 42

define goabiinternal ptr @external_address() {
; X86-LABEL: external_address:
; X86: movq external@GOTPCREL(%rip), %rax
; ARM64-LABEL: external_address:
; ARM64: adrp x0, :got:external
; ARM64-NEXT: ldr x0, [x0, :got_lo12:external]
; X86-LOCAL-LABEL: external_address:
; X86-LOCAL: leaq external(%rip), %rax
; ARM64-LOCAL-LABEL: external_address:
; ARM64-LOCAL: adrp x0, external
; ARM64-LOCAL-NEXT: add x0, x0, :lo12:external
; X86-STATIC-LABEL: external_address:
; X86-STATIC-NOT: GOTPCREL
; X86-STATIC: retq
  ret ptr @external
}

define goabiinternal ptr @defined_address() {
; X86-LABEL: defined_address:
; X86: movq defined@GOTPCREL(%rip), %rax
; ARM64-LABEL: defined_address:
; ARM64: adrp x0, :got:defined
; ARM64-NEXT: ldr x0, [x0, :got_lo12:defined]
  ret ptr @defined
}

define goabiinternal ptr @local_address() {
; X86-LABEL: local_address:
; X86: leaq local(%rip), %rax
; ARM64-LABEL: local_address:
; ARM64: adrp x0, local
; ARM64-NEXT: add x0, x0, :lo12:local
  ret ptr @local
}

!goobj.dynlink = !{!0}
!0 = !{}
