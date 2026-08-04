//===- GoObjStackMapUtilsTest.cpp -----------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "../../lib/MC/GoObjStackMapUtils.h"
#include "gtest/gtest.h"

using namespace llvm;

namespace {

TEST(GoObjStackMapUtilsTest, ClassifiesLocalsAndArgs) {
  constexpr uint32_t PointerSize = 8;
  constexpr uint64_t LocalsStart = 8;
  constexpr uint64_t LocalsSize = 32;
  constexpr uint64_t ArgsStart = 56;
  constexpr uint64_t ArgsSize = 40;

  auto Classify = [&](int64_t Offset, bool IsIndirect) {
    return goobj::classifyOrdinaryStackMapSlot(Offset, IsIndirect, PointerSize,
                                               LocalsStart, LocalsSize, 0,
                                               ArgsStart, ArgsSize);
  };

  EXPECT_EQ(Classify(8, true).Kind, goobj::StackMapSlotKind::Locals);
  EXPECT_EQ(Classify(8, true).Bit, 0u);
  EXPECT_EQ(Classify(32, true).Kind, goobj::StackMapSlotKind::Locals);
  EXPECT_EQ(Classify(32, true).Bit, 3u);

  EXPECT_EQ(Classify(56, true).Kind, goobj::StackMapSlotKind::Args);
  EXPECT_EQ(Classify(56, true).Bit, 0u);
  EXPECT_EQ(Classify(64, true).Kind, goobj::StackMapSlotKind::Args);
  EXPECT_EQ(Classify(64, true).Bit, 1u);
  EXPECT_EQ(Classify(72, true).Kind, goobj::StackMapSlotKind::Args);
  EXPECT_EQ(Classify(72, true).Bit, 2u);

  EXPECT_EQ(Classify(16, false).Kind, goobj::StackMapSlotKind::Direct);
  EXPECT_EQ(Classify(64, false).Kind, goobj::StackMapSlotKind::Direct);
}

TEST(GoObjStackMapUtilsTest, AcceptsUnalignedDirectFrameAddresses) {
  auto Classify = [](int64_t Offset) {
    return goobj::classifyOrdinaryStackMapSlot(
        Offset, false, /*PointerSize=*/8, /*LocalsStart=*/8,
        /*LocalsSize=*/32, /*LocalsBitOffset=*/0, /*ArgsStart=*/56,
        /*ArgsSize=*/40);
  };

  EXPECT_EQ(Classify(12).Kind, goobj::StackMapSlotKind::Direct);
  EXPECT_EQ(Classify(39).Kind, goobj::StackMapSlotKind::Direct);
  EXPECT_EQ(Classify(60).Kind, goobj::StackMapSlotKind::Direct);
  EXPECT_EQ(Classify(0).Kind, goobj::StackMapSlotKind::Invalid);
  EXPECT_EQ(Classify(40).Kind, goobj::StackMapSlotKind::Invalid);
  EXPECT_EQ(Classify(52).Kind, goobj::StackMapSlotKind::Invalid);
  EXPECT_EQ(Classify(96).Kind, goobj::StackMapSlotKind::Invalid);
}

TEST(GoObjStackMapUtilsTest, RejectsReservedUnalignedAndOutOfRangeSlots) {
  auto Classify = [](int64_t Offset) {
    return goobj::classifyOrdinaryStackMapSlot(
        Offset, true, /*PointerSize=*/8, /*LocalsStart=*/8,
        /*LocalsSize=*/32, /*LocalsBitOffset=*/0, /*ArgsStart=*/56,
        /*ArgsSize=*/40);
  };

  EXPECT_EQ(Classify(-8).Kind, goobj::StackMapSlotKind::Invalid);
  EXPECT_EQ(Classify(0).Kind, goobj::StackMapSlotKind::Invalid);
  EXPECT_EQ(Classify(12).Kind, goobj::StackMapSlotKind::Invalid);
  EXPECT_EQ(Classify(40).Kind, goobj::StackMapSlotKind::Invalid);
  EXPECT_EQ(Classify(52).Kind, goobj::StackMapSlotKind::Invalid);
  EXPECT_EQ(Classify(96).Kind, goobj::StackMapSlotKind::Invalid);
}

TEST(GoObjStackMapUtilsTest, AppliesX86LocalsCallSlotBias) {
  auto Classify = [](int64_t Offset) {
    return goobj::classifyOrdinaryStackMapSlot(
        Offset, true, /*PointerSize=*/8, /*LocalsStart=*/0,
        /*LocalsSize=*/32, /*LocalsBitOffset=*/1, /*ArgsStart=*/48,
        /*ArgsSize=*/16);
  };

  EXPECT_EQ(Classify(0).Kind, goobj::StackMapSlotKind::Locals);
  EXPECT_EQ(Classify(0).Bit, 1u);
  EXPECT_EQ(Classify(24).Kind, goobj::StackMapSlotKind::Locals);
  EXPECT_EQ(Classify(24).Bit, 4u);
  EXPECT_EQ(Classify(32).Kind, goobj::StackMapSlotKind::Invalid);
}

} // namespace
