; RUN: llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj < %s -o %t.o
; RUN: %python %S/../../MC/GoObj/Inputs/dump-goobj.py %t.o | FileCheck %s

%go.descriptor.weak_offset = type <{ i32 }>
%go.runtime.Method = type <{ i32, i32, i32, i32 }>
%go.runtime.Imethod = type <{ i32, i32 }>
%go.descriptor.methods = type <{ [1 x %go.runtime.Method], [1 x %go.runtime.Imethod] }>

@target = constant i8 0, section ".rodata", align 1
@weak_offset = constant %go.descriptor.weak_offset <{ i32 ptrtoint (ptr @target to i32) }>, section ".rodata", align 4, !goobj.weak_relocs !0
@method_name = constant i8 0, section ".rodata", align 1
@method_type = constant i8 0, section ".rodata", align 1
@methods = constant %go.descriptor.methods <{
  [1 x %go.runtime.Method] [
    %go.runtime.Method <{
      i32 ptrtoint (ptr @method_name to i32),
      i32 ptrtoint (ptr @method_type to i32),
      i32 ptrtoint (ptr @method_text to i32),
      i32 ptrtoint (ptr @method_text to i32)
    }>
  ],
  [1 x %go.runtime.Imethod] [
    %go.runtime.Imethod <{
      i32 ptrtoint (ptr @method_name to i32),
      i32 ptrtoint (ptr @method_type to i32)
    }>
  ]
}>, section ".rodata", align 4

declare void @method_text()

!0 = !{i32 0}

; CHECK-DAG: symdef {{[0-9]+}}: weak_offset abi=0 type=3 size=4
; CHECK-DAG: symdef {{[0-9]+}}: methods abi=0 type=3 size=24
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=4 type=32773 add=0 target=target
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=0 size=4 type=5 add=0 target=method_name
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=4 size=4 type=26 add=0 target=method_type
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=8 size=4 type=26 add=0 target=method_text
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=12 size=4 type=26 add=0 target=method_text
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=16 size=4 type=5 add=0 target=method_name
; CHECK: reloc {{[0-9]+}}.{{[0-9]+}}: off=20 size=4 type=5 add=0 target=method_type
