# REQUIRES: x86-registered-target
# RUN: llvm-mc -triple=x86_64-unknown-linux-goobj -filetype=obj %s -o %t
# RUN: %python %S/Inputs/dump-goobj.py %t | FileCheck %s

.goobj.assembly
.text
.globl test
test:
.Lbegin:
  nop
.Lbody:
  retq
.Lend:
.goobj.asmfunc test, 0, 0, 0, 0, 10
.goobj.asmdebug test, 5, 0, 1, "input.s"
.goobj.asmpc test, .Lbegin, -2, 10, "input.s"
.goobj.asmline test, .Lbegin, 10, 1, "input.s"
.goobj.asmline test, .Lbody, 11, 2, "input.s"

# CHECK-DAG: file 0: input.s
# CHECK-DAG: type=dwarf_info
# CHECK-DAG: type=dwarf_lines
# CHECK-DAG: type=106 add=0 target=test kind=R_DWTXTADDR_U4
# CHECK-DAG: type=1 add=0 target=test kind=R_ADDR
