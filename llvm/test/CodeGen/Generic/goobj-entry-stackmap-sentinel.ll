; REQUIRES: aarch64-registered-target, x86-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin-goobj -filetype=obj %s -o %t.a64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.a64.o | \
; RUN:   FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t.x86.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.x86.o | \
; RUN:   FileCheck %s

; EntryArgsStackMapID still produces ArgsPointerMaps bitmap 0, while native Go
; encodes PCDATA_StackMapIndex=-1 at entry. runtime getStackMap maps -1 to 0.
;
; CHECK: type=funcdata target= data=01000000
; CHECK: type=pcdata target= pc=[0-{{[0-9]+}}:-1]

define goabiinternal ptr @entry_stackmap_sentinel(ptr %pointer) {
entry:
  ret ptr %pointer
}
