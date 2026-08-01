#include "radixSort.h"
#include "sortutil.h"

#include <algorithm>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <numeric>
#include <vector>

namespace
{

void check( bool condition, const char* expression, int line )
{
    if( condition )
        return;
    std::fprintf( stderr, "radix gate failed at line %d: %s\n", line, expression );
    std::exit( 1 );
}

#define CHECK( expression ) check( bool( expression ), #expression, __LINE__ )
#define REQUIRE( expression ) CHECK( expression )

struct SmallRecord
{
    std::uint32_t key = 0;
    std::uint32_t originalIndex = 0;
};
static_assert( sizeof( SmallRecord ) == 8 );

std::uint32_t nextRandom( std::uint32_t& state )
{
    const std::uint64_t next = std::uint64_t( state ) * 1664525u + 1013904223u;
    state = std::uint32_t( next & 0xffffffffu );
    return state;
}

template<class Value>
void deterministicShuffle( std::vector<Value>& values, std::uint32_t state )
{
    for( std::size_t valueCount = values.size(); valueCount > 1; --valueCount )
    {
        const std::size_t otherIndex = std::size_t( std::uint64_t( nextRandom( state ) ) % valueCount );
        std::swap( values[ valueCount - 1 ], values[ otherIndex ] );
    }
}

template<class Value, class Less>
void stableReferenceSort( std::vector<Value>& values, Less less )
{
    if( values.size() < 2 )
        return;
    std::vector<Value> scratch( values.size() );
    Value* source = values.data();
    Value* destination = scratch.data();
    bool sourceIsScratch = false;
    std::size_t width = 1;
    while( width < values.size() )
    {
        std::size_t begin = 0;
        while( begin < values.size() )
        {
            const std::size_t middle = begin + std::min( width, values.size() - begin );
            const std::size_t end = middle + std::min( width, values.size() - middle );
            std::size_t left = begin;
            std::size_t right = middle;
            std::size_t out = begin;
            while( left < middle && right < end )
            {
                if( less( source[ right ], source[ left ] ) )
                    destination[ out++ ] = source[ right++ ];
                else
                    destination[ out++ ] = source[ left++ ];
            }
            while( left < middle ) destination[ out++ ] = source[ left++ ];
            while( right < end ) destination[ out++ ] = source[ right++ ];
            begin = end;
        }
        std::swap( source, destination );
        sourceIsScratch = !sourceIsScratch;
        if( width > values.size() / 2 )
            break;
        width *= 2;
    }
    if( sourceIsScratch )
        std::copy( source, source + values.size(), values.data() );
}

template<class Key>
void checkLargeSort( const std::vector<Key>& keys )
{
    std::vector<std::uint32_t> expected( keys.size() );
    std::iota( expected.begin(), expected.end(), 0u );
    stableReferenceSort( expected, [ & ]( std::uint32_t a, std::uint32_t b ) { return keys[ a ] < keys[ b ]; } );

    std::vector<std::uint32_t> order( keys.size() );
    std::vector<std::uint32_t> scratch( keys.size() );
    radix::sortKeyLarge( keys.data(), order.data(), scratch.data(), keys.size() );
    CHECK( order == expected );

    std::vector<radix::WordIndex> pairScratch( keys.size() * 2 );
    radix::sortKeyLargePairs( keys.data(), order.data(), pairScratch.data(), keys.size() );
    CHECK( order == expected );
}

std::vector<std::uint32_t> makeU32Keys( std::size_t count )
{
    std::uint32_t state = 0xC7A6u ^ std::uint32_t( count );
    std::vector<std::uint32_t> keys( count );
    for( std::size_t keyIndex = 0; keyIndex < count; ++keyIndex )
        keys[ keyIndex ] = keyIndex % 7 == 0 ? 42u : nextRandom( state );
    return keys;
}

std::vector<float> makeFloatKeys( std::size_t count )
{
    std::uint32_t state = 0xF10A7u ^ std::uint32_t( count );
    std::vector<float> keys( count );
    for( std::size_t keyIndex = 0; keyIndex < count; ++keyIndex )
    {
        const std::int32_t signedValue = std::int32_t( nextRandom( state ) % 20001u ) - 10000;
        keys[ keyIndex ] = keyIndex % 11 == 0 ? ( keyIndex % 22 == 0 ? -0.0f : 0.0f ) : float( signedValue ) * 0.125f;
    }
    return keys;
}

void verifyLargePaths()
{
    for( const std::size_t count : { std::size_t( 0 ), std::size_t( 1 ), std::size_t( 2 ), std::size_t( 15 ), std::size_t( 255 ),
                                     std::size_t( 256 ), std::size_t( 257 ), std::size_t( 2047 ), std::size_t( 2048 ), std::size_t( 65537 ) } )
    {
        const std::vector<std::uint32_t> u32Keys = makeU32Keys( count );
        std::vector<std::uint8_t> u8Keys( count );
        std::vector<std::uint16_t> u16Keys( count );
        for( std::size_t keyIndex = 0; keyIndex < count; ++keyIndex )
        {
            u8Keys[ keyIndex ] = std::uint8_t( u32Keys[ keyIndex ] & 0xffu );
            u16Keys[ keyIndex ] = std::uint16_t( u32Keys[ keyIndex ] & 0xffffu );
        }
        checkLargeSort( u8Keys );
        checkLargeSort( u16Keys );
        checkLargeSort( u32Keys );
        checkLargeSort( makeFloatKeys( count ) );

        std::vector<std::uint64_t> u64Keys( count );
        for( std::size_t keyIndex = 0; keyIndex < count; ++keyIndex )
            u64Keys[ keyIndex ] = ( std::uint64_t( u32Keys[ keyIndex ] ) << 32 ) | std::uint64_t( u32Keys[ count - keyIndex - 1 ] );
        std::vector<std::uint32_t> expected( count );
        std::iota( expected.begin(), expected.end(), 0u );
        stableReferenceSort( expected, [ & ]( std::uint32_t a, std::uint32_t b ) { return u64Keys[ a ] < u64Keys[ b ]; } );
        std::vector<std::uint32_t> order( count );
        std::vector<std::uint32_t> scratch( count );
        radix::sortKeyLarge( u64Keys.data(), order.data(), scratch.data(), count );
        CHECK( order == expected );
    }

    for( std::vector<std::uint32_t> keys : { std::vector<std::uint32_t>( 4096, 7u ), makeU32Keys( 4096 ) } )
    {
        checkLargeSort( keys );
        stableReferenceSort( keys, []( std::uint32_t a, std::uint32_t b ) { return a < b; } );
        checkLargeSort( keys );
        std::reverse( keys.begin(), keys.end() );
        checkLargeSort( keys );
    }
}

void verifySmallAndIndexedPaths()
{
    constexpr std::size_t kCount = 4097;
    std::vector<SmallRecord> records( kCount );
    for( std::size_t recordIndex = 0; recordIndex < kCount; ++recordIndex )
        records[ recordIndex ] = SmallRecord{ std::uint32_t( recordIndex % 19 ), std::uint32_t( recordIndex ) };

    std::vector<SmallRecord> expected = records;
    stableReferenceSort( expected, []( const SmallRecord& a, const SmallRecord& b ) { return a.key < b.key; } );
    std::vector<SmallRecord> scratchRecords( kCount );
    radix::sortKeySmall( records.data(), scratchRecords.data(), records.size(), []( const SmallRecord& record ) { return record.key; } );
    REQUIRE( records.size() == expected.size() );
    for( std::size_t recordIndex = 0; recordIndex < records.size(); ++recordIndex )
    {
        CHECK( records[ recordIndex ].key == expected[ recordIndex ].key );
        CHECK( records[ recordIndex ].originalIndex == expected[ recordIndex ].originalIndex );
    }

    const std::vector<std::uint32_t> keys = makeU32Keys( kCount );
    std::vector<std::uint32_t> subset;
    for( std::uint32_t keyIndex = 0; keyIndex < keys.size(); ++keyIndex )
        if( keyIndex % 3 != 0 )
            subset.push_back( keyIndex );
    std::vector<std::uint32_t> expectedSubset = subset;
    stableReferenceSort( expectedSubset, [ & ]( std::uint32_t a, std::uint32_t b ) { return keys[ a ] < keys[ b ]; } );
    std::vector<std::uint32_t> subsetScratch( subset.size() );
    radix::sortKeyLargeIndexed( keys.data(), subset.data(), subsetScratch.data(), subset.size() );
    CHECK( subset == expectedSubset );

    deterministicShuffle( subset, 0x51A7u );
    expectedSubset = subset;
    stableReferenceSort( expectedSubset, [ & ]( std::uint32_t a, std::uint32_t b ) { return keys[ a ] < keys[ b ]; } );
    radix::sortKeyLargeIndexed( keys.data(), subset.data(), subsetScratch.data(), subset.size() );
    CHECK( subset == expectedSubset );

    std::vector<float> floatRecords = makeFloatKeys( kCount );
    std::vector<float> expectedFloats = floatRecords;
    stableReferenceSort( expectedFloats, []( float a, float b ) { return a < b; } );
    std::vector<float> floatScratch( kCount );
    radix::sortKeySmall( floatRecords.data(), floatScratch.data(), floatRecords.size(), []( float value ) { return value; } );
    CHECK( floatRecords == expectedFloats );
}

struct EdgeRecord
{
    std::uint32_t from = 0;
    std::uint32_t to = 0;
    std::uint32_t originalIndex = 0;
};
static_assert( sizeof( EdgeRecord ) == 12 );

void verifyRipwireWrappers()
{
    for( const std::size_t count : { std::size_t( 2047 ), std::size_t( 2048 ), std::size_t( 2049 ), std::size_t( 65537 ) } )
    {
        const std::vector<float> scores = makeFloatKeys( count );
        std::vector<float> nonnegativeScores( count );
        for( std::size_t scoreIndex = 0; scoreIndex < count; ++scoreIndex )
            nonnegativeScores[ scoreIndex ] = scores[ scoreIndex ] < 0.f ? -scores[ scoreIndex ] : scores[ scoreIndex ];
        std::vector<std::uint32_t> order( count );
        std::iota( order.begin(), order.end(), 0u );
        const std::uint32_t shuffleSeed = 0xD35Cu ^ std::uint32_t( count );
        deterministicShuffle( order, shuffleSeed );
        std::vector<std::uint32_t> expected = order;
        stableReferenceSort( expected, [ & ]( std::uint32_t a, std::uint32_t b )
        {
            return rw::sortutil::lessByScoreDescId( nonnegativeScores, a, b );
        } );
        std::vector<std::uint32_t> scratch;
        rw::sortutil::radixSortByScoreDescId( order, nonnegativeScores, scratch );
        CHECK( order == expected );

        std::vector<float> adaptive = nonnegativeScores;
        rw::sortutil::radixSortNonNegativeFloatsDesc( adaptive );
        for( std::size_t scoreIndex = 1; scoreIndex < adaptive.size(); ++scoreIndex )
            CHECK( adaptive[ scoreIndex - 1 ] >= adaptive[ scoreIndex ] );

        std::vector<EdgeRecord> edges( count );
        for( std::size_t edgeIndex = 0; edgeIndex < count; ++edgeIndex )
            edges[ edgeIndex ] = EdgeRecord{ std::uint32_t( edgeIndex % 31 ), std::uint32_t( edgeIndex % 17 ), std::uint32_t( edgeIndex ) };
        deterministicShuffle( edges, shuffleSeed ^ 0xED6Eu );
        std::vector<EdgeRecord> expectedEdges = edges;
        stableReferenceSort( expectedEdges, rw::sortutil::lessByFromTo<EdgeRecord> );
        std::vector<EdgeRecord> edgeScratch;
        rw::sortutil::radixSortByFromTo( edges, edgeScratch );
        REQUIRE( edges.size() == expectedEdges.size() );
        for( std::size_t edgeIndex = 0; edgeIndex < edges.size(); ++edgeIndex )
        {
            CHECK( edges[ edgeIndex ].from == expectedEdges[ edgeIndex ].from );
            CHECK( edges[ edgeIndex ].to == expectedEdges[ edgeIndex ].to );
            if( count >= 2048 )
                CHECK( edges[ edgeIndex ].originalIndex == expectedEdges[ edgeIndex ].originalIndex );
        }
    }
}

void verifyQuantization()
{
    CHECK( radix::quantizeFloatToU16( -2.f, -1.f, 1.f ) == 0u );
    CHECK( radix::quantizeFloatToU16( 2.f, -1.f, 1.f ) == UINT16_MAX );
    CHECK( radix::quantizeFloatToU16( 0.f, -1.f, 1.f ) == 32768u );
    CHECK( radix::quantizeFloatToU16Signed1024( -1024.f ) == 0u );
    CHECK( radix::quantizeFloatToU16Signed1024( 1024.f ) == UINT16_MAX );
}

}

int main()
{
    verifyLargePaths();
    verifySmallAndIndexedPaths();
    verifyRipwireWrappers();
    verifyQuantization();
    std::puts( "radix gate: PASS" );
    return 0;
}
