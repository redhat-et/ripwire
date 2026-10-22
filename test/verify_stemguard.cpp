#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "stemguard.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace
{

using rw::StemGuardTable;

std::uint64_t mix( std::uint64_t x )
{
    x += 0x9e3779b97f4a7c15ull;
    x = ( x ^ ( x >> 30 ) ) * 0xbf58476d1ce4e5b9ull;
    x = ( x ^ ( x >> 27 ) ) * 0x94d049bb133111ebull;
    return x ^ ( x >> 31 );
}

struct Rng
{
    std::uint64_t s;
    std::uint64_t next() { return s = mix( s ); }
    int           below( int n ) { return int( next() % std::uint64_t( n ) ); }
    double        unit() { return double( next() >> 11 ) * 0x1.0p-53; }
};

struct Corpus
{
    std::size_t      docs = 0, terms = 0;
    std::vector<int> exact, all, dl;
    double           avgdl = 1.0;
    double           k1 = 1.5, b = 0.75;
    StemGuardTable   table;
    void             build()
    {
        double sum = 0;
        for( int d : dl )
        {
            sum += d;
        }
        avgdl = docs ? sum / double( docs ) : 1.0;
        table = rw::buildStemGuard( docs, terms, exact.data(), all.data(), dl.data(), avgdl, k1, b );
    }
    double word( std::size_t i, std::size_t u ) const { return rw::stemGuardWord( table, exact.data(), dl.data(), avgdl, k1, b, i, u ); }
};

Corpus randomCorpus( Rng& r )
{
    Corpus c;
    c.docs  = std::size_t( 2 + r.below( 40 ) );
    c.terms = std::size_t( 1 + r.below( 4 ) );
    c.k1    = 0.1 + r.unit() * 9.9;
    c.b     = r.unit();
    c.exact.assign( c.docs * c.terms, 0 );
    c.all.assign( c.docs * c.terms, 0 );
    c.dl.assign( c.docs, 0 );
    for( std::size_t i = 0; i < c.docs; ++i )
    {
        c.dl[ i ] = 1 + r.below( 5000 );
        for( std::size_t u = 0; u < c.terms; ++u )
        {
            const int e = r.below( 3 ) == 0 ? 1 + r.below( 50 ) : 0;
            const int s = r.below( 2 ) == 0 ? r.below( 50 ) : 0;
            c.exact[ i * c.terms + u ] = e;
            c.all[ i * c.terms + u ]   = e + s;   // tfStemAll holds the exact tokens too
        }
    }
    c.build();
    return c;
}

// The scorer's query-level arithmetic, unit occurrences and every word kept.
std::vector<double> finals( const Corpus& c, const std::vector<double>& mul, double& peakOut )
{
    double P = 0;
    for( std::size_t u = 0; u < c.terms; ++u )
    {
        P += c.table.cap[ u ];
    }
    peakOut = P;
    std::vector<double> out( c.docs, 0.0 );
    for( std::size_t i = 0; i < c.docs; ++i )
    {
        double s = 0;
        int    k = 0;
        for( std::size_t u = 0; u < c.terms; ++u )
        {
            if( rw::stemGuardMatches( c.table, c.exact.data(), i, u ) )
            {
                s += c.word( i, u );
                k += c.exact[ i * c.terms + u ] > 0 ? 1 : 0;
            }
        }
        out[ i ] = rw::stemGuardTier( P, k, s * mul[ i ] );
    }
    return out;
}

}   // namespace

TEST_CASE( "table: no exact hit anywhere sets the floor to idf and leaves the stem part at zero stem mass" )
{
    Corpus c;
    c.docs = 3; c.terms = 1; c.exact = { 0, 0, 0 }; c.all = { 0, 0, 0 }; c.dl = { 10, 10, 10 };
    c.build();
    CHECK( c.table.floorE[ 0 ] == doctest::Approx( c.table.idf[ 0 ] ) );
    CHECK( c.table.stemMax[ 0 ] == 0 );
    CHECK( c.table.df[ 0 ] == 0 );
    CHECK( c.word( 0, 0 ) == doctest::Approx( 0.0 ) );
    CHECK( c.table.cap[ 0 ] == doctest::Approx( 0.0 ) );
}

