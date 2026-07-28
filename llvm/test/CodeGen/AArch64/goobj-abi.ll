; REQUIRES: aarch64-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -goobj-package-path=main -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s --check-prefix=OBJ

declare goabiinternal void @"runtime.GC"()

define goabiinternal i64 @add(i64 %a, i64 %b) {
entry:
  %sum = add i64 %a, %b
  ret i64 %sum
}

define goabi0 i64 @stackadd(i64 %a, i64 %b) {
entry:
  %sum = add i64 %a, %b
  ret i64 %sum
}

define goabiinternal void @calls() {
entry:
  call goabiinternal void @"runtime.GC"()
  ret void
}

define goabiinternal i64 @largeframe(i64 %value) {
entry:
  %buf = alloca [8192 x i8], align 16
  %slot = getelementptr inbounds [8192 x i8], ptr %buf, i64 0, i64 8191
  store volatile i8 1, ptr %slot, align 1
  ret i64 %value
}

define goabiinternal i64 @largeclosure(i64 %value, ptr nest %ctxt) {
entry:
  %buf = alloca [8192 x i8], align 16
  %slot = getelementptr inbounds [8192 x i8], ptr %buf, i64 0, i64 8191
  store volatile i8 1, ptr %slot, align 1
  %capture = load i64, ptr %ctxt, align 8
  %sum = add i64 %capture, %value
  ret i64 %sum
}

; ASM-LABEL: stackadd:
; ASM: ldp x{{[0-9]+}}, x{{[0-9]+}}, [sp, #8]
; ASM: str x{{[0-9]+}}, [sp, #24]

; ASM-LABEL: calls:
; ASM: ldr x17, [x28, #16]
; ASM: cmp sp, x17
; ASM: b.ls [[CALLS_MORESTACK:.LBB[0-9_]+]]
; ASM: str x30, [sp]
; ASM: bl runtime.GC
; ASM: [[CALLS_MORESTACK]]:
; ASM: mov x3, x30
; ASM: bl runtime.morestack_noctxt

; ASM-LABEL: largeframe:
; ASM: sub x16, sp, #{{[0-9]+}}
; ASM: cmp x16, x17
; ASM: b.ls [[LARGE_MORESTACK:.LBB[0-9_]+]]
; ASM: [[LARGE_MORESTACK]]:
; ASM: mov x3, x30
; ASM: str x0, [sp, #8]
; ASM: bl runtime.morestack_noctxt
; ASM: ldr x0, [sp, #8]

; ASM-LABEL: largeclosure:
; ASM: sub x16, sp, #{{[0-9]+}}
; ASM: b.ls [[CLOSURE_MORESTACK:.LBB[0-9_]+]]
; ASM: [[CLOSURE_MORESTACK]]:
; ASM: mov x3, x30
; ASM: bl runtime.morestack

; OBJ: header: go object darwin arm64
; OBJ: symdef {{[0-9]+}}: add abi=1 type=1
; OBJ: symdef {{[0-9]+}}: stackadd abi=0 type=1
; OBJ: symdef {{[0-9]+}}: calls abi=1 type=1
; OBJ: symdef {{[0-9]+}}: largeframe abi=1 type=1
; OBJ: symdef {{[0-9]+}}: largeclosure abi=1 type=1
; OBJ: nonpkgref {{[0-9]+}}: runtime.GC abi=1 type=0 size=0
; OBJ: nonpkgref {{[0-9]+}}: runtime.morestack_noctxt abi=0 type=0 size=0
; OBJ: nonpkgref {{[0-9]+}}: runtime.morestack abi=0 type=0 size=0
; OBJ: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size=4 type=9 add=0 target=runtime.GC
; OBJ: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size=4 type=9 add=0 target=runtime.morestack_noctxt
; OBJ: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size=4 type=9 add=0 target=runtime.morestack
