; RUN: opt -passes=elim-avail-extern -S %s -o %t.ll
; RUN: FileCheck %s --check-prefix=IR < %t.ll
; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %t.ll -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -filetype=obj %t.ll -o %t.arm64.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.arm64.o | FileCheck %s
;
; Imported function bodies can disappear before codegen. Their attributes and
; global-variable metadata must still identify the original package slots.
; IR: @dep.data = external global i64, !goobj.import
; IR: declare goabi0 void @"dep.func<ABI0>"() #[[ATTR:[0-9]+]]
; IR: attributes #[[ATTR]] = { "goobj.import.flags2"="4" "goobj.import.index"="7" "goobj.import.package"="dep" }
; CHECK: pkgidx 1: dep
; CHECK-DAG: refname 1:7: dep.func
; CHECK-DAG: refname 1:9: dep.data
; CHECK: refflags 1:7: flag=0 flag2=4
; CHECK-DAG: reloc {{.*}}target=dep.func {{.*}}pkg=1 sym=7
; CHECK-DAG: reloc {{.*}}target=dep.data {{.*}}pkg=1 sym=9

@dep.data = available_externally global i64 1, !goobj.import !0

define available_externally goabi0 void @"dep.func<ABI0>"() #0 {
  ret void
}
define goabiinternal i64 @caller() "frame-pointer"="all" {
  call goabi0 void @"dep.func<ABI0>"()
  %y = load i64, ptr @dep.data
  ret i64 %y
}
attributes #0 = { "goobj.import.package"="dep" "goobj.import.index"="7" "goobj.import.flags2"="4" }
!0 = !{!"dep", i32 9, i32 0}
