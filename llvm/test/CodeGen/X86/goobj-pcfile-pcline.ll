; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | FileCheck %s --check-prefixes=COMMON,X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s --check-prefixes=COMMON,ARM64
;
; This IR mirrors a small C source used only as a debug-info reference:
;
;   long cdebug(long x) {
;     long y = x + 1;
;     if (y > 10)
;       y -= 3;
;     return y * 2;
;   }
;
; The generated LLVM IR is adjusted to use Go's internal ABI so the Go object
; writer emits function metadata for it.

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-goobj"

source_filename = "cdebug.c"

define goabiinternal i64 @cdebug(i64 %x) !dbg !10 {
entry:
  %y = add nsw i64 %x, 1, !dbg !20
  %cmp = icmp sgt i64 %y, 10, !dbg !21
  br i1 %cmp, label %then, label %done, !dbg !21

then:
  %sub = sub nsw i64 %y, 3, !dbg !22
  br label %done, !dbg !22

done:
  %v = phi i64 [ %sub, %then ], [ %y, %entry ], !dbg !23
  %ret = shl nsw i64 %v, 1, !dbg !23
  ret i64 %ret, !dbg !23
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!6, !7}

!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "clang", isOptimized: false, runtimeVersion: 0, emissionKind: LineTablesOnly, enums: !2, splitDebugInlining: false, nameTableKind: None)
!1 = !DIFile(filename: "cdebug.c", directory: "/tmp/goobj-debug")
!2 = !{}
!6 = !{i32 7, !"Dwarf Version", i32 4}
!7 = !{i32 2, !"Debug Info Version", i32 3}
!10 = distinct !DISubprogram(name: "cdebug", scope: !1, file: !1, line: 1, type: !11, scopeLine: 1, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !2)
!11 = !DISubroutineType(types: !12)
!12 = !{!13, !13}
!13 = !DIBasicType(name: "long", size: 64, encoding: DW_ATE_signed)
!20 = !DILocation(line: 2, column: 12, scope: !10)
!21 = !DILocation(line: 3, column: 7, scope: !10)
!22 = !DILocation(line: 4, column: 7, scope: !10)
!23 = !DILocation(line: 5, column: 3, scope: !10)

; COMMON: file-count: 1
; COMMON-NEXT: file 0: {{.*}}cdebug.c
; COMMON: hasheddef-count: 4
; COMMON: nonpkgdef-count: 0
; X86: hash 0: a21821a940f91b1a89b53461b092269e
; X86-NEXT: hash 1: f9ced9dca799cb1833bd530443fd1f9e
; X86-NEXT: hash 2: 2677aa574f61b902c15de55332c2c2ea
; ARM64: hash 0: 105a58e8d53963b571ff833d8449eeda
; ARM64-NEXT: hash 1: 3bef6118e9cf260f78533cdf1a6375ec
; ARM64-NEXT: hash 2: 3a577c7591ae76fd8b51f8e7ea4ac9d8
; COMMON-NEXT: hash 3: 4b0e7a681c0340c9a97ef4802a3af2f8
; COMMON: aux {{[0-9]+}}.{{[0-9]+}}: type=funcdata target= data=0100000000000000 pkg=hashed sym=3
; COMMON-NEXT: aux {{[0-9]+}}.{{[0-9]+}}: type=funcdata target= data=0100000000000000 pkg=hashed sym=3
; COMMON-NEXT: aux {{[0-9]+}}.{{[0-9]+}}: type=pcsp target= pc={{.*}} pkg=hashed sym=0
; COMMON-NEXT: aux {{[0-9]+}}.{{[0-9]+}}: type=pcfile target= pc={{.*}}:0{{.*}} pkg=hashed sym=0
; COMMON-NEXT: aux {{[0-9]+}}.{{[0-9]+}}: type=pcline target= pc=[
; COMMON-SAME: :2
; COMMON-SAME: :3
; COMMON-SAME: :5
; COMMON-SAME: pkg=hashed sym=1
; COMMON-NEXT: aux {{[0-9]+}}.{{[0-9]+}}: type=pcdata target= pc={{.*}} pkg=hashed sym=2
; COMMON-NEXT: aux {{[0-9]+}}.{{[0-9]+}}: type=pcdata target= pc={{.*}} pkg=hashed sym=0
