; REQUIRES: x86-registered-target
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -goobj-package-path=main -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s --check-prefix=OBJ

declare goabiinternal void @"runtime.GC"()
declare goabiinternal void @"runtime.panicmem"()

define goabiinternal void @pcsp_cfg(ptr %p, i1 %cond) #0 {
entry:
  call goabiinternal void @"runtime.GC"()
  br i1 %cond, label %then, label %join, !prof !0

then:
  call goabiinternal void @"runtime.GC"()
  br label %join

join:
  %isnil = icmp eq ptr %p, null
  br i1 %isnil, label %nil, label %cont

nil:
  call goabiinternal void @"runtime.panicmem"()
  br label %cont

cont:
  load volatile i8, ptr %p
  ret void
}

attributes #0 = { "frame-pointer"="non-leaf" }

!0 = !{!"branch_weights", i32 1, i32 1000}

; MachineBlockPlacement puts the cold then block after the epilogue and return,
; but the block is reached while the frame is still active. The later
; morestack block has no frame.
;
; ASM-LABEL: pcsp_cfg:
; ASM: callq runtime.panicmem
; ASM: retq
; ASM: callq runtime.GC
; ASM: callq "runtime.morestack_noctxt<ABI0>"

; The return occupies PC quanta 59-60. The out-of-line then block at 61-68
; restores the 24-byte frame depth before morestack restores the entry depth.
; OBJ: aux 0.3: type=pcsp target= pc=[0-7:0,7-14:8,14-59:24,59-60:8,60-61:0,61-68:24,68-100:0]
; OBJ: reloc 0.2: off=62 size=4 type=7 add=0 target=runtime.GC