TEST_CASE( "table: a stem row below the exact row clamps to zero" )
{
    Corpus c;
    c.docs = 2; c.terms = 1; c.exact = { 3, 0 }; c.all = { 1, 2 }; c.dl = { 10, 10 };
    c.build();
    CHECK( c.table.stemOnly[ 0 ] == 0 );
    CHECK( c.table.stemOnly[ 1 ] == 2 );
}

TEST_CASE( "table: empty inputs give an empty table" )
{
    StemGuardTable t = rw::buildStemGuard( 0, 3, nullptr, nullptr, nullptr, 1.0, 1.5, 0.75 );
    CHECK( t.stemOnly.empty() );
    CHECK( t.cap.empty() );
    t = rw::buildStemGuard( 3, 0, nullptr, nullptr, nullptr, 1.0, 1.5, 0.75 );
    CHECK( t.df.empty() );
}

TEST_CASE( "table: df counts exact or stem and matches a brute-force recount" )
{
    Rng r{ 20261022 };
    for( int round = 0; round < 200; ++round )
    {
        const Corpus c = randomCorpus( r );
        for( std::size_t u = 0; u < c.terms; ++u )
        {
            int n = 0;
            for( std::size_t i = 0; i < c.docs; ++i )
            {
                n += c.all[ i * c.terms + u ] > 0 ? 1 : 0;
            }
            CHECK( c.table.df[ u ] == n );
        }
    }
}

TEST_CASE( "single word: every stem-only score is below every exact score, on 2000 random corpora" )
{
    Rng r{ 20261022 };
    for( int round = 0; round < 2000; ++round )
    {
        const Corpus c = randomCorpus( r );
        for( std::size_t u = 0; u < c.terms; ++u )
        {
            double maxStem = 0, minExact = 1e300;
            for( std::size_t i = 0; i < c.docs; ++i )
            {
                const std::size_t at = i * c.terms + u;
                if( c.exact[ at ] > 0 )
                {
                    minExact = std::min( minExact, c.word( i, u ) );
                }
                else if( c.table.stemOnly[ at ] > 0 )
                {
                    maxStem = std::max( maxStem, c.word( i, u ) );
                }
            }
            if( minExact < 1e300 )
            {
                REQUIRE( maxStem < minExact );
            }
        }
    }
}

TEST_CASE( "tier: more exact words always outscore fewer, under any multiplier in (0, 1]" )
{
    Rng r{ 20261022 };
    for( int round = 0; round < 1000; ++round )
    {
        const Corpus        c = randomCorpus( r );
        std::vector<double> mul( c.docs );
        for( double& m : mul )
        {
            m = 0.05 + 0.95 * r.unit();
        }
        double              P = 0;
        const std::vector<double> f = finals( c, mul, P );
        std::vector<int>    k( c.docs, 0 );
        for( std::size_t i = 0; i < c.docs; ++i )
        {
            for( std::size_t u = 0; u < c.terms; ++u )
            {
                k[ i ] += c.exact[ i * c.terms + u ] > 0 ? 1 : 0;
            }
        }
        for( std::size_t i = 0; i < c.docs; ++i )
        {
            for( std::size_t j = 0; j < c.docs; ++j )
            {
                if( k[ i ] > k[ j ] && f[ j ] > 0 )
                {
                    REQUIRE( f[ i ] > f[ j ] );
                }
            }
        }
    }
}

TEST_CASE( "bound: P covers every summed score, and cap covers every word score" )
{
    Rng r{ 20261022 };
    for( int round = 0; round < 1000; ++round )
    {
        const Corpus c = randomCorpus( r );
        double       P = 0;
        for( std::size_t u = 0; u < c.terms; ++u )
        {
            P += c.table.cap[ u ];
        }
        for( std::size_t i = 0; i < c.docs; ++i )
        {
            double s = 0;
            for( std::size_t u = 0; u < c.terms; ++u )
            {
                REQUIRE( c.word( i, u ) <= c.table.cap[ u ] );
                s += c.word( i, u );
            }
            REQUIRE( s <= P );
        }
    }
}

