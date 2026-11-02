#pragma once

#include "infra/sortutil.h"   // svLess — the sanitizer-safe order the table below is sorted and searched in

#include <algorithm>
#include <cstddef>
#include <iterator>
#include <string_view>

namespace rw
{

// MORE EVIDENCE FOR A RUBY RECEIVER'S TYPE (docs/research/ruby-roadmap.md R4; test/rubyrecvevidencecheck.sh; parser version
// 275). What ingest_binds.h RubyBareCallWalk and graph.h's Ruby lookups share about a receiver built by an Active Record
// relation chain: which methods are its links, and how a typed receiver's `via` (model.h RubyTypedRecv::via) spells the chain
// that built it. Ruby-only: the relation is Active Record's, and the chain is Ruby's call syntax.
//
// A RELATION LINK is a query method Active Record answers on a model class and on a relation of it alike, returning another
// relation of that model: `User.where( … )`, `User.all`, `User.where( … ).order( :name )`. A chain of links rooted at a
// constant builds a relation of that class; a call on it answers from the class's CLASS side (a scope written as
// `def self.m` reaches through the relation, and so does a class method), and otherwise from Active Record — outside the
// tree. A finder at the end of a chain (ingest_binds.h kRubyTypedFinders: `first`, `find_by`, …) builds an instance.
// Excluded on purpose: names a Hash or an Enumerable answers too (`select`, `except`, `only`, `find_each`), so a chain is
// read only where every link is a relation's beyond doubt.
inline constexpr std::string_view kRubyRelationLinks[] = {
    "all", "and", "distinct", "eager_load", "excluding", "extending", "group", "having", "in_order_of", "includes", "joins",
    "left_joins", "left_outer_joins", "limit", "lock", "merge", "none", "not", "offset", "or", "order", "preload", "readonly",
    "references", "reorder", "rewhere", "strict_loading", "unscope", "where", "without",
};
constexpr bool rubyRelationLinksSorted() noexcept
{
    for( std::size_t i = 1; i < std::size( kRubyRelationLinks ); ++i )
    {
        if( !sortutil::svLess( kRubyRelationLinks[ i - 1 ], kRubyRelationLinks[ i ] ) )
        {
            return false;
        }
    }
    return true;
}
static_assert( rubyRelationLinksSorted(), "kRubyRelationLinks must be strictly sorted (binary search, svLess)" );

inline constexpr std::size_t kRubyRelationChainLinks = 8;   // a query chain is short; a hostile one costs a bounded walk
inline constexpr char        kRubyViaSeparator       = '.';  // no Ruby method name holds one

inline bool rubyIsRelationLink( std::string_view name ) noexcept
{
    return std::binary_search( std::begin( kRubyRelationLinks ), std::end( kRubyRelationLinks ), name, sortutil::svLess );
}

// A typed receiver's `via` is the method that built it (`new`, `find_by`), or for a value a relation chain built, every
// link from the constant outward joined by kRubyViaSeparator: `User.where( … ).order( … ).first` → "where.order.first".
// Calls `onLink` on each link in order and stops at the first that returns true; returns whether one did.
template<class OnLink>
inline bool rubyAnyViaLink( std::string_view via, OnLink&& onLink )
{
    for( std::size_t from = 0; from <= via.size(); )
    {
        const std::size_t cut  = via.find( kRubyViaSeparator, from );
        const std::size_t stop = cut == std::string_view::npos ? via.size() : cut;
        if( onLink( via.substr( from, stop - from ) ) )
        {
            return true;
        }
        from = stop + 1;
    }
    return false;
}

// The method that built the value last: the whole `via`, or its last link.
inline std::string_view rubyViaLast( std::string_view via ) noexcept
{
    const std::size_t cut = via.rfind( kRubyViaSeparator );
    return cut == std::string_view::npos ? via : via.substr( cut + 1 );
}

// Does `via` build a relation — its last link one — rather than an instance? A relation answers from its class's class side.
inline bool rubyViaIsRelation( std::string_view via ) noexcept
{
    return rubyIsRelationLink( rubyViaLast( via ) );
}

} // namespace rw
