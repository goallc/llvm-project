//===- GoObjIdentity.h - Stable LLVM names for Go symbols -------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// LLVM names separate package-owned definitions during LTO. The GoObj writer
// decodes explicitly marked names; the native object format remains unchanged.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_BINARYFORMAT_GOOBJIDENTITY_H
#define LLVM_BINARYFORMAT_GOOBJIDENTITY_H

#include "llvm/ADT/StringExtras.h"

#include <cstdint>
#include <optional>
#include <string>

namespace llvm::GoObj {

inline std::string encodeLLVMIdentity(StringRef Name, StringRef Owner,
                                      std::optional<uint32_t> Index) {
  return "__goid$v1$" + toHex(Owner) + "$" +
         (Index ? "p" + utostr(*Index) : "n") + "$" + Name.str();
}
// Empty means invalid. Decode only symbols explicitly marked with version 1.
inline StringRef decodeLLVMIdentity(StringRef Name) {
  if (!Name.consume_front("__goid$v1$"))
    return {};
  auto [Owner, Rest] = Name.split('$');
  auto [Slot, Native] = Rest.split('$');
  if (Owner.empty() || Owner.size() % 2 || Native.empty() ||
      !llvm::all_of(Owner, [](char C) { return isHexDigit(C); }))
    return {};
  if (Slot != "n" && Slot != "r") {
    uint32_t Index;
    if (!Slot.consume_front("p") || Slot.empty() ||
        Slot.getAsInteger(10, Index) || utostr(Index) != Slot)
      return {};
  }
  return Native;
}

} // namespace llvm::GoObj

#endif // LLVM_BINARYFORMAT_GOOBJIDENTITY_H
