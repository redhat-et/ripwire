#pragma once

// repeateddecision.h — QD-REPEATED-DECISION: a decision written twice inside ONE function.
//
// THE CASE THIS EXISTS FOR (QD-SLIPS-FIX, 2026-11-19). Two of #697's merged complexity slips had the same tell, and no
// --quality-delta row named it:
//   * defGroupsDropSilent (src/defattrib.h, d04531421) tested `groups.untied[k] && !named[k]` twice — once to count
//     what a drop would leave, once in the renumbering loop. The fix named the decision once (defGroupsSilent, a mask)
//     and ccx went 14 -> 2.
//   * chooseInWindow (test/showcase_capture.py, fb23cb777) copied its pass loop — `n = firstWindow( lo, hi, ok )`, the
//     print, the return — a second time for the last-resort passes. The fix ran both pass tables through one loop
//     (scanPasses) and the complexity row 12 -> 16 went away.
// A complexity number says THAT a function is hard to follow; it does not say that the cheapest fix is to decide once.
// This reads the function's own body for the two shapes and hands the row a fix= that names them with their lines.
//
// WHAT IT READS, and nothing else. The body's VERBATIM token stream (clones.h's one scanner, maximal munch on):
//   repeated condition — the condition of an `if` / `while` / `elif`, or a parenthesized condition right before `?`,
//                        token-identical to an earlier one in the same body and at least kRepeatedConditionMinTokens
//                        long (shorter ones — `x == nullptr`, `!ok` — are single facts that are cheap to re-test);
//   cloned loop body   — two `for` / `while` loops whose bodies are token-identical (a braced body of at least
//                        kClonedLoopMinTokens tokens), or, in an indentation language, whose first kClonedLoopMinTokens
//                        body tokens are.
// It is a FACET: it adds fix= text to a complexity or tangle row that already exists, so it can never make a row, and
// never make one gate. Report-only by construction.
//
// WHAT IT CANNOT SEE: the same decision spelled two ways (`a && b` vs `b && a`, a renamed local), a condition re-tested
// after the state it reads changed on purpose (a fix= is advice, the reader can overrule it), Ruby/Lua/Elixir conditions
// (no closing token to read to), and a loop body in an indentation language beyond its first kClonedLoopMinTokens tokens.
//
// DETERMINISM: a pure function of the body bytes; the first repeat in token order is the one named.

#include "cloneidiom.h"   // IdiomTok, idiomCloseOf, idiomBracketStep — the token view and bracket matcher the idiom grammars use
#include "infra/strkern.h"   // strkern::lineNumberAt — a finding's line from its byte offset
#include "clones.h"       // scanCodeTokens — THE one code scanner
#include "model.h"

#include <algorithm>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw::decision
{

constexpr std::size_t kRepeatedConditionMinTokens = 6;    // `groups.untied[k] && !named[k]` is 11; `p != nullptr` is 3
constexpr std::size_t kClonedLoopMinTokens        = 12;   // a loop body that short is a line, not a copied block
constexpr std::size_t kFixConditionMaxBytes       = 60;   // the condition as quoted in fix=, whitespace collapsed

// The two fix= openings: what the legend keys off, and what a reader greps for.
inline constexpr std::string_view kNameDecisionFix = "name the decision once: ";
inline constexpr std::string_view kNameLoopFix     = "name the loop once: ";

// How a language closes a condition: a parenthesized group (the C family), the depth-0 `:` (Python, GDScript), the
// depth-0 `{` (Go, Rust, Swift), or not readable at all.
enum class CondClose : std::uint8_t { Paren, Colon, Brace, None };

inline constexpr std::uint32_t kColonCondLangMask = langBit( Lang::Python ) | langBit( Lang::GDScript );
inline constexpr std::uint32_t kBraceCondLangMask = langBit( Lang::Go ) | langBit( Lang::Rust ) | langBit( Lang::Swift );
inline constexpr std::uint32_t kNoCondLangMask    = langBit( Lang::Ruby ) | langBit( Lang::Lua ) | langBit( Lang::Elixir ) | langBit( Lang::Bash )
                                                  | langBit( Lang::Clojure ) | langBit( Lang::Markdown ) | langBit( Lang::Unknown );

inline CondClose condCloseOf( Lang lang ) noexcept
{
    if( langInMask( kNoCondLangMask, lang ) )
    {
        return CondClose::None;
    }
    if( langInMask( kColonCondLangMask, lang ) )
    {
        return CondClose::Colon;
    }
    return langInMask( kBraceCondLangMask, lang ) ? CondClose::Brace : CondClose::Paren;
}

inline constexpr std::string_view kConditionKeywords[] = { "if", "while", "elif" };
inline constexpr std::string_view kLoopKeywords[]      = { "for", "while" };

// A token range [begin, end) of the body.
struct TokSpan
{
    std::size_t begin = 0;
    std::size_t end   = 0;
};

// The index of the first depth-0 `stop` token at or after `from`, or t.size() — also when a bracket closes first: the keyword
// sat inside an expression (`[x for x in xs]`), not at a statement.
inline std::size_t depthZeroStop( const std::vector<IdiomTok>& t, std::size_t from, std::string_view stop ) noexcept
{
    std::size_t depth = 0;
    for( std::size_t j = from; j < t.size(); ++j )
    {
        const int step = idiomBracketStep( t[j].text );
        if( depth == 0 && ( t[j].text == stop || step < 0 ) )
        {
            return t[j].text == stop ? j : t.size();
        }
        depth = step > 0 ? depth + 1 : ( step < 0 ? depth - 1 : depth );
    }
    return t.size();
}

// Whether a keyword at t[at] opens a STATEMENT. In an indentation language a statement keyword starts its line, which is what
// tells `if x:` from the conditional expression `a if x else b` and a comprehension's `for`; the C family reads every one.
inline bool opensStatement( const std::string& bytes, const std::vector<IdiomTok>& t, std::size_t at, CondClose close ) noexcept
{
    if( close != CondClose::Colon )
    {
        return true;
    }
    for( std::size_t k = std::size_t( t[at].text.data() - bytes.data() ); k > 0; --k )
    {
        const char c = bytes[k - 1];
        if( c == '\n' )
        {
            return true;
        }
        if( c != ' ' && c != '\t' )
        {
            return false;
        }
    }
    return true;
}

// The condition after the keyword at t[at], or an empty span when the language's closing token never comes.
inline TokSpan headerAfter( const std::vector<IdiomTok>& t, std::size_t at, CondClose close ) noexcept
{
    const std::size_t from = at + 1;
    if( close == CondClose::Paren )
    {
        if( from >= t.size() || t[from].text != "(" )
        {
            return {};
        }
        const std::size_t shut = idiomCloseOf( t, from, t.size() );
        return shut < t.size() ? TokSpan{ from + 1, shut } : TokSpan{};
    }
    const std::size_t stop = depthZeroStop( t, from, close == CondClose::Colon ? ":" : "{" );
    return stop < t.size() ? TokSpan{ from, stop } : TokSpan{};
}

inline std::uint64_t spanKey( const std::vector<IdiomTok>& t, TokSpan s )
{
    std::string joined;
    for( std::size_t k = s.begin; k < s.end; ++k )
    {
        joined += t[k].text;
        joined += '\x02';
    }
    return fnv1a64( joined );
}

// Every condition of the body, in token order: keyword conditions, and (paren languages) a group closed right before `?`.
inline std::vector<TokSpan> conditionsOf( const std::string& bytes, const std::vector<IdiomTok>& t, CondClose close )
{
    std::vector<TokSpan> out;
    for( std::size_t k = 0; k < t.size(); ++k )
    {
        if( std::ranges::contains( kConditionKeywords, t[k].text ) && opensStatement( bytes, t, k, close ) )
        {
            const TokSpan s = headerAfter( t, k, close );
            if( s.end > s.begin )
            {
                out.push_back( s );
            }
        }
        else if( close == CondClose::Paren && t[k].text == "(" )
        {
            const std::size_t shut = idiomCloseOf( t, k, t.size() );
            if( shut + 1 < t.size() && t[shut + 1].text == "?" )
            {
                out.push_back( { k + 1, shut } );
            }
        }
    }
    return out;
}

// Every loop body of the body, in token order: the braced block after the header, or (an indentation language) the first
// kClonedLoopMinTokens tokens after the header's `:`. A body shorter than that is not a block worth naming and is left out.
inline std::vector<TokSpan> loopBodiesOf( const std::string& bytes, const std::vector<IdiomTok>& t, CondClose close )
{
    std::vector<TokSpan> out;
    for( std::size_t k = 0; k < t.size(); ++k )
    {
        if( !std::ranges::contains( kLoopKeywords, t[k].text ) || !opensStatement( bytes, t, k, close ) )
        {
            continue;
        }
        const TokSpan head = headerAfter( t, k, close );
        if( head.end <= head.begin )
        {
            continue;
        }
        const std::size_t open = close == CondClose::Paren ? head.end + 1 : head.end;   // the `{` (or `:`) after the header
        if( open >= t.size() )
        {
            continue;
        }
        TokSpan body;
        if( close == CondClose::Colon )
        {
            body = { open + 1, std::min( t.size(), open + 1 + kClonedLoopMinTokens ) };
        }
        else if( t[open].text == "{" )
        {
            body = { open + 1, idiomCloseOf( t, open, t.size() ) };
        }
        if( body.end >= body.begin + kClonedLoopMinTokens )
        {
            out.push_back( body );
        }
    }
    return out;
}

// The first span repeated later in `spans`, after it ends, with at least `minTokens` tokens: { first, again }, or two empty spans.
inline std::pair<TokSpan, TokSpan> firstRepeat( const std::vector<IdiomTok>& t, const std::vector<TokSpan>& spans, std::size_t minTokens )
{
    std::vector<std::uint64_t> keys;
    keys.reserve( spans.size() );
    for( const TokSpan& s : spans )
    {
        keys.push_back( s.end - s.begin >= minTokens ? spanKey( t, s ) : 0 );
    }
    for( std::size_t b = 0; b < spans.size(); ++b )
    {
        for( std::size_t a = 0; keys[b] != 0 && a < b; ++a )
        {
            if( keys[a] == keys[b] && spans[b].begin >= spans[a].end )
            {
                return { spans[a], spans[b] };
            }
        }
    }
    return {};
}

inline std::size_t offsetOf( const std::string& bytes, std::string_view w ) noexcept { return std::size_t( w.data() - bytes.data() ); }

// A span's source text, whitespace runs collapsed to one space, cut at kFixConditionMaxBytes on a UTF-8 boundary.
inline std::string spanText( const std::string& bytes, const std::vector<IdiomTok>& t, TokSpan s )
{
    const std::size_t from = offsetOf( bytes, t[s.begin].text );
    const std::size_t to   = offsetOf( bytes, t[s.end - 1].text ) + t[s.end - 1].text.size();
    std::string       out;
    for( std::size_t k = from; k < to; ++k )
    {
        const bool space = bytes[k] == ' ' || bytes[k] == '\t' || bytes[k] == '\n' || bytes[k] == '\r';
        if( !space || ( !out.empty() && out.back() != ' ' ) )
        {
            out += space ? ' ' : bytes[k];
        }
    }
    if( out.size() > kFixConditionMaxBytes )
    {
        std::size_t cut = kFixConditionMaxBytes;
        while( cut > 0 && ( static_cast<unsigned char>( out[cut] ) & 0xC0 ) == 0x80 )
        {
            --cut;
        }
        out.resize( cut );
        out += "...";
    }
    return out;
}

// The fix= text for one function body bytes[sigEnd, end) in `lang`, or "" when it repeats no decision.
inline std::string repeatedDecisionFix( const std::string& bytes, std::size_t bodyBegin, std::size_t bodyEnd, Lang lang )
{
    const CondClose close = condCloseOf( lang );
    if( close == CondClose::None || bodyEnd <= bodyBegin || bodyEnd > bytes.size() )
    {
        return {};
    }
    std::vector<IdiomTok> t;
    scanCodeTokens( bytes, bodyBegin, bodyEnd, usesHashLineComments( lang ), true,
                    [ & ]( std::string_view w, CodeTokenKind kind ) { t.push_back( { w, kind } ); } );
    std::string out;
    const auto [ cond, condAgain ] = firstRepeat( t, conditionsOf( bytes, t, close ), kRepeatedConditionMinTokens );
    if( condAgain.end > condAgain.begin )
    {
        out += kNameDecisionFix;
        out += spanText( bytes, t, cond ) + " is tested at lines " + std::to_string( strkern::lineNumberAt( bytes, offsetOf( bytes, t[cond.begin].text ) ) )
             + " and " + std::to_string( strkern::lineNumberAt( bytes, offsetOf( bytes, t[condAgain.begin].text ) ) );
    }
    const auto [ loop, loopAgain ] = firstRepeat( t, loopBodiesOf( bytes, t, close ), kClonedLoopMinTokens );
    if( loopAgain.end > loopAgain.begin )
    {
        out += out.empty() ? "" : "; ";
        out += kNameLoopFix;
        out += "the loop body at line " + std::to_string( strkern::lineNumberAt( bytes, offsetOf( bytes, t[loop.begin].text ) ) ) + " repeats at line "
             + std::to_string( strkern::lineNumberAt( bytes, offsetOf( bytes, t[loopAgain.begin].text ) ) );
    }
    return out;
}

}   // namespace rw::decision