TEST_CASE( "bound: one symbol holding the max tf for every term stays under P" )
{
    Corpus c;
    c.docs = 3; c.terms = 3;
    c.exact = { 50, 50, 50,  0, 0, 0,  1, 1, 1 };
    c.all   = { 50, 50, 50, 40, 40, 40,  1, 1, 1 };
    c.dl    = { 1, 5000, 10 };
    c.build();
    double P = 0;
    for( std::size_t u = 0; u < 3; ++u )
    {
        P += c.table.cap[ u ];
    }
    double s = 0;
    for( std::size_t u = 0; u < 3; ++u )
    {
        s += c.word( 0, u );
    }
    CHECK( s <= P );
}

TEST_CASE( "synthetic: one long exact file beats three short stem files" )
{
    Corpus c;
    c.docs = 4; c.terms = 1;
    c.exact = { 1, 0, 0, 0 };
    c.all   = { 1, 9, 9, 9 };
    c.dl    = { 4000, 20, 20, 20 };
    c.build();
    for( std::size_t i = 1; i < 4; ++i )
    {
        CHECK( c.word( 0, 0 ) > c.word( i, 0 ) );
    }
    CHECK( c.word( 1, 0 ) > 0.0 );
}

TEST_CASE( "pair: one exact word beats two stem words, which beat one stem word" )
{
    Corpus c;
    c.docs = 5; c.terms = 2;
    //            doc0 exact on t0 | doc1 stem on both | doc2 stem on t0 | filler
    c.exact = { 2, 0,  0, 0,  0, 0,  0, 0,  0, 0 };
    c.all   = { 2, 0,  1, 1,  1, 0,  0, 0,  0, 0 };
    c.dl    = { 10, 10, 10, 10, 10 };
    c.build();
    const std::vector<double> mul( c.docs, 1.0 );
    double                    P = 0;
    const std::vector<double> f = finals( c, mul, P );
    CHECK( f[ 0 ] > f[ 1 ] );
    CHECK( f[ 1 ] > f[ 2 ] );
    CHECK( f[ 2 ] > 0.0 );
    CHECK( f[ 3 ] == doctest::Approx( 0.0 ) );
}

TEST_CASE( "two-word trap: tier k=1 is deterministic and below tier k=2" )
{
    Corpus c;
    c.docs = 4; c.terms = 2;
    c.exact = { 1, 1,  1, 0,  0, 1,  0, 0 };
    c.all   = { 1, 1,  1, 5,  5, 1,  0, 0 };
    c.dl    = { 10, 10, 10, 10 };
    c.build();
    const std::vector<double> mul( c.docs, 1.0 );
    double                    P1 = 0, P2 = 0;
    const std::vector<double> a = finals( c, mul, P1 );
    const std::vector<double> b = finals( c, mul, P2 );
    CHECK( a == b );
    CHECK( a[ 0 ] > a[ 1 ] );
    CHECK( a[ 0 ] > a[ 2 ] );
    CHECK( a[ 1 ] > 0.0 );
    CHECK( a[ 2 ] > 0.0 );
}

TEST_CASE( "match: any and all follow the exact-or-stem rule" )
{
    Corpus c;
    c.docs = 3; c.terms = 2;
    c.exact = { 1, 1,  1, 0,  0, 0 };
    c.all   = { 1, 1,  1, 2,  0, 0 };
    c.dl    = { 10, 10, 10 };
    c.build();
    auto holdsAll = [&]( std::size_t i ) {
        return rw::stemGuardMatches( c.table, c.exact.data(), i, 0 ) && rw::stemGuardMatches( c.table, c.exact.data(), i, 1 );
    };
    CHECK( holdsAll( 0 ) );
    CHECK( holdsAll( 1 ) );   // doc1 holds term 1 only as a stem
    CHECK( !holdsAll( 2 ) );
    CHECK( rw::stemGuardMatches( c.table, c.exact.data(), 1, 0 ) );
    CHECK( !rw::stemGuardMatches( c.table, c.exact.data(), 2, 0 ) );
}

TEST_CASE( "tier: an unmatched symbol stays at zero" )
{
    CHECK( rw::stemGuardTier( 100.0, 0, 0.0 ) == doctest::Approx( 0.0 ) );
    CHECK( rw::stemGuardTier( 100.0, 2, 3.0 ) == doctest::Approx( 2 * 101.0 + 3.0 ) );
}
