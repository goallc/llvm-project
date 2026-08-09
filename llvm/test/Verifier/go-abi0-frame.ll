; RUN: split-file %s %t
; RUN: opt -passes=verify -disable-output %t/valid.ll
; RUN: not opt -passes=verify -disable-output %t/wrong-cc.ll 2>&1 | \
; RUN:   FileCheck %s --check-prefix=WRONG-CC
; RUN: not opt -passes=verify -disable-output %t/may-inline.ll 2>&1 | \
; RUN:   FileCheck %s --check-prefix=MAY-INLINE

;--- valid.ll
declare ptr @llvm.go.abi0.frame()

define goabi0 ptr @valid() noinline {
  %frame = call ptr @llvm.go.abi0.frame()
  ret ptr %frame
}

;--- wrong-cc.ll
declare ptr @llvm.go.abi0.frame()

define goabiinternal ptr @wrong_cc() noinline {
  %frame = call ptr @llvm.go.abi0.frame()
  ret ptr %frame
}

; WRONG-CC: llvm.go.abi0.frame requires a goabi0 function

;--- may-inline.ll
declare ptr @llvm.go.abi0.frame()

define goabi0 ptr @may_inline() {
  %frame = call ptr @llvm.go.abi0.frame()
  ret ptr %frame
}

; MAY-INLINE: llvm.go.abi0.frame requires a noinline function
