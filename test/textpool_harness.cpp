// textpool_harness.cpp — test/textpoolcheck.sh's driver for src/infra/internedtext.h (MEM-REF-SHRINK step 2).
// Arms (each prints PASS or FAIL and the run exits 1 on any FAIL):
//   A  canonical under concurrency: 8 threads intern the same 30,000 texts in 8 different orders (crossing three segment
//      boundaries); every thread got the same id for a text, distinct texts got distinct ids, and text(id) gives the text back.
//   B  the empty text is id 0 and never takes a slot; an InternedText of "" is empty().
//   C  InternedText's comparisons are the TEXT's: sorting InternedTexts gives std::string's order, == agrees with text equality.
//   D  edits (+=, push_back, assign, clear, operator+) give std::string's answers.
//   E  segment creation races: 40 fresh pools, 8 threads released together, each interning its own 600 texts, so several
//      threads make the same segment at once (the CAS loser frees its copy and writes into the winner's); under TSan a relaxed
//      publish is a reported race. Every text reads back.
//   F  the per-thread front cache (internRefText): 8 threads build InternedTexts of the same 30,000 texts twice (the second pass
//      hits the cache) plus 4,096-apart colliding indices; every thread's names equal thread 0's and read back their text.
#include "internedtext.h"

#include <algorithm>
#include <atomic>
#include <memory>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>

namespace
{
int gFails = 0;
void check( bool ok, const char* arm, const char* what )
{
    std::printf( "  %s  %s %s\n", ok ? "PASS" : "FAIL", arm, what );
    gFails += ok ? 0 : 1;
}
std::string textOf( std::size_t i ) { return "name_" + std::to_string( i * 7919 % 100003 ) + ( i % 3 == 0 ? std::string( 30, 'x' ) : "" ); }
}

