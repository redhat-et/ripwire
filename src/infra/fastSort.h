// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  fastSort.h
//
//  Small facade over vendored no-allocation comparison sorters.
//  Use explicit algorithms for shape-sensitive hot paths:
//      * infra::sort::unstable           -> pdqsort, general comparator sort
//      * infra::sort::unstableBranchless -> branchless pdqsort for arithmetic/default comparators
//

#pragma once

#include "pdqsort.hpp"

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

}   // namespace infra::sort
