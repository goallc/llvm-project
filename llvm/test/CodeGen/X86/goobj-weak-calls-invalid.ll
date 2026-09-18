; RUN: not --crash llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o /dev/null 2>&1 | FileCheck %s

@data = global i8 0, section ".noptrdata"
declare goabiinternal void @callee()
!goobj.weak_calls = !{!0}
!0 = !{ptr @data, ptr @callee}

; CHECK: LLVM ERROR: expected !goobj.weak_calls to name a defined caller and a function callee
