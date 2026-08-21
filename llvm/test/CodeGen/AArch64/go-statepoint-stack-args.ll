; REQUIRES: aarch64-registered-target
; RUN: llc -mtriple=aarch64-apple-darwin -verify-machineinstrs \
; RUN:   -stop-after=finalize-isel < %s | FileCheck %s

%aggregate = type { ptr addrspace(1), i64, ptr addrspace(1) }
%goret.home = type { ptr, i64, ptr }

declare goabiinternal void @safepoint()

define goabiinternal ptr addrspace(1) @scalar_stack_arg(
    ptr addrspace(1) %p0,
    i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5,
    i64 %a6, i64 %a7, i64 %a8, i64 %a9, i64 %a10,
    i64 %a11, i64 %a12, i64 %a13, i64 %a14, i64 %a15,
    ptr readonly byval(ptr addrspace(1)) align 8 %p16.home) gc "statepoint-example" {
entry:
  %p16 = load ptr addrspace(1), ptr %p16.home, align 8
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 1, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %p16) ]
  %relocated = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token, i32 0, i32 0)
  ret ptr addrspace(1) %relocated
}

define goabiinternal ptr addrspace(1) @aggregate_stack_arg(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4,
    i64 %a5, i64 %a6, i64 %a7, i64 %a8, i64 %a9,
    i64 %a10, i64 %a11, i64 %a12, i64 %a13, i64 %a14,
    ptr readonly byval(%aggregate) align 8 %value.home) gc "statepoint-example" {
entry:
  %value = load %aggregate, ptr %value.home, align 8
  %first = extractvalue %aggregate %value, 0
  %second = extractvalue %aggregate %value, 2
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 2, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %first, ptr addrspace(1) %second) ]
  %first.relocated = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token, i32 0, i32 0)
  %second.relocated = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token, i32 1, i32 1)
  %result = select i1 true, ptr addrspace(1) %first.relocated,
      ptr addrspace(1) %second.relocated
  ret ptr addrspace(1) %result
}

define goabiinternal ptr addrspace(1) @merged_stack_arg(
    ptr addrspace(1) %p0,
    i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5,
    i64 %a6, i64 %a7, i64 %a8, i64 %a9, i64 %a10,
    i64 %a11, i64 %a12, i64 %a13, i64 %a14, i64 %a15,
    ptr byval(ptr addrspace(1)) align 8 %p16.home) gc "statepoint-example" {
entry:
  %p16 = load ptr addrspace(1), ptr %p16.home, align 8
  %condition = icmp ne ptr addrspace(1) %p0, null
  %merged = select i1 %condition, ptr addrspace(1) %p0,
      ptr addrspace(1) %p16
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 3, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %merged) ]
  %relocated = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token, i32 0, i32 0)
  ret ptr addrspace(1) %relocated
}

define goabiinternal ptr addrspace(1) @relocated_stack_arg(
    ptr addrspace(1) %p0,
    i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5,
    i64 %a6, i64 %a7, i64 %a8, i64 %a9, i64 %a10,
    i64 %a11, i64 %a12, i64 %a13, i64 %a14, i64 %a15,
    ptr readonly byval(ptr addrspace(1)) align 8 %p16.home) gc "statepoint-example" {
entry:
  %p16 = load ptr addrspace(1), ptr %p16.home, align 8
  %condition = icmp ne ptr addrspace(1) %p0, null
  %token1 = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 4, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %p16) ]
  %relocated1 = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token1, i32 0, i32 0)
  br i1 %condition, label %safepoint, label %skip

safepoint:
  %token2 = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 5, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %relocated1) ]
  %relocated2 = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token2, i32 0, i32 0)
  br label %merge

skip:
  br label %merge

merge:
  %merged = phi ptr addrspace(1) [ %relocated2, %safepoint ],
                                 [ %relocated1, %skip ]
  %token3 = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 6, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %merged) ]
  %relocated3 = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token3, i32 0, i32 0)
  ret ptr addrspace(1) %relocated3
}

