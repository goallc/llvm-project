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

define goabiinternal i64 @morestack_statepoint(i64 %value) "go-stack-growth-statepoint" {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  ret i64 %value
}

define goabi0 void @"abi0_pointer_arguments<ABI0>"(ptr %first, ptr %second, ptr %third)
    "frame-pointer"="non-leaf" "go-stack-growth-statepoint" {
entry:
  call goabiinternal void @use_three_pointers(
      ptr %first, ptr %second, ptr %third)
  ret void
}

define goabiinternal %many.results @initialized_pointer_result(ptr %pointer)
    "go-stack-growth-statepoint" "go_results_tuple" {
entry:
  %buf = alloca [5000 x i8], align 8
  %slot = getelementptr inbounds [5000 x i8], ptr %buf, i64 0, i64 4999
  store volatile i8 1, ptr %slot, align 1
  ret %many.results zeroinitializer
}

define goabiinternal %partial.results @partial_aggregate_result(
    ptr %first, ptr %second)
    "go-stack-growth-statepoint" "go_results_tuple" {
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
    ptr %pointer) "go-stack-growth-statepoint" {
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
    "go-stack-growth-statepoint" "go_results_tuple" {
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

; CHECK-LABEL: name: morestack_statepoint
; CHECK-NOT: ANNOTATION_LABEL
; CHECK: STATEPOINT 5147424658422983495, 0, 0, &"runtime.morestack_noctxt<ABI0>",
; CHECK-SAME: 2, 22, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0,
; CHECK-SAME: csr_64_go, implicit-def $rsp, implicit-def $ssp
; CHECK-NOT: CALL64pcrel32

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
; CHECK: STATEPOINT 5147424658422983495, 0, 0, &"runtime.morestack_noctxt<ABI0>",
; CHECK-SAME: 2, 23, 2, 0, 2, 0, 2, 3,
; CHECK-SAME: 1, 8, $rsp, 8, 1, 8, $rsp, 16, 1, 8, $rsp, 24,
; CHECK-SAME: 2, 0, 2, 3, 0, 0, 1, 1, 2, 2,
; CHECK-SAME: csr_64_go, implicit-def $rsp, implicit-def $ssp
; CHECK: renamable $rax = MOV64rm $rbp, 1, $noreg, 16, $noreg
; CHECK: renamable $rbx = MOV64rm $rbp, 1, $noreg, 24, $noreg
; CHECK: renamable $rcx = MOV64rm $rbp, 1, $noreg, 32, $noreg

; CHECK-LABEL: name: initialized_pointer_result
; CHECK: MOV64mr $rsp, 1, $noreg, 72, $noreg, $rax
; CHECK: STATEPOINT 5147424658422983495, 0, 0, &"runtime.morestack_noctxt<ABI0>",
; CHECK-SAME: 2, 22, 2, 0, 2, 0, 2, 1,
; CHECK-SAME: 1, 8, $rsp, 72,
; CHECK-SAME: 2, 0, 2, 1, 0, 0,
; CHECK-SAME: csr_64_go, implicit-def $rsp, implicit-def $ssp

; CHECK-LABEL: name: partial_aggregate_result
; CHECK: MOV64mr $rsp, 1, $noreg, 80, $noreg, $rax
; CHECK: MOV64mr $rsp, 1, $noreg, 88, $noreg, $rbx
; CHECK: STATEPOINT 5147424658422983495, 0, 0, &"runtime.morestack_noctxt<ABI0>",
; CHECK-SAME: 2, 22, 2, 0, 2, 0, 2, 2,
; CHECK-SAME: 1, 8, $rsp, 80, 1, 8, $rsp, 88,
; CHECK-SAME: 2, 0, 2, 2, 0, 0, 1, 1,
; CHECK-SAME: csr_64_go, implicit-def $rsp, implicit-def $ssp

; CHECK-LABEL: name: scalar_stack_argument
; CHECK: STATEPOINT 5147424658422983495, 0, 0, &"runtime.morestack_noctxt<ABI0>",
; CHECK-SAME: 2, 22, 2, 0, 2, 0, 2, 1,
; CHECK-SAME: 1, 8, $rsp, 64,
; CHECK-SAME: 2, 0, 2, 1, 0, 0,
; CHECK-SAME: csr_64_go, implicit-def $rsp, implicit-def $ssp

; CHECK-LABEL: name: aggregate_stack_argument
; CHECK: STATEPOINT 5147424658422983495, 0, 0, &"runtime.morestack_noctxt<ABI0>",
; CHECK-SAME: 2, 22, 2, 0, 2, 0, 2, 2,
; CHECK-SAME: 1, 8, $rsp, 48, 1, 8, $rsp, 64,
; CHECK-SAME: 2, 0, 2, 2, 0, 0, 1, 1,
; CHECK-SAME: csr_64_go, implicit-def $rsp, implicit-def $ssp
