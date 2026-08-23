; REQUIRES: x86-registered-target, plugins, llvm-dylib
; RUN: llc -load %llvmshlibdir/CGTestPlugin%pluginext \
; RUN:   -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | \
; RUN:   FileCheck %s

define goabiinternal i64 @goobj_async_preemption_ranges(i64 %v) #0 {
entry:
  %add = add i64 %v, 7
  ret i64 %add
}

; The callback's precise ranges override this fail-closed frontend fallback.
attributes #0 = { "go-async-unsafe" }

; CHECK: symdef 0: goobj_async_preemption_ranges
; CHECK: type=pcdata target= pc=[0-4:-2,4-5:-1]
