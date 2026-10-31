#pragma once

#include "radixSort.h"

#include <algorithm>
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <vector>

namespace rw::sortutil
{

// SORTING AND SEARCHING std::string_view: ALWAYS THROUGH THIS, NEVER THROUGH operator<.
// libstdc++'s string_view three-way compare computes `n1 - n2` on size_type and lets it wrap
// (bits/string_view.h, _S_compare). That wrap is well-defined C++, but the G1 sanitizer stack runs
// -fsanitize=integer, which REPORTS it, and -fno-sanitize-recover=all turns the report into an abort.
// libc++ computes the same answer without the subtraction and never reports — so a default-comparator
// std::sort / std::binary_search / std::lower_bound over string_view is green on macOS (including the
// macOS ASan leg) and kills EVERY run on the Linux sanitizer leg the moment two compared views differ
// in length. That is not hypothetical: it took main red at 69a17f9 with `unsigned integer overflow:
// 3 - 17` raised from inside std::binary_search over the external-name veto's table.
//
// svLess is the SAME total order operator< defines, so a table already sorted under operator< stays
// sorted under this, and any container may switch to it without re-ordering. It is constexpr because
// the tables that use it prove their own sortedness in a static_assert, and std::memcmp cannot be used
// in a constant expression. test/portablebuildcheck.sh arm #6 keeps the default comparator from
// coming back.
constexpr bool svLess( std::string_view a, std::string_view b ) noexcept
{
    const std::size_t n = a.size() < b.size() ? a.size() : b.size();
    for( std::size_t i = 0; i < n; ++i )
    {
        // char_traits<char>::compare is memcmp, so the order is UNSIGNED-byte order. Comparing as plain
        // char would sort a byte >= 0x80 before 'a' on a signed-char target and silently reorder a table.
        const unsigned char ca = static_cast<unsigned char>( a[ i ] );
        const unsigned char cb = static_cast<unsigned char>( b[ i ] );
        if( ca != cb )
        {
            return ca < cb;
        }
    }
    return a.size() < b.size();
}


inline bool lessByScoreDescId( const std::vector<float>& scores, std::uint32_t a, std::uint32_t b ) noexcept
{
    if( scores[a] != scores[b] )
    {
        return scores[a] > scores[b];
    }
    return a < b;
}

template<class KeyOf>
inline void radixSortUint32ByKey( std::vector<std::uint32_t>& values, std::vector<std::uint32_t>& scratch, KeyOf keyOf )
{
    const std::size_t count = values.size();
    if( count < 2 )
    {
        return;
    }
    scratch.resize( count );
    radix::sortKeySmall( values.data(), scratch.data(), count, keyOf );
}

inline std::uint32_t nonNegativeFloatDescKey( float value ) noexcept
{
    std::uint32_t bits = std::bit_cast<std::uint32_t>( value );
    if( ( bits & 0x7fffffffu ) == 0u )
    {
        bits = 0u;   // bitwise normalization survives the global no-signed-zeros fast-math contract
    }
    return ~bits;
}

// Deterministic descending radix sort for nonnegative finite float magnitudes. This avoids libc++'s
// bitset-partition implementation, whose internal unsigned-negation idiom trips the full integer sanitizer.
inline void radixSortNonNegativeFloatsDesc( std::vector<float>& values )
{
    const std::size_t count = values.size();
    if( count < 2 )
    {
        return;
    }

    std::vector<float> scratch( count );
    radix::sortKeySmall( values.data(), scratch.data(), count, []( float value ) noexcept { return nonNegativeFloatDescKey( value ); } );
}

// Sort ids by `(scores[id] desc, id asc)`. PageRank/HITS/BM25-style score vectors are nonnegative finite
// floats, so their IEEE bits are already an ascending numeric key; bitwise-not flips that into descending
// order. Stable radix preserves the id-ascending tie-break after the optional id pre-pass.
inline void radixSortByScoreDescId( std::vector<std::uint32_t>& order, const std::vector<float>& scores, std::vector<std::uint32_t>& scratch )
{
    constexpr std::size_t kRadixThreshold = 2048;
    const std::size_t count = order.size();
    if( count < kRadixThreshold )
    {
        std::sort( order.begin(), order.end(), [ &scores ]( std::uint32_t a, std::uint32_t b ) noexcept { return lessByScoreDescId( scores, a, b ); } );
        return;
    }

    bool idsInRange = true;
    bool canUseFloatBits = true;
    for( std::uint32_t id : order )
    {
        if( id >= scores.size() || !std::isfinite( scores[ id ] ) || scores[ id ] < 0.0f )
        {
            idsInRange = id < scores.size();
            canUseFloatBits = false;
            break;
        }
    }
    if( !idsInRange )
    {
        std::sort( order.begin(), order.end() );
        return;
    }
    if( !canUseFloatBits )
    {
        std::sort( order.begin(), order.end(), [ &scores ]( std::uint32_t a, std::uint32_t b ) noexcept { return lessByScoreDescId( scores, a, b ); } );
        return;
    }

    bool isAlreadySorted = true;
    for( std::size_t i = 1; i < count; ++i )
    {
        if( lessByScoreDescId( scores, order[ i ], order[ i - 1 ] ) )
        {
            isAlreadySorted = false;
            break;
        }
    }
    if( isAlreadySorted )
    {
        return;
    }

    bool isIdSorted = true;
    for( std::size_t i = 1; i < count; ++i )
    {
        if( order[ i ] < order[ i - 1 ] )
        {
            isIdSorted = false;
            break;
        }
    }
    if( !isIdSorted )
    {
        radixSortUint32ByKey( order, scratch, []( std::uint32_t id ) noexcept { return id; } );
    }

    radixSortUint32ByKey( order, scratch, [ &scores ]( std::uint32_t id ) noexcept { return nonNegativeFloatDescKey( scores[ id ] ); } );
}

inline void radixSortByScoreDescId( std::vector<std::uint32_t>& order, const std::vector<float>& scores )
{
    std::vector<std::uint32_t> scratch;
    radixSortByScoreDescId( order, scores, scratch );
}

template<class Edge>
inline bool lessByFromTo( const Edge& a, const Edge& b ) noexcept
{
    if( a.from != b.from )
    {
        return a.from < b.from;
    }
    return a.to < b.to;
}

// Stable LSD radix for graph edge records with uint32-compatible `from` and `to` members.
// This is intentionally narrow: use it for dense POD edge lists, not string-heavy records.
template<class Edge>
inline void radixSortByFromTo( std::vector<Edge>& values, std::vector<Edge>& scratch )
{
    constexpr std::size_t kRadixThreshold = 2048;
    const std::size_t count = values.size();
    if( count < kRadixThreshold )
    {
        std::sort( values.begin(), values.end(), lessByFromTo<Edge> );
        return;
    }

    bool isAlreadySorted = true;
    for( std::size_t i = 1; i < count; ++i )
    {
        if( lessByFromTo( values[ i ], values[ i - 1 ] ) )
        {
            isAlreadySorted = false;
            break;
        }
    }
    if( isAlreadySorted )
    {
        return;
    }

    scratch.resize( count );
    const auto toKey   = []( const Edge& e ) noexcept { return std::uint32_t( e.to ); };
    const auto fromKey = []( const Edge& e ) noexcept { return std::uint32_t( e.from ); };
    radix::sortKeySmall( values.data(), scratch.data(), count, toKey );
    radix::sortKeySmall( values.data(), scratch.data(), count, fromKey );
}

template<class Edge>
inline void radixSortByFromTo( std::vector<Edge>& values )
{
    std::vector<Edge> scratch;
    radixSortByFromTo( values, scratch );
}

}   // namespace rw::sortutil
