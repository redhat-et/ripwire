// clonepersist_harness.cpp — the CLONES-PERSIST harness for src/clones.h (cloneBodyKey + the two-pass findClones).
// Compiled by test/clonepersistcheck.sh against the shipped clones.h AND against a mutated copy whose verify step
// is removed (every member of a shared key is grouped unread); the gate requires the shipped build to pass and
// the mutant to fail K4, so the exact verification is proven load-bearing.
//
// Checks (each prints PASS/FAIL; any FAIL exits 2):
//   K1  key identity: two bodies with the same normalized stream (renamed identifiers, other literals) get the
//       SAME key; a body that differs by one operator gets a DIFFERENT key; the token field equals normalizeSpan's.
//   K2  a computed key is never kCloneKeyNone (0), even for an empty body.
//   K3  the token field SATURATES at 2^24-1 (a 2^24-token body), and a saturated key is verified, never rejected:
//       minTokens=2^24 still groups two identical 2^24-token bodies.
//   K4  forced collision: three bodies A, B, C where A == C and B differs, with ALL keys forced EQUAL — findClones
//       emits exactly one group {A, C}. (The mutant without the verify step emits {A, B, C}.)
//   K5  keyless parity: the same corpus with cloneKeys empty (size mismatch), with keys computed by cloneBodyKey,
//       and with half the keys 0 gives byte-identical group listings.
//   K6  an unreadable member of a shared key drops out; the rest still group (never a crash).
//   K7  order: biggest first, then path, line, first id — two groups whose first members share file and line
//       come out in id order.
//
// Touches only files under argv[1].

#include "clones.h"

#include <cstdio>
#include <fstream>
#include <cstdint>
#include <string>
#include <vector>

using namespace rw;

static int g_fail = 0;
static void check( bool cond, const char* msg )
{
    std::printf( "  %s  %s\n", cond ? "PASS" : "FAIL", msg );
    if( !cond )
    {
        g_fail = 1;
    }
}

static std::string writeFile( const std::string& dir, const std::string& name, const std::string& src )
{
    std::ofstream( dir + "/" + name, std::ios::binary ) << src;
    return dir + "/" + name;
}

// one function symbol per body; `bodies` are written one file each unless `sameFile`, which puts them all in one
// file on ONE line (the K7 tie). Keys come from cloneBodyKey unless the caller overwrites ing.cloneKeys.
static IngestResult corpus( const std::string& dir, const std::string& tag, const std::vector<std::string>& bodies, bool sameFile )
{
    IngestResult ing;
    if( sameFile )
    {
        std::string all;
        std::vector<std::pair<std::uint32_t, std::uint32_t>> spans;
        for( const std::string& b : bodies )
        {
            const std::uint32_t at = std::uint32_t( all.size() );
            all += b;
            spans.push_back( { at, std::uint32_t( all.size() ) } );
            all += ' ';
        }
        ing.files.push_back( writeFile( dir, tag + ".c", all ) );
        for( const auto& [a, b] : spans )
        {
            Symbol s;
            s.id = NodeId( ing.symbols.size() ); s.kind = SymKind::Function; s.lang = Lang::C; s.fileId = 0; s.line = 1;
            s.sigStartByte = a; s.sigEndByte = a; s.endByte = b; s.name = "fn" + std::to_string( s.id );
            ing.cloneKeys.push_back( cloneBodyKey( all, a, b, false ) );
            ing.symbols.push_back( std::move( s ) );
        }
        return ing;
    }
    for( std::size_t i = 0; i < bodies.size(); ++i )
    {
        ing.files.push_back( writeFile( dir, tag + std::to_string( i ) + ".c", bodies[i] ) );
        Symbol s;
        s.id = NodeId( ing.symbols.size() ); s.kind = SymKind::Function; s.lang = Lang::C; s.fileId = std::uint32_t( i ); s.line = 1;
        s.sigStartByte = 0; s.sigEndByte = 0; s.endByte = std::uint32_t( bodies[i].size() ); s.name = "fn" + std::to_string( s.id );
        ing.cloneKeys.push_back( cloneBodyKey( bodies[i], 0, std::uint32_t( bodies[i].size() ), false ) );
        ing.symbols.push_back( std::move( s ) );
    }
    return ing;
}

static std::string listing( const std::vector<CloneGroup>& groups )
{
    std::string out;
    for( const CloneGroup& g : groups )
    {
        out += "GROUP tokens=" + std::to_string( g.tokens ) + ":";
        for( NodeId m : g.members )
        {
            out += " " + std::to_string( m );
        }
        out += "\n";
    }
    return out;
}

// a body of exactly `stmts` statements `x = y + 1;` (6 tokens each) plus braces, with identifier/literal spelling `v`
static std::string body( int stmts, const std::string& v, const char* op = "+" )
{
    std::string s = "{ ";
    for( int i = 0; i < stmts; ++i )
    {
        s += v + "a" + std::to_string( i ) + " = " + v + "b " + op + " " + std::to_string( i + 7 ) + "; ";
    }
    return s + "}";
}

