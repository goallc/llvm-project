; RUN: not llc -mtriple=x86_64-unknown-linux-goobj -filetype=obj %s -o /dev/null 2>&1 | FileCheck %s
; A carrier may travel through opt/bitcode without the Go runtime. Actual
; materialization requires an assembler registered on the codegen thread.
; CHECK: Plan 9 inline assembly: no Go assembler registered by the codegen driver

define goabiinternal void @plan9() naked noinline "go-plan9-context"="{}" {
  call void asm sideeffect "MOVQ $42, AX\0ARET\0A", ""()
  unreachable
}
