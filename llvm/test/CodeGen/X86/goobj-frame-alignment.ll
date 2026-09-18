; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s --check-prefix=OBJ
; RUN: llc -mtriple=x86_64-unknown-linux-goobj < %s | FileCheck %s --check-prefix=ASM

; A byte-aligned leaf object must not reduce the physical Go frame alignment.
; Go frames are pointer-aligned, and their complete contents stay above SP so
; an injected async-preemption frame cannot overwrite live local storage.
define goabiinternal i8 @byte_aligned_frame() {
entry:
  %buf = alloca [1100 x i8], align 1
  %first = getelementptr inbounds [1100 x i8], ptr %buf, i64 0, i64 0
  %last = getelementptr inbounds [1100 x i8], ptr %buf, i64 0, i64 1099
  store volatile i8 1, ptr %first, align 1
  store volatile i8 2, ptr %last, align 1
  %a = load volatile i8, ptr %first, align 1
  %b = load volatile i8, ptr %last, align 1
  %sum = add i8 %a, %b
  ret i8 %sum
}

; OBJ: symdef 0: byte_aligned_frame abi=1 type=1 size={{[0-9]+}}
; OBJ: aux 0.{{[0-9]+}}: type=funcinfo target= args=0 locals=1104
; OBJ: aux 0.{{[0-9]+}}: type=pcsp target= pc=[{{.*}}:1104,{{.*}}:0]

; ASM-LABEL: byte_aligned_frame:
; The stack check covers the aligned 1104-byte frame while using StackSmall's
; 128-byte guard slack. The prologue still reserves the complete frame.
; ASM: leaq -976(%rsp), %r12
; ASM: callq "runtime.morestack_noctxt<ABI0>"
; ASM: subq $1104, %rsp
; ASM-NOT: -{{[0-9]+}}(%rsp)
; ASM: addq $1104, %rsp
; ASM: retq

!goobj.config = !{!0}
!0 = !{!"goallc.goobj", !"linux", !"amd64", !"go1.27", !"", !"", !"", !"test/pkg", !"0", !"1", !"0", !1}
!1 = !{}
