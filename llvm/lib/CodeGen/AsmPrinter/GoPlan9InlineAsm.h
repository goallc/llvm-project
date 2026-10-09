//===- GoPlan9InlineAsm.h - Deferred Go assembler bridge ----------*- C++
//-*-===//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#ifndef LLVM_LIB_CODEGEN_ASMPRINTER_GOPLAN9INLINEASM_H
#define LLVM_LIB_CODEGEN_ASMPRINTER_GOPLAN9INLINEASM_H
namespace llvm {
class AsmPrinter;
class Function;
class MachineInstr;
class MCContext;
class MCStreamer;
class MCSymbol;
bool emitGoPlan9InlineAsm(AsmPrinter &, const MachineInstr &, const Function &,
                          MCSymbol *, MCContext &, MCStreamer &);
} // namespace llvm
#endif
