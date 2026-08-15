; RUN: not llvm-as %s -o /dev/null 2>&1 | FileCheck %s

%opaque = type opaque

; CHECK: Attributes 'goret' and 'goretindex' must be used together!
define goabiinternal void @missing_index(ptr goret(i64) %result) {
  ret void
}

; CHECK: Attributes 'goret' and 'goretindex' must be used together!
define goabiinternal void @missing_type(ptr "goretindex"="0" %result) {
  ret void
}

; CHECK: 'goret' is only valid with a Go calling convention
define void @wrong_cc(ptr goret(i64) "goretindex"="0" %result) {
  ret void
}

; CHECK: duplicate 'goretindex'
define goabiinternal void @duplicate(
    ptr goret(i64) "goretindex"="0" %result0,
    ptr goret(i64) "goretindex"="0" %result1) {
  ret void
}

; CHECK: 'goretindex' values must be in increasing parameter order
define goabiinternal void @unordered(
    ptr goret(i64) "goretindex"="1" %result1,
    ptr goret(i64) "goretindex"="0" %result0) {
  ret void
}

; CHECK: 'goretindex' is out of range
define goabiinternal void @out_of_range(ptr goret(i64) "goretindex"="1" %result) {
  ret void
}

; CHECK: Attribute 'goret' does not support unsized types!
define goabiinternal void @unsized(ptr goret(%opaque) "goretindex"="0" %result) {
  ret void
}

; CHECK: Attribute 'goret' is incompatible with other ABI parameter attributes!
define goabiinternal void @incompatible(
    ptr byval(i64) goret(i64) "goretindex"="0" %result) {
  ret void
}

; CHECK: 'goretindex' must be an unsigned decimal integer
define goabiinternal void @invalid_index(
    ptr goret(i64) "goretindex"="not-a-number" %result) {
  ret void
}