int main()
{
    // A. Eight threads, the same texts, eight orders.
    static rw::TextPool   pool;
    constexpr std::size_t kTexts = 30000, kThreads = 8;
    constexpr std::size_t kStride[ kThreads ] = { 1, 7, 11, 13, 17, 19, 23, 29 };   // coprime with kTexts: each order is a permutation
    std::vector<std::string> texts;
    for( std::size_t i = 0; i < kTexts; ++i )
    {
        texts.push_back( textOf( i ) );
    }
    std::vector<std::vector<std::uint32_t>> ids( kThreads, std::vector<std::uint32_t>( kTexts ) );
    std::vector<std::thread> workers;
    for( std::size_t t = 0; t < kThreads; ++t )
    {
        workers.emplace_back( [ &, t ] {
            for( std::size_t k = 0; k < kTexts; ++k )
            {
                const std::size_t i = ( t % 2 == 0 ) ? ( k * kStride[ t ] ) % kTexts : kTexts - 1 - ( k * kStride[ t ] ) % kTexts;
                ids[ t ][ i ] = pool.intern( texts[ i ] );
            }
        } );
    }
    for( std::thread& w : workers )
    {
        w.join();
    }
    bool same = true, roundTrip = true;
    for( std::size_t i = 0; i < kTexts; ++i )
    {
        for( std::size_t t = 1; t < kThreads; ++t )
        {
            same = same && ids[ t ][ i ] == ids[ 0 ][ i ];
        }
        roundTrip = roundTrip && pool.text( ids[ 0 ][ i ] ) == texts[ i ];
    }
    std::vector<std::uint32_t> sorted = ids[ 0 ];
    std::ranges::sort( sorted );
    const bool distinct = std::ranges::adjacent_find( sorted ) == sorted.end() && sorted.front() != rw::TextPool::kEmptyId;
    check( same, "A", "every thread got one id per text" );
    check( distinct, "A", "distinct texts got distinct non-empty ids" );
    check( roundTrip, "A", "text(id) gives the text back" );
    check( sorted.back() == kTexts, "A", "ids are dense: the last is the text count (no slot taken twice)" );

    // B. The empty text.
    check( pool.intern( "" ) == rw::TextPool::kEmptyId && pool.text( rw::TextPool::kEmptyId ).empty(), "B", "\"\" is id 0 with empty text" );
    check( rw::InternedText( std::string_view() ).empty() && !rw::InternedText( std::string_view( "a" ) ).empty(), "B", "InternedText(\"\").empty()" );

    // C. Order and equality are the text's.
    const std::vector<std::string> words = { "zeta", "alpha", "", "alphabet", "Beta", "alpha", "m" };
    std::vector<rw::InternedText> named;
    for( const std::string& w : words )
    {
        named.emplace_back( w );
    }
    std::vector<std::string> byString = words;
    std::ranges::sort( byString );
    std::ranges::sort( named );
    bool order = true;
    for( std::size_t i = 0; i < words.size(); ++i )
    {
        order = order && named[ i ] == std::string_view( byString[ i ] );
    }
    check( order, "C", "sorting InternedTexts gives std::string's order" );
    check( rw::InternedText( std::string_view( "alpha" ) ) == rw::InternedText( std::string_view( "alpha" ) )
               && !( rw::InternedText( std::string_view( "alpha" ) ) == rw::InternedText( std::string_view( "alphabet" ) ) ),
           "C", "== agrees with text equality" );

    // D. Edits.
    rw::InternedText e;
    e = std::string( "ab" );
    e += "cd";
    e.push_back( '=' );
    check( e == std::string_view( "abcd=" ), "D", "+= and push_back" );
    check( e + "x" == "abcd=x" && "<" + e == "<abcd=" && e + e == "abcd=abcd=", "D", "operator+" );
    e.assign( "q" );
    check( e == std::string_view( "q" ) && e.size() == 1, "D", "assign" );
    e.clear();
    check( e.empty() && e == std::string_view(), "D", "clear" );

    // E. Fresh pools, threads released together.
    bool raced = true;
    for( int round = 0; round < 40; ++round )
    {
        auto                     fresh = std::make_unique<rw::TextPool>();
        std::atomic<int>         ready{ 0 };
        std::vector<std::thread> racers;
        std::vector<std::vector<std::uint32_t>> got( kThreads, std::vector<std::uint32_t>( 600 ) );
        for( std::size_t t = 0; t < kThreads; ++t )
        {
            racers.emplace_back( [ &, t ] {
                ready.fetch_add( 1 );
                while( ready.load() < int( kThreads ) )
                {
                }
                for( std::size_t k = 0; k < 600; ++k )
                {
                    got[ t ][ k ] = fresh->intern( texts[ t * 600 + k ] );
                }
            } );
        }
        for( std::thread& r : racers )
        {
            r.join();
        }
        for( std::size_t t = 0; t < kThreads; ++t )
        {
            for( std::size_t k = 0; k < 600; ++k )
            {
                raced = raced && fresh->text( got[ t ][ k ] ) == texts[ t * 600 + k ];
            }
        }
    }
    check( raced, "E", "40 pools with 8 threads making segments together: every text reads back" );

    // F. The front cache on the process-wide pool.
    std::vector<std::vector<rw::InternedText>> names( kThreads, std::vector<rw::InternedText>( kTexts ) );
    std::vector<std::thread> namers;
    for( std::size_t t = 0; t < kThreads; ++t )
    {
        namers.emplace_back( [ &, t ] {
            for( int pass = 0; pass < 2; ++pass )
            {
                for( std::size_t k = 0; k < kTexts; ++k )
                {
                    const std::size_t i = ( k * kStride[ t ] ) % kTexts;
                    names[ t ][ i ]     = texts[ i ];
                }
            }
        } );
    }
    for( std::thread& n : namers )
    {
        n.join();
    }
    bool cached = true;
    for( std::size_t i = 0; i < kTexts; ++i )
    {
        cached = cached && names[ 0 ][ i ] == std::string_view( texts[ i ] );
        for( std::size_t t = 1; t < kThreads; ++t )
        {
            cached = cached && names[ t ][ i ] == names[ 0 ][ i ];
        }
    }
    check( cached, "F", "front-cached names from 8 threads agree and read back" );

    std::printf( "textpool: %s\n", gFails == 0 ? "ALL PASS" : "FAILURES" );
    return gFails == 0 ? 0 : 1;
}
