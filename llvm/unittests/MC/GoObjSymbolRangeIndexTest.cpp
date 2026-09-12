//===- GoObjSymbolRangeIndexTest.cpp
//---------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "../../lib/MC/GoObjSymbolRangeIndex.h"
#include "gtest/gtest.h"
#include <limits>
#include <random>

using namespace llvm;

TEST(GoObjSymbolRangeIndexTest, BoundariesAndPriority) {
  GoObjSymbolRangeIndex Index;
  // Symbols deliberately arrive out of address and priority order.
  Index.add(nullptr, 20, 40, 3);
  Index.add(nullptr, 10, 30, 2);
  Index.add(nullptr, 15, 25, 0);
  Index.add(nullptr, 15, 25, 1);
  Index.add(nullptr, 40, 40, 4);
  Index.add(nullptr, 50, std::numeric_limits<uint64_t>::max(), 5);
  Index.build();
  EXPECT_EQ(Index.find(nullptr, 9), std::nullopt);
  EXPECT_EQ(Index.find(nullptr, 10), 2u);
  EXPECT_EQ(Index.find(nullptr, 14), 2u);
  EXPECT_EQ(Index.find(nullptr, 15), 0u);
  EXPECT_EQ(Index.find(nullptr, 24), 0u);
  EXPECT_EQ(Index.find(nullptr, 25), 2u);
  EXPECT_EQ(Index.find(nullptr, 30), 3u);
  EXPECT_EQ(Index.find(nullptr, 39), 3u);
  EXPECT_EQ(Index.find(nullptr, 40), std::nullopt);
  EXPECT_EQ(Index.find(nullptr, 49), std::nullopt);
  EXPECT_EQ(Index.find(nullptr, 50), 5u);
  EXPECT_EQ(Index.find(nullptr, std::numeric_limits<uint64_t>::max() - 1), 5u);
  EXPECT_EQ(Index.find(nullptr, std::numeric_limits<uint64_t>::max()),
            std::nullopt);
}

TEST(GoObjSymbolRangeIndexTest, MatchesLinearLookup) {
  struct Symbol {
    const MCSection *Section;
    uint64_t Begin, End;
  };
  // Identity-only keys, never dereferenced by the index.
  int SectionStorage[3];
  const MCSection *Sections[] = {
      nullptr, reinterpret_cast<const MCSection *>(&SectionStorage[0]),
      reinterpret_cast<const MCSection *>(&SectionStorage[1]),
      reinterpret_cast<const MCSection *>(&SectionStorage[2])};
  std::mt19937 Random(0);
  for (unsigned Trial = 0; Trial < 100; ++Trial) {
    GoObjSymbolRangeIndex Index;
    std::vector<Symbol> Symbols;
    for (unsigned I = 0; I < 100; ++I) {
      uint64_t Begin = Random() % 256;
      Symbols.push_back({Sections[Random() % 3], Begin, Begin + Random() % 64});
      const auto &S = Symbols.back();
      Index.add(S.Section, S.Begin, S.End, I);
    }
    Index.build();
    for (const auto *Section : Sections) {
      for (uint64_t Offset = 0; Offset < 320; ++Offset) {
        std::optional<uint32_t> Expected;
        for (uint32_t I = 0; I < Symbols.size(); ++I) {
          const auto &S = Symbols[I];
          if (S.Section == Section && S.Begin <= Offset && Offset < S.End) {
            Expected = I;
            break;
          }
        }
        ASSERT_EQ(Index.find(Section, Offset), Expected)
            << "trial " << Trial << " offset " << Offset;
      }
    }
  }
}
