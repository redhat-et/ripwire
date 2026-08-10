// jsonwalk_unit.cpp — W2-M0 differential driver for the jsonStringEnd hoist.
//
// The hoist claims to be a PURE refactor: rw::jsonStringEnd (jsonesc.h) is now the one escape-aware JSON
// string walk, and both former owners forward into it — mcpdetail::stringEnd (mcpjson.h, npos on an
// unterminated string) and minedjson::skipString (eval.h, one-past-the-close and clamped to size()).
//
// A refactor claim is only worth its differential, so this driver carries VERBATIM COPIES of the two
// PRE-HOIST bodies (see legacyStringEnd / legacySkipString below, transcribed from 037a121) and asserts
// the live functions agree with them on every input in an exhaustive corpus. That is the only way to prove
// "no behaviour change" for a walk whose whole job is edge cases: a live-binary diff can only reach the
// inputs some verb happens to construct, and the interesting ones here (trailing backslash at EOF,
// unterminated string, escaped quote at the boundary) are exactly the ones a well-formed request never has.
//
// Corpus: an EXHAUSTIVE enumeration of every string over the alphabet {'"', '\\', 'x'} up to length 8
// (3^0..3^8 = 9841 strings), each probed at EVERY start offset — the alphabet is closed over the three
// byte classes the walk distinguishes, so exhaustive-to-8 covers every escape/quote interleaving the walk
// can branch on. Plus a hand-written table of named shapes for readability, and the two wrappers' own
// precondition arms (skipString's not-a-quote guard, which the core deliberately does not have).
//
// Run by test/jsonwalkcheck.sh. Prints "  PASS/FAIL <name>" lines and a final UNIT ALL PASS.

#include "mcpjson.h"     // rw::mcpdetail::stringEnd  — the live (forwarding) implementation
#include "eval.h"        // rw::minedjson::skipString — the live (forwarding) implementation
#include "infra/jsonesc.h"     // rw::jsonStringEnd         — the shared core

#include <cstdio>
#include <string>
#include <vector>

namespace
{

int  failCount = 0;
long checkCount = 0;

void ok( const char* what ) { std::printf( "  PASS  %s\n", what ); }
void no( const char* what ) { std::printf( "  FAIL  %s\n", what ); ++failCount; }

// ── the two PRE-HOIST bodies, transcribed verbatim from 037a121 ────────────────────────────────────
// mcpjson.h:66-73 as it stood before the hoist.
std::size_t legacyStringEnd( const std::string& s, std::size_t quotePos ) noexcept
{
    std::size_t q = quotePos + 1;
    while( q < s.size() && s[q] != '"' )
    {
        q += ( s[q] == '\\' && q + 1 < s.size() ) ? 2 : 1;
    }
    return q < s.size() ? q : std::string::npos;
}

// eval.h:454-460 as it stood before the hoist.
std::size_t legacySkipString( const std::string& s, std::size_t pos )
{
    if( pos >= s.size() || s[pos] != '"' )
    {
        return pos;
    }
    std::size_t i = pos + 1;
    while( i < s.size() && s[i] != '"' )
    {
        i += ( s[i] == '\\' && i + 1 < s.size() ) ? 2 : 1;
    }
    return ( i < s.size() ) ? i + 1 : s.size();
}

// A readable rendering of a probe string for failure messages (the corpus is all-ASCII by construction).
std::string show( const std::string& s )
{
    std::string out = "\"";
    for( char c : s )
    {
        if( c == '\\' ) { out += "\\\\"; }
        else if( c == '"' ) { out += "\\\""; }
        else
        {
            out += c;
        }
    }
    out += "\"";
    return out;
}

// One probe: both wrappers must agree with their own legacy body, and the mcp wrapper must equal the core.
bool probe( const std::string& s, std::size_t pos, std::string& whyOut )
{
    ++checkCount;

    const std::size_t liveEnd   = rw::mcpdetail::stringEnd( s, pos );
    const std::size_t legacyEnd = legacyStringEnd( s, pos );
    if( liveEnd != legacyEnd )
    {
        whyOut = "stringEnd diverged at " + show( s ) + " pos=" + std::to_string( pos );
        return false;
    }

    // the core IS what the mcp wrapper returns — same convention, no adaptation
    if( rw::jsonStringEnd( s, pos ) != legacyEnd )
    {
        whyOut = "jsonStringEnd != legacy stringEnd at " + show( s ) + " pos=" + std::to_string( pos );
        return false;
    }

    const std::size_t liveSkip   = rw::minedjson::skipString( s, pos );
    const std::size_t legacySkip = legacySkipString( s, pos );
    if( liveSkip != legacySkip )
    {
        whyOut = "skipString diverged at " + show( s ) + " pos=" + std::to_string( pos );
        return false;
    }

    return true;
}

}   // namespace

