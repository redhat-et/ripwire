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
// Floors, stated: a count spelled past twenty (or under two: "one of: a, b" is a choice, not a count), a list split by a
// sentence, a list body over kMaxListBytes, a fenced code block, a closed set held in an enum (CamelCase enumerators) or
// in another language's array, and a count of rows or files (no list) are not checked.

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
    // The set whose members are exactly `items` (sorted, unique), else the first set (in name order) that holds every one
    // of them; nullptr when none does. An exact set wins: a complete list of kSafeModes is not short of kAllModes.
    const NameSet* covering( const std::vector<std::string>& items ) const
    {
        for( const NameSet& s : sets_ )
        {
            if( s.members == items )
            {
                return &s;
            }
        }
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

// The string elements of the brace list whose first token is toks[from] (just past its `{`), into `members`: adjacent
// literals ("read" "only") are ONE element, a comma starts the next. The index of the closing `}`, or npos when the list
// does not close or holds a token that is neither (a nested brace, an identifier: more than names).
inline std::size_t braceStringMembers( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::vector<std::string>& members )
{
    bool afterString = false;
    for( std::size_t q = from; q < toks.size(); ++q )
    {
        if( tokIs( src, toks[q], "}" ) )
        {
            return q;
        }
        if( toks[q].kind == TokKind::String )
        {
            if( afterString )
            {
                members.back() += tokContent( src, toks[q] );
            }
            else
            {
                members.emplace_back( tokContent( src, toks[q] ) );
            }
            afterString = true;
        }
        else if( tokIs( src, toks[q], "," ) )
        {
            afterString = false;
        }
        else
        {
            return std::string::npos;
        }
    }
    return std::string::npos;
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
        // Cursor counts down to 1, index = cursor - 1: `b-- > 0` wrapped the unsigned past token 0 when the declaration
        // opens the file (`auto k = { … }` with no `;`, `{` or `}` before it), which G1's -fsanitize=integer aborts on.
        for( std::size_t cursor = nameAt; !cArray && !stdArray && cursor > 0; --cursor )
        {
            const std::size_t b = cursor - 1;
            if( tokIs( src, toks[b], ";" ) || tokIs( src, toks[b], "{" ) || tokIs( src, toks[b], "}" ) )
            {
                break;
            }
            stdArray = tokIs( src, toks[b], "array" ) && b + 1 < nameAt && tokIs( src, toks[b + 1], "<" );
        }
        if( toks[nameAt].kind != TokKind::Ident || !( cArray || stdArray ) )
        {
            continue;
        }
        NameSet    set{ std::string( tokText( src, toks[nameAt] ) ), {} };
        const bool closed = braceStringMembers( src, toks, k + 2, set.members ) != std::string::npos;
        if( closed && set.members.size() >= 3 && std::all_of( set.members.begin(), set.members.end(), []( const std::string& m ) { return isNameWord( m ); } ) )
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
        if( cw.size() != w.size() )
        {
            continue;
        }
        const auto up    = []( char c ) { return static_cast<char>( c - 'a' + 'A' ); };
        const bool upper = std::equal( w.begin(), w.end(), cw.begin(), [ & ]( char a, char b ) { return a == up( b ); } );
        if( w == cw || upper || ( w[0] == up( cw[0] ) && w.substr( 1 ) == cw.substr( 1 ) ) )   // "three", "Three", "THREE"
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
        // starts_with, not compare( i, 4, … ): libstdc++'s string_view compare subtracts the lengths as unsigned when a short
        // tail ("a", "an") matches the separator's prefix, which G1's -fsanitize=integer aborts on (libc++ does not, so macOS
        // cannot see it, and CMakeLists.txt's libstdc++ ignorelist covers basic_string's twin of the idiom, not string_view's)
        if( body.substr( i ).starts_with( "and " ) || body.substr( i ).starts_with( "or " ) )
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

// A list of names is short; a longer body is prose. The bound also keeps a paragraph of rejected candidates linear: each
// one stops its end scan here instead of at the paragraph's end.
inline constexpr std::size_t kMaxListBytes = 512;

// Does the body end here? A list ends at the ")" that closes a paren form, or at ". ", ";" or the text's end after a colon.
// npos when no end falls within kMaxListBytes of `from`.
inline std::size_t listEnd( std::string_view t, std::size_t from, bool paren ) noexcept
{
    const std::size_t bound = std::min( t.size(), from + kMaxListBytes );
    for( std::size_t i = from; i < bound; ++i )
    {
        const char c = t[i];
        if( paren ? c == ')' : ( c == ';' || c == '\n' || ( c == '.' && ( i + 1 == t.size() || isSpace( t[i + 1] ) ) ) ) )
        {
            return i;
        }
        if( paren && c == '(' )
        {
            const std::size_t close = t.substr( 0, bound ).find( ')', i );   // a gloss inside the list, within the bound
            if( close == std::string_view::npos )
            {
                return std::string_view::npos;
            }
            i = close;
        }
    }
    return paren || bound < t.size() ? std::string_view::npos : t.size();
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

// A Markdown text with every fenced code block (its fence lines and body) blanked to spaces, newlines kept (same length:
// every byte keeps its offset), so an example in a fence is never judged as prose. A fence is three or more backticks or
// tildes after up to three spaces, and it closes at a run of the same character at least as long (CommonMark).
inline std::string maskFencedCode( std::string_view s )
{
    std::string out( s );
    char        fenceChar = 0;
    std::size_t fenceLen  = 0;
    for( std::size_t lineAt = 0; lineAt < out.size(); )
    {
        const std::size_t nl      = out.find( '\n', lineAt );
        const std::size_t lineEnd = nl == std::string::npos ? out.size() : nl;
        std::size_t       p       = lineAt;
        while( p < lineEnd && p - lineAt < 3 && out[p] == ' ' )
        {
            ++p;
        }
        const char  c   = p < lineEnd ? out[p] : '\0';
        std::size_t run = 0;
        while( ( c == '`' || c == '~' ) && p + run < lineEnd && out[p + run] == c )
        {
            ++run;
        }
        const bool closes = fenceChar != 0 && c == fenceChar && run >= fenceLen;
        if( fenceChar == 0 && run >= 3 )
        {
            fenceChar = c;
            fenceLen  = run;
        }
        if( fenceChar != 0 )
        {
            std::fill( out.begin() + static_cast<std::ptrdiff_t>( lineAt ), out.begin() + static_cast<std::ptrdiff_t>( lineEnd ), ' ' );
        }
        if( closes )
        {
            fenceChar = 0;
            fenceLen  = 0;
        }
        lineAt = lineEnd + 1;
    }
    return out;
}

// A Markdown text with each paragraph's soft line breaks turned into spaces (same length: every byte keeps its offset).
// A break stays when the next line opens a block: a blank line, a heading, a list item, a table row, a fence or a quote.
// The marker is read after the line's indentation: an indented continuation line (" beta, gamma.") continues the paragraph.
inline std::string unwrapParagraphs( std::string_view s )
{
    std::string out( s );
    for( std::size_t i = 0; i + 1 < out.size(); ++i )
    {
        if( out[i] != '\n' )
        {
            continue;
        }
        std::size_t at = i + 1;
        while( at < out.size() && ( out[at] == ' ' || out[at] == '\t' ) )
        {
            ++at;
        }
        const char n = at < out.size() ? out[at] : '\n';
        // a fence opens with three backticks or tildes; a line that starts with one backticked name continues the paragraph
        const bool fence = out.compare( at, 3, "```" ) == 0 || out.compare( at, 3, "~~~" ) == 0;
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
    const std::string text = detail::unwrapParagraphs( detail::maskFencedCode( src ) );
    detail::judgeCountLists( text, 0, nullptr, sets, out );
    return out;
}

// C++: each run of adjacent string literals (one string value: a help paragraph spans many literals; a "\n" escape reads as
// a space), the literals' contents joined, every byte mapped back to its source offset. A blank line between two literals
// also ends the run.
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
            flush();   // only adjacent literals are one string value: a comma (the next array element), a paren, any token ends it
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
