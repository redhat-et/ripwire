// verify_strkern.cpp — the doctest gate for src/infra/strkern.h: SIMD-vs-scalar parity for every kernel,
// the tokenizer-equivalence arm for src/lexindex.h's mask-driven walkers, and the byte-identity arm for
// the three emit escapers the run-copy rewrite touched (rw::escapeXml and rw::appendCdataSafe in
// src/serialize.h, rw::jsonesc::escapeInto in src/infra/jsonesc.h).
//
// It replaces two standalone harnesses — test/strkern_harness.cpp (14 arms) and
// test/emitescape_harness.cpp (4 arms) — with one target in the repo's own doctest form
// (test/verify_csr.cpp, test/verify_pagerank.cpp): DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN, one TEST_CASE per
// kernel and per escaper arm, one CHECK/REQUIRE per assertion, built as the CMake target
// `ripwire_test_strkern` beside `ripwire_test_csr`. Every arm of both harnesses is preserved, including
// both fixed-seed corpora, the all-256-bytes-at-every-offset sweep, and both mutation controls.
//
//   A  classMasks            — per-byte [A-Z]/[a-z]/[0-9]/alnum bitmasks over one block, vector path vs
//                              the range-test oracle, for EVERY length 0..kBlockBytes.
//   B  lowerFoldAscii        — in-place A-Z fold, vector vs SWAR-scalar, on buffers that straddle every
//                              block boundary.
//   C  lowerFoldedEquals     — folded compare vs the scalar twin, including every single-byte difference
//                              position and the case-only differences that are the point of the kernel.
//   D  findByte / find3      — first-occurrence scans vs the scalar twins AND vs a naive memchr/memcmp
//                              oracle, needle present and absent, matches at 0 / at n-1 / straddling.
//   E  findByteset           — 256-bit set scan; sets built to hit the (b>>3, b&7) packing's seams
//                              (empty, full, the 0x80 boundary, one byte only, the XML-escape set) —
//                              vector == the SHIPPED scalar tail == the re-deriving ORACLE == naive.
//   E0 Byteset256            — the set stores TWO derivations of itself (bits for the SIMD table lookups,
//                              words for the scalar tail's O(1) test), both written by add(). This arm
//                              reads both back for every set and every byte value; it is the arm that
//                              exists because the 2026-09-10 tail defect was invisible to all the others.
//   F  tokenizer equivalence — forEachLexSubtoken / forEachLexSubtokenHashed as shipped vs VERBATIM
//                              copies of the pre-2026-09-10 byte-at-a-time walkers kept in this file.
//   G  real text             — every arm above re-run over every byte of the repo's src/ and docs/.
//   H  escapers              — the three emit escapers vs the ORIGINAL per-byte loops, frozen verbatim
//                              here as `*Ref`, over 222k adversarial inputs.
//
// Corpora: (1) a fixed-seed random sweep — 100k buffers, lengths 0..300, drawn from four alphabets
// (identifier-ish, full ASCII, high-bit/UTF-8, and a camel/acronym-dense generator that manufactures the
// exact seams the tokenizer rule turns on); (2) every regular file under src/ and docs/ of the repo root
// (RIPWIRE_ROOT in the environment, else the RIPWIRE_TEST_ROOT this target is compiled with, else "."),
// read whole — the random arms cannot produce the distribution of `ACRONYMWord`, `snake_case` and `//`
// runs the shipped rule was tuned on; (3) the escapers' adversarial corpus, every byte value alone and in
// order, a special byte at every offset of a filler run past two AVX2 blocks, every invalid-UTF-8 shape,
// the CDATA close sequences, and 200k deterministic fuzz strings biased to the special set.
//
// Each corpus is walked ONCE, in a memoised builder, and the TEST_CASEs read its fields — so splitting
// the old bundled arms into one assertion apiece costs no extra pass over 100k buffers.
//
// NON-VACUITY: a TEST_CASE prints the compiled path (`strkern path: NEON|AVX2|scalar`). On arm64/x86_64
// the gate script REQUIRES a vector path — a scalar-only build there would compare the oracle to itself.
// CAN GO RED: -DSTRKERN_MUTATE=1 perturbs the SIMD tables and drops the high half of the set from the
// Byteset256's `words`; -DEMITESCAPE_MUTATE_BYTESET=1 adds a byteset with '<' missing and asserts the
// comparison SEES it. test/strkerncheck.sh and test/emitescapecheck.sh prove both.

// READING --quality-delta ON THIS FILE. It reports new-symbol debt here, and three families of it are
// deliberate rather than unfixed. (1) The `*Ref` walkers and escapers are FROZEN VERBATIM copies of the
// code they check — escapeIntoRef ccx=31, refForEachLexSubtoken* ccx=16 — and restructuring an oracle to
// flatter a metric destroys the only thing it is for. (2) The TEST_CASE bodies repeat a 36-43 token
// shape (read the memoised result, INFO the counts, CHECK one field); that repetition IS one-assertion-
// per-test-case, the form this conversion was asked for, and collapsing it would put several arms back
// behind one CHECK. (3) The memoised builders (sweep/realText/escapeRun) are WALKS whose branch count is
// mostly "has this arm already failed" — each per-kernel probe is its own function, which is where the
// splitting was worth doing and where it was done.

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "infra/strkern.h"
#include "infra/jsonesc.h"
#include "lexindex.h"
#include "lexical.h"            // LexHeadIndex — the empty-bucket arm below is this header's
#include "serialize.h"
#include "harnesscommon.h"      // DeterministicRng — the sanitizer-clean generator the SIMD harnesses share

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <string_view>
#include <utility>          // std::move — `keep` is the one place a first-wins message is retained
#include <vector>

#if !defined( RIPWIRE_TEST_ROOT )
    #define RIPWIRE_TEST_ROOT "."
#endif

namespace sk = rw::strkern;

using rw::appendCdataSafe;
using rw::escapeXml;
using rw::xmlControlCharRef;
using rw::xmlSafeByte;
using rw::xmlScrubIsLossy;