define goabiinternal ptr addrspace(1) @mutated_stack_arg(
    ptr addrspace(1) %p0,
    i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5,
    i64 %a6, i64 %a7, i64 %a8, i64 %a9, i64 %a10,
    i64 %a11, i64 %a12, i64 %a13, i64 %a14, i64 %a15,
    ptr byval(ptr addrspace(1)) align 8 %p16.home) gc "statepoint-example" {
entry:
  %p16 = load ptr addrspace(1), ptr %p16.home, align 8
  store ptr addrspace(1) null, ptr %p16.home, align 8
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 7, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %p16) ]
  %relocated = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token, i32 0, i32 0)
  ret ptr addrspace(1) %relocated
}

define goabiinternal ptr addrspace(1) @byval_home_address(
    ptr addrspace(1) %heap,
    ptr addrspace(1) byval(%aggregate) align 8 %value.home) gc "statepoint-example" {
entry:
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 8, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %heap,
                    ptr addrspace(1) %value.home) ]
  %heap.relocated = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token, i32 0, i32 0)
  %home.relocated = call ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
      token %token, i32 1, i32 1)
  ret ptr addrspace(1) %home.relocated
}

define goabiinternal { i64, i64, i64, i64, i64, i64, i64, i64,
                       i64, i64, i64, i64, i64, i64, i64 }
    @goret_home_address(
        ptr addrspace(1) goret(%goret.home) align 8 "goretindex"="15" %result)
    #0 gc "statepoint-example" {
entry:
  %token = call goabiinternal token (i64, i32, ptr, i32, i32, ...)
      @llvm.experimental.gc.statepoint.p0(
          i64 9, i32 0, ptr elementtype(void ()) @safepoint,
          i32 0, i32 0, i32 0, i32 0)
      [ "gc-live"(ptr addrspace(1) %result) ]
  %result.relocated = call ptr addrspace(1)
      @llvm.experimental.gc.relocate.p1(
      token %token, i32 0, i32 0)
  store ptr null, ptr addrspace(1) %result.relocated, align 8
  ret { i64, i64, i64, i64, i64, i64, i64, i64,
        i64, i64, i64, i64, i64, i64, i64 } zeroinitializer
}

declare token @llvm.experimental.gc.statepoint.p0(
    i64 immarg, i32 immarg, ptr, i32 immarg, i32 immarg, ...)
declare ptr addrspace(1) @llvm.experimental.gc.relocate.p1(
    token, i32 immarg, i32 immarg)
attributes #0 = { "go_results_tuple" }

