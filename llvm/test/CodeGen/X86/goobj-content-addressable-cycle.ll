; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s --check-prefix=X86
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.x86.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.opt.o | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s --check-prefix=ARM64

; Content-addressable closures can form a cycle when each closure materializes
; the other's function pointer. The component needs stable hashes instead of a
; recursive hash walk.

@llvm.compiler.used = appending global [4 x ptr] [
  ptr @"example.com/cycle.left#QUJDREVGR0g=#",
  ptr @"example.com/cycle.right#SElKS0xNTk8=#",
  ptr @"example.com/cycle.left#UFFSU1RVVlc=#",
  ptr @"example.com/cycle.right#WFlaMTIzNDU=#"
], section "llvm.metadata"

define goabiinternal void @"example.com/cycle.left#QUJDREVGR0g=#"(ptr %slot) !goobj.content_addressable !0 {
entry:
  store ptr @"example.com/cycle.right#SElKS0xNTk8=#", ptr %slot, align 8
  ret void
}

define goabiinternal void @"example.com/cycle.right#SElKS0xNTk8=#"(ptr %slot) !goobj.content_addressable !0 {
entry:
  store ptr @"example.com/cycle.left#QUJDREVGR0g=#", ptr %slot, align 8
  ret void
}

; These two definitions differ only in their temporary inline-context hashes.
; Their canonical names, machine bytes, relocation graph, and final hashes must
; match the first component.
define goabiinternal void @"example.com/cycle.left#UFFSU1RVVlc=#"(ptr %slot) !goobj.content_addressable !0 {
entry:
  store ptr @"example.com/cycle.right#WFlaMTIzNDU=#", ptr %slot, align 8
  ret void
}

define goabiinternal void @"example.com/cycle.right#WFlaMTIzNDU=#"(ptr %slot) !goobj.content_addressable !0 {
entry:
  store ptr @"example.com/cycle.left#UFFSU1RVVlc=#", ptr %slot, align 8
  ret void
}

!0 = !{i1 true}

; X86: hasheddef [[X86_LEFT0:[0-9]+]]: example.com/cycle.left abi=1 type=1 size={{[1-9][0-9]*}} align=0 flag={{[0-9]+}} flag2=0
; X86-NEXT: hasheddef [[X86_RIGHT0:[0-9]+]]: example.com/cycle.right abi=1 type=1 size={{[1-9][0-9]*}} align=0 flag={{[0-9]+}} flag2=0
; X86-NEXT: hasheddef [[X86_LEFT1:[0-9]+]]: example.com/cycle.left abi=1 type=1 size={{[1-9][0-9]*}} align=0 flag={{[0-9]+}} flag2=0
; X86-NEXT: hasheddef [[X86_RIGHT1:[0-9]+]]: example.com/cycle.right abi=1 type=1 size={{[1-9][0-9]*}} align=0 flag={{[0-9]+}} flag2=0
; X86: hash [[X86_LEFT0]]: [[X86_LEFT_HASH:[0-9a-f]+]]
; X86-NEXT: hash [[X86_RIGHT0]]: [[X86_RIGHT_HASH:[0-9a-f]+]]
; X86-NEXT: hash [[X86_LEFT1]]: [[X86_LEFT_HASH]]
; X86-NEXT: hash [[X86_RIGHT1]]: [[X86_RIGHT_HASH]]
; X86-DAG: reloc {{[0-9.]+}}: off={{[0-9]+}} size={{[0-9]+}} type=1 add=0 target=example.com/cycle.right kind=R_ADDR pkg=hashed sym=[[X86_RIGHT0]]
; X86-DAG: reloc {{[0-9.]+}}: off={{[0-9]+}} size={{[0-9]+}} type=1 add=0 target=example.com/cycle.left kind=R_ADDR pkg=hashed sym=[[X86_LEFT0]]
; X86-DAG: reloc {{[0-9.]+}}: off={{[0-9]+}} size={{[0-9]+}} type=1 add=0 target=example.com/cycle.right kind=R_ADDR pkg=hashed sym=[[X86_RIGHT1]]
; X86-DAG: reloc {{[0-9.]+}}: off={{[0-9]+}} size={{[0-9]+}} type=1 add=0 target=example.com/cycle.left kind=R_ADDR pkg=hashed sym=[[X86_LEFT1]]
; X86-NOT: example.com/cycle.left#QUJDREVGR0g=#
; X86-NOT: example.com/cycle.right#SElKS0xNTk8=#
; X86-NOT: example.com/cycle.left#UFFSU1RVVlc=#
; X86-NOT: example.com/cycle.right#WFlaMTIzNDU=#

; ARM64: hasheddef [[ARM64_LEFT0:[0-9]+]]: example.com/cycle.left abi=1 type=1 size={{[1-9][0-9]*}} align=0 flag={{[0-9]+}} flag2=0
; ARM64-NEXT: hasheddef [[ARM64_RIGHT0:[0-9]+]]: example.com/cycle.right abi=1 type=1 size={{[1-9][0-9]*}} align=0 flag={{[0-9]+}} flag2=0
; ARM64-NEXT: hasheddef [[ARM64_LEFT1:[0-9]+]]: example.com/cycle.left abi=1 type=1 size={{[1-9][0-9]*}} align=0 flag={{[0-9]+}} flag2=0
; ARM64-NEXT: hasheddef [[ARM64_RIGHT1:[0-9]+]]: example.com/cycle.right abi=1 type=1 size={{[1-9][0-9]*}} align=0 flag={{[0-9]+}} flag2=0
; ARM64: hash [[ARM64_LEFT0]]: [[ARM64_LEFT_HASH:[0-9a-f]+]]
; ARM64-NEXT: hash [[ARM64_RIGHT0]]: [[ARM64_RIGHT_HASH:[0-9a-f]+]]
; ARM64-NEXT: hash [[ARM64_LEFT1]]: [[ARM64_LEFT_HASH]]
; ARM64-NEXT: hash [[ARM64_RIGHT1]]: [[ARM64_RIGHT_HASH]]
; ARM64-DAG: reloc {{[0-9.]+}}: off={{[0-9]+}} size={{[0-9]+}} type={{[0-9]+}} add=0 target=example.com/cycle.right kind={{.*}} pkg=hashed sym=[[ARM64_RIGHT0]]
; ARM64-DAG: reloc {{[0-9.]+}}: off={{[0-9]+}} size={{[0-9]+}} type={{[0-9]+}} add=0 target=example.com/cycle.left kind={{.*}} pkg=hashed sym=[[ARM64_LEFT0]]
; ARM64-DAG: reloc {{[0-9.]+}}: off={{[0-9]+}} size={{[0-9]+}} type={{[0-9]+}} add=0 target=example.com/cycle.right kind={{.*}} pkg=hashed sym=[[ARM64_RIGHT1]]
; ARM64-DAG: reloc {{[0-9.]+}}: off={{[0-9]+}} size={{[0-9]+}} type={{[0-9]+}} add=0 target=example.com/cycle.left kind={{.*}} pkg=hashed sym=[[ARM64_LEFT1]]
; ARM64-NOT: example.com/cycle.left#QUJDREVGR0g=#
; ARM64-NOT: example.com/cycle.right#SElKS0xNTk8=#
; ARM64-NOT: example.com/cycle.left#UFFSU1RVVlc=#
; ARM64-NOT: example.com/cycle.right#WFlaMTIzNDU=#
