; RUN: split-file %s %t
; RUN: llvm-link %t/weak.ll %t/reference.ll %t/strong.ll -S -o %t.ws.ll
; RUN: opt -passes='default<O2>' -S %t.ws.ll -o %t.ws.opt.ll
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.ws.ll -o %t.ws.x86_64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.ws.x86_64.o | FileCheck %s --check-prefix=OBJECT --implicit-check-not="target=weak_"
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.ws.ll -o %t.ws.aarch64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.ws.aarch64.o | FileCheck %s --check-prefix=OBJECT --implicit-check-not="target=weak_"
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.ws.opt.ll -o %t.ws.opt.x86_64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.ws.opt.x86_64.o | FileCheck %s --check-prefix=OBJECT --implicit-check-not="target=weak_"
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.ws.opt.ll -o %t.ws.opt.aarch64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.ws.opt.aarch64.o | FileCheck %s --check-prefix=OBJECT --implicit-check-not="target=weak_"
; RUN: llvm-link %t/strong.ll %t/reference.ll %t/weak.ll -S -o %t.sw.ll
; RUN: opt -passes='default<O2>' -S %t.sw.ll -o %t.sw.opt.ll
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.sw.ll -o %t.sw.x86_64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.sw.x86_64.o | FileCheck %s --check-prefix=OBJECT --implicit-check-not="target=weak_"
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.sw.ll -o %t.sw.aarch64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.sw.aarch64.o | FileCheck %s --check-prefix=OBJECT --implicit-check-not="target=weak_"
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.sw.opt.ll -o %t.sw.opt.x86_64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.sw.opt.x86_64.o | FileCheck %s --check-prefix=OBJECT --implicit-check-not="target=weak_"
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.sw.opt.ll -o %t.sw.opt.aarch64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.sw.opt.aarch64.o | FileCheck %s --check-prefix=OBJECT --implicit-check-not="target=weak_"
; RUN: llvm-link %t/weak.ll %t/bare.ll -S | FileCheck %s --check-prefix=BARE
; RUN: llvm-link %t/bare.ll %t/weak.ll -S | FileCheck %s --check-prefix=BARE

; The selected definition owns its linker relationships. A discarded weak
; definition must not contribute keep or marker edges, in either link order.
; Targets remain compiler.used roots so metadata-only references survive O2.
; Linking also remaps references from declarations to the strong definition.
; OBJECT-DAG: symdef [[DATA:[0-9]+]]: shared abi=0 type=5 size=1
; OBJECT-DAG: symdef [[FUNC:[0-9]+]]: func abi=1 type=1
; OBJECT-DAG: reloc [[DATA]].{{[0-9]+}}: off=0 size=0 type=27 add=0 target=strong_keep
; OBJECT-DAG: reloc [[DATA]].{{[0-9]+}}: off=0 size=0 type=102 add=0 target=strong_init
; OBJECT-DAG: reloc [[FUNC]].{{[0-9]+}}: off=0 size=0 type=24 add=16 target=strong_iface
; OBJECT-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=0 type=27 add=0 target=shared
; BARE-NOT: !goobj.keep
; BARE-NOT: !goobj.marker_relocs
; BARE: @shared = global i8 3
; BARE-NOT: !goobj.keep
; BARE-NOT: !goobj.marker_relocs

;--- weak.ll
@shared = weak global i8 1, section ".noptrdata", !goobj.keep !0, !goobj.marker_relocs !1
@weak_keep = external global i8
@weak_init = external global i8
@weak_iface = external global i8
@llvm.compiler.used = appending global [5 x ptr] [ptr @shared, ptr @func, ptr @weak_keep, ptr @weak_init, ptr @weak_iface], section "llvm.metadata"
define weak goabiinternal void @func() !goobj.marker_relocs !2 {
  ret void
}
!0 = !{ptr @weak_keep}
!1 = !{!3}
!2 = !{!4}
!3 = !{ptr @weak_init, i32 102, i64 0}
!4 = !{ptr @weak_iface, i32 24, i64 8}

;--- strong.ll
@shared = global i8 2, section ".noptrdata", !goobj.keep !0, !goobj.marker_relocs !1
@strong_keep = external global i8
@strong_init = external global i8
@strong_iface = external global i8
@llvm.compiler.used = appending global [5 x ptr] [ptr @shared, ptr @func, ptr @strong_keep, ptr @strong_init, ptr @strong_iface], section "llvm.metadata"
define goabiinternal void @func() !goobj.marker_relocs !2 {
  ret void
}
!0 = !{ptr @strong_keep}
!1 = !{!3}
!2 = !{!4}
!3 = !{ptr @strong_init, i32 102, i64 0}
!4 = !{ptr @strong_iface, i32 24, i64 16}

;--- bare.ll
@shared = global i8 3
define goabiinternal void @func() {
  ret void
}

;--- reference.ll
@shared = external global i8
@remap = global i8 0, section ".noptrdata", !goobj.keep !0
@llvm.compiler.used = appending global [2 x ptr] [ptr @shared, ptr @remap], section "llvm.metadata"
!0 = !{ptr @shared}
