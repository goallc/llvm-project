; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=x86_64-unknown-linux-goobj < %s | FileCheck %s --check-prefix=X86-ASM
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s --check-prefix=ARM64
; RUN: llc -mtriple=aarch64-unknown-linux-goobj < %s | FileCheck %s --check-prefix=ARM64-ASM

@trace.live.arginfo = weak constant [3 x i8] c"\00\08\ff", section ".rodata", align 1
@trace.live.vector.arginfo = weak constant [5 x i8] c"\00\10\10\10\ff", section ".rodata", align 1
@llvm.compiler.used = appending global [2 x ptr] [ptr @trace.live.arginfo, ptr @trace.live.vector.arginfo], section "llvm.metadata"

declare goabiinternal void @trace.sink(ptr)

; SelectionDAG maps this address-observable entry store to the incoming
; argument's canonical ABI home. ArgLive must switch to the live map at that
; existing store's final PC without inserting another store.
define goabiinternal ptr @trace.live(ptr %p) !goobj.func.arginfo !0 {
entry:
  %slot = alloca ptr, align 8
  store ptr %p, ptr %slot, align 8
  call goabiinternal void @trace.sink(ptr %slot)
  %value = load ptr, ptr %slot, align 8
  ret ptr %value
}

!0 = !{ptr @trace.live.arginfo, i64 8, i64 0, i64 0, i64 8}

; Register preservation for morestack and ordinary local spills do not prove
; that the canonical vector homes are valid. Keep the zero map throughout.
define goabiinternal <4 x float> @trace.live.vector(<4 x float> %x, <4 x float> %y) !goobj.func.arginfo !1 {
entry:
  %frame = alloca [32768 x i8], align 1
  call goabiinternal void @trace.sink(ptr %frame)
  %sum = fadd <4 x float> %x, %y
  ret <4 x float> %sum
}

!1 = !{ptr @trace.live.vector.arginfo, i64 32, i64 0, i64 0, i64 16, i64 16, i64 16}

; X86: symdef 0: trace.live
; X86: symdef 1: trace.live.vector
; X86: aux 0.9: type=pcdata {{.*}}pc=[0-{{[0-9]+}}:1,{{[0-9]+}}-{{[0-9]+}}:2,{{[0-9]+}}-{{[0-9]+}}:1]
; X86: type=funcdata target=trace.live.arginfo data=0008ff
; X86: type=funcdata {{.*}}data=000001
; X86: aux 1.{{[0-9]+}}: type=pcdata {{.*}}pc=[0-{{[0-9]+}}:1]
; X86: type=funcdata target=trace.live.vector.arginfo data=00101010ff
; X86: type=funcdata {{.*}}data=0000

; ARM64: symdef 0: trace.live
; ARM64: symdef 1: trace.live.vector
; ARM64: aux 0.9: type=pcdata {{.*}}pc=[0-{{[0-9]+}}:1,{{[0-9]+}}-{{[0-9]+}}:2]
; ARM64: type=funcdata target=trace.live.arginfo data=0008ff
; ARM64: type=funcdata {{.*}}data=000001
; ARM64: aux 1.{{[0-9]+}}: type=pcdata {{.*}}pc=[0-{{[0-9]+}}:1]
; ARM64: type=funcdata target=trace.live.vector.arginfo data=00101010ff
; ARM64: type=funcdata {{.*}}data=0000

; X86-ASM-LABEL: trace.live:
; X86-ASM: movq %rax, 16(%rsp){{.*}}8-byte Spill
; X86-ASM-NEXT: .Lgoobj_arglive{{[0-9]+}}:
; X86-ASM-LABEL: trace.live.vector:
; X86-ASM-NOT: .Lgoobj_arglive
; X86-ASM: .Lfunc_end1:

; ARM64-ASM-LABEL: trace.live:
; ARM64-ASM: str x0, [sp, #40]{{.*}}8-byte Spill
; ARM64-ASM-NEXT: .Lgoobj_arglive{{[0-9]+}}:
; ARM64-ASM-LABEL: trace.live.vector:
; ARM64-ASM-NOT: .Lgoobj_arglive
; ARM64-ASM: .Lfunc_end1:
