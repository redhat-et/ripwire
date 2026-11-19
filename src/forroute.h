// forroute.h — RT1 (owner decision 2026-11-18, "Accept V1, start RT1"): which --for questions a targeted verb answers.
//
// THE RULE, AND WHERE IT CAME FROM. Lane P1 (results/P1_VERBROUTE_1118) fixed two text-only rules before running any verb on a
// held-out question, in rules.py, and this file transcribes them; it adds nothing and tunes nothing:
//   rule E (the symbol): every backtick span of the question that is an identifier path (`a`, `a.b`, `a::b`, `a#b`) AND looks
//          like code (contains _ :: . or #, or has a lower-to-upper step) is a candidate; the LAST candidate is the symbol.
//          No candidate: no route. On P1's 49 cells E named 23 of 23 named symbols right and invented none.
//   rule R (the kind), case-insensitive, first match wins, only when E found a symbol:
//          1 transitive    — transitive | hops?\b | up to (two|three|\d) | level by level | call levels | \btrace\b | depends? on
//          2 direct-radius — blast radius | what breaks | at risk | affected | must change | have to change | which files
//          3 who-calls     — \bcall(s|ed|ers?)?\b
//          else the question stays on --for. R read the kind right on 21 of 21 routed cells.
// The kind picks the verb one to one: transitive → --impact, direct-radius → --uses, who-calls → --callers.
//
// HOW FAITHFUL THE TRANSCRIPTION IS. rules.py runs Python `re` on str (Unicode). Two readings here are narrower, both on
// non-ASCII text only: \b and \w treat a UTF-8 code point as a word character unless it is Latin-1 punctuation
// (U+00A0-U+00BF, U+00D7, U+00F7) or General Punctuation (U+2000-U+206F: dashes, quotes, ellipsis), and re.I's two non-ASCII
// folds (the Kelvin sign to k, the long s to s) are not made. results/RT1_ROUTE_1118 checks this file against rules.py on every
// question of the development and confirmation sets.
#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>

#include "infra/namesplit.h"   // isIdentChar — the ASCII word byte
#include "lexical.h"           // routeLower — the ASCII-lowered task

namespace rw::forroute
{

enum class RouteKind : std::uint8_t
{
    None,           // the question stays on --for
    Transitive,     // → --impact
    DirectRadius,   // → --uses
    WhoCalls,       // → --callers
    WhereUsed,      // → --uses (RT2)
};

// One row per routed kind, indexed by RouteKind: its name and the verb flag that answers it, spelled as a selector flag takes it.
struct KindRow
{
    std::string_view name;
    std::string_view verbFlag;
};
inline constexpr KindRow kKindRows[] =
{
    { "", "" },                           // None
    { "transitive", "--impact=" },        // Transitive
    { "direct-radius", "--uses=" },       // DirectRadius
    { "who-calls", "--callers=" },        // WhoCalls
    { "where-used", "--uses=" },          // WhereUsed
};
static_assert( std::size( kKindRows ) == std::size_t( RouteKind::WhereUsed ) + 1, "one row per RouteKind, in enum order" );
[[nodiscard]] constexpr std::string_view kindName( RouteKind k ) noexcept { return kKindRows[ std::size_t( k ) ].name; }
[[nodiscard]] constexpr std::string_view verbFlag( RouteKind k ) noexcept { return kKindRows[ std::size_t( k ) ].verbFlag; }

namespace detail
{
[[nodiscard]] constexpr bool isAsciiAlpha( char c ) noexcept { return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ); }
[[nodiscard]] constexpr bool isAsciiDigit( char c ) noexcept { return c >= '0' && c <= '9'; }
[[nodiscard]] constexpr bool isIdentHead( char c ) noexcept { return isAsciiAlpha( c ) || c == '_' || c == '$'; }
[[nodiscard]] constexpr bool isIdentTail( char c ) noexcept { return isIdentHead( c ) || isAsciiDigit( c ); }

// Python's \w at byte `at` of `s` (see the header for the non-ASCII reading). A continuation byte reads as its code point's lead.
[[nodiscard]] inline bool isWordAt( std::string_view s, std::size_t at ) noexcept
{
    const auto c = static_cast<unsigned char>( s[ at ] );
    if( c < 0x80 )
    {
        return rw::namesplit::isIdentChar( char( c ) );
    }
    std::size_t lead = at;
    while( lead > 0 && ( static_cast<unsigned char>( s[ lead ] ) & 0xC0u ) == 0x80u )
    {
        --lead;
    }
    const auto b0 = static_cast<unsigned char>( s[ lead ] );
    const auto b1 = lead + 1 < s.size() ? static_cast<unsigned char>( s[ lead + 1 ] ) : 0u;
    const auto b2 = lead + 2 < s.size() ? static_cast<unsigned char>( s[ lead + 2 ] ) : 0u;
    if( b0 == 0xC2u && b1 >= 0xA0u && b1 <= 0xBFu )
    {
        return false;   // U+00A0-U+00BF: no-break space, Latin-1 punctuation and signs
    }
    if( b0 == 0xC3u && ( b1 == 0x97u || b1 == 0xB7u ) )
    {
        return false;   // U+00D7 ×, U+00F7 ÷
    }
    if( b0 == 0xE2u && ( b1 == 0x80u || b1 == 0x81u ) && b2 >= 0x80u )
    {
        return false;   // U+2000-U+207F: General Punctuation (dashes, quotes, ellipsis) and the super/subscript head
    }
    return true;
}
// A \b between bytes at-1 and at.
[[nodiscard]] inline bool isBoundary( std::string_view s, std::size_t at ) noexcept
{
    const bool before = at > 0 && isWordAt( s, at - 1 );
    const bool after  = at < s.size() && isWordAt( s, at );
    return before != after;
}

// IDENT.fullmatch: [A-Za-z_$][A-Za-z0-9_$]* ( (::|.|#) [A-Za-z_$][A-Za-z0-9_$]* )*
[[nodiscard]] inline bool isIdentPath( std::string_view s ) noexcept
{
    std::size_t i = 0;
    for( ;; )
    {
        if( i >= s.size() || !isIdentHead( s[ i ] ) )
        {
            return false;
        }
        ++i;
        while( i < s.size() && isIdentTail( s[ i ] ) )
        {
            ++i;
        }
        if( i == s.size() )
        {
            return true;
        }
        if( s.substr( i, 2 ) == "::" )
        {
            i += 2;
        }
        else if( s[ i ] == '.' || s[ i ] == '#' )
        {
            ++i;
        }
        else
        {
            return false;
        }
    }
}

// rules.py codeish: _ :: . # anywhere, or a lower-to-upper step.
[[nodiscard]] inline bool isCodeShaped( std::string_view s ) noexcept
{
    if( s.find_first_of( "_.#" ) != std::string_view::npos || s.find( "::" ) != std::string_view::npos )
    {
        return true;
    }
    for( std::size_t i = 0; i + 1 < s.size(); ++i )
    {
        if( s[ i ] >= 'a' && s[ i ] <= 'z' && s[ i + 1 ] >= 'A' && s[ i + 1 ] <= 'Z' )
        {
            return true;
        }
    }
    return false;
}

// Does `word` occur in `lq` at an offset `okAt` accepts? The one walk every cue test below shares.
template <class OkAt>
[[nodiscard]] inline bool occursWhere( std::string_view lq, std::string_view word, OkAt okAt )
{
    // anyField's fields are the text between occurrences: each field that a separator follows ends where one occurrence begins
    return rw::namesplit::anyField( lq, word, true, [ & ]( std::string_view field )
    {
        const std::size_t at = std::size_t( field.data() - lq.data() ) + field.size();
        return at < lq.size() && okAt( at );
    } );
}
// Does any cue occur in `lq` at all?
[[nodiscard]] inline bool hasAnyCue( std::string_view lq, std::span<const std::string_view> cues )
{
    return std::ranges::any_of( cues, [ & ]( std::string_view cue ) { return lq.find( cue ) != std::string_view::npos; } );
}
// `word` with \b after it, and also before it when `before` (`hops?\b` and `depends? on` are unanchored on the left).
[[nodiscard]] inline bool hasBoundedWord( std::string_view lq, std::string_view word, bool before )
{
    return occursWhere( lq, word, [ & ]( std::size_t at ) { return ( !before || isBoundary( lq, at ) ) && isBoundary( lq, at + word.size() ); } );
}
// `\bcall(s|ed|ers?)?\b`: a \b before "call" and after one of its suffixes (the empty one included).
[[nodiscard]] inline bool hasCallWord( std::string_view lq )
{
    constexpr std::string_view kSuffixes[] = { "s", "ed", "ers", "er", "" };
    return occursWhere( lq, "call", [ & ]( std::size_t at )
    {
        return isBoundary( lq, at ) && std::ranges::any_of( kSuffixes, [ & ]( std::string_view suf )
        {
            return lq.substr( at + 4, suf.size() ) == suf && isBoundary( lq, at + 4 + suf.size() );
        } );
    } );
}

[[nodiscard]] inline bool isTransitive( std::string_view lq ) noexcept
{
    constexpr std::string_view kPlain[] = { "transitive", "level by level", "call levels", "depend on", "depends on" };
    if( hasAnyCue( lq, kPlain ) )
    {
        return true;
    }
    if( hasBoundedWord( lq, "hop", false ) || hasBoundedWord( lq, "hops", false ) )
    {
        return true;
    }
    const bool upTo = occursWhere( lq, "up to ", [ & ]( std::size_t at )
    {
        const std::string_view rest = lq.substr( at + 6 );
        return rest.starts_with( "two" ) || rest.starts_with( "three" ) || ( !rest.empty() && isAsciiDigit( rest[ 0 ] ) );
    } );
    return upTo || occursWhere( lq, "trace", [ & ]( std::size_t at ) { return isBoundary( lq, at ) && isBoundary( lq, at + 5 ); } );
}

// The first non-space byte after `lq[at, at+len)` when that word is bounded on both sides; npos when it is not.
[[nodiscard]] inline std::size_t afterBoundedWord( std::string_view lq, std::size_t at, std::size_t len )
{
    if( !isBoundary( lq, at ) || !isBoundary( lq, at + len ) )
    {
        return std::string_view::npos;
    }
    std::size_t k = at + len;
    while( k < lq.size() && ( lq[ k ] == ' ' || lq[ k ] == '\t' || lq[ k ] == '\n' || lq[ k ] == '\r' || lq[ k ] == '\f' || lq[ k ] == '\v' ) )
    {
        ++k;
    }
    return k;
}

// \bused\b(?!\s+by\b): "used", unless it is passive "used by X" (that names the user, not where the subject is used).
[[nodiscard]] inline bool hasUsedNotBy( std::string_view lq )
{
    return occursWhere( lq, "used", [ & ]( std::size_t at )
    {
        const std::size_t k = afterBoundedWord( lq, at, 4 );
        return k != std::string_view::npos && ( k == at + 4 || !( lq.substr( k, 2 ) == "by" && isBoundary( lq, k + 2 ) ) );
    } );
}

// rule R2's where-used cues (RT2; see the header for the pattern this transcribes).
[[nodiscard]] inline bool isWhereUsed( std::string_view lq )
{
    constexpr std::string_view kWords[] = { "usage", "usages", "reference", "references", "referenced", "referencing", "pass", "passes",
                                            "passed", "passing", "apply", "applies", "applied", "invoke", "invokes", "invoked" };
    if( std::ranges::any_of( kWords, [ & ]( std::string_view w ) { return hasBoundedWord( lq, w, true ); } ) )
    {
        return true;
    }
    if( occursWhere( lq, "decorat", [ & ]( std::size_t at ) { return isBoundary( lq, at ); } ) )
    {
        return true;
    }
    if( hasUsedNotBy( lq ) )
    {
        return true;
    }
    // \bwhere is\b[^?]*\buse: "use" with a \b before it, after "where is" and before any '?'
    return occursWhere( lq, "where is", [ & ]( std::size_t at )
    {
        if( !isBoundary( lq, at ) || !isBoundary( lq, at + 8 ) )
        {
            return false;
        }
        const std::size_t q    = lq.find( '?', at + 8 );
        const std::string_view rest = lq.substr( at + 8, q == std::string_view::npos ? std::string_view::npos : q - at - 8 );
        const std::size_t base = at + 8;
        return occursWhere( rest, "use", [ & ]( std::size_t u ) { return isBoundary( lq, base + u ); } );
    } );
}

// Where the sentence that `from` sits in ends: the first '?', or the first '.' followed by whitespace or the end — a '.' inside a
// dotted name (`Application.initialize`) does not end it (Python's (?:[^?.]|\.(?!\s|$))*). npos: the text's end.
[[nodiscard]] inline std::size_t sentenceEnd( std::string_view lq, std::size_t from )
{
    for( std::size_t i = from; i < lq.size(); ++i )
    {
        const bool spaceNext = i + 1 == lq.size() || lq[ i + 1 ] == ' ' || lq[ i + 1 ] == '\t' || lq[ i + 1 ] == '\n' || lq[ i + 1 ] == '\r'
                            || lq[ i + 1 ] == '\f' || lq[ i + 1 ] == '\v';
        if( lq[ i ] == '?' || ( lq[ i ] == '.' && spaceNext ) )
        {
            return i;
        }
    }
    return std::string_view::npos;
}

// `word`, bounded on both sides, at an offset in [from, the end of from's sentence).
[[nodiscard]] inline bool wordInSentence( std::string_view lq, std::size_t from, std::string_view word )
{
    const std::size_t      stop = sentenceEnd( lq, from );
    const std::string_view span = lq.substr( from, stop == std::string_view::npos ? std::string_view::npos : stop - from );
    return occursWhere( span, word, [ & ]( std::size_t at ) { return isBoundary( lq, from + at ) && isBoundary( lq, from + at + word.size() ); } );
}

// \b(does|do|did)\b S \bcall\b starting at `from`, within one sentence.
[[nodiscard]] inline bool auxThenCall( std::string_view lq, std::size_t from )
{
    const std::size_t      stop = sentenceEnd( lq, from );
    const std::string_view span = lq.substr( from, stop == std::string_view::npos ? std::string_view::npos : stop - from );
    return std::ranges::any_of( std::array<std::string_view, 3>{ "does", "do", "did" }, [ & ]( std::string_view aux )
    {
        return occursWhere( span, aux, [ & ]( std::size_t at )
        {
            const std::size_t a = from + at;
            return isBoundary( lq, a ) && isBoundary( lq, a + aux.size() ) && wordInSentence( lq, a + aux.size(), "call" );
        } );
    } );
}

// \bwhat\s+(?!calls\b)\S S \bcalls\b: "what X calls" — never "what calls X".
[[nodiscard]] inline bool whatSubjectCalls( std::string_view lq )
{
    return occursWhere( lq, "what", [ & ]( std::size_t at )
    {
        const std::size_t k = afterBoundedWord( lq, at, 4 );
        if( k == std::string_view::npos || k == at + 4 || k >= lq.size() )
        {
            return false;   // not the word "what", no space after it, or nothing after the space
        }
        const bool callsNext = lq.substr( k, 5 ) == "calls" && isBoundary( lq, k + 5 );
        return !callsNext && wordInSentence( lq, k + 1, "calls" );
    } );
}

// RT2-V: does the question ask what X CALLS (its callees)? See the header for the pattern this transcribes.
[[nodiscard]] inline bool asksCallees( std::string_view lq )
{
    if( hasBoundedWord( lq, "callee", true ) || hasBoundedWord( lq, "callees", true ) )
    {
        return true;
    }
    for( const std::string_view aux : { std::string_view( "what does" ), std::string_view( "what do" ), std::string_view( "what did" ) } )
    {
        if( occursWhere( lq, aux, [ & ]( std::size_t at ) { return isBoundary( lq, at ) && isBoundary( lq, at + aux.size() ) && wordInSentence( lq, at + aux.size(), "call" ); } ) )
        {
            return true;
        }
    }
    if( occursWhere( lq, "which", [ & ]( std::size_t at ) { return isBoundary( lq, at ) && isBoundary( lq, at + 5 ) && auxThenCall( lq, at + 5 ); } ) )
    {
        return true;
    }
    return whatSubjectCalls( lq );
}

// rule R's direct-radius cues: plain substrings.
inline constexpr std::string_view kDirectRadiusCues[] = { "blast radius", "what breaks", "at risk", "affected", "must change", "have to change", "which files" };
} // namespace detail

namespace detail
{
// A span's trailing "()" or "!" (a call or a Rust macro spelling) is not part of the symbol.
[[nodiscard]] constexpr std::string_view trimCallSuffix( std::string_view span ) noexcept
{
    if( span.ends_with( "()" ) )
    {
        span.remove_suffix( 2 );
    }
    else if( span.ends_with( '!' ) )
    {
        span.remove_suffix( 1 );
    }
    return span;
}
// re.findall(r"`([^`\n]+)`"): each span, leftmost first; the scan resumes after a match, and a backtick that opens nothing is skipped.
template <class OnSpan>
inline void forEachBacktickSpan( std::string_view q, OnSpan onSpan )
{
    for( std::size_t i = q.find( '`' ); i != std::string_view::npos; )
    {
        const std::size_t j = q.find_first_of( "`\n", i + 1 );
        if( j != std::string_view::npos && q[ j ] == '`' && j > i + 1 )
        {
            onSpan( q.substr( i + 1, j - i - 1 ) );
            i = q.find( '`', j + 1 );
        }
        else
        {
            i = q.find( '`', i + 1 );
        }
    }
}
} // namespace detail

// Rule E2: the symbol the question names, or "" (no route): the last code-shaped span, else the last identifier span.
[[nodiscard]] inline std::string extractSymbol( std::string_view q )
{
    std::string_view codeShaped, plain;
    detail::forEachBacktickSpan( q, [ & ]( std::string_view raw )
    {
        const std::string_view span = detail::trimCallSuffix( raw );
        if( detail::isIdentPath( span ) )
        {
            ( detail::isCodeShaped( span ) ? codeShaped : plain ) = span;
        }
    } );
    return std::string( codeShaped.empty() ? plain : codeShaped );
}