namespace
{

// The repo root whose src/ and docs/ the real-text arms read. The environment wins so a gate script can
// point the binary at the tree it is checking; the compiled-in source dir keeps a bare `ctest` honest.
const char* repoRoot()
{
    const char* env = std::getenv( "RIPWIRE_ROOT" );
    return ( env != nullptr && env[ 0 ] != '\0' ) ? env : RIPWIRE_TEST_ROOT;
}

// ============================================================================
// corpora
// ============================================================================

// four alphabets, each aimed at a different failure mode
enum class Alphabet
{
    Identifier,   // [A-Za-z0-9_] — the tokenizer's natural food
    FullAscii,    // 0x00..0x7F — every separator, every nibble-table seam ('@' '[' '`' '{' ':' '/')
    HighBit,      // 0x00..0xFF — proves the >= 0x80 half is a separator and never folds
    CamelDense    // manufactured camel / ACRONYMWord / digit seams at high density
};

void drawBuffer( DeterministicRng& gen, Alphabet alpha, std::size_t n, std::string& out )
{
    static const char kIdent[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";
    out.clear();
    out.reserve( n );
    while( out.size() < n )
    {
        const std::uint64_t r = gen.next();
        switch( alpha )
        {
            case Alphabet::Identifier:
                out.push_back( kIdent[ r % ( sizeof( kIdent ) - 1 ) ] );
                break;
            case Alphabet::FullAscii:
                out.push_back( char( r & 0x7F ) );
                break;
            case Alphabet::HighBit:
                out.push_back( char( r & 0xFF ) );
                break;
            case Alphabet::CamelDense:
            {
                // a short run of one class, then switch — so seams land every 1..4 bytes
                const int         kind   = int( r & 3 );
                const std::size_t runLen = 1 + std::size_t( ( r >> 2 ) & 3 );
                for( std::size_t j = 0; j < runLen && out.size() < n; ++j )
                {
                    const std::uint64_t s = gen.next();
                    switch( kind )
                    {
                        case 0: out.push_back( char( 'A' + ( s % 26 ) ) ); break;
                        case 1: out.push_back( char( 'a' + ( s % 26 ) ) ); break;
                        case 2: out.push_back( char( '0' + ( s % 10 ) ) ); break;
                        default: out.push_back( ( s & 1 ) ? '_' : ' ' ); break;
                    }
                }
                break;
            }
        }
    }
    out.resize( n );
}

// every regular file under <root>/src and <root>/docs, read whole
void loadRepoText( const char* root, std::vector<std::string>& outFiles, std::vector<std::string>& outNames )
{
    for( const char* sub : { "src", "docs" } )
    {
        const std::filesystem::path dir = std::filesystem::path( root ) / sub;
        std::error_code             ec;
        if( !std::filesystem::is_directory( dir, ec ) )
        {
            continue;
        }
        for( std::filesystem::recursive_directory_iterator it( dir, ec ), end; it != end && !ec; it.increment( ec ) )
        {
            if( !it->is_regular_file( ec ) )
            {
                continue;
            }
            std::FILE* fp = std::fopen( it->path().string().c_str(), "rb" );
            if( fp == nullptr )
            {
                continue;
            }
            std::string bytes;
            char        buf[ 65536 ];
            std::size_t got = 0;
            while( ( got = std::fread( buf, 1, sizeof( buf ), fp ) ) > 0 )
            {
                bytes.append( buf, got );
            }
            std::fclose( fp );
            outFiles.push_back( std::move( bytes ) );
            outNames.push_back( it->path().string() );
        }
    }
}

// ============================================================================
// the kernels' oracles and comparisons
// ============================================================================

bool masksEqual( const sk::Masks& a, const sk::Masks& b )
{
    return a.alnum == b.alnum && a.upper == b.upper && a.lower == b.lower && a.digit == b.digit;
}

// ONE window, every length 0..maxN at that offset, vector vs oracle. Both classMasks arms funnel through
// here — the whole-alphabet sweep below and the random sweep's probe — because the compare and the way it
// spells a divergence are the same question asked at two offsets, and two copies of it would be a clone
// the quality delta is right to name.
std::string compareClassMasksWindow( const char* p, std::size_t off, std::size_t maxN )
{
    for( std::size_t n = 0; n <= maxN; ++n )
    {
        sk::Masks got{}, want{};
        sk::classMasks( p + off, n, got );
        sk::classMasks_scalar( p + off, n, want );
        if( !masksEqual( got, want ) )
        {
            char msg[ 256 ];
            std::snprintf( msg, sizeof( msg ),
                           "off=%zu n=%zu got(a=%08x u=%08x l=%08x d=%08x) want(a=%08x u=%08x l=%08x d=%08x)",
                           off, n, got.alnum, got.upper, got.lower, got.digit,
                           want.alnum, want.upper, want.lower, want.digit );
            return msg;
        }
    }
    return {};
}

// the same, at EVERY offset of one buffer
std::string classMasksSweep( const std::string& text )
{
    for( std::size_t off = 0; off < text.size(); ++off )
    {
        const std::size_t avail = text.size() - off;
        const std::string msg   = compareClassMasksWindow( text.data(), off,
                                                           avail < sk::kBlockBytes ? avail : sk::kBlockBytes );
        if( !msg.empty() )
        {
            return msg;
        }
    }
    return {};
}

// ============================================================================
// Arm F — the tokenizer, and the VERBATIM pre-change walkers it must equal
// ============================================================================

// Kept byte-for-byte as they stood at 05f4b892 (src/lexindex.h:130 and :201) so this arm compares the new
// mask-driven walkers against the OLD code, not against a paraphrase of it. Do not "clean these up".

// lexUpperOpensToken left shipped code with the state machines (the mask algebra
// `U & (A<<1) & ( ~(U<<1) | (L>>1) )` states the same rule); kept HERE, verbatim from 05f4b892, because a
// reference walker that borrowed the shipped rule would move with it and prove nothing.
static bool refLexUpperOpensToken( std::string_view text, std::size_t k, bool prevUpper ) noexcept
{
    const unsigned char next = ( k + 1 < text.size() ) ? static_cast< unsigned char >( text[ k + 1 ] ) : 0u;
    return !prevUpper || ( next >= 'a' && next <= 'z' );
}

template< class EmitFn >
void refForEachLexSubtoken( std::string_view text, EmitFn&& emit )
{
    constexpr std::size_t kNoTokenByte = ~std::size_t( 0 );
    std::size_t           tokStartByte = kNoTokenByte;
    bool                  prevUpper    = false;
    for( std::size_t k = 0; k < text.size(); ++k )
    {
        const unsigned char c     = static_cast< unsigned char >( text[ k ] );
        const bool          upper = c >= 'A' && c <= 'Z';
        const bool          lower = c >= 'a' && c <= 'z';
        const bool          digit = c >= '0' && c <= '9';
        if( !upper && !lower && !digit )
        {
            if( tokStartByte != kNoTokenByte ) { emit( tokStartByte, k ); tokStartByte = kNoTokenByte; }
            prevUpper = false;
            continue;
        }
        if( upper && tokStartByte != kNoTokenByte && refLexUpperOpensToken( text, k, prevUpper ) )
        {
            emit( tokStartByte, k );
            tokStartByte = k;
        }
        if( tokStartByte == kNoTokenByte )
        {
            tokStartByte = k;
        }
        prevUpper = upper;
    }
    if( tokStartByte != kNoTokenByte )
    {
        emit( tokStartByte, text.size() );
    }
}

template< class EmitFn >
void refForEachLexSubtokenHashed( std::string_view text, EmitFn&& emit )
{
    constexpr std::size_t   kNoTokenByte = ~std::size_t( 0 );
    constexpr std::uint64_t kFnvBasis    = 1469598103934665603ull;
    std::size_t             tokStartByte = kNoTokenByte;
    std::uint64_t           h            = kFnvBasis;
    bool                    prevUpper    = false;
    const auto mix = [ & ]( unsigned char c ) noexcept { h = rw::hashutil::fnv1aAbsorb( h, char( rw::lexLowerByte( c ) ) ); };
    const auto beginToken = [ & ]( unsigned char c, std::size_t k ) noexcept
    {
        tokStartByte = k;
        h            = kFnvBasis;
        mix( c );
    };
    for( std::size_t k = 0; k < text.size(); ++k )
    {
        const unsigned char c     = static_cast< unsigned char >( text[ k ] );
        const bool          upper = c >= 'A' && c <= 'Z';
        const bool          lower = c >= 'a' && c <= 'z';
        const bool          digit = c >= '0' && c <= '9';
        if( !upper && !lower && !digit )
        {
            if( tokStartByte != kNoTokenByte ) { emit( tokStartByte, k, h ); tokStartByte = kNoTokenByte; }
            prevUpper = false;
            continue;
        }
        if( upper && tokStartByte != kNoTokenByte && refLexUpperOpensToken( text, k, prevUpper ) )
        {
            emit( tokStartByte, k, h );
            beginToken( c, k );
            prevUpper = true;
            continue;
        }
        if( tokStartByte == kNoTokenByte ) { beginToken( c, k ); prevUpper = upper; continue; }
        mix( c );
        prevUpper = upper;
    }
    if( tokStartByte != kNoTokenByte )
    {
        emit( tokStartByte, text.size(), h );
    }
}

struct Tok
{
    std::size_t   start = 0;
    std::size_t   end   = 0;
    std::uint64_t hash  = 0;
};

// Compare all four lists for one text. Returns "" when identical, else the first divergence.
std::string tokenizerDiff( std::string_view text )
{
    static std::vector< Tok > refH, newH, refS, newS;
    refH.clear();
    refForEachLexSubtokenHashed( text, [ & ]( std::size_t s, std::size_t e, std::uint64_t h ) { refH.push_back( { s, e, h } ); } );
    newH.clear();
    rw::forEachLexSubtokenHashed( text, [ & ]( std::size_t s, std::size_t e, std::uint64_t h ) { newH.push_back( { s, e, h } ); } );
    refS.clear();
    refForEachLexSubtoken( text, [ & ]( std::size_t s, std::size_t e ) { refS.push_back( { s, e, 0 } ); } );
    newS.clear();
    rw::forEachLexSubtoken( text, [ & ]( std::size_t s, std::size_t e ) { newS.push_back( { s, e, 0 } ); } );

    char msg[ 384 ];
    if( refS.size() != newS.size() )
    {
        std::snprintf( msg, sizeof( msg ), "span COUNT %zu vs %zu (len=%zu)", refS.size(), newS.size(), text.size() );
        return msg;
    }
    for( std::size_t i = 0; i < refS.size(); ++i )
    {
        if( refS[ i ].start != newS[ i ].start || refS[ i ].end != newS[ i ].end )
        {
            std::snprintf( msg, sizeof( msg ), "span #%zu [%zu,%zu) vs [%zu,%zu) (len=%zu)", i,
                           refS[ i ].start, refS[ i ].end, newS[ i ].start, newS[ i ].end, text.size() );
            return msg;
        }
    }
    if( refH.size() != newH.size() )
    {
        std::snprintf( msg, sizeof( msg ), "hashed COUNT %zu vs %zu (len=%zu)", refH.size(), newH.size(), text.size() );
        return msg;
    }
    for( std::size_t i = 0; i < refH.size(); ++i )
    {
        if( refH[ i ].start != newH[ i ].start || refH[ i ].end != newH[ i ].end || refH[ i ].hash != newH[ i ].hash )
        {
            std::snprintf( msg, sizeof( msg ), "hashed #%zu [%zu,%zu)#%016llx vs [%zu,%zu)#%016llx (len=%zu)", i,
                           refH[ i ].start, refH[ i ].end, ( unsigned long long )refH[ i ].hash,
                           newH[ i ].start, newH[ i ].end, ( unsigned long long )newH[ i ].hash, text.size() );
            return msg;
        }
        // and the fused hash must still equal the standalone lexSubtokenHash of the same span
        const std::uint64_t standalone = rw::lexSubtokenHash( text.data() + newH[ i ].start, newH[ i ].end - newH[ i ].start );
        if( standalone != newH[ i ].hash )
        {
            std::snprintf( msg, sizeof( msg ), "fused hash #%zu %016llx != lexSubtokenHash %016llx", i,
                           ( unsigned long long )newH[ i ].hash, ( unsigned long long )standalone );
            return msg;
        }
        // ... and the hash-free walker's spans must be the same spans
        if( refS[ i ].start != newH[ i ].start || refS[ i ].end != newH[ i ].end )
        {
            std::snprintf( msg, sizeof( msg ), "walker disagreement #%zu [%zu,%zu) vs [%zu,%zu)", i,
                           refS[ i ].start, refS[ i ].end, newH[ i ].start, newH[ i ].end );
            return msg;
        }
    }
    return {};
}

// ============================================================================
// the memoised sweeps — each corpus is walked ONCE, whatever the test order
// ============================================================================

struct Sets
{
    sk::Byteset256 setEmpty, setFull, setOne, setHighOnly, setXml;
    const sk::Byteset256* all[ 5 ]  = {};
    const char*           names[ 5 ] = { "empty", "full", "one", "high", "xml" };

    Sets()
    {
        for( unsigned b = 0; b < 256u; ++b )
        {
            setFull.add( static_cast< unsigned char >( b ) );
        }
        setOne.add( 'q' );
        setHighOnly.addRange( 0x80, 0xFF );
        for( char c : { '&', '<', '>', '"', '\'', '\t', '\n', '\r' } )
        {
            setXml.add( static_cast< unsigned char >( c ) );
        }
        setXml.addRange( 0x80, 0xFF );
        all[ 0 ] = &setEmpty; all[ 1 ] = &setFull; all[ 2 ] = &setOne; all[ 3 ] = &setHighOnly; all[ 4 ] = &setXml;
    }
};

const Sets& sets()
{
    static const Sets s;
    return s;
}

struct Sweep
{
    std::size_t   bufferCount = 0;
    // The generator's state after the whole sweep — a pure function of HOW MANY draws the loop made, and
    // therefore the fingerprint of the corpus every arm saw. It is printed and gated (strkerncheck.sh)
    // because the sweep contract is that the corpus does NOT move when an arm fails: a build whose
    // kernels are all broken must still have swept exactly the buffers the green build swept, or the
    // failure it reports describes a different experiment. Pure observation — no extra draw.
    std::uint64_t rngState    = 0;
    std::string   classFail, foldFail, eqFail, findFail, tokFail;
};

// ── one probe per kernel ──────────────────────────────────────────────────────────────────────────────
// The sweep below is a WALK, and each of these is one kernel's question asked of the buffer it is
// standing on. They take `gen` rather than pre-drawn values so the draw ORDER — and therefore the corpus
// every arm sees — is exactly the one the standalone harness drew before 2026-09-10. Each returns "" or
// the first divergence, spelled so a failure names the input rather than an offset.

// A — classMasks at every offset/length that fits in one block, but only on a slice (the full
// O(n * block) sweep on 100k buffers would dominate the gate's runtime).
std::string probeClassMasks( DeterministicRng& gen, const std::string& buf, int iter, Alphabet alpha )
{
    const std::size_t n        = buf.size();
    const std::size_t probeOff = n == 0 ? 0 : std::size_t( gen.next() % n );
    const std::size_t avail    = n - probeOff;
    const std::string msg      = compareClassMasksWindow( buf.data(), probeOff,
                                                          avail < sk::kBlockBytes ? avail : sk::kBlockBytes );
    if( msg.empty() )
    {
        return {};
    }
    char out[ 320 ];
    std::snprintf( out, sizeof( out ), "iter=%d alpha=%d %s", iter, int( alpha ), msg.c_str() );
    return out;
}

// B — lowerFoldAscii, vector vs SWAR scalar, in place, and then against the A-Z definition byte by byte.
std::string probeFold( const std::string& buf, int iter, Alphabet alpha )
{
    std::string folded( buf ), foldedRef( buf );
    sk::lowerFoldAscii( folded.data(), folded.size() );
    sk::lowerFoldAscii_scalar( foldedRef.data(), foldedRef.size() );
    if( folded != foldedRef )
    {
        char msg[ 128 ];
        std::snprintf( msg, sizeof( msg ), "iter=%d alpha=%d n=%zu", iter, int( alpha ), buf.size() );
        return msg;
    }
    for( std::size_t k = 0; k < buf.size(); ++k )
    {
        const unsigned char c    = static_cast< unsigned char >( buf[ k ] );
        const unsigned char want = ( c >= 'A' && c <= 'Z' ) ? static_cast< unsigned char >( c + 0x20 ) : c;
        if( static_cast< unsigned char >( folded[ k ] ) != want )
        {
            char msg[ 128 ];
            std::snprintf( msg, sizeof( msg ), "definition iter=%d k=%zu byte=%02x", iter, k, c );
            return msg;
        }
    }
    return {};
}

// C — lowerFoldedEquals: the equal case, then every single-byte perturbation of one random position.
std::string probeFoldedEquals( DeterministicRng& gen, const std::string& buf, int iter )
{
    const std::size_t n = buf.size();
    std::string       lowered( buf );
    sk::lowerFoldAscii_scalar( lowered.data(), lowered.size() );
    if( !sk::lowerFoldedEquals( buf.data(), lowered.data(), n )
        || !sk::lowerFoldedEquals_scalar( buf.data(), lowered.data(), n ) )
    {
        return "self-compare returned false";
    }
    const std::size_t at  = std::size_t( gen.next() % n );
    const char        old = lowered[ at ];
    lowered[ at ]         = char( static_cast< unsigned char >( old ) ^ 0x01 );
    if( sk::lowerFoldedEquals( buf.data(), lowered.data(), n ) != sk::lowerFoldedEquals_scalar( buf.data(), lowered.data(), n ) )
    {
        char msg[ 128 ];
        std::snprintf( msg, sizeof( msg ), "perturbed iter=%d at=%zu n=%zu", iter, at, n );
        return msg;
    }
    return {};
}

// D — findByte, vector vs scalar twin vs a naive memchr oracle.
std::string probeFindByte( DeterministicRng& gen, const std::string& buf, int iter )
{
    const std::size_t n      = buf.size();
    const char        needle = char( gen.next() & 0xFF );
    const std::size_t got    = sk::findByte( buf.data(), n, needle );
    const std::size_t ref    = sk::findByte_scalar( buf.data(), n, needle );
    std::size_t       naive  = n;
    for( std::size_t k = 0; k < n; ++k )
    {
        if( buf[ k ] == needle ) { naive = k; break; }
    }
    if( got != ref || got != naive )
    {
        char msg[ 160 ];
        std::snprintf( msg, sizeof( msg ), "findByte iter=%d got=%zu ref=%zu naive=%zu n=%zu", iter, got, ref, naive, n );
        return msg;
    }
    return {};
}

// D — find3. Half the time the needle is PLANTED so a hit is exercised, half the time drawn at random.
std::string probeFind3( DeterministicRng& gen, const std::string& buf, int iter )
{
    const std::size_t n = buf.size();
    char needle3[ 3 ] = { char( gen.next() & 0xFF ), char( gen.next() & 0xFF ), char( gen.next() & 0xFF ) };
    if( n >= 3 && ( gen.next() & 1 ) )
    {
        const std::size_t at = std::size_t( gen.next() % ( n - 2 ) );
        std::memcpy( needle3, buf.data() + at, 3 );
    }
    const std::size_t got   = sk::find3( buf.data(), n, needle3 );
    const std::size_t ref   = sk::find3_scalar( buf.data(), n, needle3 );
    std::size_t       naive = n;
    for( std::size_t k = 0; k + 3 <= n; ++k )
    {
        if( std::memcmp( buf.data() + k, needle3, 3 ) == 0 ) { naive = k; break; }
    }
    if( got != ref || got != naive )
    {
        char msg[ 160 ];
        std::snprintf( msg, sizeof( msg ), "find3 iter=%d got=%zu ref=%zu naive=%zu n=%zu", iter, got, ref, naive, n );
        return msg;
    }
    return {};
}

// E — findByteset: vector == the SHIPPED scalar tail == the re-deriving ORACLE == naive. The oracle is
// the third value on purpose — it rebuilds the four words from `bits` through contains(), so it is what
// stops the set's two stored representations from drifting apart unseen.
std::string probeFindByteset( DeterministicRng& gen, const std::string& buf, int iter )
{
    const Sets&       S    = sets();
    const std::size_t n    = buf.size();
    const std::size_t si   = std::size_t( gen.next() % 5u );
    const std::size_t got  = sk::findByteset( buf.data(), n, *S.all[ si ] );
    const std::size_t ref  = sk::findByteset_scalar( buf.data(), n, *S.all[ si ] );
    const std::size_t ora  = sk::findByteset_oracle( buf.data(), n, *S.all[ si ] );
    std::size_t       naive = n;
    for( std::size_t k = 0; k < n; ++k )
    {
        if( S.all[ si ]->contains( static_cast< unsigned char >( buf[ k ] ) ) ) { naive = k; break; }
    }
    if( got != ref || got != ora || got != naive )
    {
        char msg[ 224 ];
        std::snprintf( msg, sizeof( msg ), "findByteset[%s] iter=%d got=%zu ref=%zu oracle=%zu naive=%zu n=%zu",
                       S.names[ si ], iter, got, ref, ora, naive, n );
        return msg;
    }
    return {};
}

const Sweep& sweep()
{
    static const Sweep s = []
    {
        Sweep            r;
        DeterministicRng gen{ 0x5DEECE66Dull };
        std::string      buf;

        for( int iter = 0; iter < 100000; ++iter )
        {
            const Alphabet    alpha = Alphabet( iter & 3 );
            const std::size_t n     = std::size_t( gen.next() % 301u );   // 0..300, straddles 16/32 repeatedly
            drawBuffer( gen, alpha, n, buf );
            ++r.bufferCount;

            // EVERY probe runs on EVERY iteration; only the MESSAGE is first-wins. The arms report the
            // first divergence, but the draw order is the contract: probeClassMasks, probeFoldedEquals,
            // probeFindByte, probeFind3 and probeFindByteset each pull from `gen`, so skipping one after
            // another arm had already failed moved every later buffer and every later probe input off the
            // corpus the green run swept. The failing report then described a DIFFERENT sweep from the one
            // that passed, and a second, independent divergence could be shifted out of existence by the
            // first. `keep` is the one place first-wins lives (CodeRabbit #127 / 3985249745).
            //
            // On a GREEN run this is byte-for-byte the old behaviour: no arm ever holds a message, so every
            // probe ran under the old spelling too, in this same order, off this same stream.
            const auto keep = []( std::string& slot, std::string&& msg )
            {
                if( slot.empty() ) { slot = std::move( msg ); }
            };
            keep( r.classFail, probeClassMasks( gen, buf, iter, alpha ) );
            keep( r.foldFail,  probeFold( buf, iter, alpha ) );
            if( n > 0 )                                  // a PRECONDITION of the probe, not a skip-on-failure
            {
                keep( r.eqFail, probeFoldedEquals( gen, buf, iter ) );
            }
            keep( r.findFail, probeFindByte( gen, buf, iter ) );
            keep( r.findFail, probeFind3( gen, buf, iter ) );
            keep( r.findFail, probeFindByteset( gen, buf, iter ) );
            {
                const std::string d = tokenizerDiff( buf );
                if( !d.empty() )
                {
                    char msg[ 512 ];
                    std::snprintf( msg, sizeof( msg ), "iter=%d alpha=%d %s", iter, int( alpha ), d.c_str() );
                    keep( r.tokFail, msg );
                }
            }
        }
        r.rngState = gen.state;
        return r;
    }();
    return s;
}

struct RealText
{
    std::size_t fileCount = 0;
    std::size_t totalBytes = 0;
    std::string classFail, foldFail, findFail, tokFail;
};

// ── the same questions, asked of one real file ────────────────────────────────────────────────────────
// Real text is not optional here: the random alphabets cannot produce the distribution of `ACRONYMWord`,
// `snake_case` and `//` runs the shipped tokenizer rule was tuned on, nor the doc-comment shapes the
// escapers meet. Each returns "" or the name of the file that diverged.

// every block-aligned window plus the ragged tail — the whole file's bytes are classified
std::string probeFileClassMasks( const std::string& text, const std::string& name )
{
    for( std::size_t off = 0; off < text.size(); off += sk::kBlockBytes )
    {
        const std::size_t avail = text.size() - off;
        const std::size_t m     = avail < sk::kBlockBytes ? avail : sk::kBlockBytes;
        sk::Masks         got{}, want{};
        sk::classMasks( text.data() + off, m, got );
        sk::classMasks_scalar( text.data() + off, m, want );
        if( !masksEqual( got, want ) )
        {
            return name + " @" + std::to_string( off );
        }
    }
    return {};
}

std::string probeFileFold( const std::string& text, const std::string& name )
{
    std::string folded( text ), foldedRef( text );
    sk::lowerFoldAscii( folded.data(), folded.size() );
    sk::lowerFoldAscii_scalar( foldedRef.data(), foldedRef.size() );
    if( folded != foldedRef )
    {
        return name;
    }
    if( !sk::lowerFoldedEquals( text.data(), folded.data(), text.size() ) )
    {
        return name + " (foldedEquals)";
    }
    return {};
}

// the needle a --grep trigram probe would use: the file's own middle three bytes
std::string probeFileFinds( const std::string& text, const std::string& name )
{
    if( text.size() < 3 )
    {
        return {};
    }
    const Sets&       S  = sets();
    const std::size_t at = text.size() / 2 - 1;
    char              needle3[ 3 ];
    std::memcpy( needle3, text.data() + at, 3 );
    const std::size_t got3  = sk::find3( text.data(), text.size(), needle3 );
    const std::size_t ref3  = sk::find3_scalar( text.data(), text.size(), needle3 );
    std::size_t       naive = text.size();
    for( std::size_t k = 0; k + 3 <= text.size(); ++k )
    {
        if( std::memcmp( text.data() + k, needle3, 3 ) == 0 ) { naive = k; break; }
    }
    const std::size_t gotS = sk::findByteset( text.data(), text.size(), S.setXml );
    const std::size_t refS = sk::findByteset_scalar( text.data(), text.size(), S.setXml );
    const std::size_t oraS = sk::findByteset_oracle( text.data(), text.size(), S.setXml );
    if( got3 != ref3 || got3 != naive || gotS != refS || gotS != oraS )
    {
        return name;
    }
    return {};
}

const RealText& realText()
{
    static const RealText s = []
    {
        RealText                   r;
        std::vector< std::string > files, names;
        loadRepoText( repoRoot(), files, names );
        r.fileCount = files.size();

        for( std::size_t fi = 0; fi < files.size(); ++fi )
        {
            const std::string& text = files[ fi ];
            r.totalBytes += text.size();
            if( r.classFail.empty() ) { r.classFail = probeFileClassMasks( text, names[ fi ] ); }
            if( r.foldFail.empty() )  { r.foldFail  = probeFileFold( text, names[ fi ] ); }
            if( r.findFail.empty() )  { r.findFail  = probeFileFinds( text, names[ fi ] ); }
            if( r.tokFail.empty() )
            {
                const std::string d = tokenizerDiff( text );
                if( !d.empty() )
                {
                    r.tokFail = names[ fi ] + ": " + d;
                }
            }
        }
        return r;
    }();
    return s;
}

// ============================================================================
// Arm H — the emit escapers and the frozen per-byte references they must equal
// ============================================================================

std::string escapeXmlRef( std::string_view s )
{
    std::string out;
    const auto put = [ & ]( const char* lit ) { while( *lit ) { out.push_back( *lit++ ); } };
    const char*       d = s.data();
    const std::size_t n = s.size();
    for( std::size_t i = 0; i < n; )
    {
        const char c = d[i];
        switch( c )
        {
            case '&':  put( "&amp;" );  ++i; break;
            case '<':  put( "&lt;" );   ++i; break;
            case '>':  put( "&gt;" );   ++i; break;
            case '"':  put( "&quot;" ); ++i; break;
            case '\'': put( "&apos;" ); ++i; break;
            case '\t':
            case '\n':
            case '\r': put( xmlControlCharRef( c ) ); ++i; break;
            default:
                if( static_cast<unsigned char>( c ) < 0x80 ) { out.push_back( xmlSafeByte( c ) ); ++i; }
                else if( const int len = rw::jsonesc::utf8SeqLen( d, i, n ); len == 0 ) { out.push_back( '?' ); ++i; }
                else
                {
                    for( int k = 0; k < len; ++k )
                    {
                        out.push_back( d[i + k] );
                    }
                    i += std::size_t( len );
                }
        }
    }
    return out;
}

std::string appendCdataSafeRef( std::string_view body )
{
    std::string safe;
    const char*       d = body.data();
    const std::size_t n = body.size();
    for( std::size_t i = 0; i < n; )
    {
        if( i + 2 < n && d[i] == ']' && d[i + 1] == ']' && d[i + 2] == '>' )
        { safe += "]]]]><![CDATA[>";  i += 3;  continue; }
        const unsigned char c = static_cast<unsigned char>( d[i] );
        if( c < 0x80 ) { safe += xmlSafeByte( d[i] ); ++i; }
        else if( const int len = rw::jsonesc::utf8SeqLen( d, i, n ); len == 0 ) { safe += '?'; ++i; }
        else { safe.append( d + i, std::size_t( len ) ); i += std::size_t( len ); }
    }
    return safe;
}

std::string escapeIntoRef( std::string_view s, bool escapeAngleAmp, bool validateUtf8, bool replacementAsTextEscape )
{
    std::string       out;
    const char*       d = s.data();
    const std::size_t n = s.size();
    std::size_t       i = 0;
    while( i < n )
    {
        const unsigned char c = static_cast<unsigned char>( d[i] );
        if( c < 0x80 )
        {
            switch( c )
            {
                case '"':  out += "\\\""; ++i; continue;
                case '\\': out += "\\\\"; ++i; continue;
                case '\n': out += "\\n";  ++i; continue;
                case '\r': out += "\\r";  ++i; continue;
                case '\t': out += "\\t";  ++i; continue;
                case '<':  if( escapeAngleAmp ) { out += "\\u003c"; ++i; continue; } break;
                case '>':  if( escapeAngleAmp ) { out += "\\u003e"; ++i; continue; } break;
                case '&':  if( escapeAngleAmp ) { out += "\\u0026"; ++i; continue; } break;
                default: break;
            }
            if( c < 0x20 )
            { char b[ 8 ]; std::snprintf( b, sizeof( b ), "\\u%04x", unsigned( c ) ); out += b; }
            else
            {
                out += char( c );
            }
            ++i;
            continue;
        }
        if( !validateUtf8 ) { out += char( c ); ++i; continue; }
        const int len = rw::jsonesc::utf8SeqLen( d, i, n );
        if( len == 0 )
        {
            if( replacementAsTextEscape ) { out += "\\ufffd"; }
            else                          { out += "\xEF\xBF\xBD"; }
            ++i;
        }
        else { out.append( d + i, std::size_t( len ) ); i += std::size_t( len ); }
    }
    return out;
}

// ── the shipped functions, wrapped to the same signature ──────────────────────────────────────────────

std::string escapeXmlNew( std::string_view s )
{
    std::vector<char> buf;
    const std::string_view v = escapeXml( s, buf );
    return std::string( v );
}

std::string appendCdataSafeNew( std::string_view s )
{
    std::string out;
    appendCdataSafe( s, out );
    return out;
}

std::string escapeIntoNew( std::string_view s, bool a, bool v, bool r )
{
    std::string out;
    rw::jsonesc::escapeInto( s, out, a, v, r );
    return out;
}

// ── MUT: the same run-copy shape with '<' dropped from the byte set ───────────────────────────────────
// Deliberately WRONG. Not compiled into anything shipped; it exists so the gate can prove that this
// comparison actually notices a set member going missing (a byteset bug is silent otherwise — the output
// is still well-formed-looking text, just with a raw '<' where an entity belonged).
#if EMITESCAPE_MUTATE_BYTESET
std::string escapeXmlMutatedSet( std::string_view s )
{
    std::string       out;
    const char*       d = s.data();
    const std::size_t n = s.size();
    const auto put = [ & ]( const char* lit ) { while( *lit ) { out.push_back( *lit++ ); } };
    for( std::size_t i = 0; i < n; )
    {
        const char c = d[i];
        switch( c )
        {
            // '<' intentionally absent from the set — falls through to the verbatim copy below.
            case '&':  put( "&amp;" );  ++i; break;
            case '>':  put( "&gt;" );   ++i; break;
            case '"':  put( "&quot;" ); ++i; break;
            case '\'': put( "&apos;" ); ++i; break;
            case '\t':
            case '\n':
            case '\r': put( xmlControlCharRef( c ) ); ++i; break;
            default:
                if( static_cast<unsigned char>( c ) < 0x80 ) { out.push_back( xmlSafeByte( c ) ); ++i; }
                else if( const int len = rw::jsonesc::utf8SeqLen( d, i, n ); len == 0 ) { out.push_back( '?' ); ++i; }
                else
                {
                    for( int k = 0; k < len; ++k ) { out.push_back( d[i + k] ); }
                    i += std::size_t( len );
                }
        }
    }
    return out;
}
#endif

// ── the adversarial corpus, one function per shape it is adversarial about ────────────────────────────

void addCase( std::vector<std::string>& v, std::string s ) { v.push_back( std::move( s ) ); }

// A — every byte value alone, and all 256 in order.
void addByteValueCases( std::vector<std::string>& cases )
{
    std::string all;
    for( int b = 0; b < 256; ++b )
    {
        addCase( cases, std::string( 1, char( b ) ) );
        all.push_back( char( b ) );
    }
    addCase( cases, all );
    addCase( cases, std::string() );
}

// B — a special byte planted at every offset of a filler run, across every length up to two 32-byte AVX2
// blocks plus a tail: the block-boundary sweep a SIMD run loop and its scalar tail must both survive.
void addOffsetSweepCases( std::vector<std::string>& cases )
{
    const char specials[] = { '&', '<', '>', '"', '\'', '\t', '\n', '\r', '\0', '\x0b', '\x1f', '\x7f',
                              char( 0x80 ), char( 0xC3 ), char( 0xFF ), ']' };
    for( char sp : specials )
    {
        for( std::size_t len = 1; len <= 96; ++len )
        {
            for( std::size_t at = 0; at < len; at += ( len > 40 ? 7 : 1 ) )
            {
                std::string s( len, 'a' );
                s[at] = sp;
                addCase( cases, s );
            }
        }
    }
}

// C/D — invalid UTF-8 shapes (bare continuation, overlong 2/3/4-byte forms, surrogate halves, >U+10FFFF,
// a sequence truncated at end-of-buffer) and the valid multibyte + BOM cases they must not be confused
// with. Each is placed alone, around specials, and at 31/32/33 bytes so a block boundary splits it.
void addUtf8Cases( std::vector<std::string>& cases )
{
    const char* bad[] = {
        "\x80", "\xBF", "\xC0\x80", "\xC1\xBF", "\xC2", "\xE0\x80\x80", "\xE0\x9F\xBF",
        "\xED\xA0\x80", "\xED\xBF\xBF", "\xE2\x82", "\xF0\x80\x80\x80", "\xF0\x8F\xBF\xBF",
        "\xF4\x90\x80\x80", "\xF5\x80\x80\x80", "\xFE", "\xFF", "\xF0\x9D\x84",
    };
    for( const char* b : bad )
    {
        std::string s( b );
        addCase( cases, s );
        addCase( cases, "abc" + s );
        addCase( cases, s + "abc" );
        addCase( cases, "abc" + s + "<&>" );
        addCase( cases, std::string( 31, 'x' ) + s );
        addCase( cases, std::string( 32, 'x' ) + s );
        addCase( cases, std::string( 33, 'x' ) + s );
    }
    // lone continuation byte as the very last byte of the buffer
    addCase( cases, std::string( 40, 'q' ) + "\xBF" );
    addCase( cases, std::string( 40, 'q' ) + "\xE2\x82" );

    const char* good[] = { "\xC3\xA9", "\xE2\x82\xAC", "\xF0\x9D\x84\x9E", "\xEF\xBB\xBF", "\xEF\xBF\xBD" };
    for( const char* g : good )
    {
        std::string s( g );
        addCase( cases, s );
        addCase( cases, s + "<" + s );
        addCase( cases, std::string( 30, 'z' ) + s + std::string( 30, 'z' ) );
        addCase( cases, std::string( 31, 'z' ) + s );
    }
}

// E — the CDATA close sequences appendCdataSafe splits, including the ones that only LOOK like one.
void addCdataCases( std::vector<std::string>& cases )
{
    addCase( cases, "]]>" );
    addCase( cases, "]]" );
    addCase( cases, "]" );
    addCase( cases, "]]]" );
    addCase( cases, "]]]]>" );
    addCase( cases, "a]]>b" );
    addCase( cases, "]]>]]>" );
    addCase( cases, std::string( 31, 'p' ) + "]]>" );
    addCase( cases, std::string( 32, 'p' ) + "]]>" + std::string( 32, 'p' ) );
    addCase( cases, std::string( 30, 'p' ) + "]]" );
    addCase( cases, "]]\x01>" );
}

// G — 200k deterministic fuzz strings over an alphabet biased to the special set. Fixed seed, so a
// failure reproduces anywhere.
void addFuzzCases( std::vector<std::string>& cases )
{
    DeterministicRng  rng{ 0x9E3779B97F4A7C15ull };
    const std::string alphabet = "abcdefgh<>&\"'\t\n\r]] \x01\x1f\x7f\x80\xC3\xA9\xE2\x82\xAC\xF0\x9D\x84\x9E\xFF";
    for( int k = 0; k < 200000; ++k )
    {
        const std::size_t len = std::size_t( rng.next() % 201 );
        std::string       s;
        s.reserve( len );
        for( std::size_t j = 0; j < len; ++j )
        {
            s.push_back( alphabet[ std::size_t( rng.next() % alphabet.size() ) ] );
        }
        cases.push_back( std::move( s ) );
    }
}

std::vector<std::string> buildEscapeCorpus()
{
    std::vector<std::string> cases;
    addByteValueCases( cases );
    addOffsetSweepCases( cases );
    addUtf8Cases( cases );
    addCdataCases( cases );
    addFuzzCases( cases );
    return cases;
}

// appendCdataSafe's only non-scrub rewrite is the "]]>" split, so on an input xmlScrubIsLossy calls
// CLEAN the escaped form must equal the input with that one substitution applied and nothing else. This
// is the cheap direction of the §B12.7 disclosure predicate, and it is the direction a run-copy bug in
// the escaper would break: a skipped run is a moved byte.
bool lossyDisagrees( const std::string& s )
{
    if( xmlScrubIsLossy( s ) )
    {
        return false;
    }
    std::string expanded;
    for( std::size_t i = 0; i < s.size(); )
    {
        if( i + 2 < s.size() && s[i] == ']' && s[i + 1] == ']' && s[i + 2] == '>' )
        { expanded += "]]]]><![CDATA[>"; i += 3; }
        else { expanded += s[i]; ++i; }
    }
    return appendCdataSafeRef( s ) != expanded;
}

struct EscapeRun
{
    std::size_t caseCount = 0;
    std::size_t xmlBad = 0, cdataBad = 0, jsonBad = 0, lossyBad = 0, mutDiff = 0;
};

const EscapeRun& escapeRun()
{
    static const EscapeRun s = []
    {
        EscapeRun                      r;
        const std::vector<std::string> cases = buildEscapeCorpus();
        r.caseCount = cases.size();
        for( const std::string& s : cases )
        {
            if( escapeXmlNew( s ) != escapeXmlRef( s ) ) { ++r.xmlBad; }
            if( appendCdataSafeNew( s ) != appendCdataSafeRef( s ) ) { ++r.cdataBad; }
            for( int mode = 0; mode < 8; ++mode )
            {
                const bool a = ( mode & 1 ) != 0;
                const bool v = ( mode & 2 ) != 0;
                const bool t = ( mode & 4 ) != 0;
                if( escapeIntoNew( s, a, v, t ) != escapeIntoRef( s, a, v, t ) ) { ++r.jsonBad; }
            }
            if( lossyDisagrees( s ) ) { ++r.lossyBad; }
#if EMITESCAPE_MUTATE_BYTESET
            if( escapeXmlMutatedSet( s ) != escapeXmlRef( s ) ) { ++r.mutDiff; }
#endif
        }
        return r;
    }();
    return s;
}

}   // namespace

// ============================================================================
// the arms
// ============================================================================

TEST_CASE( "strkern: the compiled path is the one this target claims" )
{
    // NON-VACUITY BANNER. printf, not doctest's MESSAGE, because test/strkerncheck.sh greps this line
    // exactly: on arm64 it must say NEON and on x86-64 AVX2, or the parity arms below compare the scalar
    // oracle to itself and prove nothing.
    std::printf( "strkern: path=%s block=%zu root=%s\n", sk::kPathName, sk::kBlockBytes, repoRoot() );
    std::printf( "strkern path: %s\n", sk::kPathName );
    // The sweep's draw fingerprint, on its own grep-able line. strkerncheck.sh asserts the GREEN build and
    // the -DSTRKERN_MUTATE=1 build print the SAME value: every probe runs on every iteration, so a failing
    // arm cannot shorten the RNG stream and move the corpus out from under the arms that come after it.
    std::printf( "strkern sweep-rng: %016llx buffers=%zu\n",
                 static_cast< unsigned long long >( sweep().rngState ), sweep().bufferCount );
    CHECK( sk::kBlockBytes <= sk::kMaxBlockBytes );
}

// ── LexHeadIndex: the EMPTY bucket and the EMPTY longRows (CodeRabbit #127 / 3985249670) ─────────────
// matchRow picks its scan range as `bucketIdx.data() + bucketOff[len]` for a token of at most kMaxLen
// bytes and as `longRows.data() … + longRows.size()` above it. On the ordinary table NO row is longer
// than 64 bytes, so `longRows` is EMPTY and `data()` may be null — and a 65+ byte corpus token whose
// lowercased head is in the head set reaches exactly that expression. A length bucket that holds no row
// is the same shape one level down.
//
// `null + 0` is a null pointer value, not undefined behaviour ([expr.add]/4, C++17 onward; this project
// is C++23), and `first != last` is then false, so the loop body never runs. This arm is that claim in
// executable form, under the same -fsanitize=address,undefined,integer,-fno-sanitize-recover=all build
// arm 1 runs: it drives BOTH empty ranges and asserts the answer is kNoRow. It also drives the NON-empty
// long path, so it is not a test of two early returns.
TEST_CASE( "strkern: LexHeadIndex empty length bucket and empty longRows" )
{
    using rw::LexHeadIndex;

    // A table whose every row is short: longRows is empty, and most length buckets are empty too.
    const std::vector< std::string > shortTable{ "alpha", "beta", "gamma" };
    const auto                        shortTokOf = [ & ]( std::size_t m ) -> const std::string& { return shortTable[ m ]; };
    const LexHeadIndex                shortIx    = rw::buildLexHeadIndex( shortTable.size(), shortTokOf );
    REQUIRE( shortIx.longRows.empty() );
    CHECK( shortIx.longRows.data() + shortIx.longRows.size() == shortIx.longRows.data() );

    // a 70-byte token whose head 'a' IS in the head set — the length bucket does not exist, so the
    // kMaxLen branch is not taken and the empty longRows range is what decides the answer.
    const std::string longTok( 70, 'a' );
    CHECK( shortIx.matchRow( longTok.data(), longTok.size(), shortTokOf ) == LexHeadIndex::kNoRow );
    // an in-range length whose bucket is empty (no 4-byte row starts with 'a'), head still in the set
    const std::string fourA = "aaaa";
    CHECK( shortIx.matchRow( fourA.data(), fourA.size(), shortTokOf ) == LexHeadIndex::kNoRow );
    // the rows that DO exist still resolve — the arm is not passing because everything returns kNoRow
    CHECK( shortIx.matchRow( shortTable[ 1 ].data(), shortTable[ 1 ].size(), shortTokOf ) == 1u );

    // NON-EMPTY longRows: one 70-byte row, so the long branch has something to scan and hits.
    const std::vector< std::string > longTable{ "alpha", std::string( 70, 'a' ) };
    const auto                        longTokOf = [ & ]( std::size_t m ) -> const std::string& { return longTable[ m ]; };
    const LexHeadIndex                longIx    = rw::buildLexHeadIndex( longTable.size(), longTokOf );
    REQUIRE( longIx.longRows.size() == 1u );
    CHECK( longIx.matchRow( longTok.data(), longTok.size(), longTokOf ) == 1u );
}

TEST_CASE( "strkern: A1 classMasks over all 256 byte values, every offset and length" )
{
    std::string every;
    for( unsigned b = 0; b < 256u; ++b )
    {
        every.push_back( char( b ) );
    }
    const std::string fail = classMasksSweep( every );
    INFO( "first divergence: ", fail );
    CHECK( fail.empty() );
}

TEST_CASE( "strkern: A2 classMasks single-byte classes are exactly [A-Z]/[a-z]/[0-9]" )
{
    // bytes >= 0x80 are separators by construction — the high-nibble table maps 8..F to 0
    bool defOk = true;
    for( unsigned b = 0; b < 256u; ++b )
    {
        const char c = char( b );
        sk::Masks  m{};
        sk::classMasks( &c, 1, m );
        const bool wantUpper = b >= 'A' && b <= 'Z';
        const bool wantLower = b >= 'a' && b <= 'z';
        const bool wantDigit = b >= '0' && b <= '9';
        defOk = defOk && ( ( m.upper & 1u ) != 0 ) == wantUpper && ( ( m.lower & 1u ) != 0 ) == wantLower
                      && ( ( m.digit & 1u ) != 0 ) == wantDigit
                      && ( ( m.alnum & 1u ) != 0 ) == ( wantUpper || wantLower || wantDigit );
    }
    CHECK( defOk );
}

TEST_CASE( "strkern: A3 classMasks vector == scalar oracle over the random corpus" )
{
    const Sweep& s = sweep();
    INFO( "buffers: ", s.bufferCount, "  first divergence: ", s.classFail );
    CHECK( s.classFail.empty() );
}

TEST_CASE( "strkern: B1 lowerFoldAscii vector == SWAR scalar == the A-Z definition" )
{
    const Sweep& s = sweep();
    INFO( "buffers: ", s.bufferCount, "  first divergence: ", s.foldFail );
    CHECK( s.foldFail.empty() );
}

TEST_CASE( "strkern: C1 lowerFoldedEquals vector == scalar, equal and perturbed" )
{
    const Sweep& s = sweep();
    INFO( "buffers: ", s.bufferCount, "  first divergence: ", s.eqFail );
    CHECK( s.eqFail.empty() );
}

TEST_CASE( "strkern: D1/E1 findByte / find3 / findByteset vector == scalar == oracle == naive" )
{
    const Sweep& s = sweep();
    INFO( "buffers: ", s.bufferCount, "  first divergence: ", s.findFail );
    CHECK( s.findFail.empty() );
}

TEST_CASE( "strkern: E0 Byteset256 carries two agreeing representations (bits vs words)" )
{
    // The set stores the SIMD tables' (b >> 3, b & 7) packing and the scalar tail's (b >> 6, b & 63) words,
    // both written by add(). Nothing else in the header would notice one of them going stale — and the
    // 2026-09-10 defect this arm was written for (the tail re-deriving its words on every call) was
    // invisible to every correctness arm in this file.
    const Sets& S = sets();
    std::string fail;
    for( std::size_t si = 0; si < 5 && fail.empty(); ++si )
    {
        std::uint64_t rederived[ 4 ] = { 0, 0, 0, 0 };
        for( unsigned b = 0; b < 256u && fail.empty(); ++b )
        {
            const unsigned char c = static_cast< unsigned char >( b );
            if( S.all[ si ]->contains( c ) )
            {
                rederived[ b >> 6 ] |= std::uint64_t( 1 ) << ( b & 63u );
            }
            if( S.all[ si ]->contains( c ) != S.all[ si ]->containsWord( c ) )
            {
                char msg[ 128 ];
                std::snprintf( msg, sizeof( msg ), "set=%s byte=%02x bits=%d words=%d", S.names[ si ], b,
                               int( S.all[ si ]->contains( c ) ), int( S.all[ si ]->containsWord( c ) ) );
                fail = msg;
            }
        }
        for( int w = 0; w < 4 && fail.empty(); ++w )
        {
            if( rederived[ w ] != S.all[ si ]->words[ w ] )
            {
                char msg[ 160 ];
                std::snprintf( msg, sizeof( msg ), "set=%s word[%d] stored=%016llx rederived=%016llx",
                               S.names[ si ], w, ( unsigned long long )S.all[ si ]->words[ w ],
                               ( unsigned long long )rederived[ w ] );
                fail = msg;
            }
        }
    }
    INFO( "first divergence: ", fail );
    CHECK( fail.empty() );
}

TEST_CASE( "strkern: F1 tokenizer equals the pre-change walker on the registered seam cases" )
{
    // The hand-written seam table from docs/EVALS.md §4 — the cases the acronym rule exists for, spelled
    // out so a failure names the input rather than a random offset.
    static const char* kCases[] = {
        "", "a", "A", "aB", "Ab", "AB", "ABc", "aBc", "MCP", "MCP2Server", "HTTPServer", "IOError",
        "XMLHttpRequest", "_max_speed", "updateCollisionPositionVelocity", "foo bar", "  ", "__",
        "A1B2C3", "camelCASE", "CASEcamel", "endsWithUPPER", "x", "0", "9a", "a9", "Z", "aZ", "ZZa",
        "ZZZZZZZZZZZZZZZZZZZZa",                                   // acronym run straddling a 16-byte block
        "aaaaaaaaaaaaaaaBcccccccccccccccDeeeeeeeeeeeeeeeF",         // camel seam at 15/31/47
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaBc",                        // camel seam exactly at 32
        "ABCDEFGHIJKLMNOPa", "ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFa",   // acronym seam at 16 and at 32
        "____________________abc", "abc____________________",
    };
    std::string firstFail;
    for( const char* c : kCases )
    {
        const std::string d = tokenizerDiff( c );
        if( !d.empty() && firstFail.empty() )
        {
            firstFail = std::string( "\"" ) + c + "\": " + d;
        }
    }
    INFO( "cases: ", sizeof( kCases ) / sizeof( kCases[ 0 ] ), "  first failure: ", firstFail );
    CHECK( firstFail.empty() );
}

TEST_CASE( "strkern: F2 tokenizer == pre-change walker (spans + fused hashes) on the random corpus" )
{
    const Sweep& s = sweep();
    INFO( "buffers: ", s.bufferCount, "  first divergence: ", s.tokFail );
    CHECK( s.tokFail.empty() );
}

TEST_CASE( "strkern: G0 the real-text corpus is big enough for the arms below to mean anything" )
{
    const RealText& r = realText();
    INFO( "files under ", repoRoot(), "/{src,docs}: ", r.fileCount );
    REQUIRE( r.fileCount >= 50 );
}

TEST_CASE( "strkern: G1 classMasks vs oracle over every byte of src/ + docs/" )
{
    const RealText& r = realText();
    INFO( "files: ", r.fileCount, " bytes: ", r.totalBytes, "  first divergence: ", r.classFail );
    CHECK( r.classFail.empty() );
}

TEST_CASE( "strkern: G2 lowerFoldAscii / lowerFoldedEquals over src/ + docs/" )
{
    const RealText& r = realText();
    INFO( "files: ", r.fileCount, "  first divergence: ", r.foldFail );
    CHECK( r.foldFail.empty() );
}

TEST_CASE( "strkern: G3 find3 / findByteset over src/ + docs/" )
{
    const RealText& r = realText();
    INFO( "files: ", r.fileCount, "  first divergence: ", r.findFail );
    CHECK( r.findFail.empty() );
}

TEST_CASE( "strkern: G4 tokenizer == pre-change walker over every byte of src/ + docs/" )
{
    const RealText& r = realText();
    INFO( "files: ", r.fileCount, " bytes: ", r.totalBytes, "  first divergence: ", r.tokFail );
    CHECK( r.tokFail.empty() );
}

TEST_CASE( "escape: escapeXml byte-identical to the frozen per-byte reference" )
{
    const EscapeRun& e = escapeRun();
    INFO( "inputs: ", e.caseCount, "  mismatches: ", e.xmlBad );
    CHECK( e.xmlBad == 0 );
}

TEST_CASE( "escape: appendCdataSafe byte-identical to the frozen per-byte reference" )
{
    const EscapeRun& e = escapeRun();
    INFO( "inputs: ", e.caseCount, "  mismatches: ", e.cdataBad );
    CHECK( e.cdataBad == 0 );
}

TEST_CASE( "escape: escapeInto byte-identical to the frozen per-byte reference (8 flag combos)" )
{
    const EscapeRun& e = escapeRun();
    INFO( "inputs: ", e.caseCount, "  mismatches: ", e.jsonBad );
    CHECK( e.jsonBad == 0 );
}

TEST_CASE( "escape: xmlScrubIsLossy(false) really means appendCdataSafe moved no byte" )
{
    const EscapeRun& e = escapeRun();
    INFO( "inputs: ", e.caseCount, "  disagreements: ", e.lossyBad );
    CHECK( e.lossyBad == 0 );
}

#if EMITESCAPE_MUTATE_BYTESET
TEST_CASE( "escape: MUT a byteset missing '<' DISAGREES with the reference (the gate can go red)" )
{
    const EscapeRun& e = escapeRun();
    std::printf( "  MUT: %zu of %zu inputs differ\n", e.mutDiff, e.caseCount );
    CHECK( e.mutDiff > 0 );
}
#endif
