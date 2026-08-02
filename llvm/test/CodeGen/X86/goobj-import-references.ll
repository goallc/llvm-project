; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj -o %t.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.opt.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj < %s -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s
; RUN: opt -passes='default<O2>' -S < %s | llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj -o %t.arm64.opt.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.opt.o | FileCheck %s

@"fmt.data" = external global i8, !goobj.import !2
@"fmt.inlined#AAAAAAAAAAA=#suffix" = external global i8, !goobj.import !3
@"fmt.unused" = external global i8, !goobj.import !8
@"type:string" = external global i8, !goobj.builtin !4
@data_source = constant ptr @"fmt.data", section ".rodata", align 8
@inline_source = constant ptr @"fmt.inlined#AAAAAAAAAAA=#suffix", section ".rodata", align 8
@llvm.compiler.used = appending global [6 x ptr] [ptr @source, ptr @data_source, ptr @inline_source, ptr @"fmt.data", ptr @"fmt.inlined#AAAAAAAAAAA=#suffix", ptr @"type:string"], section "llvm.metadata"

declare !goobj.import !5 goabiinternal void @"os.Exit"(i64)

define goabiinternal void @source() "frame-pointer"="non-leaf" {
  call goabiinternal void @"os.Exit"(i64 1)
  ret void
}

!goobj.imports = !{!0, !1}
!0 = !{!"os", !"os", !"0123456789abcdef"}
!1 = !{!"fmt", !"fmt", !"fedcba9876543210"}
!2 = !{!"fmt", i32 9, i32 1}
!3 = !{!"fmt", i32 10, i32 0}
!4 = !{i32 7}
!5 = !{!"os", i32 15, i32 0}

!goobj.marker_relocs = !{!6, !7}
!6 = !{ptr @source, ptr @"type:string", i32 23, i64 0}
!7 = !{ptr @data_source, ptr @"fmt.data", i32 23, i64 0}
!8 = !{!"fmt", i32 11, i32 0}

; CHECK: autolib-count: 2
; CHECK-NEXT: autolib 0: os fingerprint=0123456789abcdef
; CHECK-NEXT: autolib 1: fmt fingerprint=fedcba9876543210
; CHECK: pkgidx-count: 3
; CHECK-NEXT: pkgidx 0:
; CHECK-DAG: pkgidx [[FMTIDX:[12]]]: fmt
; CHECK-DAG: pkgidx [[OSIDX:[12]]]: os
; CHECK-DAG: refname [[FMTIDX]]:9: fmt.data
; CHECK-DAG: refname [[FMTIDX]]:10: fmt.inlinedsuffix
; CHECK-DAG: refname [[OSIDX]]:15: os.Exit
; CHECK: refflags [[FMTIDX]]:9: flag=0 flag2=1
; CHECK-NOT: nonpkgref {{[0-9]+}}: fmt.data
; CHECK-NOT: nonpkgref {{[0-9]+}}: os.Exit
; CHECK-NOT: fmt.unused
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=8 {{.*}}target=fmt.data {{.*}}pkg=[[FMTIDX]] sym=9
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=23 add=0 target=fmt.data {{.*}}pkg=[[FMTIDX]] sym=9
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=23 add=0 target=builtin:7 {{.*}}pkg=builtin sym=7
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}target=os.Exit {{.*}}pkg=[[OSIDX]] sym=15
