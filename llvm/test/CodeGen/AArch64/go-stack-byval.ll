; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O2 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=aarch64-unknown-linux-gnu -O2 -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=MIR

%pair = type { i64, i64 }

declare goabiinternal void @consume(i64, i64, i64, i64, i64, i64, i64, i64,
                                    i64, i64, i64, i64, i64, i64, i64, i64,
                                    ptr byval(i64) align 8)
declare goabiinternal void @consume_pair(
    i64, i64, i64, i64, i64, i64, i64, i64,
    i64, i64, i64, i64, i64, i64, i64,
    ptr byval(%pair) align 8)
declare goabiinternal float @consume_memory_float(
    ptr byval(float) align 4, float)
declare void @llvm.lifetime.start.p0(ptr captures(none))

define goabiinternal void @ssa_stack_argument() {
; CHECK-LABEL: ssa_stack_argument:
; CHECK-NOT: memcpy
; The frontend alloca remains an ordinary source object. Generic byval
; lowering copies its value into the outgoing Go argument area.
; CHECK: mov w{{[0-9]+}}, #42
; CHECK: str x{{[0-9]+}}, [sp, #8]
; CHECK: bl consume
entry:
  %argument = alloca i64, align 8
  store i64 42, ptr %argument, align 8
  call goabiinternal void @consume(
      i64 0, i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7,
      i64 8, i64 9, i64 10, i64 11, i64 12, i64 13, i64 14, i64 15,
      ptr byval(i64) align 8 %argument)
  ret void
}

define goabiinternal void @register_argument_byval_source(i64 %value) {
; CHECK-LABEL: register_argument_byval_source:
; Existing incoming argument-copy elision reuses %value's fixed home for the
; temporary, while ordinary byval lowering still writes the outgoing slot.
; CHECK: bl consume
; MIR-LABEL: name: register_argument_byval_source
; MIR: fixedStack:
; MIR: - { id: 0, type: spill-slot, offset: 8, size: 8
; MIR: stack:           []
; MIR: %[[VALUE:[0-9]+]]:gpr64 = COPY $x0
; MIR: STRXui %[[VALUE]], %fixed-stack.0, 0
; MIR: STRXui %[[VALUE]], %{{[0-9]+}}, 1
entry:
  %argument = alloca i64, align 8
  store i64 %value, ptr %argument, align 8
  call goabiinternal void @consume(
      i64 0, i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7,
      i64 8, i64 9, i64 10, i64 11, i64 12, i64 13, i64 14, i64 15,
      ptr byval(i64) align 8 %argument)
  ret void
}

define goabiinternal void @memory_stack_argument(ptr %source) {
; CHECK-LABEL: memory_stack_argument:
; CHECK-NOT: memcpy
; CHECK: ldr x{{[0-9]+}}, [x{{[0-9]+}}]
; CHECK: str x{{[0-9]+}}, [sp, #8]
; CHECK: bl consume
entry:
  call goabiinternal void @consume(
      i64 0, i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7,
      i64 8, i64 9, i64 10, i64 11, i64 12, i64 13, i64 14, i64 15,
      ptr byval(i64) align 8 %source)
  ret void
}

define goabiinternal void @ssa_aggregate_stack_argument() {
; CHECK-LABEL: ssa_aggregate_stack_argument:
; CHECK: ldr q[[VALUE:[0-9]+]], [sp, #{{[1-9][0-9]*}}]
; CHECK: stur q[[VALUE]], [sp, #8]
; CHECK: bl consume_pair
; MIR-LABEL: name: ssa_aggregate_stack_argument
; MIR: stack:
; MIR: - { id: 0, name: argument, type: default, offset: 0, size: 16
; MIR: LDRQui %stack.0.argument
; MIR: STURQi
; MIR-SAME: store (s128) into stack + 8
entry:
  %argument = alloca %pair, align 8
  store %pair { i64 13, i64 17 }, ptr %argument, align 8
  call goabiinternal void @consume_pair(
      i64 0, i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7,
      i64 8, i64 9, i64 10, i64 11, i64 12, i64 13, i64 14,
      ptr byval(%pair) align 8 %argument)
  ret void
}

define goabiinternal void @noncanonical_stack_argument() {
; Lifetime markers do not change the ordinary source-object plus byval-copy
; semantics.
; MIR-LABEL: name: noncanonical_stack_argument
; MIR: stack:
; MIR-NEXT: - { id: 0,
entry:
  %argument = alloca i64, align 8
  call void @llvm.lifetime.start.p0(ptr %argument)
  store i64 42, ptr %argument, align 8
  call goabiinternal void @consume(
      i64 0, i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7,
      i64 8, i64 9, i64 10, i64 11, i64 12, i64 13, i64 14, i64 15,
      ptr byval(i64) align 8 %argument)
  ret void
}

define goabiinternal i64 @read_stack_argument(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7,
    i64 %a8, i64 %a9, i64 %a10, i64 %a11, i64 %a12, i64 %a13, i64 %a14,
    i64 %a15, ptr byval(i64) align 8 %value) {
; CHECK-LABEL: read_stack_argument:
; CHECK: ldr x0, [sp, #8]
; CHECK-NEXT: ret
entry:
  %result = load i64, ptr %value, align 8
  ret i64 %result
}

define goabiinternal ptr @address_stack_pair_argument(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7,
    i64 %a8, i64 %a9, i64 %a10, i64 %a11, i64 %a12, i64 %a13, i64 %a14,
    ptr byval(%pair) align 8 %value) {
; CHECK-LABEL: address_stack_pair_argument:
; CHECK: add x0, sp, #8
; MIR-LABEL: name: address_stack_pair_argument
; MIR: fixedStack:
; MIR-NEXT: - { id: 0, type: default, offset: 8, size: 16
; MIR-NEXT: isImmutable: false, isAliased: true
entry:
  ret ptr %value
}

define goabiinternal float @read_memory_float(
    ptr byval(float) align 4 %memory, float %register) {
; CHECK-LABEL: read_memory_float:
; CHECK: ldr [[MEMORY:s[0-9]+]], [sp, #8]
; CHECK: fadd s0, [[MEMORY]], s0
entry:
  %loaded = load float, ptr %memory, align 4
  %sum = fadd float %loaded, %register
  ret float %sum
}

define goabiinternal float @call_memory_float(ptr %source, float %register) {
; CHECK-LABEL: call_memory_float:
; CHECK: str {{w[0-9]+}}, [sp, #8]
; CHECK: bl consume_memory_float
entry:
  %result = call goabiinternal float @consume_memory_float(
      ptr byval(float) align 4 %source, float %register)
  ret float %result
}