int main()
{
    // ── arm 1: exhaustive over {'"','\\','x'} up to length 8, every start offset ────────────────────
    {
        const char        alphabet[] = { '"', '\\', 'x' };
        std::string       why;
        bool              clean      = true;
        long              strings    = 0;

        for( int len = 0; len <= 8 && clean; ++len )
        {
            const long total = [ & ] { long t = 1; for( int k = 0; k < len; ++k ) { t *= 3; } return t; }();
            for( long code = 0; code < total && clean; ++code )
            {
                std::string s;
                s.reserve( std::size_t( len ) );
                long rest = code;
                for( int k = 0; k < len; ++k ) { s += alphabet[ rest % 3 ]; rest /= 3; }
                ++strings;

                // every start offset, plus one PAST the end (both wrappers must stay in bounds)
                for( std::size_t pos = 0; pos <= s.size() && clean; ++pos )
                {
                    if( !probe( s, pos, why ) )
                    {
                        clean = false;
                    }
                }
            }
        }

        if( clean )
        {
            char msg[ 192 ];
            std::snprintf( msg, sizeof( msg ),
                           "exhaustive {quote,backslash,x}^0..8: %ld strings, %ld probes — live == legacy on every one",
                           strings, checkCount );
            ok( msg );
        }
        else
        {
            no( why.c_str() );
        }
    }

    // ── arm 2: the named shapes, spelled out so a reader can see what is covered ────────────────────
    {
        struct Shape { const char* name; std::string s; std::size_t pos; };
        const std::vector<Shape> shapes = {
            { "empty string literal",              "\"\"",              0 },
            { "plain string",                      "\"abc\"",           0 },
            { "escaped quote inside",              "\"a\\\"b\"",        0 },
            { "escaped backslash then close",      "\"a\\\\\"",         0 },
            { "UNTERMINATED (no closing quote)",   "\"abc",             0 },
            { "trailing backslash at EOF",         "\"abc\\",           0 },
            { "backslash-quote at EOF (unterm)",   "\"abc\\\"",         0 },
            { "empty buffer",                      "",                  0 },
            { "lone quote",                        "\"",                0 },
            { "pos past end",                      "\"ab\"",            9 },
            { "not-a-quote at pos (skip guard)",   "abc",               0 },
            { "nested-looking payload",            "\"{\\\"k\\\":1}\"", 0 },
            { "NUL byte inside the string",        std::string( "\"a\0b\"", 5 ), 0 },
            { "control bytes inside",              "\"a\tb\nc\"",       0 },
            { "high bytes inside",                 "\"a\xff\xfe\x80\"", 0 },
        };

        bool        clean = true;
        std::string why;
        for( const Shape& sh : shapes )
        {
            if( !probe( sh.s, sh.pos, why ) )
            {
                no( ( std::string( "named shape '" ) + sh.name + "': " + why ).c_str() );
                clean = false;
            }
        }
        if( clean )
        {
            ok( "15 named shapes (unterminated / trailing-backslash / NUL / high bytes / past-end)" );
        }
    }

    // ── arm 3: the two CONVENTIONS are the documented ones, not accidentally unified ────────────────
    // This is the arm that would catch a future "tidy-up" collapsing the wrappers into one return shape.
    {
        const std::string terminated   = "\"ab\"";
        const std::string unterminated = "\"ab";

        bool clean = true;
        if( rw::mcpdetail::stringEnd( terminated, 0 ) != 3 )                  { no( "stringEnd: closing-quote INDEX on a terminated string" ); clean = false; }
        if( rw::minedjson::skipString( terminated, 0 ) != 4 )                 { no( "skipString: ONE PAST the close on a terminated string" ); clean = false; }
        if( rw::mcpdetail::stringEnd( unterminated, 0 ) != std::string::npos ){ no( "stringEnd: npos on an unterminated string (H3 truncation detector)" ); clean = false; }
        if( rw::minedjson::skipString( unterminated, 0 ) != unterminated.size() ) { no( "skipString: clamps to size() on an unterminated string" ); clean = false; }
        if( rw::minedjson::skipString( "abc", 1 ) != 1 )                      { no( "skipString: not-a-quote precondition returns pos unchanged" ); clean = false; }
        if( clean )
        {
            ok( "the two return conventions are preserved and distinct (npos vs clamp; index vs one-past)" );
        }
    }

    // ── arm 4: isJsonWs is RFC 8259 §2 exactly — the folded clone family's contract ─────────────────
    {
        bool clean = true;
        for( int b = 0; b < 256; ++b )
        {
            const char c        = char( b );
            const bool expected = ( b == ' ' || b == '\t' || b == '\n' || b == '\r' );
            if( rw::isJsonWs( c ) != expected )
            {
                char msg[ 96 ];
                std::snprintf( msg, sizeof( msg ), "isJsonWs disagrees on byte 0x%02x", unsigned( b ) );
                no( msg );
                clean = false;
                break;
            }
        }
        // the bytes JSON does NOT call whitespace, named explicitly (the std::isspace trap)
        if( clean && ( rw::isJsonWs( '\v' ) || rw::isJsonWs( '\f' ) ) )
        { no( "isJsonWs must reject VT/FF — std::isspace accepts them, JSON does not" ); clean = false; }
        if( clean )
        {
            ok( "isJsonWs == RFC 8259 §2 over all 256 bytes (VT/FF rejected)" );
        }
    }

    if( failCount == 0 ) { std::printf( "UNIT ALL PASS\n" ); return 0; }
    std::printf( "UNIT FAILURES: %d\n", failCount );
    return 1;
}
