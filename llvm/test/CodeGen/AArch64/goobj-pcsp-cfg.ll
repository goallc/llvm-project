; REQUIRES: aarch64-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs \
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
; but the block is reached while the frame is still active. The pre-frame
; morestack block has no frame.
;
; ASM-LABEL: pcsp_cfg:
; ASM: bl "runtime.morestack_noctxt<ABI0>"
; ASM: bl runtime.panicmem
; ASM: ldr x30, [sp], #32
; ASM: ret
; ASM: bl runtime.GC

; The stack check and morestack path occupy PC quanta 0-11. The return occupies
; 25-26; the out-of-line then block at 26-30 executes with the frame active.
; OBJ: aux 0.3: type=pcsp target= pc=[0-11:0,11-25:32,25-26:0,26-30:32]
; OBJ: reloc 0.3: off=104 size=4 type=9 add=0 target=runtime.GC
