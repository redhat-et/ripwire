#pragma once
// countdrift.h — the defect-shape facet count-drift: a prose COUNT that no longer matches the list it introduces.
//
// The shape (CodeRabbit class B, the count sub-shape: "the twelve: api-surface, …, verbosity" after a thirteenth kind
// landed; "ELEVEN KINDS" after the twelfth): a count word followed by the list it counts —
//     the thirteen: a, b, c          six facets (a, b, c, d, e, f)          3 modes: x, y and z
// — read in two ways, both deterministic and local:
//   * SELF: the count says N and the list holds M != N items;
//   * NAME SET: the list's items are all members of ONE string-literal array the tree defines (a closed set the code
//     iterates, kQualityKindNames-style), and the array holds a different number than the count says; the row names
//     the array and the members the list leaves out.
// Where it reads: a Markdown file's paragraphs (soft line breaks joined) and a C++ file's string-literal runs (a help or
// legend paragraph spans many literals). An item is a bare or backticked lower-case word (kebab or snake), optionally
// followed by a parenthesized gloss; a list with anything else in it is prose, not a list, and is not judged.
// Floors, stated: a count spelled past twenty, a list split by a sentence, a closed set held in an enum (CamelCase
// enumerators) or in another language's array, and a count of rows or files (no list) are not checked.

