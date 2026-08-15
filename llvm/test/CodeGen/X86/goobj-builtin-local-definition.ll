; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s --check-prefix=ABSENT

; The builtin declaration deliberately has a different LLVM function type
; from the canonical definition.  They remain separate GlobalValues through
; code generation and are joined only when the GoObj relocation is written.

declare goabiinternal void @"runtime.growslice<builtin.133>"(ptr)
declare goabiinternal void @"runtime.external<builtin.134>"()
declare goabi0 void @"runtime.onlyinternal<builtin.135><ABI0>"()
declare goabiinternal void @"runtime.onlyabi0<builtin.136>"()
declare goabi0 void @"runtime.abi0local<builtin.137><ABI0>"()
declare goabiinternal void @"runtime.packagelocal<builtin.138>"()
@"runtime.hashed<builtin.139>" = external global i8
@runtime.hashed = weak constant i8 0, section ".rodata", align 1,
    !goobj.content_hash !2

define goabiinternal ptr @runtime.growslice(ptr %p, i64 %n)
    "go-nosplit" !goobj.symbol.nonpackage !0 !goobj.symbol.flags !1 {
  ret ptr %p
}

define goabiinternal void @runtime.onlyinternal() "go-nosplit" {
  ret void
}

define goabi0 void @"runtime.onlyabi0<ABI0>"() "go-nosplit" {
  ret void
}

define goabi0 void @"runtime.abi0local<ABI0>"()
    "go-nosplit" !goobj.symbol.nonpackage !0 {
  ret void
}

define goabiinternal void @runtime.packagelocal() "go-nosplit" {
  ret void
}

define goabiinternal void @caller(ptr %p) "go-nosplit" {
  call goabiinternal void @"runtime.growslice<builtin.133>"(ptr %p)
  call goabiinternal void @"runtime.external<builtin.134>"()
  call goabi0 void @"runtime.onlyinternal<builtin.135><ABI0>"()
  call goabiinternal void @"runtime.onlyabi0<builtin.136>"()
  call goabi0 void @"runtime.abi0local<builtin.137><ABI0>"()
  call goabiinternal void @"runtime.packagelocal<builtin.138>"()
  ret void
}

!0 = !{i1 true}
!1 = !{i32 0, i32 16}
!2 = !{!"0123456789abcdef"}
!goobj.marker_relocs = !{!3}
!3 = !{ptr @caller, ptr @"runtime.hashed<builtin.139>", i32 23, i64 0}

; The ABIInternal builtin call resolves to the non-package canonical
; definition in this object, just like runtime.growslice in native GoObj.
; CHECK-DAG: nonpkgdef [[GROWSLICE:[0-9]+]]: runtime.growslice abi=1 {{.*}}flag2=16
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}target=runtime.growslice {{.*}}pkg=none sym=[[GROWSLICE]]

; A same-ABI ABI0 definition is also eligible for local resolution.
; CHECK-DAG: nonpkgdef [[ABI0LOCAL:[0-9]+]]: runtime.abi0local abi=0
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}target=runtime.abi0local {{.*}}pkg=none sym=[[ABI0LOCAL]]

; The same identity lookup preserves the definition's assigned GoObj block.
; CHECK-DAG: symdef [[PACKAGELOCAL:[0-9]+]]: runtime.packagelocal abi=1
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}target=runtime.packagelocal {{.*}}pkg=self sym=[[PACKAGELOCAL]]
; CHECK-DAG: hasheddef [[HASHED:[0-9]+]]: runtime.hashed abi=0
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}target=runtime.hashed {{.*}}pkg=hashed sym=[[HASHED]]

; Missing definitions and canonical definitions with the wrong ABI retain
; their builtin-index identities.
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}target=builtin:134 {{.*}}pkg=builtin sym=134
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}target=builtin:135 {{.*}}pkg=builtin sym=135
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}target=builtin:136 {{.*}}pkg=builtin sym=136
; ABSENT-NOT: target=builtin:133
; ABSENT-NOT: target=builtin:137
; ABSENT-NOT: target=builtin:138
; ABSENT-NOT: target=builtin:139
