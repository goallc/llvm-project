; REQUIRES: aarch64-registered-target
; RUN: llc -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

; The Go frontend embeds the complete Go object text header and GoObj binary
; settings in the IR. llc must not need a matching set of -goobj-* flags.
target triple = "aarch64-apple-darwin-goobj"

define goabiinternal void @main.main() {
entry:
  ret void
}

!goobj.config = !{!0}
!0 = !{!"goallc.goobj", !"darwin", !"arm64", !"go1.27", !"GOARM64", !"v8.0", !"metadata-build", !"main", !"1", !"1", !1}
!1 = !{!"metadata-test"}

; CHECK: header: go object darwin arm64 go1.27 GOARM64=v8.0 X:metadata-test\nbuild id "metadata-build"\nmain\n\n!\n
; CHECK: flags: 1
; CHECK: symdef {{[0-9]+}}: main.main