#include "defectshape.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw::defectshape
{

// One closed set of names the code holds: a string-literal array of three or more lower-case words.
struct NameSet
{
    std::string              name;
    std::vector<std::string> members;   // sorted, unique
    friend auto operator<=>( const NameSet&, const NameSet& ) = default;
    friend bool operator==( const NameSet&, const NameSet& ) = default;
};

class NameSetTable
{
public:
    NameSetTable() = default;
    // Name order, then members: one table whatever order the files were read in.
    explicit NameSetTable( std::vector<NameSet> sets ) : sets_( std::move( sets ) ) { rw::sortutil::sortUnique( sets_ ); }
    // The first set (in name order) that holds every one of `items` (sorted, unique); nullptr when none does.
    const NameSet* covering( const std::vector<std::string>& items ) const
    {
        for( const NameSet& s : sets_ )
        {
            if( std::includes( s.members.begin(), s.members.end(), items.begin(), items.end() ) )
            {
                return &s;
            }
        }
        return nullptr;
    }
    std::size_t size() const noexcept { return sets_.size(); }

private:
    std::vector<NameSet> sets_;
};

namespace detail
{

inline bool isNameWord( std::string_view w ) noexcept   // a-z first, then a-z 0-9 - _
{
    return wordCaseOf( w ) == WordCase::Lower;
}

// Append the string-literal arrays of a C++ file: `NAME[] = { "a", "b", "c" }` or `std::array<…> NAME = { … }`, every
// element a name word, three or more of them.
inline void appendNameSetsOfCpp( std::string_view src, std::vector<NameSet>& out )
{
    const std::vector<Tok> toks = lexCpp( src );
    for( std::size_t k = 1; k + 1 < toks.size(); ++k )
    {
        if( !tokIs( src, toks[k], "=" ) || !tokIs( src, toks[k + 1], "{" ) )
        {
            continue;
        }
        std::size_t nameAt = k - 1;   // NAME =   or   NAME[ N ] =
        if( tokIs( src, toks[nameAt], "]" ) )
        {
            while( nameAt > 0 && !tokIs( src, toks[nameAt], "[" ) )
            {
                --nameAt;
            }
            nameAt = nameAt > 0 ? nameAt - 1 : 0;
        }
        // an array: the C declarator `NAME[ N ]`, or a `std::array<…>` type in the same declaration (an aggregate
        // `Labels labels = { … }` holds fields, not a set of names)
        const bool cArray = tokIs( src, toks[k - 1], "]" );
        bool       stdArray = false;
        for( std::size_t b = nameAt; !cArray && !stdArray && b-- > 0 && !tokIs( src, toks[b], ";" ) && !tokIs( src, toks[b], "{" ) && !tokIs( src, toks[b], "}" ); )
        {
            stdArray = tokIs( src, toks[b], "array" ) && b + 1 < nameAt && tokIs( src, toks[b + 1], "<" );
        }
        if( toks[nameAt].kind != TokKind::Ident || !( cArray || stdArray ) )
        {
            continue;
        }
        NameSet     set{ std::string( tokText( src, toks[nameAt] ) ), {} };
        std::size_t q  = k + 2;
        bool        ok = true;
        for( ; q < toks.size() && !tokIs( src, toks[q], "}" ); ++q )
        {
            if( toks[q].kind == TokKind::String && isNameWord( tokContent( src, toks[q] ) ) )
            {
                set.members.emplace_back( tokContent( src, toks[q] ) );
            }
            else if( !tokIs( src, toks[q], "," ) )
            {
                ok = false;
                break;
            }
        }
        if( ok && q < toks.size() && set.members.size() >= 3 )
        {
            rw::sortutil::sortUnique( set.members );
            out.push_back( std::move( set ) );
        }
    }
}

inline constexpr std::array<std::string_view, 21> kCountWords = { "zero",   "one",     "two",     "three",    "four",     "five",    "six",
                                                                  "seven",  "eight",   "nine",    "ten",      "eleven",   "twelve",  "thirteen",
                                                                  "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty" };

// The count a word spells (a number word or one or two digits), or -1.
inline int countOf( std::string_view w ) noexcept
{
    if( !w.empty() && w.size() <= 2 && std::all_of( w.begin(), w.end(), []( char c ) { return c >= '0' && c <= '9'; } ) )
    {
        return w.size() == 1 ? w[0] - '0' : ( w[0] - '0' ) * 10 + ( w[1] - '0' );
    }
    for( std::size_t i = 0; i < kCountWords.size(); ++i )
    {
        const std::string_view cw = kCountWords[i];
        if( cw.size() == w.size() && ( w == cw || ( w[0] == cw[0] - 'a' + 'A' && w.substr( 1 ) == cw.substr( 1 ) ) ) )   // "three", "Three"
        {
            return static_cast<int>( i );
        }
    }
    return -1;
}

inline bool isWordChar( char c ) noexcept
{
    return isIdentChar( c ) || c == '-';
}

// The items of a list body "a, b and c" — each a bare or backticked name word, an optional "(gloss)" after it — or
// empty when the body holds anything else (then it is prose, not a list).
inline std::vector<std::string> listItems( std::string_view body )
{
    std::vector<std::string> items;
    std::size_t              i = 0;
    const auto               skipSpace = [ & ] { while( i < body.size() && isSpace( body[i] ) ) { ++i; } };
    while( true )
    {
        skipSpace();
        const bool tick = i < body.size() && body[i] == '`';
        i += tick ? 1 : 0;
        const std::size_t b = i;
        while( i < body.size() && isWordChar( body[i] ) )
        {
            ++i;
        }
        const std::string_view w = body.substr( b, i - b );
        if( !isNameWord( w ) || ( tick && ( i >= body.size() || body[i++] != '`' ) ) )
        {
            return {};
        }
        items.emplace_back( w );
        skipSpace();
        if( i < body.size() && body[i] == '(' )   // a gloss: (C++), (report-only)
        {
            // a gloss that itself lists ("memguardcheck (B6b, B21)") may be what the count counts: not a list we can judge
            const std::size_t close = body.find( ')', i );
            if( close == std::string_view::npos || body.substr( i, close - i ).find( ',' ) != std::string_view::npos )
            {
                return {};
            }
            i = close + 1;
            skipSpace();
        }
        if( i >= body.size() )
        {
            break;
        }
        // the separator: "," (an "and"/"or" may follow it), or a bare "and"/"or"; anything else makes the body prose
        const bool comma = body[i] == ',';
        if( comma )
        {
            ++i;
            skipSpace();
        }
        if( body.compare( i, 4, "and " ) == 0 || body.compare( i, 3, "or " ) == 0 )
        {
            i += body[i] == 'a' ? 4 : 3;
        }
        else if( !comma )
        {
            return {};
        }
    }
    return items.size() >= 2 ? items : std::vector<std::string>{};
}

// Does the body end here? A list ends at the ")" that closes a paren form, or at ". ", ";" or the text's end after a colon.
inline std::size_t listEnd( std::string_view t, std::size_t from, bool paren ) noexcept
{
    for( std::size_t i = from; i < t.size(); ++i )
    {
        const char c = t[i];
        if( paren ? c == ')' : ( c == ';' || c == '\n' || ( c == '.' && ( i + 1 == t.size() || isSpace( t[i + 1] ) ) ) ) )
        {
            return i;
        }
        if( paren && c == '(' )
        {
            const std::size_t close = t.find( ')', i );   // a gloss inside the list
            if( close == std::string_view::npos )
            {
                return std::string_view::npos;
            }
            i = close;
        }
    }
    return paren ? std::string_view::npos : t.size();
}

inline constexpr std::array<std::string_view, 7> kNotANoun = { "by", "the", "of", "in", "to", "a", "an" };

// One count-introduced list found in a text: where its count word starts, the count, the items, and the phrase text.
struct CountList
{
    std::size_t              at    = 0;
    int                      count = 0;
    std::vector<std::string> items;
    std::string              phrase;
};

// Every count-introduced list in `t`: COUNT [up to three words] ':' LIST  or  COUNT NOUNS '(' LIST ')'. The paren form
// needs a plural noun right before the paren ("six facets (a, b, …)"), so "the two (a, b, c) snapshots" and "68 by
// the (caller, callee)" are not lists of the count; a digit count needs a noun ("13 kinds:"), so "3.2 The gate (…)" is
// a section number.
inline std::vector<CountList> countLists( std::string_view t )
{
    std::vector<CountList> out;
    for( std::size_t i = 0; i < t.size(); ++i )
    {
        if( !isWordChar( t[i] ) || ( i > 0 && ( isWordChar( t[i - 1] ) || t[i - 1] == '.' ) ) )
        {
            continue;
        }
        std::size_t e = i;
        while( e < t.size() && isWordChar( t[e] ) )
        {
            ++e;
        }
        const int count = countOf( t.substr( i, e - i ) );
        if( count < 2 )
        {
            i = e;
            continue;
        }
        const bool                    digits = t[i] >= '0' && t[i] <= '9';
        std::size_t                   p      = e;
        std::vector<std::string_view> noun;
        while( noun.size() <= 3 )
        {
            std::size_t q = p;
            while( q < t.size() && t[q] == ' ' )
            {
                ++q;
            }
            if( q < t.size() && ( t[q] == ':' || t[q] == '(' ) )
            {
                p = q;
                break;
            }
            std::size_t w = q;
            while( w < t.size() && isWordChar( t[w] ) )
            {
                ++w;
            }
            if( w == q || noun.size() == 3 )
            {
                p = std::string_view::npos;
                break;
            }
            noun.push_back( t.substr( q, w - q ) );
            p = w;
        }
        if( p == std::string_view::npos || p >= t.size() )
        {
            continue;
        }
        const bool paren = t[p] == '(';
        if( ( digits && noun.empty() )
            || ( paren && ( noun.empty() || noun.back().back() != 's' || std::find( kNotANoun.begin(), kNotANoun.end(), noun.front() ) != kNotANoun.end() ) ) )
        {
            continue;
        }
        const std::size_t end = listEnd( t, p + 1, paren );
        if( end == std::string_view::npos )
        {
            continue;
        }
        std::vector<std::string> items = listItems( t.substr( p + 1, end - p - 1 ) );
        if( !items.empty() )
        {
            out.push_back( { i, count, std::move( items ), std::string( t.substr( i, end - i + ( paren ? 1 : 0 ) ) ) } );
        }
    }
    return out;
}

// A Markdown text with each paragraph's soft line breaks turned into spaces (same length: every byte keeps its offset).
// A break stays when the next line opens a block: a blank line, a heading, a list item, a table row, a fence or a quote.
inline std::string unwrapParagraphs( std::string_view s )
{
    std::string out( s );
    for( std::size_t i = 0; i + 1 < out.size(); ++i )
    {
        if( out[i] != '\n' )
        {
            continue;
        }
        const char n = out[i + 1];
        // a fence opens with three backticks or tildes; a line that starts with one backticked name continues the paragraph
        const bool fence = out.compare( i + 1, 3, "```" ) == 0 || out.compare( i + 1, 3, "~~~" ) == 0;
        const bool block = isSpace( n ) || n == '#' || n == '*' || n == '-' || n == '|' || fence || n == '>' || ( n >= '0' && n <= '9' );
        if( !block )
        {
            out[i] = ' ';
        }
    }
    return out;
}

inline void judgeCountLists( std::string_view text, std::size_t base, const std::vector<std::size_t>* offsetOf, const NameSetTable& sets,
                             std::vector<Site>& out )
{
    for( CountList& cl : countLists( text ) )
    {
        std::string why;
        std::vector<std::string> sorted = cl.items;
        rw::sortutil::sortUnique( sorted );
        if( static_cast<std::size_t>( cl.count ) != cl.items.size() )
        {
            why = "says " + std::to_string( cl.count ) + ", lists " + std::to_string( cl.items.size() );
        }
        else if( const NameSet* s = sorted.size() >= 3 ? sets.covering( sorted ) : nullptr; s != nullptr && s->members.size() != static_cast<std::size_t>( cl.count ) )
        {
            std::vector<std::string> missing;
            std::set_difference( s->members.begin(), s->members.end(), sorted.begin(), sorted.end(), std::back_inserter( missing ) );
            why = "says " + std::to_string( cl.count ) + ", " + s->name + " holds " + std::to_string( s->members.size() );
            if( !missing.empty() )
            {
                why += "; missing " + capList( missing );
            }
        }
        if( why.empty() )
        {
            continue;
        }
        const std::size_t at = offsetOf != nullptr ? ( *offsetOf )[cl.at] : base + cl.at;
        out.push_back( { Facet::CountDrift, static_cast<std::uint32_t>( at ), collapseSpaces( cl.phrase ), {}, std::move( why ) } );
    }
}

}   // namespace detail

// Markdown: every paragraph's count-introduced lists.
inline std::vector<Site> scanCountDriftMarkdown( std::string_view src, const NameSetTable& sets )
{
    std::vector<Site> out;
    const std::string text = detail::unwrapParagraphs( src );
    detail::judgeCountLists( text, 0, nullptr, sets, out );
    return out;
}

// C++: each run of lines holding string literals, the literals' contents joined (a help paragraph spans many literals;
// a "\n" escape reads as a space), every byte mapped back to its source offset.
inline std::vector<Site> scanCountDriftCpp( std::string_view src, const NameSetTable& sets )
{
    std::vector<Site>              out;
    const std::vector<detail::Tok> toks = detail::lexCpp( src );
    std::string                    text;
    std::vector<std::size_t>       offsetOf;
    std::uint32_t                  lastEnd = 0;
    const auto flush = [ & ]
    {
        if( !text.empty() )
        {
            detail::judgeCountLists( text, 0, &offsetOf, sets, out );
        }
        text.clear();
        offsetOf.clear();
    };
    for( const detail::Tok& t : toks )
    {
        if( t.kind != detail::TokKind::String )
        {
            if( text.empty() )
            {
                continue;   // no paragraph pending: nothing to end, so no newline to look for
            }
            if( !detail::tokIs( src, t, "," ) || std::count( src.begin() + lastEnd, src.begin() + t.begin, '\n' ) > 0 )
            {
                flush();
            }
            lastEnd = t.end;   // the next look starts after this comma: each byte is scanned once
            continue;
        }
        if( !text.empty() && std::count( src.begin() + lastEnd, src.begin() + t.begin, '\n' ) > 1 )
        {
            flush();   // a blank line between two literals ends the paragraph
        }
        for( std::uint32_t b = t.contentBegin; b < t.contentEnd; ++b )
        {
            const bool esc = src[b] == '\\' && b + 1 < t.contentEnd;
            text.push_back( esc && src[b + 1] == 'n' ? ' ' : esc && src[b + 1] == '"' ? '"' : src[b] );
            offsetOf.push_back( b );
            b += esc ? 1 : 0;
        }
        lastEnd = t.end;
    }
    flush();
    return out;
}

using detail::appendNameSetsOfCpp;

}   // namespace rw::defectshape
