; RUN: llc -mtriple=aarch64-apple-darwin-goobj -goobj-package-path=example/pkg -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

@before = internal constant i64 42, section ".rodata", align 8
@.str = private unnamed_addr constant [24 x i8] c"bad data want %d, got %d"
@after = internal constant i64 84, section ".rodata", align 8

define goabiinternal ptr @private_string_address() {
entry:
  ret ptr @.str
}

; CHECK: symdef [[STR:[0-9]+]]: goallc.{{[0-9a-f]+}}.stmp_{{[0-9]+}} abi=65535 type=3 size=24 align={{[0-9]+}} flag=2 flag2=0
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}target=goallc.{{[0-9a-f]+}}.stmp_{{[0-9]+}}
; CHECK-DAG: data: {{.*}}62616420646174612077616e742025642c20676f74202564
