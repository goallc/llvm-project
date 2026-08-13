; RUN: llc -mtriple=aarch64-apple-darwin-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

@before = internal constant i64 42, section ".rodata", align 8
@.str = private unnamed_addr constant [24 x i8] c"bad data want %d, got %d"
@after = internal constant i64 84, section ".rodata", align 8

define goabiinternal ptr @private_string_address() {
entry:
  ret ptr @.str
}

; CHECK: hasheddef [[STR:[0-9]+]]: .L.str abi=0 type=3 size=24 align={{[0-9]+}} flag=3 flag2=0
; CHECK-DAG: hash [[STR]]: 1ec75dfa41be6d04ae97fd5b835b6056
; CHECK-DAG: reloc {{[0-9]+}}.{{[0-9]+}}: {{.*}}target=.L.str
; CHECK-DAG: data: {{.*}}62616420646174612077616e742025642c20676f74202564
