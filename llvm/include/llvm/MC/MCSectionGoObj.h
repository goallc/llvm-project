//===- MCSectionGoObj.h - Go object machine code sections -------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_MC_MCSECTIONGOOBJ_H
#define LLVM_MC_MCSECTIONGOOBJ_H

#include "llvm/MC/MCSection.h"

namespace llvm {

class MCSymbol;

class MCSectionGoObj final : public MCSection {
  friend class MCContext;

  SectionKind Kind;

  MCSectionGoObj(StringRef Name, SectionKind K, MCSymbol *Begin)
      : MCSection(Name, K.isText(), K.isBSS(), Begin), Kind(K) {}

public:
  SectionKind getKind() const { return Kind; }
};

} // end namespace llvm

#endif // LLVM_MC_MCSECTIONGOOBJ_H
