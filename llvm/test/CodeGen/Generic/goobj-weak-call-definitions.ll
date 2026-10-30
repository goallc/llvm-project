; RUN: split-file %s %t
; RUN: llvm-link %t/weak.ll %t/strong.ll -S -o %t.ws.ll
; RUN: opt -passes='default<O2>' -S %t.ws.ll -o %t.ws.opt.ll
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.ws.ll -o %t.ws.x86_64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.ws.x86_64.o | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.ws.ll -o %t.ws.aarch64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.ws.aarch64.o | FileCheck %s --check-prefix=ARM
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.ws.opt.ll -o %t.ws.opt.x86_64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.ws.opt.x86_64.o | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.ws.opt.ll -o %t.ws.opt.aarch64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.ws.opt.aarch64.o | FileCheck %s --check-prefix=ARM
; RUN: llvm-link %t/strong.ll %t/weak.ll -S -o %t.sw.ll
; RUN: opt -passes='default<O2>' -S %t.sw.ll -o %t.sw.opt.ll
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.sw.ll -o %t.sw.x86_64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.sw.x86_64.o | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.sw.ll -o %t.sw.aarch64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.sw.aarch64.o | FileCheck %s --check-prefix=ARM
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.sw.opt.ll -o %t.sw.opt.x86_64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.sw.opt.x86_64.o | FileCheck %s --check-prefix=X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.sw.opt.ll -o %t.sw.opt.aarch64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.sw.opt.aarch64.o | FileCheck %s --check-prefix=ARM
; RUN: llvm-link %t/weak.ll %t/bare.ll -S | FileCheck %s --check-prefix=BARE
; RUN: llvm-link %t/bare.ll %t/weak.ll -S | FileCheck %s --check-prefix=BARE
; RUN: opt -passes='default<O2>' -S %t/inline.ll -o %t.inline.ll
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.inline.ll -o %t.inline.x86_64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.inline.x86_64.o | FileCheck %s --check-prefix=INLINE-X86
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.inline.ll -o %t.inline.aarch64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.inline.aarch64.o | FileCheck %s --check-prefix=INLINE-ARM
; REQUIRES: x86-registered-target, aarch64-registered-target

; Discarded definitions must not weaken calls made by the prevailing body.
; The selected definition owns only its own targets, even when both bodies
; call the same functions. A winner without an attachment has no weak edges.
; X86: type=7 add=0 target=loser
; X86: type=32775 add=0 target=winner
; ARM: type=9 add=0 target=loser
; ARM: type=32777 add=0 target=winner
; BARE-NOT: !goobj.weak_calls
; BARE: define goabiinternal void @caller()
; BARE-NOT: !goobj.weak_calls
; Inlining into an unrelated caller must not expand a per-definition weak
; contract. Such calls remain conservatively strong, as in the old protocol.
; INLINE-X86-NOT: type=32775
; INLINE-X86: type=7 add=0 target=loser
; INLINE-X86-NOT: type=32775
; INLINE-ARM-NOT: type=32777
; INLINE-ARM: type=9 add=0 target=loser
; INLINE-ARM-NOT: type=32777

;--- weak.ll
declare goabiinternal void @loser()
declare goabiinternal void @winner()
define weak goabiinternal void @caller() "frame-pointer"="all" !goobj.weak_calls !0 {
  call goabiinternal void @loser()
  call goabiinternal void @winner()
  ret void
}
!0 = !{ptr @loser}

;--- strong.ll
declare goabiinternal void @loser()
declare goabiinternal void @winner()
define goabiinternal void @caller() "frame-pointer"="all" !goobj.weak_calls !0 {
  call goabiinternal void @loser()
  call goabiinternal void @winner()
  ret void
}
!0 = !{ptr @winner}

;--- bare.ll
define goabiinternal void @caller() { ret void }

;--- inline.ll
declare goabiinternal void @loser() noinline
define internal goabiinternal void @inline_me() alwaysinline !goobj.weak_calls !0 {
  call goabiinternal void @loser()
  ret void
}
define goabiinternal void @outer() "frame-pointer"="all" {
  call goabiinternal void @inline_me()
  ret void
}
!0 = !{ptr @loser}
