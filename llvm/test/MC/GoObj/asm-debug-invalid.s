# REQUIRES: x86-registered-target
# RUN: not llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t 2>&1 | FileCheck %s
.goobj.asmdebug test, 3, 0, 1, "input.s"
# CHECK: invalid GoObj assembly debug metadata
