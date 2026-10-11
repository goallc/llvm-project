; REQUIRES: aarch64-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -filetype=obj %s -o %t
; RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s

; The structured module marker selects Go assembly composite relocations.
!goobj.assembly = !{!0}
!0 = !{i32 1}

module asm ".text"
module asm ".globl caller"
module asm "caller:"
module asm "  bl callee"
module asm "  bl external.func"
module asm "  adrp x0, data"
module asm "  add x0, x0, :lo12:data"
module asm "  adrp x1, data"
module asm "  ldrb w1, [x1, :lo12:data]"
module asm "  adrp x1, data"
module asm "  ldrh w1, [x1, :lo12:data]"
module asm "  adrp x1, data"
module asm "  ldr w1, [x1, :lo12:data]"
module asm "  adrp x1, data"
module asm "  ldr x1, [x1, :lo12:data]"
module asm "  adrp x2, data"
module asm "  add x2, x2, :lo12:external.data"
module asm "  adrp x3, data"
module asm "  nop"
module asm "  add x3, x3, :lo12:data"
module asm "  adrp x4, data"
module asm "  adr x4, data"
module asm "  ret"
module asm ".globl callee"
module asm "callee:"
module asm "  ret"
module asm ".globl split_adrp"
module asm "split_adrp:"
module asm "  adrp x5, data"
module asm ".globl split_add"
module asm "split_add:"
module asm "  add x5, x5, :lo12:data"
module asm "  ret"
module asm ".data"
module asm ".globl ptr"
module asm "ptr:"
module asm "  .xword callee"
module asm "  .xword external.data+8"
module asm ".globl data"
module asm "data:"
module asm "  .xword 0"

; CHECK: reloc {{[0-9]+}}.2: off=8 size=8 type=3 add=0 target=data
; CHECK-NEXT: reloc {{[0-9]+}}.3: off=16 size=8 type=37 add=0 target=data
; CHECK-NEXT: reloc {{[0-9]+}}.4: off=24 size=8 type=38 add=0 target=data
; CHECK-NEXT: reloc {{[0-9]+}}.5: off=32 size=8 type=39 add=0 target=data
; CHECK-NEXT: reloc {{[0-9]+}}.6: off=40 size=8 type=40 add=0 target=data

