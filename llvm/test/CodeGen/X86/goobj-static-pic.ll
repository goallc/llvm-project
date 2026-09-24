; RUN: llc -mtriple=x86_64-unknown-linux-goobj -relocation-model=pic -filetype=obj %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s --check-prefixes=CHECK,X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -relocation-model=pic -filetype=obj %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s --check-prefixes=CHECK,ARM64
; RUN: opt -passes='default<O2>' -S %s | llc -mtriple=aarch64-unknown-linux-goobj -relocation-model=pic -filetype=obj -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s --check-prefixes=CHECK,ARM64
; RUN: opt -passes='default<O2>' -S %s | llc -mtriple=x86_64-unknown-linux-goobj -relocation-model=pic -filetype=obj -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s --check-prefixes=CHECK,X86

; An indexed Go STATIC definition can be shared by multiple plugins. Keep its
; Go object identity while using LLVM's normal preemptable-data GOT lowering.
@shared = global ptr null, align 8, !goobj.symbol.index !0
!0 = !{i32 0, i16 -1}
!goobj.dynlink = !{!1}
!1 = !{}

define goabiinternal ptr @load_shared() {
  %p = load ptr, ptr @shared, align 8
  ret ptr %p
}

; CHECK: symdef 0: shared abi=65535 type=9 size=8 align=8 flag=0 flag2=0
; R_GOTPCREL (amd64) and R_ARM64_GOTPCREL must both reference the STATIC definition.
; X86: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size=4 type=29 add=0 target=shared
; ARM64: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size=4 type=34 add=0 target=shared
