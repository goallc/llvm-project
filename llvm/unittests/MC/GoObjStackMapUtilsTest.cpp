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

TEST(GoObjStackMapUtilsTest, ExpandsIndirectPointerVectorLocations) {
  auto Words = goobj::expandStackMapPointerWords(
      /*Offset=*/24, /*Size=*/16, /*IsIndirect=*/true, /*PointerSize=*/8);
  ASSERT_TRUE(Words);
  EXPECT_EQ(*Words, (SmallVector<int64_t, 4>{24, 32}));
}

TEST(GoObjStackMapUtilsTest, RejectsInvalidPointerVectorLocations) {
  EXPECT_FALSE(goobj::expandStackMapPointerWords(
      /*Offset=*/24, /*Size=*/12, /*IsIndirect=*/true, /*PointerSize=*/8));
  EXPECT_FALSE(goobj::expandStackMapPointerWords(
      /*Offset=*/24, /*Size=*/16, /*IsIndirect=*/false, /*PointerSize=*/8));
  EXPECT_FALSE(goobj::expandStackMapPointerWords(
      /*Offset=*/std::numeric_limits<int64_t>::max(), /*Size=*/16,
      /*IsIndirect=*/true, /*PointerSize=*/8));
}

TEST(GoObjStackMapUtilsTest, ClassifiesEveryPointerVectorWord) {
  auto Locals = goobj::expandStackMapPointerWords(
      /*Offset=*/8, /*Size=*/16, /*IsIndirect=*/true, /*PointerSize=*/8);
  ASSERT_TRUE(Locals);
  for (auto [Index, Offset] : llvm::enumerate(*Locals)) {
    goobj::StackMapSlot Slot = goobj::classifyOrdinaryStackMapSlot(
        Offset, /*IsIndirect=*/true, /*PointerSize=*/8, /*LocalsStart=*/8,
        /*LocalsSize=*/32, /*LocalsBitOffset=*/0, /*ArgsStart=*/56,
        /*ArgsSize=*/40);
    EXPECT_EQ(Slot.Kind, goobj::StackMapSlotKind::Locals);
    EXPECT_EQ(Slot.Bit, Index);
  }

  auto Args = goobj::expandStackMapPointerWords(
      /*Offset=*/56, /*Size=*/16, /*IsIndirect=*/true, /*PointerSize=*/8);
  ASSERT_TRUE(Args);
  for (auto [Index, Offset] : llvm::enumerate(*Args)) {
    goobj::StackMapSlot Slot = goobj::classifyOrdinaryStackMapSlot(
        Offset, /*IsIndirect=*/true, /*PointerSize=*/8, /*LocalsStart=*/8,
        /*LocalsSize=*/32, /*LocalsBitOffset=*/0, /*ArgsStart=*/56,
        /*ArgsSize=*/40);
    EXPECT_EQ(Slot.Kind, goobj::StackMapSlotKind::Args);
    EXPECT_EQ(Slot.Bit, Index);
  }
}

TEST(GoObjStackMapUtilsTest, RejectsInvalidVectorWordPlacement) {
  auto Unaligned = goobj::expandStackMapPointerWords(
      /*Offset=*/12, /*Size=*/16, /*IsIndirect=*/true, /*PointerSize=*/8);
  ASSERT_TRUE(Unaligned);
  for (int64_t Offset : *Unaligned)
    EXPECT_EQ(goobj::classifyOrdinaryStackMapSlot(
                  Offset, /*IsIndirect=*/true, /*PointerSize=*/8,
                  /*LocalsStart=*/8, /*LocalsSize=*/32,
                  /*LocalsBitOffset=*/0, /*ArgsStart=*/56, /*ArgsSize=*/40)
                  .Kind,
              goobj::StackMapSlotKind::Invalid);

  auto OutOfBounds = goobj::expandStackMapPointerWords(
      /*Offset=*/88, /*Size=*/16, /*IsIndirect=*/true, /*PointerSize=*/8);
  ASSERT_TRUE(OutOfBounds);
  EXPECT_EQ(goobj::classifyOrdinaryStackMapSlot(
                (*OutOfBounds)[0], /*IsIndirect=*/true, /*PointerSize=*/8,
                /*LocalsStart=*/8, /*LocalsSize=*/32,
                /*LocalsBitOffset=*/0, /*ArgsStart=*/56, /*ArgsSize=*/40)
                .Kind,
            goobj::StackMapSlotKind::Args);
  EXPECT_EQ(goobj::classifyOrdinaryStackMapSlot(
                (*OutOfBounds)[1], /*IsIndirect=*/true, /*PointerSize=*/8,
                /*LocalsStart=*/8, /*LocalsSize=*/32,
                /*LocalsBitOffset=*/0, /*ArgsStart=*/56, /*ArgsSize=*/40)
                .Kind,
            goobj::StackMapSlotKind::Invalid);
}

