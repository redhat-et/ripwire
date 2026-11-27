// textpool_harness.cpp — test/textpoolcheck.sh's driver for src/infra/internedtext.h and src/refnames.h (MEM-REF-SHRINK step 2).
// Arms (each prints PASS or FAIL and the run exits 1 on any FAIL):
//   A  canonical under concurrency: 8 threads intern the same 30,000 texts in 8 different orders (crossing three segment
//      boundaries); every thread got the same id for a text, distinct texts got distinct ids, and text(id) gives the text back.
//   B  the empty text is id 0 and never takes a slot; an InternedText of "" is empty().
//   C  InternedText's comparisons are the TEXT's: sorting InternedTexts gives std::string's order, == agrees with text equality.
//   D  edits (+=, push_back, assign, clear, operator+) give std::string's answers.
//   E  segment creation under concurrency: 40 fresh pools, 8 threads released together, each interning its own 600 texts, so
//      several threads make the same segment at once (the CAS loser frees its copy and writes into the winner's). Proves no crash,
//      no lost text and (under TSan) no race on what the harness touches. It does NOT observe the segment pointer's
//      acquire/release: a fully relaxed mutant passes, because the shard locks order every access a test can make. That
//      ordering is the formal guarantee only.
//   F  the per-thread front cache (rw::internCached): 8 threads build InternedTexts of the same 30,000 texts twice (30,000 texts over
//      512 slots: hits, misses and evictions); every thread's names equal thread 0's and read back their text.
//   G  hash collisions are resolved by TEXT, not by tag: fixed pairs found by brute force against the vendored
//      ankerl::unordered_dense::hash<std::string_view> (unseeded wyhash). "n85186" / "n1381407" share a pool shard and its
//      32-bit tag (38 bits); "n900597" / "n2694216" share a front-cache slot and its tag. Each pair must get two ids and read
//      back its own text. The arm first re-checks that each pair still collides and FAILS if not (a changed hash must re-derive
//      the pairs, never pass blind). Kills the tag-only-equality mutants of TextPool::intern and internCached.
//   H  (run as `textpool_harness exitrace`, by the gate, several times) a DETACHED thread keeps interning reference names while
//      main returns: the process pool must outlive static destruction (refnames.h NoDestroy). Under ASan a destroyed pool is a
//      heap-use-after-free (seen in 4 of 5 runs of the mutant; the gate runs it 5 times).
//   I  TextPool::lookup / InternedText::ifInterned never insert: an absent text is nullopt and idCount does not move; an interned
//      one comes back equal to its InternedText; the empty text is the empty value; a shard+tag collision (arm G's pair) is
//      told apart by text.
//   J  IdKeyedCsr (K1a LOCALTYPE-PACK): a key's values come back in add order, a repeat within a key is dropped, keys never
//      mix (same owner other name, same name other owner), an add after seal() + seal() appends after the sealed values,
//      found values are mutable in place, and an absent key is an empty span.
//   K  determinism: two tables fed the same adds, whose names were interned in OPPOSITE orders in two pools (so every id
//      differs), answer every lookup identically, value for value.
#include "refnames.h"
#include "infra/idkeyedmap.h"

#include <chrono>

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

// Static storage, not a local of exitRace: the detached thread keeps storing to it after exitRace and main return. A local was
// a stack-use-after-return (Linux ASan's default fake stack reported it, #608 CI); under gcc, which does not check that, the
// stray store landed in the exit path's frames and the run hung until the gate's timeout. std::atomic<bool> is trivially
// destructible, so static destruction leaves it alone.
constinit std::atomic<bool> gExitRaceStarted{ false };

int exitRace()
{
    std::atomic<bool>& started = gExitRaceStarted;
    std::thread( [] {
        for( std::uint64_t i = 0;; ++i )
        {
            rw::InternedText name( std::string_view( "exit_" + std::to_string( i ) ) );
            gExitRaceStarted.store( true, std::memory_order_relaxed );
            if( name.str().empty() )
            {
                std::abort();
            }
        }
    } ).detach();
    while( !started.load() )
    {
        std::this_thread::yield();
    }
    std::this_thread::sleep_for( std::chrono::milliseconds( 80 ) );
    std::printf( "textpool: exitrace returning while the detached thread interns\n" );
    return 0;   // static destruction runs now, with the thread still interning
}

