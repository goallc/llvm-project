; REQUIRES: aarch64-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -goobj-package-path=main -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s --check-prefix=OBJ

declare goabiinternal void @"runtime.GC"()

define goabiinternal i64 @add(i64 %a, i64 %b) #0 {
entry:
  %sum = add i64 %a, %b
  ret i64 %sum
}

define goabi0 i64 @stackadd(i64 %a, i64 %b) #0 {
entry:
  %sum = add i64 %a, %b
  ret i64 %sum
}

define goabiinternal void @calls() #0 {
entry:
  call goabiinternal void @"runtime.GC"()
  ret void
}

define goabiinternal i64 @local_calls(i64 %value) #0 {
entry:
  %slot = alloca i64, align 8
  store volatile i64 %value, ptr %slot, align 8
  call goabiinternal void @"runtime.GC"()
  %result = load volatile i64, ptr %slot, align 8
  ret i64 %result
}

define goabiinternal i64 @mediumframe(i64 %value) #0 {
entry:
  %buf = alloca [2048 x i8], align 16
  %slot = getelementptr inbounds [2048 x i8], ptr %buf, i64 0, i64 2047
  store volatile i8 1, ptr %slot, align 1
  ret i64 %value
}

define goabiinternal i64 @largeframe(i64 %value) #0 {
entry:
  %buf = alloca [8192 x i8], align 16
  %slot = getelementptr inbounds [8192 x i8], ptr %buf, i64 0, i64 8191
  store volatile i8 1, ptr %slot, align 1
  ret i64 %value
}

define goabiinternal i64 @largeclosure(i64 %value, ptr nest %ctxt) #0 {
entry:
  %buf = alloca [8192 x i8], align 16
  %slot = getelementptr inbounds [8192 x i8], ptr %buf, i64 0, i64 8191
  store volatile i8 1, ptr %slot, align 1
  %capture = load i64, ptr %ctxt, align 8
  %sum = add i64 %capture, %value
  ret i64 %sum
}

%aggregate = type { i64, i64, i64, i64, i64, i64, i64, i64 }

define goabiinternal %aggregate @aggregate_frame(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3,
    i64 %a4, i64 %a5, i64 %a6, i64 %a7) #0 {
entry:
  %slot = alloca %aggregate, align 16
  %v0 = insertvalue %aggregate poison, i64 %a0, 0
  %v1 = insertvalue %aggregate %v0, i64 %a1, 1
  %v2 = insertvalue %aggregate %v1, i64 %a2, 2
  %v3 = insertvalue %aggregate %v2, i64 %a3, 3
  %v4 = insertvalue %aggregate %v3, i64 %a4, 4
  %v5 = insertvalue %aggregate %v4, i64 %a5, 5
  %v6 = insertvalue %aggregate %v5, i64 %a6, 6
  %v7 = insertvalue %aggregate %v6, i64 %a7, 7
  store volatile %aggregate %v7, ptr %slot, align 16
  %result = load volatile %aggregate, ptr %slot, align 16
  ret %aggregate %result
}

