; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O2 -verify-machineinstrs < %s | FileCheck %s
; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O2 -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s --check-prefix=MIR

%pair = type { i64, i64 }

declare goabiinternal void @consume(i64, i64, i64, i64, i64, i64, i64, i64,
                                    i64, ptr byval(i64) align 8)
declare goabiinternal void @consume_pair(
    i64, i64, i64, i64, i64, i64, i64, i64,
    ptr byval(%pair) align 8)
declare goabiinternal float @consume_memory_float(
    ptr byval(float) align 4, float)
declare goabiinternal void @consume_one(ptr byval(i64) align 8)
declare goabiinternal void @observe(ptr)
declare goabiinternal void @safepoint()
declare void @llvm.lifetime.start.p0(ptr captures(none))
declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)

define goabiinternal void @ssa_stack_argument() {
; CHECK-LABEL: ssa_stack_argument:
; CHECK-NOT: memcpy
; A one-use frontend carrier is removed and initialized directly in the
; outgoing Go argument area.
; CHECK: movq $42, (%rsp)
; CHECK: callq consume
; MIR-LABEL: name: ssa_stack_argument
; MIR: fixedStack:      []
; MIR: stack:           []
entry:
  %argument = alloca i64, align 8
  store i64 42, ptr %argument, align 8
  call goabiinternal void @consume(i64 0, i64 1, i64 2, i64 3, i64 4, i64 5,
                                  i64 6, i64 7, i64 8,
                                  ptr byval(i64) align 8 %argument)
  ret void
}

define goabiinternal void @register_argument_byval_source(i64 %value) {
; CHECK-LABEL: register_argument_byval_source:
; Existing incoming argument-copy elision reuses %value's fixed home for the
; temporary, while ordinary byval lowering still writes the outgoing slot.
; CHECK: callq consume
; MIR-LABEL: name: register_argument_byval_source
; MIR: fixedStack:
; MIR: - { id: 0, type: spill-slot, offset: 0, size: 8
; MIR: stack:           []
; MIR: %[[VALUE:[0-9]+]]:gr64 = COPY $rax
; MIR: MOV64mr %fixed-stack.0{{.*}}%[[VALUE]]
; MIR: MOV64mr %{{[0-9]+}}{{.*}}%[[VALUE]]
entry:
  %argument = alloca i64, align 8
  store i64 %value, ptr %argument, align 8
  call goabiinternal void @consume(i64 0, i64 1, i64 2, i64 3, i64 4, i64 5,
                                  i64 6, i64 7, i64 8,
                                  ptr byval(i64) align 8 %argument)
  ret void
}

define goabiinternal void @memory_stack_argument(ptr %source) {
; CHECK-LABEL: memory_stack_argument:
; CHECK-NOT: memcpy
; CHECK: movq (%rax), %rax
; CHECK: movq %rax, (%rsp)
; CHECK: callq consume
entry:
  call goabiinternal void @consume(i64 0, i64 1, i64 2, i64 3, i64 4, i64 5,
                                  i64 6, i64 7, i64 8,
                                  ptr byval(i64) align 8 %source)
  ret void
}

define goabiinternal void @ssa_aggregate_stack_argument() {
; CHECK-LABEL: ssa_aggregate_stack_argument:
; CHECK-NOT: movdqu
; CHECK-NOT: movups
; CHECK-NOT: movq {{[1-9][0-9]*}}(%rsp),
; CHECK: pushq $17
; CHECK: pushq $13
; CHECK: callq consume_pair
; MIR-LABEL: name: ssa_aggregate_stack_argument
; MIR: fixedStack:      []
; MIR: stack:           []
; MIR: store (s64) into stack + 8
; MIR: store (s64) into stack
entry:
  %argument = alloca %pair, align 8
  store %pair { i64 13, i64 17 }, ptr %argument, align 8
  call goabiinternal void @consume_pair(
      i64 0, i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7,
      ptr byval(%pair) align 8 %argument)
  ret void
}

define goabiinternal void @noncanonical_stack_argument() {
; Lifetime markers do not make an otherwise one-use carrier observable.
; MIR-LABEL: name: noncanonical_stack_argument
; MIR: fixedStack:      []
; MIR: stack:           []
entry:
  %argument = alloca i64, align 8
  call void @llvm.lifetime.start.p0(ptr %argument)
  store i64 42, ptr %argument, align 8
  call goabiinternal void @consume(i64 0, i64 1, i64 2, i64 3, i64 4, i64 5,
                                  i64 6, i64 7, i64 8,
                                  ptr byval(i64) align 8 %argument)
  ret void
}

define goabiinternal void @escaped_stack_argument() {
; Passing the carrier's address to another call makes its contents observable
; and potentially mutable, so the source object and ordinary byval copy stay.
; MIR-LABEL: name: escaped_stack_argument
; MIR: stack:
; MIR-NEXT: - { id: 0, name: argument, type: default, offset: 0, size: 8
entry:
  %argument = alloca i64, align 8
  store i64 42, ptr %argument, align 8
  call goabiinternal void @observe(ptr %argument)
  call goabiinternal void @consume(i64 0, i64 1, i64 2, i64 3, i64 4, i64 5,
                                  i64 6, i64 7, i64 8,
                                  ptr byval(i64) align 8 %argument)
  ret void
}

define goabiinternal void @statepoint_stack_argument() gc "statepoint-example" {
; A pointer-free carrier used only as the target statepoint's byval argument is
; still initialized directly in the outgoing slot.
; MIR-LABEL: name: statepoint_stack_argument
; MIR: fixedStack:      []
; MIR: stack:           []
entry:
  %argument = alloca i64, align 8
  store i64 42, ptr %argument, align 8
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void (ptr)) @consume_one,
          i32 1, i32 0, ptr byval(i64) align 8 %argument, i32 0, i32 0)
  ret void
}

