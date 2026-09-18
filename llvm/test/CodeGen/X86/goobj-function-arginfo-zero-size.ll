; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o /dev/null
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj < %s -o /dev/null

; Zero-sized Go arguments use LLVM padding carriers to preserve their logical
; identity and alignment. They do not occupy or align an ABI home, so %b
; immediately follows %a in the register spill area and the frame remains one
; pointer-sized slot.

%empty = type {}
%go.abi.pad = type { i8 }

@trace.zero.arginfo = weak constant [1 x i8] c"\ff", section ".rodata", align 1
@llvm.compiler.used = appending global [1 x ptr] [ptr @trace.zero.arginfo], section "llvm.metadata"

define goabiinternal i8 @trace.zero(i8 %a, { %empty, %go.abi.pad } %empty,
                                    { [0 x i64], %go.abi.pad } %aligned,
                                    i8 %b) !goobj.func.arginfo !0 {
  %sum = add i8 %a, %b
  ret i8 %sum
}

!0 = !{ptr @trace.zero.arginfo, i64 8, i64 0,
       i64 0, i64 1, i64 0, i64 0, i64 0, i64 0, i64 1, i64 1}