// I. Lookup without insert.
static void armLookup()
{
    const std::uint32_t before = rw::RefNames::pool().idCount();
    const auto absent = rw::InternedText::ifInterned( "never_interned_lookup_text_7f3a" );
    check( !absent.has_value() && rw::RefNames::pool().idCount() == before, "I", "an absent text is nullopt and is not interned" );
    const rw::InternedText have( std::string_view( "lookup_present_text" ) );
    const auto found = rw::InternedText::ifInterned( "lookup_present_text" );
    const auto again = rw::InternedText::ifInterned( "lookup_present_text" );   // the front-cache hit
    check( found.has_value() && *found == have && again.has_value() && *again == have, "I", "an interned text comes back equal" );
    const auto empty = rw::InternedText::ifInterned( "" );
    check( empty.has_value() && empty->empty(), "I", "the empty text is the empty value" );
    rw::TextPool        g;
    const std::uint32_t a = g.intern( "n85186" );
    check( g.lookup( "n85186", rw::TextPool::hashOf( "n85186" ) ) == a && g.lookup( "n1381407", rw::TextPool::hashOf( "n1381407" ) ) == rw::TextPool::kAbsentId,
           "I", "pool lookup tells a shard+tag collision apart by text" );
}

// J. IdKeyedCsr semantics.
static void armCsr()
{
    struct Fact
    {
        int  v = 0;
        bool operator==( const Fact& ) const = default;
    };
    rw::IdKeyedCsr<rw::RefNames, Fact> t;
    const rw::InternedText x( std::string_view( "csr_x" ) ), y( std::string_view( "csr_y" ) );
    t.addUnique( 1, x, { 10 } );
    t.addUnique( 2, x, { 20 } );
    t.addUnique( 1, y, { 30 } );
    t.addUnique( 1, x, { 11 } );
    t.addUnique( 1, x, { 10 } );   // a repeat: dropped
    t.seal();
    const auto ones = t.find( 1, x );
    check( ones.size() == 2 && ones[ 0 ].v == 10 && ones[ 1 ].v == 11, "J", "add order kept, a repeat within a key dropped" );
    check( t.find( 2, x ).size() == 1 && t.find( 2, x )[ 0 ].v == 20 && t.find( 1, y ).size() == 1 && t.find( 1, y )[ 0 ].v == 30,
           "J", "keys never mix across owner or name" );
    check( t.find( 3, x ).empty() && !t.contains( 3, x ) && t.contains( 1, y ), "J", "an absent key is an empty span" );
    t.addUnique( 1, x, { 12 } );
    t.addUnique( 1, x, { 11 } );   // repeats a SEALED value: dropped
    t.addUnique( 4, y, { 40 } );
    t.seal();
    const auto more = t.find( 1, x );
    check( more.size() == 3 && more[ 0 ].v == 10 && more[ 1 ].v == 11 && more[ 2 ].v == 12 && t.find( 4, y ).size() == 1 && t.find( 2, x )[ 0 ].v == 20,
           "J", "a re-seal appends after the sealed values, dropping a repeat of one" );
    t.find( 1, y )[ 0 ].v = 31;
    check( t.find( 1, y )[ 0 ].v == 31 && t.keyCount() == 4 && t.valueCount() == 6, "J", "found values mutate in place" );
}

