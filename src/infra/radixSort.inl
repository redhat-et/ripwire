// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  radixSort.inl
//
//  Template bodies for radixSort.h — do not include directly.
//
#pragma once

namespace radix
{
namespace detail
{

template<class Key>
inline constexpr bool IsUnsignedRadixKey =
    std::is_integral_v<Key> && std::is_unsigned_v<Key> &&
    ( sizeof(Key) == 1 || sizeof(Key) == 2 || sizeof(Key) == 4 || sizeof(Key) == 8 );

template<class Key>
inline constexpr bool IsFloatRadixKey = std::is_same_v<Key, float>;

template<class Key>
inline constexpr bool IsRadixKey = IsUnsignedRadixKey<Key> || IsFloatRadixKey<Key>;

// A whole record can be relocated with one bulk byte copy exactly when it is
// trivially copyable — its bytes fully define its value and it has no move/dtor
// side effects. (C++ has no std::is_trivially_relocatable before C++26; this is
// the conservative, always-correct stand-in.) Records that fail this test are
// relocated per-element with move-assignment, which itself decays to copy-
// assignment when the type is copy-only — so non-movable types still work.
template<class Item>
inline constexpr bool IsTriviallyRelocatable = std::is_trivially_copyable_v<Item>;

template<class Key>
using SortWordFor = std::conditional_t<IsFloatRadixKey<Key>, uint32_t, Key>;

template<class Key>
inline constexpr int Passes = int( sizeof(SortWordFor<Key>) );

// Histogram / offset counters. Counts and prefix-sum positions are bounded by
// `count`, which every entry point caps at UINT32_MAX, so 32-bit halves the
// histogram footprint vs size_t (4 KB vs 8 KB for a 32-bit-word key) — it stays
// resident in L1 across the clear / accumulate / offset scans.
using Count = uint32_t;

template<class Key>
ALWAYS_INLINE bool keyIsSortable( Key key ) noexcept
{
    if constexpr ( IsFloatRadixKey<Key> ) {
        return fastmath::isFiniteFast( key );
    } else {
        return true;
}
}

template<class Key>
ALWAYS_INLINE SortWordFor<Key> sortWordOf( Key key ) noexcept
{
    if constexpr ( IsFloatRadixKey<Key> )
    {
        VERIFY_TEXT( keyIsSortable(key), "radix float keys must be finite" );

        uint32_t raw = __builtin_bit_cast( uint32_t, key );
        if( ( raw & 0x7FFFFFFFu ) == 0u ) {
            raw = 0u;                               // keep -0.0 and +0.0 stable-equal
}

        const uint32_t sign = raw >> 31;
        const uint32_t mask = sign ? 0xFFFFFFFFu : 0x80000000u;
        return raw ^ mask;
    }
    else
    {
        return key;
    }
}

template<class Key>
ALWAYS_INLINE constexpr uint8_t digitOf( Key key, int pass ) noexcept
{
    return uint8_t( ( uint64_t( key ) >> ( pass * 8 ) ) & 0xFFu );
}

ALWAYS_INLINE constexpr uint16_t quantizeFloatToU16Impl( float value, float minValue, float maxValue ) noexcept
{
    if( !std::is_constant_evaluated() )
    {
        VERIFY_TEXT( fastmath::isFiniteFast(value), "radix quantized float keys must be finite" );
        VERIFY_TEXT( fastmath::isFiniteFast(minValue) &&
                     fastmath::isFiniteFast(maxValue) &&
                     minValue < maxValue,
                     "radix quantized float key range must be finite and ordered" );
    }

    const float t = ( value - minValue ) / ( maxValue - minValue );
    const float clamped = t < 0.f ? 0.f : ( t > 1.f ? 1.f : t );
    return uint16_t( clamped * 65535.f + 0.5f );
}

ALWAYS_INLINE constexpr uint16_t quantizeFloatToU16Signed1024Impl( float value ) noexcept
{
    if( !std::is_constant_evaluated() ) {
        VERIFY_TEXT( fastmath::isFiniteFast(value), "radix quantized float keys must be finite" );
}

    constexpr float kMin = -1024.f;
    constexpr float kInvRange = 1.f / 2048.f;
    const float t = ( value - kMin ) * kInvRange;
    const float clamped = t < 0.f ? 0.f : ( t > 1.f ? 1.f : t );
    return uint16_t( clamped * 65535.f + 0.5f );
}

template<int kPasses>
inline void clearHistograms( Count (&hist)[kPasses][256] ) noexcept
{
    for( int pass = 0; pass < kPasses; ++pass ) {
        for( int bin = 0; bin < 256; ++bin ) {
            hist[pass][bin] = 0;
}
}
}

template<int kPasses>
inline bool digitPassIsNoOp( const Count (&hist)[kPasses][256],
                             int pass, std::size_t count ) noexcept
{
    for( int bin = 0; bin < 256; ++bin ) {
        if( hist[pass][bin] == count ) {
            return true;
}
}
    return false;
}

template<int kPasses>
inline void makeOffsets( const Count (&hist)[kPasses][256],
                         int pass, Count (&offsets)[256] ) noexcept
{
    Count sum = 0;
    for( int bin = 0; bin < 256; ++bin )
    {
        offsets[bin] = sum;
        sum += hist[pass][bin];
    }
}

template<class Item>
inline void copyItems( Item* dst, Item* src, std::size_t count ) noexcept
{
    if constexpr ( IsTriviallyRelocatable<Item> ) {
        memorycopy( dst, src, count * sizeof(Item) );    // one bulk move, no per-element loop
    } else {
        for( std::size_t i = 0; i < count; ++i ) {
            dst[i] = std::move( src[i] );                 // src is consumed; move-assign (copy fallback)
}
}
}

inline void copyIndices( uint32_t* dst, const uint32_t* src, std::size_t count ) noexcept
{
    memorycopy( dst, src, count * sizeof(uint32_t) );
}

template<class Key, int kPasses>
void buildHistogramsScalarKeys( const Key* keys, std::size_t count,
                                Count (&hist)[kPasses][256] ) noexcept
{
    std::size_t i = 0;
    for( ; i + 4 <= count; i += 4 )
    {
        const SortWordFor<Key> k0 = sortWordOf( keys[i + 0] );
        const SortWordFor<Key> k1 = sortWordOf( keys[i + 1] );
        const SortWordFor<Key> k2 = sortWordOf( keys[i + 2] );
        const SortWordFor<Key> k3 = sortWordOf( keys[i + 3] );
        for( int pass = 0; pass < kPasses; ++pass )
        {
            ++hist[pass][digitOf(k0, pass)];
            ++hist[pass][digitOf(k1, pass)];
            ++hist[pass][digitOf(k2, pass)];
            ++hist[pass][digitOf(k3, pass)];
        }
    }
    for( ; i < count; ++i )
    {
        const SortWordFor<Key> k = sortWordOf( keys[i] );
        for( int pass = 0; pass < kPasses; ++pass ) {
            ++hist[pass][digitOf(k, pass)];
}
    }
}

#if (defined(__ARM_NEON) || defined(__ARM_NEON__)) && \
    (!defined(__BYTE_ORDER__) || __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
template<int kPasses>
ALWAYS_INLINE void addNeonU32Bytes( uint32x4_t v,
                                    Count (&hist)[kPasses][256] ) noexcept
{
    static_assert( kPasses == 4 );
    alignas(16) uint8_t bytes[16];
    vst1q_u8( bytes, vreinterpretq_u8_u32(v) );

    ++hist[0][bytes[ 0]]; ++hist[1][bytes[ 1]]; ++hist[2][bytes[ 2]]; ++hist[3][bytes[ 3]];
    ++hist[0][bytes[ 4]]; ++hist[1][bytes[ 5]]; ++hist[2][bytes[ 6]]; ++hist[3][bytes[ 7]];
    ++hist[0][bytes[ 8]]; ++hist[1][bytes[ 9]]; ++hist[2][bytes[10]]; ++hist[3][bytes[11]];
    ++hist[0][bytes[12]]; ++hist[1][bytes[13]]; ++hist[2][bytes[14]]; ++hist[3][bytes[15]];
}

template<int kPasses>
ALWAYS_INLINE void addNeonU64Bytes( uint64x2_t v,
                                    Count (&hist)[kPasses][256] ) noexcept
{
    static_assert( kPasses == 8 );
    alignas(16) uint8_t bytes[16];
    vst1q_u8( bytes, vreinterpretq_u8_u64(v) );

    ++hist[0][bytes[ 0]]; ++hist[1][bytes[ 1]]; ++hist[2][bytes[ 2]]; ++hist[3][bytes[ 3]];
    ++hist[4][bytes[ 4]]; ++hist[5][bytes[ 5]]; ++hist[6][bytes[ 6]]; ++hist[7][bytes[ 7]];
    ++hist[0][bytes[ 8]]; ++hist[1][bytes[ 9]]; ++hist[2][bytes[10]]; ++hist[3][bytes[11]];
    ++hist[4][bytes[12]]; ++hist[5][bytes[13]]; ++hist[6][bytes[14]]; ++hist[7][bytes[15]];
}

template<int kPasses>
ALWAYS_INLINE void addNeonF32Bytes( float32x4_t v,
                                    Count (&hist)[kPasses][256] ) noexcept
{
    static_assert( kPasses == 4 );

    uint32x4_t raw = vreinterpretq_u32_f32(v);
    const uint32x4_t absBits = vandq_u32( raw, vdupq_n_u32(0x7FFFFFFFu) );
    const uint32x4_t nonZero = vcgtq_u32( absBits, vdupq_n_u32(0u) );
    raw = vandq_u32( raw, nonZero );                 // normalize -0.0 and +0.0

    const uint32x4_t signMask = vreinterpretq_u32_s32(
        vshrq_n_s32( vreinterpretq_s32_u32(raw), 31 ) );
    const uint32x4_t flip = vbslq_u32(
        signMask, vdupq_n_u32(0xFFFFFFFFu), vdupq_n_u32(0x80000000u) );

    addNeonU32Bytes( veorq_u32(raw, flip), hist );
}
#endif

template<class Key, int kPasses>
void buildHistogramsContiguousKeys( const Key* keys, std::size_t count,
                                    Count (&hist)[kPasses][256] ) noexcept
{
#if (defined(__ARM_NEON) || defined(__ARM_NEON__)) && \
    (!defined(__BYTE_ORDER__) || __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
    if constexpr ( std::is_same_v<Key, uint32_t> )
    {
        std::size_t i = 0;
        for( ; i + 4 <= count; i += 4 ) {
            addNeonU32Bytes( vld1q_u32( keys + i ), hist );
}
        for( ; i < count; ++i )
        {
            const Key k = keys[i];
            ++hist[0][digitOf(k, 0)];
            ++hist[1][digitOf(k, 1)];
            ++hist[2][digitOf(k, 2)];
            ++hist[3][digitOf(k, 3)];
        }
        return;
    }
    else if constexpr ( std::is_same_v<Key, uint64_t> )
    {
        std::size_t i = 0;
        for( ; i + 2 <= count; i += 2 ) {
            addNeonU64Bytes( vld1q_u64( keys + i ), hist );
}
        for( ; i < count; ++i )
        {
            const Key k = keys[i];
            for( int pass = 0; pass < kPasses; ++pass ) {
                ++hist[pass][digitOf(k, pass)];
}
        }
        return;
    }
    else if constexpr ( std::is_same_v<Key, float> )
    {
        std::size_t i = 0;
        for( ; i + 4 <= count; i += 4 )
        {
            const float32x4_t v = vld1q_f32( keys + i );
            VERIFY_TEXT( fastmath::isFiniteFast(keys[i + 0]) &&
                         fastmath::isFiniteFast(keys[i + 1]) &&
                         fastmath::isFiniteFast(keys[i + 2]) &&
                         fastmath::isFiniteFast(keys[i + 3]),
                         "radix float keys must be finite" );
            addNeonF32Bytes( v, hist );
        }
        for( ; i < count; ++i )
        {
            const SortWordFor<Key> k = sortWordOf( keys[i] );
            ++hist[0][digitOf(k, 0)];
            ++hist[1][digitOf(k, 1)];
            ++hist[2][digitOf(k, 2)];
            ++hist[3][digitOf(k, 3)];
        }
        return;
    }
#endif

    buildHistogramsScalarKeys( keys, count, hist );
}

template<class Key, int kPasses>
void buildHistogramsIndexedKeys( const Key* keys, const uint32_t* indices, std::size_t count,
                                 Count (&hist)[kPasses][256] ) noexcept
{
    std::size_t i = 0;
    for( ; i + 4 <= count; i += 4 )
    {
        const SortWordFor<Key> k0 = sortWordOf( keys[indices[i + 0]] );
        const SortWordFor<Key> k1 = sortWordOf( keys[indices[i + 1]] );
        const SortWordFor<Key> k2 = sortWordOf( keys[indices[i + 2]] );
        const SortWordFor<Key> k3 = sortWordOf( keys[indices[i + 3]] );
        for( int pass = 0; pass < kPasses; ++pass )
        {
            ++hist[pass][digitOf(k0, pass)];
            ++hist[pass][digitOf(k1, pass)];
            ++hist[pass][digitOf(k2, pass)];
            ++hist[pass][digitOf(k3, pass)];
        }
    }
    for( ; i < count; ++i )
    {
        const SortWordFor<Key> k = sortWordOf( keys[indices[i]] );
        for( int pass = 0; pass < kPasses; ++pass ) {
            ++hist[pass][digitOf(k, pass)];
}
    }
}

template<class Key, int kPasses>
void sortPreparedIndices( const Key* keys, uint32_t* indices, uint32_t* scratch, std::size_t count,
                          const Count (&hist)[kPasses][256] ) noexcept
{
    uint32_t* src = indices;
    uint32_t* dst = scratch;

    for( int pass = 0; pass < kPasses; ++pass )
    {
        if( digitPassIsNoOp( hist, pass, count ) ) {
            continue;
}

        Count offsets[256];
        makeOffsets( hist, pass, offsets );

        for( std::size_t i = 0; i < count; ++i )
        {
            const uint32_t index = src[i];
            const uint8_t  digit = digitOf( sortWordOf( keys[index] ), pass );
            dst[offsets[digit]++] = index;
        }

        uint32_t* tmp = src;
        src = dst;
        dst = tmp;
    }

    if( src != indices ) {
        copyIndices( indices, src, count );
}
}

} // namespace detail

ALWAYS_INLINE constexpr uint16_t quantizeFloatToU16( float value, float minValue, float maxValue ) noexcept
{
    return detail::quantizeFloatToU16Impl( value, minValue, maxValue );
}

ALWAYS_INLINE constexpr uint16_t quantizeFloatToU16Signed1024( float value ) noexcept
{
    return detail::quantizeFloatToU16Signed1024Impl( value );
}

template<class Item, class KeyOf>
void sortKeySmall( Item* items, Item* scratch, std::size_t count, KeyOf&& keyOf ) noexcept
{
    using Key = std::remove_cvref_t<decltype( keyOf( items[0] ) )>;
    static_assert( detail::IsRadixKey<Key>, "sortKeySmall keyOf(item) must return unsigned 8/16/32/64-bit integral key or finite float key" );

    if( count <= 1 ) { [[unlikely]]
        return;
}

    VERIFY_TEXT( items != nullptr,   "sortKeySmall: items must be non-null" );
    VERIFY_TEXT( scratch != nullptr, "sortKeySmall: scratch must be non-null" );
    VERIFY_TEXT( items != scratch,   "sortKeySmall: scratch must not alias items" );
    VERIFY_TEXT( count <= std::size_t(UINT32_MAX), "sortKeySmall: count exceeds uint32 histogram range" );

    constexpr int kPasses = detail::Passes<Key>;
    alignas( fastmath::hardware_destructive_interference_size ) detail::Count hist[kPasses][256];
    detail::clearHistograms( hist );

    std::size_t i = 0;
    for( ; i + 4 <= count; i += 4 )
    {
        const detail::SortWordFor<Key> k0 = detail::sortWordOf( Key( keyOf( items[i + 0] ) ) );
        const detail::SortWordFor<Key> k1 = detail::sortWordOf( Key( keyOf( items[i + 1] ) ) );
        const detail::SortWordFor<Key> k2 = detail::sortWordOf( Key( keyOf( items[i + 2] ) ) );
        const detail::SortWordFor<Key> k3 = detail::sortWordOf( Key( keyOf( items[i + 3] ) ) );
        for( int pass = 0; pass < kPasses; ++pass )
        {
            ++hist[pass][detail::digitOf(k0, pass)];
            ++hist[pass][detail::digitOf(k1, pass)];
            ++hist[pass][detail::digitOf(k2, pass)];
            ++hist[pass][detail::digitOf(k3, pass)];
        }
    }
    for( ; i < count; ++i )
    {
        const detail::SortWordFor<Key> k = detail::sortWordOf( Key( keyOf( items[i] ) ) );
        for( int pass = 0; pass < kPasses; ++pass ) {
            ++hist[pass][detail::digitOf(k, pass)];
}
    }

    Item* src = items;
    Item* dst = scratch;

    for( int pass = 0; pass < kPasses; ++pass )
    {
        if( detail::digitPassIsNoOp( hist, pass, count ) ) {
            continue;
}

        detail::Count offsets[256];
        detail::makeOffsets( hist, pass, offsets );

        for( std::size_t j = 0; j < count; ++j )
        {
            Item& item = src[j];                          // read the key before moving the record out
            const uint8_t digit = detail::digitOf( detail::sortWordOf( Key( keyOf( item ) ) ), pass );
            dst[offsets[digit]++] = std::move( item );    // src consumed this pass; move-assign (copy fallback)
        }

        Item* tmp = src;
        src = dst;
        dst = tmp;
    }

    if( src != items ) {
        detail::copyItems( items, src, count );
}
}

template<class Key>
void sortKeyLarge( const Key* keys, uint32_t* indices, uint32_t* scratch, std::size_t count ) noexcept
{
    static_assert( detail::IsRadixKey<Key>, "sortKeyLarge keys must be unsigned 8/16/32/64-bit integral values or finite floats" );

    if( count <= 1 ) [[unlikely]]
    {
        if( count == 1 && indices ) {
            indices[0] = 0;
}
        return;
    }

    VERIFY_TEXT( keys != nullptr,    "sortKeyLarge: keys must be non-null" );
    VERIFY_TEXT( indices != nullptr, "sortKeyLarge: indices must be non-null" );
    VERIFY_TEXT( scratch != nullptr, "sortKeyLarge: scratch must be non-null" );
    VERIFY_TEXT( indices != scratch, "sortKeyLarge: scratch must not alias indices" );
    VERIFY_TEXT( count <= std::size_t(UINT32_MAX), "sortKeyLarge: count exceeds uint32 index range" );

    for( std::size_t i = 0; i < count; ++i ) {
        indices[i] = uint32_t( i );
}

    constexpr int kPasses = detail::Passes<Key>;
    alignas( fastmath::hardware_destructive_interference_size ) detail::Count hist[kPasses][256];
    detail::clearHistograms( hist );
    detail::buildHistogramsContiguousKeys( keys, count, hist );
    detail::sortPreparedIndices( keys, indices, scratch, count, hist );
}

template<class Key>
void sortKeyLargeIndexed( const Key* keys, uint32_t* indices, uint32_t* scratch, std::size_t count ) noexcept
{
    static_assert( detail::IsRadixKey<Key>, "sortKeyLargeIndexed keys must be unsigned 8/16/32/64-bit integral values or finite floats" );

    if( count <= 1 ) { [[unlikely]]
        return;
}

    VERIFY_TEXT( keys != nullptr,    "sortKeyLargeIndexed: keys must be non-null" );
    VERIFY_TEXT( indices != nullptr, "sortKeyLargeIndexed: indices must be non-null" );
    VERIFY_TEXT( scratch != nullptr, "sortKeyLargeIndexed: scratch must be non-null" );
    VERIFY_TEXT( indices != scratch, "sortKeyLargeIndexed: scratch must not alias indices" );
    VERIFY_TEXT( count <= std::size_t(UINT32_MAX), "sortKeyLargeIndexed: count exceeds uint32 histogram range" );

    constexpr int kPasses = detail::Passes<Key>;
    alignas( fastmath::hardware_destructive_interference_size ) detail::Count hist[kPasses][256];
    detail::clearHistograms( hist );
    detail::buildHistogramsIndexedKeys( keys, indices, count, hist );
    detail::sortPreparedIndices( keys, indices, scratch, count, hist );
}

template<class Key>
void sortKeyLargePairs( const Key* keys, uint32_t* indices, WordIndex* scratch, std::size_t count ) noexcept
{
    static_assert( detail::IsRadixKey<Key>, "sortKeyLargePairs keys must be unsigned 8/16/32-bit integral values or finite floats" );
    static_assert( detail::Passes<Key> <= 4, "sortKeyLargePairs packs the sort word into uint32 — use sortKeyLarge for uint64 keys" );

    if( count <= 1 ) [[unlikely]]
    {
        if( count == 1 && indices ) {
            indices[0] = 0;
}
        return;
    }

    VERIFY_TEXT( keys != nullptr,    "sortKeyLargePairs: keys must be non-null" );
    VERIFY_TEXT( indices != nullptr, "sortKeyLargePairs: indices must be non-null" );
    VERIFY_TEXT( scratch != nullptr, "sortKeyLargePairs: scratch must be non-null" );
    VERIFY_TEXT( count <= std::size_t(UINT32_MAX), "sortKeyLargePairs: count exceeds uint32 index range" );
    VERIFY_TEXT( static_cast<const void*>(indices) != static_cast<const void*>(scratch),
                 "sortKeyLargePairs: scratch must not alias indices (final writeback reads scratch)" );

    // Two ping-pong halves of the scratch hold <word,index> pairs. The scatter
    // then reads pairs sequentially (no keys[idx] gather, no per-pass float flip
    // — the order word is baked in once here), which is the most cache-friendly
    // index sort for large counts.
    constexpr int kPasses = detail::Passes<Key>;
    WordIndex* src = scratch;
    WordIndex* dst = scratch + count;

    alignas( fastmath::hardware_destructive_interference_size ) detail::Count hist[kPasses][256];
    detail::clearHistograms( hist );

    for( std::size_t i = 0; i < count; ++i )
    {
        const uint32_t word = uint32_t( detail::sortWordOf( keys[i] ) );
        src[i] = WordIndex{ word, uint32_t(i) };
        for( int pass = 0; pass < kPasses; ++pass ) {
            ++hist[pass][ detail::digitOf( word, pass ) ];
}
    }

    for( int pass = 0; pass < kPasses; ++pass )
    {
        if( detail::digitPassIsNoOp( hist, pass, count ) ) {
            continue;
}

        detail::Count offsets[256];
        detail::makeOffsets( hist, pass, offsets );

        for( std::size_t i = 0; i < count; ++i )
        {
            const WordIndex wi = src[i];                 // sequential read — prefetcher-friendly
            dst[ offsets[ detail::digitOf( wi.word, pass ) ]++ ] = wi;
        }

        WordIndex* tmp = src;
        src = dst;
        dst = tmp;
    }

    for( std::size_t i = 0; i < count; ++i ) {
        indices[i] = src[i].index;
}
}

} // namespace radix
