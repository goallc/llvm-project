//===- GoObjStackMapUtils.h - Go object stack-map helpers -------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_MC_GOOBJSTACKMAPUTILS_H
#define LLVM_LIB_MC_GOOBJSTACKMAPUTILS_H

#include "llvm/ADT/SmallVector.h"
#include <cstdint>
#include <limits>
#include <optional>

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

inline std::optional<SmallVector<int64_t, 4>>
expandStackMapPointerWords(int64_t Offset, uint16_t Size, bool IsIndirect,
                           uint32_t PointerSize) {
  // A fixed vector of GC pointers is one indirect StackMaps location whose
  // size covers every lane. Go pointer maps describe pointer-sized stack
  // words, so expand that location without losing the vector at the IR or
  // machine-statepoint layers. A direct location still denotes one address
  // value and must remain pointer-sized.
  if (!Size || !PointerSize || Size % PointerSize != 0 ||
      (!IsIndirect && Size != PointerSize))
    return std::nullopt;

  SmallVector<int64_t, 4> WordOffsets;
  WordOffsets.reserve(Size / PointerSize);
  for (uint64_t Word = 0; Word != Size / PointerSize; ++Word) {
    uint64_t ByteOffset = Word * PointerSize;
    if (Offset >
        std::numeric_limits<int64_t>::max() - static_cast<int64_t>(ByteOffset))
      return std::nullopt;
    WordOffsets.push_back(Offset + static_cast<int64_t>(ByteOffset));
  }
  return WordOffsets;
}

inline std::optional<uint32_t>
classifyStackGrowthStackMapSlot(int64_t Offset, uint32_t PointerSize,
                                uint64_t ArgsStart, uint64_t ArgsSize) {
  if (Offset < 0 || !PointerSize)
    return std::nullopt;
  uint64_t UOffset = static_cast<uint64_t>(Offset);
  if (UOffset < ArgsStart || UOffset - ArgsStart >= ArgsSize ||
      ArgsSize - (UOffset - ArgsStart) < PointerSize ||
      (UOffset - ArgsStart) % PointerSize != 0)
    return std::nullopt;
  return static_cast<uint32_t>((UOffset - ArgsStart) / PointerSize);
}

inline StackMapSlot
classifyOrdinaryStackMapSlot(int64_t Offset, bool IsIndirect,
                             uint32_t PointerSize, uint64_t LocalsStart,
                             uint64_t LocalsSize, uint32_t LocalsBitOffset,
                             uint64_t ArgsStart, uint64_t ArgsSize) {
  if (Offset < 0 || PointerSize == 0)
    return {};

  uint64_t UOffset = static_cast<uint64_t>(Offset);
  auto ContainsAddress = [&](uint64_t Start, uint64_t Size) {
    return UOffset >= Start && UOffset - Start < Size;
  };
  if (!IsIndirect) {
    if (ContainsAddress(LocalsStart, LocalsSize) ||
        ContainsAddress(ArgsStart, ArgsSize))
      return {StackMapSlotKind::Direct, 0};
    return {};
  }

  auto Classify = [&](uint64_t Start, uint64_t Size, StackMapSlotKind Kind,
                      uint32_t BitOffset) -> StackMapSlot {
    if (UOffset < Start || UOffset - Start >= Size ||
        Size - (UOffset - Start) < PointerSize ||
        (UOffset - Start) % PointerSize != 0)
      return {};
    return {Kind,
            BitOffset + static_cast<uint32_t>((UOffset - Start) / PointerSize)};
  };

  if (StackMapSlot Slot = Classify(LocalsStart, LocalsSize,
                                   StackMapSlotKind::Locals, LocalsBitOffset);
      Slot.Kind != StackMapSlotKind::Invalid)
    return Slot;
  return Classify(ArgsStart, ArgsSize, StackMapSlotKind::Args,
                  /*BitOffset=*/0);
}

} // namespace llvm::goobj

#endif // LLVM_LIB_MC_GOOBJSTACKMAPUTILS_H