; CHECK-LABEL: name: scalar_stack_arg
; CHECK: fixedStack:
; CHECK: - { id: [[SCALAR_HOME:[0-9]+]], type: default, offset: 8, size: 8,
; CHECK: isImmutable: false
; CHECK: stack:
; CHECK: - { id: [[SCALAR_SLOT:[0-9]+]], name: '', type: default, offset: 0, size: 8,
; CHECK: STRXui {{.*}}, %stack.[[SCALAR_SLOT]], 0
; CHECK: STATEPOINT 1,
; CHECK-SAME: 2, 1, 1, 8, %stack.[[SCALAR_SLOT]], 0,
; CHECK-SAME: (volatile load store (s64) on %stack.[[SCALAR_SLOT]])
; CHECK-NEXT: ADJCALLSTACKUP
; CHECK-NEXT: [[SCALAR_RELOC:%[0-9]+]]:gpr64 = LDRXui %stack.[[SCALAR_SLOT]]

; CHECK-LABEL: name: aggregate_stack_arg
; CHECK: stack:
; CHECK: - { id: [[AGG_FIRST:[0-9]+]], name: '', type: default, offset: 0, size: 8,
; CHECK: - { id: [[AGG_SECOND:[0-9]+]], name: '', type: default, offset: 0, size: 8,
; CHECK: STRXui {{.*}}, %stack.[[AGG_FIRST]], 0
; CHECK: STRXui {{.*}}, %stack.[[AGG_SECOND]], 0
; CHECK: STATEPOINT 2,
; CHECK-SAME: 2, 2, 1, 8, %stack.[[AGG_FIRST]], 0, 1, 8, %stack.[[AGG_SECOND]], 0,
; CHECK-SAME: (volatile load store (s64) on %stack.[[AGG_FIRST]]),
; CHECK-SAME: (volatile load store (s64) on %stack.[[AGG_SECOND]])
; CHECK-NEXT: ADJCALLSTACKUP
; CHECK-NEXT: [[AGGREGATE_RELOC:%[0-9]+]]:gpr64 = LDRXui %stack.{{[0-9]+}}

; CHECK-LABEL: name: merged_stack_arg
; CHECK: stack:
; CHECK-NEXT: - { id: 0, name: '', type: default, offset: 0, size: 8,
; CHECK: STRXui {{.*}}, %stack.0, 0
; CHECK: STATEPOINT 3,
; CHECK-SAME: 2, 1, 1, 8, %stack.0, 0,
; CHECK-SAME: (volatile load store (s64) on %stack.0)

; CHECK-LABEL: name: relocated_stack_arg
; CHECK: stack:
; CHECK: - { id: [[HOME:[0-9]+]], name: '', type: default, offset: 0, size: 8,
; CHECK: STATEPOINT 4,
; CHECK-SAME: 2, 1, 1, 8, %stack.[[HOME]], 0,
; CHECK: STATEPOINT 5,
; CHECK-SAME: 2, 1, 1, 8, %stack.[[HOME]], 0,
; CHECK: STATEPOINT 6,
; CHECK-SAME: 2, 1, 1, 8, %stack.[[HOME]], 0,

; CHECK-LABEL: name: mutated_stack_arg
; CHECK: stack:
; CHECK-NEXT: - { id: 0, name: '', type: default, offset: 0, size: 8,
; CHECK: STRXui {{.*}}, %stack.0, 0
; CHECK: STATEPOINT 7,
; CHECK-SAME: 2, 1, 1, 8, %stack.0, 0,

; CHECK-LABEL: name: byval_home_address
; CHECK: fixedStack:
; CHECK: - { id: [[BYVAL_HOME:[0-9]+]], type: default, offset: 8, size: 24,
; CHECK: stack:
; CHECK: - { id: [[HEAP_SLOT:[0-9]+]], name: '', type: default, offset: 0, size: 8,
; CHECK: STATEPOINT 8,
; CHECK-SAME: 2, 2, 0, %fixed-stack.[[BYVAL_HOME]], 0, 1, 8, %stack.[[HEAP_SLOT]], 0,
; CHECK-NEXT: ADJCALLSTACKUP
; CHECK-NEXT: {{%[0-9]+}}:gpr64sp = ADDXri %fixed-stack.[[BYVAL_HOME]], 0, 0

; CHECK-LABEL: name: goret_home_address
; CHECK: fixedStack:
; CHECK: - { id: [[GORET_HOME:[0-9]+]], type: default, offset: 8, size: 24,
; CHECK: stack: []
; CHECK: STATEPOINT 9,
; CHECK-SAME: 2, 1, 0, %fixed-stack.[[GORET_HOME]], 0,
; CHECK-SAME: 2, 1, 0, %fixed-stack.[[GORET_HOME]], 0,
; CHECK-NEXT: ADJCALLSTACKUP
; CHECK-NEXT: [[GORET_FRAME:%[0-9]+]]:gpr64sp = ADDXri %fixed-stack.[[GORET_HOME]], 0, 0
; CHECK-NEXT: [[GORET_ADDR:%[0-9]+]]:gpr64sp = COPY [[GORET_FRAME]]
; CHECK: STRXui {{.*}}, [[GORET_ADDR]], 0
