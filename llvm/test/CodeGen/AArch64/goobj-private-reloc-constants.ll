; REQUIRES: aarch64-registered-target
; RUN: llc -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

; Optimized Go IR can contain private lookup tables whose bytes are identical
; before fixups but whose relocations name different symbols. Their Go content
; hashes must include the relocation target identity, matching cmd/internal/obj,
; so the linker cannot fold the tables together.

target triple = "aarch64-apple-darwin-goobj"

@runtime.targetA = global i8 1, section ".rodata", !goobj.symbol.nonpackage !2
@runtime.targetB = global i8 2, section ".rodata", !goobj.symbol.nonpackage !2
@table.a = private constant [1 x ptr] [ptr @runtime.targetA], align 8
@table.b = private constant [1 x ptr] [ptr @runtime.targetB], align 8
@llvm.compiler.used = appending global [2 x ptr] [ptr @table.a, ptr @table.b], section "llvm.metadata"

define ptr @p.lookup(i1 %which) !goobj.symbol.index !3 {
entry:
  %table = select i1 %which, ptr @table.a, ptr @table.b
  ret ptr %table
}

!goobj.config = !{!0}
!0 = !{!"goallc.goobj", !"darwin", !"arm64", !"go1.27", !"GOARM64", !"v8.0", !"", !"p", !"0", !"0", !1}
!1 = !{!"regabiwrappers", !"regabiargs"}
!2 = !{i1 true}
!3 = !{i32 0}

; CHECK: hasheddef 0: .Ltable.b abi=0 type=3 size=8 align=8
; CHECK-NEXT: hasheddef 1: .Ltable.a abi=0 type=3 size=8 align=8
; These are cmd/internal/obj's native SHA-256-based hashes for size 8,
; default rodata, one R_ADDR relocation, and each non-package target name.
; CHECK: hash 0: 0f368520f5468968253a6a8c2a0e2f05
; CHECK-NEXT: hash 1: 05c6989a6d8dc052c2e96991d2f58be6
; CHECK: reloc 2.{{[0-9]+}}: off=0 size=8 type=1 add=0 target=runtime.targetB
; CHECK: reloc 3.{{[0-9]+}}: off=0 size=8 type=1 add=0 target=runtime.targetA
