; RUN: llc -mtriple=aarch64-unknown-linux-goobj -goobj-package-path=main -O2 < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -goobj-package-path=main -O2 -mcpu=cortex-a53 < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -goobj-package-path=main -O2 -misched-fusion=false < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -goobj-package-path=main -O2 -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s --check-prefix=OBJ

@first = global i64 0, align 8
@second = global i64 0, align 8

define goabiinternal void @store_globals(i64 %x, i64 %y) {
entry:
  store i64 %x, ptr @first, align 8
  store i64 %y, ptr @second, align 8
  ret void
}

define goabiinternal void @store_addresses(ptr %dst) {
entry:
  store ptr @first, ptr %dst, align 8
  %next = getelementptr ptr, ptr %dst, i64 1
  store ptr @second, ptr %next, align 8
  ret void
}

; ASM-LABEL: store_globals:
; ASM:      adrp [[FIRST:x[0-9]+]], first
; ASM-NEXT: str x0, {{\[}}[[FIRST]], :lo12:first{{\]}}
; ASM-NEXT: adrp [[SECOND:x[0-9]+]], second
; ASM-NEXT: str x1, {{\[}}[[SECOND]], :lo12:second{{\]}}

; ASM-LABEL: store_addresses:
; ASM:      adrp [[FIRST:x[0-9]+]], first
; ASM-NEXT: add [[FIRST]], [[FIRST]], :lo12:first
; ASM-NEXT: adrp [[SECOND:x[0-9]+]], second
; ASM-NEXT: add [[SECOND]], [[SECOND]], :lo12:second

; OBJ: reloc 0.0: off=0 size=8 type=40 add=0 target=first
; OBJ: reloc 0.1: off=8 size=8 type=40 add=0 target=second
; OBJ: reloc 1.2: off=0 size=8 type=3 add=0 target=first
; OBJ: reloc 1.3: off=8 size=8 type=3 add=0 target=second
