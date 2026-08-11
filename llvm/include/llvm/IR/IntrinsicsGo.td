//===- IntrinsicsGo.td - Defines Go backend intrinsics -----*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file defines intrinsics used by the Go compiler and GoObj backend.
//
//===----------------------------------------------------------------------===//

// Model the out-of-band control-flow edge from a Go defer registration site to
// the function's deferreturn path. This intrinsic is only valid as the callee
// of a callbr with one indirect destination and emits no machine instruction.
def int_go_defer_edge : Intrinsic<[], [],
    [IntrNoMem, IntrHasSideEffects, IntrNoCallback, IntrNoSync, IntrNoFree,
     IntrNoDuplicate, IntrNoMerge]>;

// Return the base of the current Go ABI0 function's contiguous argument and
// result frame. The caller must be noinline because the returned address is
// tied to this physical activation record.
def int_go_abi0_frame : DefaultAttrsIntrinsic<[llvm_ptr_ty], [],
    [IntrNoMem, IntrNoCallback, IntrNoSync, IntrNoFree, IntrWillReturn]>;

// Observe the current physical address of a pointer. Go stack pointers may be
// relocated by a stack-growing call, so this operation is deliberately
// side-effecting even though it lowers to ptrtoint. Statepoint rewriting must
// relocate the pointer operand before lowering the observation.
def int_go_pointer_address : DefaultAttrsIntrinsic<
    [llvm_anyint_ty], [llvm_anyptr_ty],
    [IntrNoMem, IntrHasSideEffects, NoCapture<ArgIndex<0>>]>;

// Acquire Entries pointer-sized slots from the current P's Go write-barrier
// buffer.  This is deliberately an intrinsic rather than an ordinary call:
// the runtime entry point uses a private ABI and returns the buffer pointer in
// a target-specific fixed register.
//
// Do not narrow this to inaccessible memory.  In addition to updating runtime
// state, the operation orders the caller's stores to the returned buffer with
// the surrounding write-barrier sequence.  Likewise, do not give it the
// default nosync/nofree/willreturn attributes; the slow path may flush the
// buffer through the runtime.  The entry count is the number of pointer-sized
// slots and currently follows Go's 1..8 batching limit.
def int_go_gc_write_barrier : Intrinsic<
    [llvm_ptr_ty], [llvm_i32_ty],
    [IntrNoCallback, ImmArg<ArgIndex<0>>, Range<ArgIndex<0>, 1, 9>]>;

//===----------------------------------------------------------------------===//
// X86-specific Go intrinsics
//===----------------------------------------------------------------------===//

let TargetPrefix = "x86" in {
  // Divide the unsigned 128-bit integer (high, low) by divisor and return
  // (quotient, remainder). The divisor must be non-zero and high must be less
  // than divisor, so that both results fit in 64 bits. The intrinsic is not
  // speculatable because violating either precondition traps on X86.
  def int_x86_go_udivrem_i128_i64 :
      Intrinsic<[llvm_i64_ty, llvm_i64_ty],
                [llvm_i64_ty, llvm_i64_ty, llvm_i64_ty], [IntrNoMem]>;

  // Go's generic SSA keeps CPU-feature guards in the control-flow graph while
  // LLVM lowering happens before the target-specific Go SSA rewrites. This
  // intrinsic preserves the fact that the instruction is guarded, so X86
  // codegen may select it without enabling the feature for the whole function.
  def int_x86_go_sse41_round_f64
      : DefaultAttrsIntrinsic<[llvm_double_ty],
                              [llvm_double_ty, llvm_i32_ty],
                              [IntrNoMem, ImmArg<ArgIndex<1>>]>;

  // This is emitted only behind Go's runtime FMA feature check (or when
  // GOAMD64 already guarantees FMA).
  def int_x86_go_fma_f64
      : DefaultAttrsIntrinsic<[llvm_double_ty],
                              [llvm_double_ty, llvm_double_ty, llvm_double_ty],
                              [IntrNoMem]>;
}
