# REQUIRES: x86-registered-target
# RUN: split-file %s %t
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj %t/cross.s -o %t/cross-off.o
# RUN: %python %S/Inputs/dump-goobj.py %t/cross-off.o | FileCheck %s --check-prefix=CROSS-OFF
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj -x86-branches-within-32B-boundaries %t/cross.s -o %t/cross-on.o
# RUN: %python %S/Inputs/dump-goobj.py %t/cross-on.o | FileCheck %s --check-prefix=CROSS-ON
# RUN: llvm-mc -triple=i386-unknown-linux-goobj -filetype=obj -x86-branches-within-32B-boundaries %t/cross.s -o %t/cross-32.o
# RUN: %python %S/Inputs/dump-goobj.py %t/cross-32.o | FileCheck %s --check-prefix=CROSS-ON
# RUN: llvm-mc -triple=x86_64-pc-windows-goobj -filetype=obj -x86-branches-within-32B-boundaries %t/cross.s -o %t/cross-windows.o
# RUN: %python %S/Inputs/dump-goobj.py %t/cross-windows.o | FileCheck %s --check-prefix=CROSS-ON
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj -x86-align-branch-boundary=32 -x86-align-branch=jcc %t/cross.s -o %t/cross-explicit.o
# RUN: %python %S/Inputs/dump-goobj.py %t/cross-explicit.o | FileCheck %s --check-prefix=CROSS-ON
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj %t/end.s -o %t/end-off.o
# RUN: %python %S/Inputs/dump-goobj.py %t/end-off.o | FileCheck %s --check-prefix=END-OFF
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj -x86-branches-within-32B-boundaries %t/end.s -o %t/end-on.o
# RUN: %python %S/Inputs/dump-goobj.py %t/end-on.o | FileCheck %s --check-prefix=END-ON
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -mcpu=haswell -filetype=obj %t/fused.s -o %t/fused-off.o
# RUN: %python %S/Inputs/dump-goobj.py %t/fused-off.o | FileCheck %s --check-prefix=FUSED-OFF
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -mcpu=haswell -filetype=obj -x86-branches-within-32B-boundaries %t/fused.s -o %t/fused-on.o
# RUN: %python %S/Inputs/dump-goobj.py %t/fused-on.o | FileCheck %s --check-prefix=FUSED-ON
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -mcpu=haswell -filetype=obj -x86-align-branch-boundary=32 -x86-align-branch=jcc %t/fused.s -o %t/fused-jcc.o
# RUN: %python %S/Inputs/dump-goobj.py %t/fused-jcc.o | FileCheck %s --check-prefix=FUSED-OFF
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj %t/jmp.s -o %t/jmp-off.o
# RUN: %python %S/Inputs/dump-goobj.py %t/jmp-off.o | FileCheck %s --check-prefix=JMP-OFF
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj -x86-branches-within-32B-boundaries %t/jmp.s -o %t/jmp-on.o
# RUN: %python %S/Inputs/dump-goobj.py %t/jmp-on.o | FileCheck %s --check-prefix=JMP-ON
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj -x86-align-branch-boundary=32 -x86-align-branch=jcc %t/jmp.s -o %t/jmp-jcc.o
# RUN: %python %S/Inputs/dump-goobj.py %t/jmp-jcc.o | FileCheck %s --check-prefix=JMP-OFF
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj %t/safe.s -o %t/safe-off.o
# RUN: %python %S/Inputs/dump-goobj.py %t/safe-off.o | FileCheck %s --check-prefix=SAFE
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj -x86-branches-within-32B-boundaries %t/safe.s -o %t/safe-on.o
# RUN: %python %S/Inputs/dump-goobj.py %t/safe-on.o | FileCheck %s --check-prefix=SAFE

# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj %t/multiple.s -o %t/multiple-off.o
# RUN: %python %S/Inputs/dump-goobj.py %t/multiple-off.o | FileCheck %s --check-prefix=MULTIPLE-OFF
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj -x86-branches-within-32B-boundaries %t/multiple.s -o %t/multiple.o
# RUN: %python %S/Inputs/dump-goobj.py %t/multiple.o | FileCheck %s --check-prefix=MULTIPLE
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj -x86-align-branch-boundary=64 -x86-align-branch=jcc %t/multiple.s -o %t/multiple64.o
# RUN: %python %S/Inputs/dump-goobj.py %t/multiple64.o | FileCheck %s --check-prefix=MULTIPLE64

# A two-byte backedge at byte 31 crosses the boundary. Its displacement
# must account for padding. At byte 30 a branch ends exactly on the boundary,
# which must also be avoided.
# CROSS-OFF: nonpkgdef 0: probe abi=0 type=1 size=34
# CROSS-OFF: data: {{(90){31}75dfc3}}
# CROSS-ON: nonpkgdef 0: probe abi=0 type=1 size=35 align=32
# CROSS-ON: data: {{(90){32}75dec3}}
# END-OFF: nonpkgdef 0: probe abi=0 type=1 size=33
# END-OFF: data: {{(90){30}7500c3}}
# END-ON: nonpkgdef 0: probe abi=0 type=1 size=35
# END-ON: data: {{(90){30}66907500c3}}

# The branch alone fits at byte 32. Only the fused CMP/Jcc pair crosses.
# FUSED-OFF: nonpkgdef 0: probe abi=0 type=1 size=35
# FUSED-OFF: data: {{(90){29}4839c37400c3}}
# FUSED-ON: nonpkgdef 0: probe abi=0 type=1 size=38
# FUSED-ON: data: {{(90){29}0f1f004839c37400c3}}

# Respect the requested branch kinds: jcc-only must not move this JMP.
# JMP-OFF: nonpkgdef 0: probe abi=0 type=1 size=34
# JMP-OFF: data: {{(90){31}eb00c3}}
# JMP-ON: nonpkgdef 0: probe abi=0 type=1 size=35
# JMP-ON: data: {{(90){32}eb00c3}}

# A branch ending at byte 31 needs no padding in either mode.
# SAFE: nonpkgdef 0: probe abi=0 type=1 size=32
# SAFE: data: {{(90){29}7500c3}}

#--- cross.s
.text
.globl probe
probe:
1:
.rept 31
  nop
.endr
  jne 1b
  ret

#--- end.s
.text
.globl probe
probe:
.rept 30
  nop
.endr
  jne 1f
1:
  ret

#--- fused.s
.text
.globl probe
probe:
.rept 29
  nop
.endr
  cmpq %rax, %rbx
  je 1f
1:
  ret

#--- jmp.s
.text
.globl probe
probe:
.rept 31
  nop
.endr
  jmp 1f
1:
  ret

#--- safe.s
.text
.globl probe
probe:
.rept 29
  nop
.endr
  jne 1f
1:
  ret

# Each named text symbol is placed independently by the Go linker. The second
# symbol must start on the boundary in MC layout and carry that alignment into
# GoObj, even when the first symbol would leave it at an unaligned offset.
# MULTIPLE-OFF: nonpkgdef 0: first abi=0 type=1 size=1 align=0
# MULTIPLE-OFF: nonpkgdef 1: second abi=0 type=1 size=34 align=0
# MULTIPLE-OFF: data: {{c3(90){31}75dfc3}}
# MULTIPLE: nonpkgdef 0: first abi=0 type=1 size=32 align=32
# MULTIPLE: nonpkgdef 1: second abi=0 type=1 size=35 align=32
# MULTIPLE: data: {{c3[0-9a-f]{62}(90){32}75dec3}}
# MULTIPLE64: nonpkgdef 0: first abi=0 type=1 size=64 align=64
# MULTIPLE64: nonpkgdef 1: second abi=0 type=1 size=34 align=64
# MULTIPLE64: data: {{c3.*(90){31}75dfc3}}

#--- multiple.s
.text
.globl first
first:
  ret
.globl second
second:
1:
.rept 31
  nop
.endr
  jne 1b
  ret
