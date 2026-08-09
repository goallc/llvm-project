; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-goobj < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -stop-after=finalize-isel < %s -o - | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -stop-after=prolog-epilog < %s -o - | FileCheck %s --check-prefix=PEI

; The fixed alloca forces a frame larger than Go StackBig, which requires the
; Go stack-growth slow path. The argument is register-passed, so the generated
; slow path must also preserve ABIInternal register arguments across morestack.

define goabiinternal i64 @big_frame(i64 %x) {
entry:
  %buf = alloca [5000 x i8], align 8
  %p0 = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 0
  %p1 = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 7, ptr %p0, align 8
  store volatile i8 11, ptr %p1, align 1
  %v0 = load volatile i8, ptr %p0, align 8
  %v1 = load volatile i8, ptr %p1, align 1
  %a = zext i8 %v0 to i64
  %b = zext i8 %v1 to i64
  %sum0 = add i64 %a, %b
  %sum1 = add i64 %sum0, %x
  ret i64 %sum1
}

define goabiinternal i64 @big_closure_frame(i64 %x, ptr nest %ctxt) {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  %capture = load i64, ptr %ctxt, align 8
  %sum = add i64 %capture, %x
  ret i64 %sum
}

declare goabiinternal void @many_stack_args(
    i64, i64, i64, i64, i64, i64, i64, i64,
    i64, i64, i64, i64, i64, i64, i64, i64,
    i64, i64, i64, i64, i64, i64, i64, i64,
    i64, i64, i64, i64, i64, i64, i64, i64)
@condition = external global i1

; X86 lowers the stack arguments below to push sequences instead of reserving
; their call frame in the prologue. The Go stack check must nevertheless cover
; the deepest outgoing SP, not just this function's small fixed frame.
define goabiinternal void @large_outgoing_frame() {
entry:
  %cond = load volatile i1, ptr @condition
  br i1 %cond, label %call, label %join

call:
  call goabiinternal void @many_stack_args(
      i64 0, i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7,
      i64 8, i64 9, i64 10, i64 11, i64 12, i64 13, i64 14, i64 15,
      i64 16, i64 17, i64 18, i64 19, i64 20, i64 21, i64 22, i64 23,
      i64 24, i64 25, i64 26, i64 27, i64 28, i64 29, i64 30, i64 31)
  br label %join

join:
  ret void
}

; CHECK: symdef {{[0-9]+}}: big_frame abi=1 type=1 size={{[0-9]+}}
; CHECK: symdef {{[0-9]+}}: big_closure_frame abi=1 type=1 size={{[0-9]+}}
; CHECK: nonpkgref {{[0-9]+}}: runtime.morestack_noctxt abi=0 type=0 size=0
; CHECK: nonpkgref {{[0-9]+}}: runtime.morestack abi=0 type=0 size=0
; CHECK: aux {{[0-9]+}}.{{[0-9]+}}: type=funcinfo target= args={{[1-9][0-9]*}} locals={{[1-9][0-9][0-9][0-9][0-9]*}}
; CHECK: aux {{[0-9]+}}.{{[0-9]+}}: type=funcdata target= data=0100000000000000
; CHECK: aux {{[0-9]+}}.{{[0-9]+}}: type=funcdata target= data=0100000000000000
; CHECK: aux 0.{{[0-9]+}}: type=pcdata target= pc=[0-{{[0-9]+}}:-1]
; CHECK-NEXT: aux 0.{{[0-9]+}}: type=pcdata target= pc=[0-{{[0-9]+}}:0]
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size=4 type=7 add=0 target=runtime.morestack_noctxt
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off={{[0-9]+}} size=4 type=7 add=0 target=runtime.morestack
; The outgoing frame is 72 bytes of alignment/register-argument space plus 23
; 8-byte PUSHes. PCSP must reach 256 bytes at the call, return to zero before
; the CFG join, and thereby let funcMaxSPDelta size a grown Go stack correctly.
; CHECK: aux 2.{{[0-9]+}}: type=pcsp target= pc=[{{.*}}:256,{{[0-9]+}}-{{[0-9]+}}:0]

; ASM-LABEL: big_frame:
; Match Go's single stack-check loop: the hot entry executes the check
; directly, and morestack jumps back to that same check.
; ASM-NOT: jmp
; ASM: [[BIG_CHECK:.LBB0_[0-9]+]]:
; ASM: movq %rsp, %r12
; ASM: subq $4872, %r12
; ASM: jb [[BIG_MORESTACK:.LBB0_[0-9]+]]
; ASM: cmpq 16(%r14), %r12
; ASM: ja [[BIG_BODY:.LBB0_[0-9]+]]
; ASM: [[BIG_MORESTACK]]:
; ASM: callq runtime.morestack_noctxt
; ASM-NEXT: movq 8(%rsp), %rax
; ASM-NEXT: jmp [[BIG_CHECK]]
; ASM: [[BIG_BODY]]:
; ASM: retq

; ASM-LABEL: big_closure_frame:
; ASM: [[CLOSURE_CHECK:.LBB1_[0-9]+]]:
; ASM: callq runtime.morestack
; ASM: jmp [[CLOSURE_CHECK]]
; ASM: retq

; ASM-LABEL: large_outgoing_frame:
; ASM: leaq -128(%rsp), %r12
; ASM: cmpq 16(%r14), %r12

; MIR-LABEL: name: big_frame
; MIR: fixedStack:
; MIR-NEXT: - { id: 0, type: spill-slot, offset: 0, size: 8

; PEI-LABEL: name: big_frame
; PEI: fixedStack:
; PEI-NEXT: - { id: 0, type: spill-slot, offset: 0, size: 8
; PEI: MOV64mr {{.*rsp}}, 1, {{.*noreg}}, 8, {{.*noreg}}, {{.*rax}}
; PEI: CALL64pcrel32 &runtime.morestack_noctxt
; PEI: {{.*rax}} = MOV64rm {{.*rsp}}, 1, {{.*noreg}}, 8, {{.*noreg}}

; PEI-LABEL: name: big_closure_frame
; PEI: CALL64pcrel32 &runtime.morestack, {{.*}}implicit $rdx

; PEI-LABEL: name: large_outgoing_frame
; PEI: stackSize: 0
; PEI: maxCallFrameSize: 256
; PEI: $r12 = LEA64r $rsp, 1, $noreg, -128, $noreg
; PEI: CMP64rm $r12, $r14, 1, $noreg, 16, $noreg
; PEI: CALL64pcrel32 @many_stack_args