TEST(GoObjStackMapUtilsTest, ClassifiesStackGrowthPointerVectorWords) {
  auto Words = goobj::expandStackMapPointerWords(
      /*Offset=*/64, /*Size=*/16, /*IsIndirect=*/true, /*PointerSize=*/8);
  ASSERT_TRUE(Words);
  EXPECT_EQ(goobj::classifyStackGrowthStackMapSlot(
                (*Words)[0], /*PointerSize=*/8, /*ArgsStart=*/64,
                /*ArgsSize=*/16),
            0u);
  EXPECT_EQ(goobj::classifyStackGrowthStackMapSlot(
                (*Words)[1], /*PointerSize=*/8, /*ArgsStart=*/64,
                /*ArgsSize=*/16),
            1u);
  EXPECT_FALSE(goobj::classifyStackGrowthStackMapSlot(
      /*Offset=*/68, /*PointerSize=*/8, /*ArgsStart=*/64, /*ArgsSize=*/16));
  EXPECT_FALSE(goobj::classifyStackGrowthStackMapSlot(
      /*Offset=*/80, /*PointerSize=*/8, /*ArgsStart=*/64, /*ArgsSize=*/16));
}

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

TEST(GoObjStackMapUtilsTest, ClassifiesCompleteAllocaFrameRegions) {
  auto Classify = [](int64_t Offset, uint64_t Size) {
    return goobj::classifyOrdinaryStackMapRange(
        Offset, Size, /*PointerSize=*/8, /*LocalsStart=*/8,
        /*LocalsSize=*/32, /*LocalsBitOffset=*/0, /*ArgsStart=*/56,
        /*ArgsSize=*/40);
  };

  EXPECT_EQ(Classify(8, 32), goobj::StackMapSlotKind::Locals);
  EXPECT_EQ(Classify(56, 40), goobj::StackMapSlotKind::Args);
  EXPECT_FALSE(Classify(32, 32));
  EXPECT_FALSE(Classify(88, 16));
  EXPECT_FALSE(Classify(12, 8));
  EXPECT_FALSE(Classify(56, 12));
}

TEST(GoObjStackMapUtilsTest, ComputesNativeGoStackObjectOffsets) {
  constexpr uint64_t VarpOffset = 40;
  constexpr uint64_t ArgsStart = 56;

  EXPECT_EQ(goobj::getStackObjectFrameOffset(goobj::StackMapSlotKind::Locals,
                                             /*BaseOffset=*/8, VarpOffset,
                                             ArgsStart),
            -32);
  EXPECT_EQ(goobj::getStackObjectFrameOffset(goobj::StackMapSlotKind::Args,
                                             /*BaseOffset=*/56, VarpOffset,
                                             ArgsStart),
            0);
  EXPECT_EQ(goobj::getStackObjectFrameOffset(goobj::StackMapSlotKind::Args,
                                             /*BaseOffset=*/80, VarpOffset,
                                             ArgsStart),
            24);
  EXPECT_FALSE(goobj::getStackObjectFrameOffset(goobj::StackMapSlotKind::Locals,
                                                /*BaseOffset=*/40, VarpOffset,
                                                ArgsStart));
  EXPECT_FALSE(goobj::getStackObjectFrameOffset(
      goobj::StackMapSlotKind::Args, /*BaseOffset=*/48, VarpOffset, ArgsStart));
}

} // namespace