int main( int argc, char** argv )
{
    if( argc < 2 )
    {
        std::printf( "usage: clonepersist_harness <scratch-dir>\n" );
        return 2;
    }
    const std::string dir = argv[1];

    // K1
    {
        const std::string a = body( 10, "p" ), c = body( 10, "q" ), b = body( 10, "p", "-" );
        std::uint32_t     tc = 0;
        normalizeSpan( a, 0, std::uint32_t( a.size() ), tc );
        const std::uint64_t ka = cloneBodyKey( a, 0, std::uint32_t( a.size() ), false );
        const std::uint64_t kc = cloneBodyKey( c, 0, std::uint32_t( c.size() ), false );
        const std::uint64_t kb = cloneBodyKey( b, 0, std::uint32_t( b.size() ), false );
        check( ka == kc, "K1 renamed identifiers and other literals give the same key" );
        check( ka != kb, "K1 one changed operator gives a different key" );
        check( cloneKeyTokens( ka ) == tc && tc == 62, "K1 the key's token field equals normalizeSpan's count (62)" );
    }
    // K2
    {
        const std::string empty;
        check( cloneBodyKey( empty, 0, 0, false ) != kCloneKeyNone, "K2 an empty body still has a non-zero key" );
    }
    // K3
    {
        std::string big;
        big.reserve( std::size_t( 2 ) << 24 );
        for( std::uint32_t i = 0; i < ( std::uint32_t( 1 ) << 24 ); ++i )
        {
            big += "; ";
        }
        const std::uint64_t k = cloneBodyKey( big, 0, std::uint32_t( big.size() ), false );
        check( cloneKeyTokens( k ) == kCloneKeyTokenMask, "K3 a 2^24-token body saturates the token field at 2^24-1" );
        // minTokens above the saturated field: the key is a floor, so two identical 2^24-token bodies still group
        IngestResult      ing = corpus( dir, "k3_", { big, big }, false );
        const std::string got = listing( findClones( ing, int( std::uint32_t( 1 ) << 24 ) ) );
        check( got == "GROUP tokens=16777216: 0 1\n", "K3 minTokens=2^24 still groups two identical 2^24-token bodies (a saturated key is verified, not rejected)" );
    }
    // K4
    {
        IngestResult ing = corpus( dir, "k4_", { body( 10, "p" ), body( 10, "p", "*" ), body( 10, "z" ) }, false );
        const std::uint64_t forced = ing.cloneKeys[0];
        for( std::uint64_t& k : ing.cloneKeys )
        {
            k = forced;
        }
        const std::string got = listing( findClones( ing, 40 ) );
        std::printf( "%s", got.c_str() );
        check( got == "GROUP tokens=62: 0 2\n", "K4 forced-equal keys: exactly one group {A, C}; B (a real difference) is not a clone" );
    }
    // K5
    {
        const std::vector<std::string> bodies = { body( 12, "a" ), body( 9, "b" ), body( 12, "c" ), body( 9, "d" ), body( 12, "e", "-" ),
                                                  body( 5, "f" ), body( 9, "g" ), body( 12, "h", "-" ) };
        IngestResult      ing   = corpus( dir, "k5_", bodies, false );
        const std::string keyed = listing( findClones( ing, 40 ) );
        for( std::size_t i = 0; i < ing.cloneKeys.size(); i += 2 )
        {
            ing.cloneKeys[i] = kCloneKeyNone;
        }
        const std::string half = listing( findClones( ing, 40 ) );
        ing.cloneKeys.clear();
        const std::string keyless = listing( findClones( ing, 40 ) );
        std::printf( "%s", keyed.c_str() );
        check( keyed == "GROUP tokens=74: 0 2\nGROUP tokens=74: 4 7\nGROUP tokens=56: 1 3 6\n", "K5 keyed corpus: the three true groups, biggest first" );
        check( half == keyed, "K5 half the keys 0: identical groups" );
        check( keyless == keyed, "K5 no key array (size mismatch): identical groups" );
    }
    // K6
    {
        IngestResult ing = corpus( dir, "k6_", { body( 10, "p" ), body( 10, "q" ), body( 10, "r" ) }, false );
        std::remove( ing.files[1].c_str() );
        const std::string got = listing( findClones( ing, 40 ) );
        check( got == "GROUP tokens=62: 0 2\n", "K6 an unreadable member drops out; the other two still group" );
    }
    // K7
    {
        IngestResult      ing = corpus( dir, "k7_", { body( 8, "a" ), body( 8, "b", "-" ), body( 8, "c" ), body( 8, "d", "-" ) }, true );
        const std::string got = listing( findClones( ing, 40 ) );
        std::printf( "%s", got.c_str() );
        check( got == "GROUP tokens=50: 0 2\nGROUP tokens=50: 1 3\n", "K7 a file:line tie orders by first member id" );
    }

    std::printf( g_fail ? "clonepersist_harness: FAIL\n" : "clonepersist_harness: ALL PASS\n" );
    return g_fail ? 2 : 0;
}
