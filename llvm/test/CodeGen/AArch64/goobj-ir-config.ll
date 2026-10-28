; REQUIRES: aarch64-registered-target
; RUN: split-file %s %t
; RUN: llc -filetype=obj < %t/legacy.ll -o %t.legacy.o
; RUN: llc -filetype=obj < %t/native.ll -o %t.native.o
; RUN: cmp %t.legacy.o %t.native.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.native.o | FileCheck %s
; RUN: sed 's/!llvm.module.flags = !{!2}//' %t/native.ll | not llc -filetype=obj -o /dev/null 2>&1 | FileCheck %s --check-prefix=MISSING
; RUN: llvm-link -S %t/native.ll %t/compatible.ll -o - | FileCheck %s --check-prefix=MERGE
; RUN: not llvm-link %t/native.ll %t/incompatible.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=CONFLICT
; RUN: not llvm-link %t/incompatible.ll %t/native.ll -o /dev/null 2>&1 | FileCheck %s --check-prefix=CONFLICT

; MISSING: goobj.abi module flag must contain eight fields
; MERGE: !llvm.module.flags = !{![[FLAG:[0-9]+]]}
; MERGE: ![[FLAG]] = !{i32 1, !"goobj.abi", ![[ABI:[0-9]+]]}
; MERGE: ![[ABI]] = !{!"goallc.goobj", !"darwin", !"arm64", !"go1.27",
; CONFLICT: linking module flags 'goobj.abi': IDs have conflicting values

;--- legacy.ll
; The Go frontend embeds the complete Go object text header and GoObj binary
; settings in the IR. llc must not need a matching set of -goobj-* flags.
target triple = "aarch64-apple-darwin-goobj"

define goabiinternal void @main.main() {
entry:
  ret void
}

!goobj.config = !{!0}
!0 = !{!"goallc.goobj", !"darwin", !"arm64", !"go1.27", !"GOARM64", !"v8.0", !"metadata-build", !"main", !"1", !"1", !"1", !1}
!1 = !{!"metadata-test"}

; CHECK: header: go object darwin arm64 go1.27 GOARM64=v8.0 X:metadata-test\nbuild id "metadata-build"\nmain\n\n!\n
; CHECK: flags: 17
; CHECK: symdef {{[0-9]+}}: main.main

;--- native.ll
target triple = "aarch64-apple-darwin-goobj"
define goabiinternal void @main.main() { ret void }
!goobj.config = !{!0}
!0 = !{!"metadata-build", !"main", !"1", !"1", !"0000000000000000"}
!llvm.module.flags = !{!2}
!2 = !{i32 1, !"goobj.abi", !3}
!3 = !{!"goallc.goobj", !"darwin", !"arm64", !"go1.27", !"GOARM64", !"v8.0", !"1", !1}
!1 = !{!"metadata-test"}

;--- compatible.ll
target triple = "aarch64-apple-darwin-goobj"
!llvm.module.flags = !{!0}
!0 = !{i32 1, !"goobj.abi", !1}
!1 = !{!"goallc.goobj", !"darwin", !"arm64", !"go1.27", !"GOARM64", !"v8.0", !"1", !2}
!2 = !{!"metadata-test"}

;--- incompatible.ll
target triple = "aarch64-apple-darwin-goobj"
!llvm.module.flags = !{!0}
!0 = !{i32 1, !"goobj.abi", !1}
!1 = !{!"goallc.goobj", !"darwin", !"arm64", !"go1.28", !"GOARM64", !"v8.0", !"1", !2}
!2 = !{!"metadata-test"}
