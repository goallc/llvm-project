; RUN: llc -mtriple=x86_64-unknown-linux-gnu -O2 -verify-machineinstrs < %s | FileCheck %s

%large = type [40000 x i64]
%go.abi.pad = type { i8 }
%go_memory = type { i64, [0 x i64], [2 x [0 x i64]], %go.abi.pad }

declare token @llvm.call.preallocated.setup(i32)
declare ptr @llvm.call.preallocated.arg(token, i32)
declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)
declare goabiinternal void @consume(ptr preallocated(%large) align 8)

define goabiinternal void @copy_large_stack_argument(ptr %source) {
; CHECK-LABEL: copy_large_stack_argument:
; CHECK-NOT: memcpy
; CHECK: rep;movsq
; CHECK: callq consume
entry:
  %setup = call token @llvm.call.preallocated.setup(i32 1)
  %home = call ptr @llvm.call.preallocated.arg(token %setup, i32 0) preallocated(%large)
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %home, ptr align 8 %source,
                                  i64 320000, i1 false)
  call goabiinternal void @consume(ptr preallocated(%large) align 8 %home)
      ["preallocated"(token %setup)]
  ret void
}

define goabiinternal i64 @read_incoming_stack_argument(
    ptr preallocated(%large) align 8 %value) {
; CHECK-LABEL: read_incoming_stack_argument:
; CHECK: movq 8(%rsp), %rax
; CHECK-NEXT: retq
entry:
  %result = load i64, ptr %value, align 8
  ret i64 %result
}

; The Go ABI rejects arrays with length greater than one from register
; decomposition even when their element type is zero-sized. The preallocated
; carrier is authoritative; reconstructing the ABI from the remaining LLVM
; leaves alone would incorrectly assign this value to RBX.
define goabiinternal i64 @read_go_assigned_memory_argument(
    i8 %head, ptr preallocated(%go_memory) align 8 %value, i64 %tail) {
; CHECK-LABEL: read_go_assigned_memory_argument:
; CHECK: movq %rbx, %rax
; CHECK-NEXT: addq 8(%rsp), %rax
; CHECK-NEXT: retq
entry:
  %word = load i64, ptr %value, align 8
  %result = add i64 %word, %tail
  ret i64 %result
}

declare goabiinternal i64 @consume_go_assigned_memory_argument(
    i8, ptr preallocated(%go_memory) align 8, i64)

define goabiinternal i64 @pass_go_assigned_memory_argument(ptr %source) {
; CHECK-LABEL: pass_go_assigned_memory_argument:
; CHECK: leaq (%rsp), %rcx
; CHECK: movq {{.*}}, (%rcx)
; CHECK: movl $11, %ebx
; CHECK: movb $7, %al
; CHECK: callq consume_go_assigned_memory_argument
entry:
  %setup = call token @llvm.call.preallocated.setup(i32 1)
  %home = call ptr @llvm.call.preallocated.arg(token %setup, i32 0)
      preallocated(%go_memory)
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %home, ptr align 8 %source,
                                  i64 16, i1 false)
  %result = call goabiinternal i64 @consume_go_assigned_memory_argument(
      i8 7, ptr preallocated(%go_memory) align 8 %home, i64 11)
      ["preallocated"(token %setup)]
  ret i64 %result
}

define goabiinternal void @write_memory_result(
    ptr goret(%large) "goretindex"="0" align 8 %result) {
; CHECK-LABEL: write_memory_result:
; CHECK: movq $42, 8(%rsp)
; CHECK-NEXT: retq
entry:
  store i64 42, ptr %result, align 8
  ret void
}

define goabiinternal i64 @copy_large_memory_result() {
; CHECK-LABEL: copy_large_memory_result:
; CHECK-NOT: memcpy
; CHECK: callq write_memory_result
; CHECK: rep;movsq
entry:
  %result = alloca %large, align 8
  call goabiinternal void @write_memory_result(
      ptr goret(%large) "goretindex"="0" align 8 %result)
  %value = load i64, ptr %result, align 8
  ret i64 %value
}
