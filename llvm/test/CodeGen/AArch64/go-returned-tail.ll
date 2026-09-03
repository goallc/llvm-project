; RUN: llc -mtriple=aarch64-unknown-linux-goobj -O2 -stop-before=prolog-epilog -o - < %s | FileCheck %s --check-prefix=MIR
; RUN: llc -mtriple=aarch64-unknown-linux-goobj -O2 -o - < %s | FileCheck %s --check-prefix=ASM

@features = external global i64
@slot = external global ptr

declare goabiinternal i64 @baseline(i64 returned, ptr nest)
declare goabiinternal i64 @feature(i64 returned, ptr nest)

define goabiinternal i64 @resolver(i64 %value, ptr nest %closure) #0 {
; MIR-LABEL: name: resolver
; MIR-NOT:   hasStackFrame: true
; MIR:       TCRETURNdi @baseline, 0, csr_aarch64_go_thisreturn
; MIR:       TCRETURNri {{.*}}, 0, csr_aarch64_go,
;
; ASM-LABEL: resolver:
; ASM-NOT:   stp x29, x30
; ASM:       br x{{[0-9]+}}
; ASM:       b baseline
entry:
  %bits = load i64, ptr @features
  %initialized = icmp ne i64 %bits, 0
  br i1 %initialized, label %select, label %uninitialized

uninitialized:
  %base = musttail call goabiinternal i64 @baseline(
      i64 %value, ptr nest %closure) #1
  ret i64 %base

select:
  %hasfeature = icmp ugt i64 %bits, 1
  %callee = select i1 %hasfeature, ptr @feature, ptr @baseline
  store ptr %callee, ptr @slot
  %selected = musttail call goabiinternal i64 %callee(
      i64 %value, ptr nest %closure)
  ret i64 %selected
}

attributes #0 = { noinline "go-nosplit" }
attributes #1 = { noinline }
