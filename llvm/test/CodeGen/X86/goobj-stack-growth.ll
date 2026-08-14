; RUN: llc -mtriple=x86_64-unknown-linux-goobj -verify-machineinstrs \
; RUN:   -stop-after=prolog-epilog < %s | FileCheck %s

%pointer.aggregate = type { ptr, i64, ptr }
%many.results = type {
  i64, i64, i64, i64, i64, i64, i64, i64,
  i64, i64, i64, i64, i64, i64, i64, i64, ptr
}
%partial.results = type {
  i64, i64, i64, i64, i64, i64, i64, i64,
  i64, i64, i64, i64, i64, i64, i64, %pointer.aggregate
}

declare goabiinternal void @use_three_pointers(ptr, ptr, ptr)
declare goabi0 void @"runtime.morestack_noctxt<builtin.246><ABI0>"()
declare goabi0 void @"runtime.morestackc<builtin.245><ABI0>"()

define goabiinternal i64 @morestack_call(i64 %value) {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  ret i64 %value
}

define goabi0 void @"abi0_pointer_arguments<ABI0>"(ptr %first, ptr %second, ptr %third)
    "frame-pointer"="non-leaf" {
entry:
  call goabiinternal void @use_three_pointers(
      ptr %first, ptr %second, ptr %third)
  ret void
}

define goabiinternal %many.results @initialized_pointer_result(ptr %pointer)
 "go_results_tuple" {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  ret %many.results zeroinitializer
}

define goabiinternal %partial.results @partial_aggregate_result(
    ptr %first, ptr %second)
 "go_results_tuple" {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  ret %partial.results zeroinitializer
}

define goabiinternal ptr @scalar_stack_argument(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5,
    i64 %a6, i64 %a7, i64 %a8, i64 %a9, i64 %a10,
    i64 %a11, i64 %a12, i64 %a13, i64 %a14, i64 %a15,
    ptr %pointer) {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  ret ptr %pointer
}

define goabiinternal { ptr, ptr } @aggregate_stack_argument(
    i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5,
    i64 %a6, i64 %a7, i64 %a8, i64 %a9, i64 %a10,
    i64 %a11, i64 %a12, i64 %a13, %pointer.aggregate %value)
 "go_results_tuple" {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  %first = extractvalue %pointer.aggregate %value, 0
  %second = extractvalue %pointer.aggregate %value, 2
  %r0 = insertvalue { ptr, ptr } poison, ptr %first, 0
  %r1 = insertvalue { ptr, ptr } %r0, ptr %second, 1
  ret { ptr, ptr } %r1
}

define goabiinternal void @systemstack_growth()
 "go-systemstack" {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  ret void
}

; CHECK-LABEL: name: morestack_call
; CHECK-NOT: ANNOTATION_LABEL
; CHECK: CALL64pcrel32 &"runtime.morestack_noctxt<builtin.246><ABI0>", implicit $rsp, implicit $ssp
; CHECK: STACKMAP 5147419139155979380, 0
; CHECK-NOT: STATEPOINT

; The RSP offsets below include the 8-byte amd64 return address. The argument
; words themselves are numbered from the start of the Go ABI arg/result/home
; area, exactly as native Go ArgsPointerMaps numbers them.

; GoABI0 fixed homes retain their logical argument-area offsets, while loads
; and stack-map locations include the physical entry RSP return-address word.

; CHECK-LABEL: name: 'abi0_pointer_arguments<ABI0>'
; CHECK: fixedStack:
; CHECK: offset: 16, size: 8
; CHECK: offset: 8, size: 8
; CHECK: offset: 0, size: 8
; CHECK: CALL64pcrel32 &"runtime.morestack_noctxt<builtin.246><ABI0>", implicit $rsp, implicit $ssp
; CHECK: STACKMAP 5147419139155979380, 0,
; CHECK-SAME: 1, 8, $rsp, 8, 1, 8, $rsp, 16, 1, 8, $rsp, 24
; CHECK: renamable $rax = MOV64rm $rbp, 1, $noreg, 16, $noreg
; CHECK: renamable $rbx = MOV64rm $rbp, 1, $noreg, 24, $noreg
; CHECK: renamable $rcx = MOV64rm $rbp, 1, $noreg, 32, $noreg

; CHECK-LABEL: name: initialized_pointer_result
; CHECK: MOV64mr $rsp, 1, $noreg, 72, $noreg, $rax
; CHECK: CALL64pcrel32 &"runtime.morestack_noctxt<builtin.246><ABI0>", implicit $rsp, implicit $ssp
; The unused pointer parameter may arrive as poison. Its home is preserved for
; the ABI retry path but must not be scanned.
; CHECK: STACKMAP 5147419139155979380, 0{{$}}

; CHECK-LABEL: name: partial_aggregate_result
; CHECK: MOV64mr $rsp, 1, $noreg, 80, $noreg, $rax
; CHECK: MOV64mr $rsp, 1, $noreg, 88, $noreg, $rbx
; CHECK: CALL64pcrel32 &"runtime.morestack_noctxt<builtin.246><ABI0>", implicit $rsp, implicit $ssp
; CHECK: STACKMAP 5147419139155979380, 0{{$}}

; CHECK-LABEL: name: scalar_stack_argument
; CHECK: CALL64pcrel32 &"runtime.morestack_noctxt<builtin.246><ABI0>", implicit $rsp, implicit $ssp
; CHECK: STACKMAP 5147419139155979380, 0, 1, 8, $rsp, 64

; CHECK-LABEL: name: aggregate_stack_argument
; CHECK: CALL64pcrel32 &"runtime.morestack_noctxt<builtin.246><ABI0>", implicit $rsp, implicit $ssp
; CHECK: STACKMAP 5147419139155979380, 0,
; CHECK-SAME: 1, 8, $rsp, 48, 1, 8, $rsp, 64

; CHECK-LABEL: name: systemstack_growth
; CHECK: CMP64rm $r12, $r14, 1, $noreg, 24, $noreg
; CHECK: CALL64pcrel32 &"runtime.morestackc<builtin.245><ABI0>", implicit $rsp, implicit $ssp
; CHECK: STACKMAP 5147419139155979380, 0
