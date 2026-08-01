; REQUIRES: aarch64-registered-target
; RUN: opt -passes='default<O2>' -S < %s | FileCheck %s --check-prefix=OPT
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -verify-machineinstrs \
; RUN:   -enable-shrink-wrap=true -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | \
; RUN:   FileCheck %s --check-prefix=OBJ

define goabiinternal i64 @main.safe(ptr %p) {
entry:
  %v = load i64, ptr %p, align 8
  ret i64 %v
}

define goabiinternal i64 @main.async_unsafe(ptr %p) #0 {
; OPT-LABEL: define goabiinternal i64 @main.async_unsafe
; OPT-SAME: #[[UNSAFE:[0-9]+]]
; OPT: %v = load i64, ptr %p, align 8
entry:
  %v = load i64, ptr %p, align 8
  ret i64 %v
}

attributes #0 = { "go-async-unsafe" }
; OPT: attributes #[[UNSAFE]] = { {{.*}}"go-async-unsafe"{{.*}} }

; OBJ: symdef 0: main.safe
; OBJ: symdef 1: main.async_unsafe
; OBJ: aux 0.6: type=pcdata target= pc=[0-2:-1]
; OBJ: aux 1.14: type=pcdata target= pc=[0-2:-2]
