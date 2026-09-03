; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

@trace.arg.arginfo = weak constant [3 x i8] c"\00\08\ff", section ".rodata", align 1
@llvm.compiler.used = appending global [1 x ptr] [ptr @trace.arg.arginfo], section "llvm.metadata"

define goabiinternal void @trace.arg(ptr %p) !goobj.func.arginfo !0 {
  ret void
}

!0 = !{ptr @trace.arg.arginfo}

; CHECK: symdef 0: trace.arg
; CHECK: aux 0.0: type=funcinfo
; CHECK-COUNT-5: type=funcdata
; CHECK: type=funcdata target=trace.arg.arginfo data=0008ff
