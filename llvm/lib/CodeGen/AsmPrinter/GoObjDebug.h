//===- GoObjDebug.h - Go object debug metadata handler ---------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_CODEGEN_ASMPRINTER_GOOBJDEBUG_H
#define LLVM_LIB_CODEGEN_ASMPRINTER_GOOBJDEBUG_H

#include <memory>

namespace llvm {

class AsmPrinter;
class AsmPrinterHandler;

std::unique_ptr<AsmPrinterHandler> createGoObjDebugHandler(AsmPrinter &Asm);

} // end namespace llvm

#endif // LLVM_LIB_CODEGEN_ASMPRINTER_GOOBJDEBUG_H
