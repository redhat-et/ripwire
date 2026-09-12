// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  fastSort.h
//
//  Small facade over vendored no-allocation comparison sorters. Use explicit algorithms for
//  shape-sensitive hot paths:
//      * infra::sort::unstable           -> pdqsort, general comparator sort
//      * infra::sort::unstableBranchless -> branchless pdqsort for arithmetic/default comparators
//      * infra::sort::stable             -> timsort, stable, run-detecting; see the warning below
//
//  ── CHOOSING BETWEEN THEM, IN THE ORDER THE QUESTIONS ACTUALLY DECIDE ────────────────────────────────
//
//  1. MAGNITUDE FIRST. Almost every sort here is too small for the choice to matter. Outside one site,
//     every sort measured across seven corpora costs at most 0.5 ms per run — the entire best-case win
//     available on the largest of them was 0.32 ms of a ~750 ms run. If the sort is not a measurable
//     fraction of the run, call `unstable` and spend the attention elsewhere. Measure before choosing.
//
//  2. THEN DESCENTS PER ELEMENT — how many adjacent pairs are out of order, divided by n. This is the
//     covariate that decides, and n is NOT. Two measured closure sites three orders of magnitude apart
//     in total volume (3,994,257 elements and 4,000) sit within 2x of each other in every arm's ratio
//     column. Ask how the input was BUILT, not how big it is:
//       * ~0 descents (appended in key order, then read back) — the input is already sorted. The best
//         arm is not an algorithm at all: `if( !std::is_sorted( a, b ) ) { std::sort( a, b ); }`, three
//         lines and no dependency, measured 0.35x of std::sort where timsort managed 0.58x, and
//         0.48-0.54x where timsort managed 0.68-0.74x. Run detection in a tight vectorisable loop beats
//         run detection with a merge stack behind it.
//       * >= ~0.18 descents (a graph walk's discovery order, an id set gathered by traversal) — the
//         input is scattered and there is no run structure to find. timsort is the WORST arm measured
//         here: 1.71x std::sort on the largest such site, and 6.0x slower than a radix pass over the
//         same data. Prefer `unstableBranchless`, or radixSort.h/sortutil.h when the key is an integer
//         and the caller can own the scratch.
//       * in between (sawtooth, mostly-sorted-with-patches) is the only region where a run-detecting
//         merge sort has a case to make, and it is unmeasured here because no site produces it.
//
//  3. THEN PAYLOAD WIDTH, and only then. `unstableBranchless` needs an arithmetic or default comparator
//     and pays off on narrow records where a mispredicted branch dominates the compare. Once the record
//     is wide enough that the MOVE dominates, sort indices against keys instead of moving records —
//     that is radixSort.h's sortKeySmall/sortKeyLarge split, not a choice inside this facade.
//
//  Stability is a separate axis, not a tie-breaker: if equal elements must keep their arrival order,
//  `stable` and std::stable_sort are the only options here, and pdqsort is not one.
//
//  ── `stable` HAS NO CALL SITE IN THIS TREE, AND THAT IS THE MEASURED OUTCOME ─────────────────────────
//
//  timsort was measured against std::sort, radix, pdqsort, std::stable_sort and the three-line
//  is_sorted guard, on the real captured id sets of three candidate sites across seven corpora, medians
//  of 21 interleaved reps. It won on no shape: beaten by the is_sorted guard everywhere the input was
//  pre-sorted, worst arm everywhere it was not. It is vendored so this layer offers the third algorithm
//  with its refutation attached rather than a silent gap, and the numbers above are that refutation. Do
//  not route a caller here because timsort has a good reputation; route one here only if a site turns
//  up in region 2's middle band, with a measurement that says so.
//
//  Worth knowing before assuming the FAMILY is what matters: std::stable_sort ties radix on the one
//  site where leaving the quicksort family is a 3.5x win (0.28x both). Radix's own remaining edge there
//  is caller-owned scratch and zero per-call allocation (G2) — not raw speed. `stable`'s workspace
//  overload buys that same property for timsort, and is the only reason the vendored copy is patched.
//
//  ── THE WORKSPACE OVERLOAD ───────────────────────────────────────────────────────────────────────────
//
//      infra::sort::stableWorkspace<It> ws;   // once, outside the hot loop
//      ws.reserve_for( maxElements );         // ceil(n/2) — timsort's worst-case merge buffer
//      for( ... ) { infra::sort::stable( first, last, ws, comp ); }   // zero heap allocation per sort
//
//  The workspace is a LOCAL PATCH to the vendored header, not an upstream feature. timsort.hpp's own
//  header explains what that costs on an upgrade, and test/timsortcheck.sh gates the property. One
//  workspace cannot be shared across different iterator types by design — it is typed on the iterator,
//  because it holds that iterator's value type. The zero-allocation claim is about the SORT: a value
//  type that allocates in its own moves still allocates.
//

#pragma once

#include "pdqsort.hpp"
#include "timsort.hpp"

#include <functional>
#include <iterator>
#include <ranges>
#include <utility>

namespace infra::sort
{

template<class Iterator, class Compare = std::less<>>
void unstable( Iterator first, Iterator last, Compare comp = Compare{} )
{
    ::pdqsort( first, last, std::move( comp ) );
}

template<
    std::ranges::random_access_range Range,
    class Compare = std::ranges::less,
    class Projection = std::identity
>
    requires std::sortable<std::ranges::iterator_t<Range>, Compare, Projection>
auto unstable( Range&& range, Compare comp = {}, Projection proj = {} )
    -> std::ranges::borrowed_iterator_t<Range>
{
    auto first = std::ranges::begin( range );
    auto last  = std::ranges::end( range );

    ::pdqsort( first, last,
               [ & ]( auto&& lhs, auto&& rhs )
               {
                   return std::invoke( comp, std::invoke( proj, lhs ), std::invoke( proj, rhs ) );
               } );

    return last;
}

template<class Iterator, class Compare>
void unstableBranchless( Iterator first, Iterator last, Compare comp )
{
    ::pdqsort_branchless( first, last, std::move( comp ) );
}

template<class Iterator>
void unstableBranchless( Iterator first, Iterator last )
{
    ::pdqsort_branchless( first, last );
}

// Reusable scratch for the workspace overload of `stable`. Typed on the iterator because it holds that
// iterator's value type; reserve once, then sort through it as often as you like.
template<class Iterator>
using stableWorkspace = ::gfx::timsort_workspace<Iterator>;

// Owning form: allocates its own merge buffer and run stack, once per call. Correct everywhere, and the
// wrong thing to put in a hot loop — that is what the workspace overload below is for.
//
// The `sortable` constraint is load-bearing rather than decorative: without it a workspace argument
// would deduce as this overload's Compare, and the two would be ambiguous at every workspace call site.
template<class Iterator, class Compare = std::less<>>
    requires std::sortable<Iterator, Compare>
void stable( Iterator first, Iterator last, Compare comp = Compare{} )
{
    ::gfx::timsort( first, last, std::move( comp ) );
}

// Workspace form: zero heap allocation per sort, once `ws.reserve_for( n )` has run. The workspace is
// cleared, never shrunk, between uses, so its capacity survives every call.
template<class Iterator, class Compare = std::less<>>
    requires std::sortable<Iterator, Compare>
void stable( Iterator first, Iterator last, stableWorkspace<Iterator>& workspace, Compare comp = Compare{} )
{
    ::gfx::timsort( first, last, workspace, std::move( comp ) );
}

}   // namespace infra::sort
