; REQUIRES: aarch64-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -O2 -verify-machineinstrs \
; RUN:   -goobj-package-path=main -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o \
; RUN:   | FileCheck %s --check-prefix=OBJ

declare goabiinternal void @consume_large(ptr byval([4099 x i8]) align 1)

define goabiinternal void @large_memory_stack_argument(ptr %source) #0 {
entry:
  call goabiinternal void @consume_large(
      ptr byval([4099 x i8]) align 1 %source)
  ret void
}

attributes #0 = { "frame-pointer"="non-leaf" }

; The real loop blocks all execute with the outgoing call frame active. Check
; that GoObj PCSP covers the loop and tail-copy instructions, then returns to
; zero after the epilogue.
; OBJ: symdef 0: large_memory_stack_argument abi=1 type=1 size=136
; OBJ: aux 0.0: type=funcinfo target= args=8 locals=4120
; OBJ: aux 0.3: type=pcsp target= pc=[0-15:0,15-33:4128,33-34:0]
; OBJ: reloc 0.1: off=112 size=4 type=9 add=0 target=consume_large
