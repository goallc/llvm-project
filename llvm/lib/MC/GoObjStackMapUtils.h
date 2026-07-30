//===- GoObjStackMapUtils.h - Go object stack-map helpers -------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_MC_GOOBJSTACKMAPUTILS_H
#define LLVM_LIB_MC_GOOBJSTACKMAPUTILS_H

#include <cstdint>

namespace llvm::goobj {

enum class StackMapSlotKind {
  Invalid,
  Direct,
  Args,
  Locals,
};

struct StackMapSlot {
  StackMapSlotKind Kind = StackMapSlotKind::Invalid;
  uint32_t Bit = 0;
};

inline StackMapSlot classifyOrdinaryStackMapSlot(
    int64_t Offset, bool IsIndirect, uint32_t PointerSize, uint64_t LocalsStart,
    uint64_t LocalsSize, uint64_t ArgsStart, uint64_t ArgsSize) {
  if (Offset < 0 || PointerSize == 0)
    return {};

  uint64_t UOffset = static_cast<uint64_t>(Offset);
  auto Classify = [&](uint64_t Start, uint64_t Size,
                      StackMapSlotKind Kind) -> StackMapSlot {
    if (UOffset < Start || UOffset - Start >= Size ||
        Size - (UOffset - Start) < PointerSize ||
        (UOffset - Start) % PointerSize != 0)
      return {};
    if (!IsIndirect)
      return {StackMapSlotKind::Direct, 0};
    return {Kind, static_cast<uint32_t>((UOffset - Start) / PointerSize)};
  };

  if (StackMapSlot Slot =
          Classify(LocalsStart, LocalsSize, StackMapSlotKind::Locals);
      Slot.Kind != StackMapSlotKind::Invalid)
    return Slot;
  return Classify(ArgsStart, ArgsSize, StackMapSlotKind::Args);
}

} // namespace llvm::goobj

#endif // LLVM_LIB_MC_GOOBJSTACKMAPUTILS_H