// K. Same answers whatever the ids.
static void armIdsInvisible()
{
    struct DomA
    {
        static rw::TextPool& pool() { static rw::TextPool p; return p; }
    };
    struct DomB
    {
        static rw::TextPool& pool() { static rw::TextPool p; return p; }
    };
    constexpr std::size_t kNames = 2000;
    std::vector<std::string> names;
    for( std::size_t i = 0; i < kNames; ++i )
    {
        names.push_back( "k_" + std::to_string( i ) );
    }
    for( std::size_t i = 0; i < kNames; ++i )
    {
        DomA::pool().intern( names[ i ] );
        DomB::pool().intern( names[ kNames - 1 - i ] );
    }
    rw::IdKeyedCsr<DomA, int> a;
    rw::IdKeyedCsr<DomB, int> b;
    for( std::size_t i = 0; i < 6 * kNames; ++i )
    {
        const std::size_t   n     = ( i * 7919 ) % kNames;
        const std::uint32_t owner = std::uint32_t( i % 5 );
        a.addUnique( owner, rw::InternedTextOf<DomA>( names[ n ] ), int( i % 7 ) );
        b.addUnique( owner, rw::InternedTextOf<DomB>( names[ n ] ), int( i % 7 ) );
    }
    a.seal();
    b.seal();
    bool same     = rw::InternedTextOf<DomA>( names[ 0 ] ).str() == names[ 0 ];
    std::size_t differingIds = 0;   // the premise: the two pools really gave the names different ids
    for( std::size_t n = 0; n < kNames; ++n )
    {
        differingIds += DomA::pool().lookup( names[ n ], rw::TextPool::hashOf( names[ n ] ) ) != DomB::pool().lookup( names[ n ], rw::TextPool::hashOf( names[ n ] ) ) ? 1 : 0;
        for( std::uint32_t owner = 0; owner < 6; ++owner )
        {
            const auto x = a.find( owner, rw::InternedTextOf<DomA>( names[ n ] ) );
            const auto y = b.find( owner, rw::InternedTextOf<DomB>( names[ n ] ) );
            same = same && std::equal( x.begin(), x.end(), y.begin(), y.end() );
        }
    }
    check( differingIds > kNames / 2, "K", "premise: the two pools gave most names different ids" );
    check( same, "K", "two tables over different ids answer every lookup identically" );
}

int main( int argc, char** argv )
{
    if( argc > 1 && std::string_view( argv[ 1 ] ) == "exitrace" )
    {
        return exitRace();
    }
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
    // C2. <=> against a name and against text, on a strict prefix (libstdc++'s string_view <=> subtracts the sizes there, and the
    // G1 integer sanitizer aborts on the wrap: #608's Linux ASan leg) and on a byte >= 0x80 (memcmp order: unsigned).
    {
        const rw::InternedText shortName( std::string_view( "a" ) ), longName( std::string_view( "abcdefgh" ) ), high( std::string_view( "\xC3\xA9" ) );
        check( ( shortName <=> longName ) < 0 && ( longName <=> shortName ) > 0 && ( shortName <=> std::string_view( "abcdefgh" ) ) < 0
                   && ( longName <=> std::string_view( "a" ) ) > 0 && ( shortName <=> std::string_view( "a" ) ) == 0,
               "C", "<=> on a strict prefix: shorter first, no size subtraction" );
        check( ( shortName <=> high ) < 0 && ( high <=> std::string_view( "z" ) ) > 0, "C", "<=> is unsigned-byte order (memcmp's)" );
    }

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

    // G. Fixed colliding pairs.
    {
        const auto h = []( std::string_view t ) { return rw::TextPool::hashOf( t ); };
        const bool poolPair  = ( h( "n85186" ) >> 58 ) == ( h( "n1381407" ) >> 58 ) && std::uint32_t( h( "n85186" ) ) == std::uint32_t( h( "n1381407" ) );
        const bool frontPair = ( h( "n900597" ) & 511 ) == ( h( "n2694216" ) & 511 ) && ( h( "n900597" ) >> 32 ) == ( h( "n2694216" ) >> 32 );
        check( poolPair && frontPair, "G", "the fixed pairs still collide under the vendored hash (else re-derive them)" );
        rw::TextPool        g;
        const std::uint32_t a = g.intern( "n85186" ), b = g.intern( "n1381407" );
        check( a != b && g.text( a ) == "n85186" && g.text( b ) == "n1381407", "G", "pool: a shard+tag collision gets two ids" );
        const rw::InternedText x( std::string_view( "n900597" ) ), y( std::string_view( "n2694216" ) ), x2( std::string_view( "n900597" ) );
        check( !( x == y ) && x == x2 && x.str() == "n900597" && y.str() == "n2694216", "G", "front cache: a slot+tag collision gets two ids" );
    }

    armLookup();   // I
    armCsr();      // J
    armIdsInvisible();   // K

    std::printf( "textpool: %s\n", gFails == 0 ? "ALL PASS" : "FAILURES" );
    return gFails == 0 ? 0 : 1;
}
