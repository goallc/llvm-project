; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s

@trace.stack.arginfo = weak constant [3 x i8] c"\00\08\ff", section ".rodata", align 1
@llvm.compiler.used = appending global [1 x ptr] [ptr @trace.stack.arginfo], section "llvm.metadata"

define goabi0 void @"trace.stack<ABI0>"(ptr byval(i64) align 8 %p) !goobj.func.arginfo !0 {
  ret void
}

!0 = !{ptr @trace.stack.arginfo, i64 8, i64 8, i64 0, i64 8}

; CHECK: symdef 0: trace.stack abi=0
; CHECK: aux 0.0: type=funcinfo {{.*}}args=8
; CHECK-COUNT-2: type=pcdata
; CHECK-NOT: type=pcdata
; CHECK-COUNT-3: type=funcdata
; CHECK: type=funcdata target=trace.stack.arginfo data=0008ff
; CHECK-NOT: data=080000