// Rule R2: the question's kind by its wording alone.
[[nodiscard]] inline RouteKind kindOf( std::string_view q )
{
    const std::string lq = rw::routeLower( q );   // re.I on these all-ASCII patterns
    if( detail::isTransitive( lq ) )
    {
        return RouteKind::Transitive;
    }
    if( detail::hasAnyCue( lq, detail::kDirectRadiusCues ) )
    {
        return RouteKind::DirectRadius;
    }
    if( detail::isWhereUsed( lq ) )
    {
        return RouteKind::WhereUsed;
    }
    if( detail::hasCallWord( lq ) )
    {
        return RouteKind::WhoCalls;
    }
    return RouteKind::None;
}

// A symbol's final name segment (after the last ::, . or #): the spelling fallback when the verb refuses the full path.
[[nodiscard]] inline std::string_view lastSegment( std::string_view sym ) noexcept
{
    using rw::namesplit::afterLast;   // each cut keeps only what follows its separator, so the three compose to "after the last of any"
    return afterLast( afterLast( afterLast( sym, "::" ), "." ), "#" );
}

struct RouteDecision
{
    RouteKind   kind = RouteKind::None;
    std::string sym;   // rule E's symbol; empty with kind None
};

// Both rules: a route only when E names a symbol AND R reads a kind.
[[nodiscard]] inline RouteDecision decide( std::string_view q )
{
    if( detail::asksCallees( rw::routeLower( q ) ) )
    {
        return {};   // RT2-V: a callees question is never routed (the header)
    }
    RouteDecision d;
    d.sym = extractSymbol( q );
    if( d.sym.empty() )
    {
        return {};
    }
    d.kind = kindOf( q );
    if( d.kind == RouteKind::None )
    {
        return {};
    }
    return d;
}

} // namespace rw::forroute
