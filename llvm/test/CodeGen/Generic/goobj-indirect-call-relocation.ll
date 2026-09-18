; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main \
; RUN:   -O2 < %s | FileCheck %s --check-prefix=X86-ASM
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main \
; RUN:   -O2 -filetype=obj < %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | \
; RUN:   FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -goobj-package-path=main \
; RUN:   -O2 < %s | FileCheck %s --check-prefix=A64-ASM
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -goobj-package-path=main \
; RUN:   -O2 -filetype=obj < %s -o %t.a64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.a64.o | \
; RUN:   FileCheck %s --check-prefix=A64

declare goabiinternal void @direct()

define goabiinternal void @ordinary_indirect(ptr %callee, ptr %slot)
    "frame-pointer"="non-leaf" "go-nosplit" {
entry:
  call goabiinternal void %callee()
  %loaded = load ptr, ptr %slot, align 8
  call goabiinternal void %loaded()
  call goabiinternal void @direct()
  ret void
}

define void @tail_indirect(ptr %callee) "frame-pointer"="non-leaf"
    "go-nosplit" {
entry:
  musttail call void %callee(ptr %callee)
  ret void
}

define void @patchpoint_indirect() "frame-pointer"="non-leaf" "go-nosplit" {
entry:
  tail call void (i64, i32, ptr, i32, ...)
      @llvm.experimental.patchpoint.void(
          i64 7, i32 16, ptr inttoptr (i64 305419896 to ptr), i32 0)
  ret void
}

define goabiinternal void @fips_indirect(ptr %callee)
    "frame-pointer"="non-leaf" "go-nosplit" section ".text.fips" {
entry:
  call goabiinternal void %callee()
  ret void
}

declare void @llvm.experimental.patchpoint.void(i64, i32, ptr, i32, ...)

; Both ordinary indirect calls have zero-width, targetless R_CALLIND markers.
; The direct call retains only its ordinary architecture-specific relocation,
; and the indirect tail call has no R_CALLIND marker.
;
; X86-ASM-LABEL: ordinary_indirect:
; X86-ASM: .Lgoobj_callind0:
; X86-ASM-NEXT: callq *%rax
; X86-ASM: .Lgoobj_callind1:
; X86-ASM-NEXT: callq *(%rax)
; X86-ASM-NOT: .Lgoobj_callind
; X86-ASM: callq direct
; X86-ASM-LABEL: tail_indirect:
; X86-ASM-NOT: .Lgoobj_callind
; X86-ASM: jmpq *%rdi
; X86-ASM-LABEL: patchpoint_indirect:
; X86-ASM: movabsq $305419896,
; X86-ASM: .Lgoobj_callind2:
; X86-ASM-NEXT: callq *%
; X86-ASM-LABEL: fips_indirect:
; X86-ASM: .Lgoobj_callind3:
; X86-ASM-NEXT: callq *%rax
;
; X86: symdef 0: ordinary_indirect abi=1 type=1 size={{[0-9]+}}
; X86: symdef 1: tail_indirect abi=0 type=1 size={{[0-9]+}}
; X86: symdef 2: patchpoint_indirect abi=0 type=1 size={{[0-9]+}}
; X86: symdef 3: fips_indirect abi=1 type=2 size={{[0-9]+}}
; X86: reloc 0.{{[0-9]+}}: off=9 size=0 type=10 add=0 target=:0 kind=R_CALLIND pkg=0 sym=0
; X86: reloc 0.{{[0-9]+}}: off=15 size=0 type=10 add=0 target=:0 kind=R_CALLIND pkg=0 sym=0
; X86: reloc 0.{{[0-9]+}}: off=18 size=4 type=7 add=0 target=direct kind=R_CALL
; X86-NOT: reloc 0.{{[0-9]+}}: {{.*}}kind=R_CALLIND
; X86-NOT: reloc 1.{{[0-9]+}}: {{.*}}kind=R_CALLIND
; X86: reloc 2.{{[0-9]+}}: off={{[0-9]+}} size=0 type=10 add=0 target=:0 kind=R_CALLIND pkg=0 sym=0
; X86: reloc 3.{{[0-9]+}}: off={{[0-9]+}} size=0 type=10 add=0 target=:0 kind=R_CALLIND pkg=0 sym=0
;
; A64-ASM-LABEL: ordinary_indirect:
; A64-ASM: .Lgoobj_callind0:
; A64-ASM-NEXT: blr x0
; A64-ASM: .Lgoobj_callind1:
; A64-ASM-NEXT: blr x8
; A64-ASM-NOT: .Lgoobj_callind
; A64-ASM: bl direct
; A64-ASM-LABEL: tail_indirect:
; A64-ASM-NOT: .Lgoobj_callind
; A64-ASM: br x0
; A64-ASM-LABEL: patchpoint_indirect:
; A64-ASM: .Lgoobj_callind2:
; A64-ASM-NEXT: blr x{{[0-9]+}}
; A64-ASM-LABEL: fips_indirect:
; A64-ASM: .Lgoobj_callind3:
; A64-ASM-NEXT: blr x0
;
; A64: symdef 0: ordinary_indirect abi=1 type=1 size={{[0-9]+}}
; A64: symdef 1: tail_indirect abi=0 type=1 size={{[0-9]+}}
; A64: symdef 2: patchpoint_indirect abi=0 type=1 size={{[0-9]+}}
; A64: symdef 3: fips_indirect abi=1 type=2 size={{[0-9]+}}
; A64: reloc 0.{{[0-9]+}}: off=16 size=0 type=10 add=0 target=:0 kind=R_CALLIND pkg=0 sym=0
; A64: reloc 0.{{[0-9]+}}: off=28 size=0 type=10 add=0 target=:0 kind=R_CALLIND pkg=0 sym=0
; A64: reloc 0.{{[0-9]+}}: off=32 size=4 type=9 add=0 target=direct kind=R_CALLARM64
; A64-NOT: reloc 0.{{[0-9]+}}: {{.*}}kind=R_CALLIND
; A64-NOT: reloc 1.{{[0-9]+}}: {{.*}}kind=R_CALLIND
; A64: reloc 2.{{[0-9]+}}: off={{[0-9]+}} size=0 type=10 add=0 target=:0 kind=R_CALLIND pkg=0 sym=0
; A64: reloc 3.{{[0-9]+}}: off={{[0-9]+}} size=0 type=10 add=0 target=:0 kind=R_CALLIND pkg=0 sym=0
