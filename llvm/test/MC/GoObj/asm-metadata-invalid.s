# REQUIRES: x86-registered-target
# RUN: not llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t 2>&1 | FileCheck %s
# CHECK: error: invalid GoObj assembly PC event
.goobj.asmpc foo, label, 65536, 0