; ASM-LABEL: stackadd:
; ASM: ldp x{{[0-9]+}}, x{{[0-9]+}}, [sp, #8]
; ASM: str x{{[0-9]+}}, [sp, #24]

; ASM-LABEL: calls:
; ASM: [[CALLS_CHECK:.LBB[0-9_]+]]:
; ASM: ldr x17, [x28, #16]
; ASM: cmp sp, x17
; ASM: b.hi [[CALLS_BODY:.LBB[0-9_]+]]
; ASM: mov x3, x30
; ASM: bl runtime.morestack_noctxt
; ASM-NEXT: b [[CALLS_CHECK]]
; ASM: [[CALLS_BODY]]:
; ASM: str x30, [sp, #-16]!
; ASM: stur x29, [sp, #-8]
; ASM: sub x29, sp, #8
; ASM: bl runtime.GC
; ASM: ldur x29, [sp, #-8]
; ASM-NEXT: ldr x30, [sp], #16

; ASM-LABEL: local_calls:
; ASM: str x30, [sp, #-16]!
; ASM: str x0, [sp, #24]
; ASM: bl runtime.GC
; ASM: ldr x0, [sp, #24]
; ASM: ldr x30, [sp], #16

; ASM-LABEL: mediumframe:
; The StackSmall < frame <= StackBig path needs no explicit underflow branch.
; ASM: ldr x17, [x28, #16]
; ASM-NEXT: sub x16, sp, #{{[0-9]+}}
; ASM-NEXT: cmp x16, x17
; ASM-NEXT: b.hi

; ASM-LABEL: largeframe:
; Match Go's single stack-check loop: the hot entry executes the check
; directly, and morestack branches back to that same check.
; ASM-NOT: b .LBB
; ASM: [[LARGE_CHECK:.LBB[0-9_]+]]:
; ASM: mov x17, #{{[0-9]+}}
; ASM-NEXT: subs x16, sp, x17
; ASM-NEXT: b.lo [[LARGE_MORESTACK:.LBB[0-9_]+]]
; ASM: ldr x17, [x28, #16]
; ASM: cmp x16, x17
; ASM: b.hi [[LARGE_BODY:.LBB[0-9_]+]]
; ASM: [[LARGE_MORESTACK]]:
; ASM: mov x3, x30
; ASM: str x0, [sp, #8]
; ASM: bl runtime.morestack_noctxt
; ASM: ldr x0, [sp, #8]
; ASM-NEXT: b [[LARGE_CHECK]]
; ASM: [[LARGE_BODY]]:
; ASM: stp x29, x30, [x16, #-8]
; ASM-NEXT: mov sp, x16
; ASM: sub x29, sp, #8
; ASM: ldp x29, x30, [sp, #-8]
; ASM: mov sp, x16

; ASM-LABEL: largeclosure:
; ASM: [[CLOSURE_CHECK:.LBB[0-9_]+]]:
; ASM: mov x17, #{{[0-9]+}}
; ASM-NEXT: subs x16, sp, x17
; ASM-NEXT: b.lo [[CLOSURE_MORESTACK:.LBB[0-9_]+]]
; ASM: ldr x17, [x28, #16]
; ASM: b.hi [[CLOSURE_BODY:.LBB[0-9_]+]]
; ASM: [[CLOSURE_MORESTACK]]:
; ASM: mov x3, x30
; ASM: bl runtime.morestack
; ASM: b [[CLOSURE_CHECK]]
; ASM: [[CLOSURE_BODY]]:

; ASM-LABEL: aggregate_frame:
; ASM: str x30, [sp, #-96]!
; ASM: str x0, [sp, #16]
; ASM-NOT: str x0, [sp]
; ASM: ldr x30, [sp], #96

; OBJ: header: go object darwin arm64
; OBJ: symdef {{[0-9]+}}: add abi=1 type=1
; OBJ: symdef {{[0-9]+}}: stackadd abi=0 type=1
; OBJ: symdef {{[0-9]+}}: calls abi=1 type=1
; OBJ: symdef {{[0-9]+}}: local_calls abi=1 type=1
; OBJ: symdef {{[0-9]+}}: mediumframe abi=1 type=1
; OBJ: symdef {{[0-9]+}}: largeframe abi=1 type=1
; OBJ: symdef {{[0-9]+}}: largeclosure abi=1 type=1
; OBJ: symdef {{[0-9]+}}: aggregate_frame abi=1 type=1
; OBJ-DAG: nonpkgref {{[0-9]+}}: runtime.GC abi=1 type=0 size=0
; OBJ-DAG: nonpkgref {{[0-9]+}}: runtime.morestack_noctxt abi=0 type=0 size=0
; OBJ-DAG: nonpkgref {{[0-9]+}}: runtime.morestack abi=0 type=0 size=0
; OBJ: aux {{[0-9]+}}.{{[0-9]+}}: type=funcinfo target= args=0 locals=8
; OBJ-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size=4 type=9 add=0 target=runtime.GC
; OBJ-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size=4 type=9 add=0 target=runtime.morestack_noctxt
; OBJ-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size=4 type=9 add=0 target=runtime.morestack

attributes #0 = { "frame-pointer"="non-leaf" }
