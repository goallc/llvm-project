//===- MCSymbolGoObj.h - Go object symbols ------------------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_MC_MCSYMBOLGOOBJ_H
#define LLVM_MC_MCSYMBOLGOOBJ_H

#include "llvm/MC/MCSymbol.h"
#include <optional>

namespace llvm {

class MCSymbolGoObj : public MCSymbol {
  std::optional<uint16_t> GoABI;

public:
  MCSymbolGoObj(const MCSymbolTableEntry *Name, bool IsTemporary)
      : MCSymbol(Name, IsTemporary) {}

  bool isExternal() const { return IsExternal; }
  void setExternal(bool Value) { IsExternal = Value; }

  std::optional<uint16_t> getGoABI() const { return GoABI; }
  void setGoABI(uint16_t ABI) { GoABI = ABI; }
};

} // end namespace llvm

#endif // LLVM_MC_MCSYMBOLGOOBJ_H