define goabiinternal void @gc_live_statepoint_stack_argument()
    gc "statepoint-example" {
; An explicit gc-live use makes the carrier itself part of the statepoint
; contract, so it must not be replaced by the outgoing call slot.
; MIR-LABEL: name: gc_live_statepoint_stack_argument
; MIR: stack:
; MIR-NEXT: - { id: 0, name: argument, type: default, offset: 0, size: 8
entry:
  %argument = alloca i64, align 8
  store i64 42, ptr %argument, align 8
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 2, i32 0, ptr elementtype(void (ptr)) @consume_one,
          i32 1, i32 0, ptr byval(i64) align 8 %argument, i32 0, i32 0)
      [ "gc-live"(ptr %argument) ]
  ret void
}

define goabiinternal void @deopt_statepoint_stack_argument()
    gc "statepoint-example" {
; Go statepoints use deopt operands as frame-layout carriers. Preserve that
; source object so its per-object pointer map still names real storage.
; MIR-LABEL: name: deopt_statepoint_stack_argument
; MIR: stack:
; MIR-NEXT: - { id: 0, name: argument, type: default, offset: 0, size: 8
entry:
  %argument = alloca i64, align 8
  store i64 42, ptr %argument, align 8
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 3, i32 0, ptr elementtype(void (ptr)) @consume_one,
          i32 1, i32 0, ptr byval(i64) align 8 %argument, i32 0, i32 0)
      [ "deopt"(ptr %argument) ]
  ret void
}

define goabiinternal void @intervening_call_stack_argument() {
; A call between partial initialization and the target byval call can reuse
; the outgoing area and has no stack map for a later call's partial arguments.
; MIR-LABEL: name: intervening_call_stack_argument
; MIR: stack:
; MIR-NEXT: - { id: 0, name: argument, type: default, offset: 0, size: 16
entry:
  %argument = alloca %pair, align 8
  %first = getelementptr inbounds %pair, ptr %argument, i32 0, i32 0
  %second = getelementptr inbounds %pair, ptr %argument, i32 0, i32 1
  store i64 13, ptr %first, align 8
  call goabiinternal void @safepoint()
  store i64 17, ptr %second, align 8
  call goabiinternal void @consume_pair(
      i64 0, i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7,
      ptr byval(%pair) align 8 %argument)
  ret void
}

define goabiinternal i64 @read_stack_argument(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7,
    i64 %a8, ptr byval(i64) align 8 %value) {
; CHECK-LABEL: read_stack_argument:
; CHECK: movq 8(%rsp), %rax
; CHECK-NEXT: retq
; MIR-LABEL: name: read_stack_argument
; MIR: frameInfo:
; MIR: goABIStackArgsSize: 8
; MIR: goABIArgSize: 80
entry:
  %result = load i64, ptr %value, align 8
  ret i64 %result
}

define goabiinternal ptr @address_stack_pair_argument(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7,
    ptr byval(%pair) align 8 %value) {
; CHECK-LABEL: address_stack_pair_argument:
; CHECK: leaq 8(%rsp), %rax
; MIR-LABEL: name: address_stack_pair_argument
; MIR: fixedStack:
; MIR-NEXT: - { id: 0, type: default, offset: 0, size: 16
; MIR-NEXT: isImmutable: false, isAliased: true
entry:
  ret ptr %value
}

define goabiinternal float @read_memory_float(
    ptr byval(float) align 4 %memory, float %register) {
; CHECK-LABEL: read_memory_float:
; CHECK: addss 8(%rsp), %xmm0
entry:
  %loaded = load float, ptr %memory, align 4
  %sum = fadd float %loaded, %register
  ret float %sum
}

define goabiinternal float @call_memory_float(ptr %source, float %register) {
; CHECK-LABEL: call_memory_float:
; CHECK: movl {{.*}}, (%rsp)
; CHECK: callq consume_memory_float
entry:
  %result = call goabiinternal float @consume_memory_float(
      ptr byval(float) align 4 %source, float %register)
  ret float %result
}
