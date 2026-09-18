; RUN: llc -mtriple=x86_64-unknown-linux-goobj -goobj-package-path=main -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

; FMV implementation suffixes are LLVM storage identities, not Go runtime
; names. The writer strips each suffix and records a static ABI, while
; relocations continue to distinguish the definitions by symbol index.

define goabiinternal void @source() {
entry:
  ret void
}

define internal goabiinternal void @"source<goallc.fmv.baseline>"()
    !goobj.symbol.nonpackage !0 {
entry:
  ret void
}

define internal goabiinternal void @"source<goallc.fmv.sse41-fma>"()
    !goobj.symbol.nonpackage !0 {
entry:
  ret void
}

define internal goabiinternal void @"source<goallc.fmv.resolve>"()
    !goobj.symbol.nonpackage !0 {
entry:
  ret void
}

define internal goabi0 void @"source<goallc.fmv.abi0><ABI0>"()
    !goobj.symbol.nonpackage !0 {
entry:
  ret void
}

@baseline_ptr = global ptr @"source<goallc.fmv.baseline>"
@optimized_ptr = global ptr @"source<goallc.fmv.sse41-fma>"
@resolver_ptr = global ptr @"source<goallc.fmv.resolve>"
@abi0_ptr = global ptr @"source<goallc.fmv.abi0><ABI0>"

; CHECK-DAG: symdef [[SOURCE:[0-9]+]]: source abi=1 type=1
; CHECK-DAG: symdef [[BASEPTR:[0-9]+]]: baseline_ptr abi=0 type=7
; CHECK-DAG: symdef [[OPTPTR:[0-9]+]]: optimized_ptr abi=0 type=7
; CHECK-DAG: symdef [[RESPTR:[0-9]+]]: resolver_ptr abi=0 type=7
; CHECK-DAG: symdef [[ABI0PTR:[0-9]+]]: abi0_ptr abi=0 type=7
; CHECK-DAG: nonpkgdef [[BASE:[0-9]+]]: source abi=65535 type=1
; CHECK-DAG: nonpkgdef [[OPT:[0-9]+]]: source abi=65535 type=1
; CHECK-DAG: nonpkgdef [[RES:[0-9]+]]: source abi=65535 type=1
; CHECK-DAG: nonpkgdef [[ABI0:[0-9]+]]: source abi=65535 type=1
; CHECK-DAG: reloc [[BASEPTR]].{{[0-9]+}}: {{.*}}target=source {{.*}}pkg=none sym=[[BASE]]
; CHECK-DAG: reloc [[OPTPTR]].{{[0-9]+}}: {{.*}}target=source {{.*}}pkg=none sym=[[OPT]]
; CHECK-DAG: reloc [[RESPTR]].{{[0-9]+}}: {{.*}}target=source {{.*}}pkg=none sym=[[RES]]
; CHECK-DAG: reloc [[ABI0PTR]].{{[0-9]+}}: {{.*}}target=source {{.*}}pkg=none sym=[[ABI0]]

!0 = !{i1 true}
