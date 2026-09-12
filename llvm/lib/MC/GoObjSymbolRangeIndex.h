//===- GoObjSymbolRangeIndex.h - Go object symbol ranges ----------*- C++
//-*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_MC_GOOBJSYMBOLRANGEINDEX_H
#define LLVM_LIB_MC_GOOBJSYMBOLRANGEINDEX_H

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include <cstdint>
#include <optional>
#include <set>
#include <vector>

namespace llvm {
class MCSection;

/// Resolve half-open section ranges to the first containing symbol in the
/// original symbol table. Overlapping ranges and aliases retain that priority.
/// Construction takes O(S log S); each relocation lookup takes O(log S).
class GoObjSymbolRangeIndex {
  struct Event {
    uint64_t Offset;
    uint32_t Symbol;
    bool Start;
  };
  struct Range {
    uint64_t Begin, End;
    uint32_t Symbol;
  };
  DenseMap<const MCSection *, std::vector<Event>> Events;
  DenseMap<const MCSection *, std::vector<Range>> Ranges;

public:
  void add(const MCSection *Section, uint64_t Begin, uint64_t End,
           uint32_t Symbol) {
    if (Begin >= End)
      return;
    auto &E = Events[Section];
    E.push_back({Begin, Symbol, true});
    E.push_back({End, Symbol, false});
  }

  void build() {
    Ranges.clear();
    for (auto &[Section, E] : Events) {
      llvm::sort(E, [](const Event &A, const Event &B) {
        return A.Offset < B.Offset;
      });
      auto &R = Ranges[Section];
      std::set<uint32_t> Active;
      for (size_t I = 0; I < E.size();) {
        uint64_t Begin = E[I].Offset;
        do {
          if (E[I].Start)
            Active.insert(E[I].Symbol);
          else
            Active.erase(E[I].Symbol);
          ++I;
        } while (I < E.size() && E[I].Offset == Begin);
        if (I == E.size() || Active.empty())
          continue;
        uint64_t End = E[I].Offset;
        uint32_t Symbol = *Active.begin();
        if (!R.empty() && R.back().End == Begin && R.back().Symbol == Symbol)
          R.back().End = End;
        else
          R.push_back({Begin, End, Symbol});
      }
    }
    Events.clear();
  }

  std::optional<uint32_t> find(const MCSection *Section,
                               uint64_t Offset) const {
    auto It = Ranges.find(Section);
    if (It == Ranges.end())
      return std::nullopt;
    const auto &R = It->second;
    auto Upper =
        llvm::upper_bound(R, Offset, [](uint64_t O, const Range &Entry) {
          return O < Entry.Begin;
        });
    if (Upper == R.begin())
      return std::nullopt;
    const Range &Entry = *std::prev(Upper);
    if (Offset < Entry.End)
      return Entry.Symbol;
    return std::nullopt;
  }
};
} // namespace llvm

#endif
