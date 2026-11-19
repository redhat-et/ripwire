#pragma once

// defectshape.h — the scanners behind --quality-delta's defect-shape kind: four shapes of a REAL defect that
// review keeps finding by hand and that a deterministic syntactic check finds at write time.
//
//   format-arity    C++: a literal std::format / format_to / format_to_n / print / println, fmt::format /
//                   format_to / format_to_n / print / println, rw::emitTo / rw::formatTo format string whose
//                   replacement fields do not match its arguments. Python: a "literal".format( ... ).
//                   std::format_string rejects too FEW arguments at compile time and accepts too MANY
//                   silently; Python raises on too few at run time and ignores too many.
//   utf8-cut        C++: a byte cap on display text — a cut (resize / erase / substr( 0, N )) plus an appended
//                   ellipsis on the same string, the cut length being the bound of a size comparison on that
//                   string or a cap-named constant — or an ellipsis appended once a single-char push loop
//                   reaches a size cap, with no UTF-8 boundary back-off anywhere in the function.
//   dedup-first     C++: std::unique / std::ranges::unique with a lambda predicate over a type that carries a
//                   severity-like field (a bounded name token sev / severity / priority / prio), where neither
//                   the predicate nor a sort before it in the function reads that field: the FIRST row of a
//                   run survives, not the most severe.
//   vacuous-assert  Bash test scripts: an assertion (grep -q, [ -s ] / [ -n ] / [ = ], cmp / diff, case) that
//                   PASSES on the empty text a crashed run under test leaves — through a capture, a file it
//                   redirected into, a pipe or a wrapper — when nothing reads that run's status and no other
//                   check in the scope fails on the same empty text; and three status shapes beside it: a FAIL
//                   reporter's flag set inside $( ), an rc=$? no test reads, a `| head || fallback`.
//
// Each scanner returns SITES: a facet, the byte the offending text starts at (the caller anchors it on the
// innermost enclosing definition, or on the file), and the offending text NORMALIZED (comments dropped,
// whitespace runs collapsed). The normalized text is the site's identity across a change: --quality-delta
// reports a site only when its text is not among the baseline's sites of that facet, so an untouched, moved
// or renamed defect is not new, and an edited one is.
//
// PRECISION BEFORE RECALL. Every test below answers "not this shape" when it cannot decide — a format held in
// a named constant or a macro, a pack expansion, a named predicate, a producer this file never assigns — and
// each of those is a stated miss, never a finding. The legend names the floors.

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>
#include <charconv>
#include <system_error>

#include <cctype>

#include "infra/Diagnostics.h"
#include "infra/namesplit.h"   // the ONE ASCII identifier-character pair and the quote-pair strip
#include "infra/sortutil.h"    // svLess: the string_view order a comparator lambda may use (portablebuildcheck #6c)
#include "infra/tablelookup.h"  // findByField: an assignment by its node
#include "shstatus.h"          // vacuous-assert: the B43 exit-status matcher (one matcher, common code)

namespace rw::defectshape
{

enum class Facet : std::uint8_t
{
    FormatArity   = 0,
    Utf8Cut       = 1,
    DedupFirst    = 2,
    VacuousAssert = 3,
};
inline constexpr std::size_t kFacetCount = 4;
inline constexpr std::array<std::string_view, kFacetCount> kFacetNames = { "format-arity", "utf8-cut", "dedup-first", "vacuous-assert" };

inline constexpr std::string_view facetName( Facet f ) noexcept
{
    return kFacetNames[ static_cast<std::size_t>( f ) ];
}

// The one facet whose rows gate, on ANY origin: a placeholder/argument mismatch on a literal format has no
// legitimate intent (an argument the format never prints is dropped output; a field with no argument is a
// compile error or a run-time exception), so it is a defect, not debt. The other three are report-only.
inline constexpr bool facetGatesOnAnyOrigin( Facet f ) noexcept
{
    return f == Facet::FormatArity;
}

struct Site
{
    Facet         facet     = Facet::FormatArity;
    std::uint32_t startByte = 0;
    std::string   text;
};

// A definition's byte span [begin, end) in the scanned file — the function bodies the per-function rules
// (utf8-cut, dedup-first) and the Bash scopes (vacuous-assert) read.
struct Span
{
    std::uint32_t begin = 0;
    std::uint32_t end   = 0;
};

namespace detail
{

// identifiers are read ASCII-only, the house rule (namesplit.h): a non-ASCII byte outside a literal becomes a
// one-byte punctuator, which no shape below matches.
using rw::namesplit::isIdentChar;
using rw::namesplit::isIdentStart;

inline bool isDigit( char c ) noexcept
{
    return c >= '0' && c <= '9';
}

inline bool isSpace( char c ) noexcept
{
    return std::isspace( static_cast<unsigned char>( c ) ) != 0;
}

enum class TokKind : std::uint8_t
{
    Ident,
    Number,
    String,
    Char,
    Punct,
};

// One token of a C-family or Python source: [begin, end) in the file. A String token spans its prefix and
// quotes; contentBegin/contentEnd are the bytes between the quotes (between the raw delimiters for a C++ raw
// string, between the triple quotes for a Python long string).
struct Tok
{
    TokKind       kind         = TokKind::Punct;
    std::uint32_t begin        = 0;
    std::uint32_t end          = 0;
    std::uint32_t contentBegin = 0;
    std::uint32_t contentEnd   = 0;
};

inline std::string_view tokText( std::string_view src, const Tok& t ) noexcept
{
    return src.substr( t.begin, t.end - t.begin );
}

inline std::string_view tokContent( std::string_view src, const Tok& t ) noexcept
{
    return src.substr( t.contentBegin, t.contentEnd - t.contentBegin );
}

inline bool tokIs( std::string_view src, const Tok& t, std::string_view s ) noexcept
{
    return tokText( src, t ) == s;
}

// The longest punctuator at `i` from a small fixed table (longest first), else one byte.
inline std::uint32_t punctLen( std::string_view s, std::size_t i ) noexcept
{
    static constexpr std::array<std::string_view, 27> kPunct = {
        "<<=", ">>=", "<=>", "->*", "...", "::", "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||",
        "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "**", ":=",
    };
    for( std::string_view p : kPunct )
    {
        if( s.substr( i, p.size() ) == p )
        {
            return static_cast<std::uint32_t>( p.size() );
        }
    }
    return 1;
}

// Skip a quoted run starting at the opening quote s[i]; returns the index one past the closing quote (or the
// end of the line for an unterminated literal). Backslash escapes the next byte.
inline std::size_t skipQuoted( std::string_view s, std::size_t i, char q ) noexcept
{
    bool escaped = false;
    for( std::size_t j = i + 1; j < s.size(); ++j )
    {
        if( s[j] == '\n' )
        {
            return j;   // unterminated on its line: stop there rather than swallow the file
        }
        if( !escaped && s[j] == q )
        {
            return j + 1;
        }
        escaped = !escaped && s[j] == '\\';
    }
    return s.size();
}

// What lexCpp saw of the preprocessor, for the format-arity skips (rv-cr-qd-kinds-068 F1/F2): the byte each
// live directive starts at, and the names this file #defines (function-like or object-like).
struct CppPreproc
{
    std::vector<std::uint32_t> directives;   // the '#' byte of each directive outside an #if 0 region, ascending
    std::vector<std::string>   macros;       // every name a #define in this file defines; sorted, unique
};

// The identifier at s[i..] after spaces and tabs; advances i past it (empty when there is none).
inline std::string_view ppWord( std::string_view s, std::size_t& i ) noexcept
{
    while( i < s.size() && ( s[i] == ' ' || s[i] == '\t' ) )
    {
        ++i;
    }
    const std::size_t b = i;
    while( i < s.size() && isIdentChar( s[i] ) )
    {
        ++i;
    }
    return s.substr( b, i - b );
}

// `#if 0` (nothing but a comment after the 0): the region up to its own #else / #elif / #endif is dead code,
// never compiled, so nothing in it is judged (F3). Returns the start of the line holding the directive that
// ends the region (the caller lexes that directive as usual), or s.size() when the region never closes.
inline std::size_t skipIfZeroRegion( std::string_view s, std::size_t lineEnd ) noexcept
{
    int depth = 0;
    for( std::size_t ls = lineEnd; ls < s.size(); )
    {
        std::size_t j = ls;
        while( j < s.size() && ( s[j] == ' ' || s[j] == '\t' ) )
        {
            ++j;
        }
        if( j < s.size() && s[j] == '#' )
        {
            ++j;
            const std::string_view w = ppWord( s, j );
            if( w == "if" || w == "ifdef" || w == "ifndef" )
            {
                ++depth;
            }
            else if( w == "endif" || w == "else" || w == "elif" || w == "elifdef" || w == "elifndef" )
            {
                if( depth == 0 )
                {
                    return ls;
                }
                depth -= ( w == "endif" ) ? 1 : 0;
            }
        }
        const std::size_t nl = s.find( '\n', ls );
        ls                   = ( nl == std::string_view::npos ) ? s.size() : nl + 1;
    }
    return s.size();
}

// The directive at s[hash] is `#if 0`, alone on its line but for a comment.
inline bool isIfZero( std::string_view s, std::size_t hash ) noexcept
{
    std::size_t j = hash + 1;
    if( ppWord( s, j ) != "if" )
    {
        return false;
    }
    while( j < s.size() && ( s[j] == ' ' || s[j] == '\t' ) )
    {
        ++j;
    }
    if( j >= s.size() || s[j] != '0' )
    {
        return false;
    }
    ++j;
    while( j < s.size() && ( s[j] == ' ' || s[j] == '\t' || s[j] == '\r' ) )
    {
        ++j;
    }
    return j >= s.size() || s[j] == '\n' || ( s[j] == '/' && j + 1 < s.size() && ( s[j + 1] == '/' || s[j + 1] == '*' ) );
}

// C++ tokens with comments and preprocessor directives dropped. A directive is skipped whole (continuation
// lines included): a format inside a macro body is never judged — its arguments are whatever the expansion
// site passes. An `#if 0` region is dropped whole (F3). `pp`, when given, receives each directive's byte and
// the names this file #defines.
inline std::vector<Tok> lexCpp( std::string_view s, CppPreproc* pp = nullptr )
{
    std::vector<Tok> out;
    std::size_t      i         = 0;
    bool             lineStart = true;
    while( i < s.size() )
    {
        const char c = s[i];
        if( c == '\n' )
        {
            lineStart = true;
            ++i;
            continue;
        }
        if( isSpace( c ) )
        {
            ++i;
            continue;
        }
        if( c == '/' && i + 1 < s.size() && s[i + 1] == '/' )
        {
            while( i < s.size() && s[i] != '\n' )
            {
                ++i;
            }
            continue;
        }
        if( c == '/' && i + 1 < s.size() && s[i + 1] == '*' )
        {
            const std::size_t e = s.find( "*/", i + 2 );
            i                   = ( e == std::string_view::npos ) ? s.size() : e + 2;
            continue;
        }
        if( c == '#' && lineStart )
        {
            const std::size_t hash = i;
            if( pp != nullptr )
            {
                pp->directives.push_back( static_cast<std::uint32_t>( hash ) );
                std::size_t j = hash + 1;
                if( ppWord( s, j ) == "define" )
                {
                    const std::string_view name = ppWord( s, j );
                    if( !name.empty() )
                    {
                        pp->macros.emplace_back( name );
                    }
                }
            }
            // the directive runs to the first newline a backslash does not continue
            while( i < s.size() && !( s[i] == '\n' && ( i == 0 || s[i - 1] != '\\' ) ) )
            {
                ++i;
            }
            if( isIfZero( s, hash ) )
            {
                i = skipIfZeroRegion( s, i < s.size() ? i + 1 : i );
            }
            continue;
        }
        lineStart = false;
        const std::uint32_t b = static_cast<std::uint32_t>( i );
        if( isIdentStart( c ) )
        {
            std::size_t j = i;
            while( j < s.size() && isIdentChar( s[j] ) )
            {
                ++j;
            }
            const std::string_view word = s.substr( i, j - i );
            const bool isStrPrefix = word == "L" || word == "u" || word == "U" || word == "u8" || word == "R" || word == "LR" || word == "uR"
                                  || word == "UR" || word == "u8R";
            if( isStrPrefix && j < s.size() && s[j] == '"' )
            {
                if( word.back() == 'R' )
                {
                    const std::size_t open = s.find( '(', j + 1 );
                    if( open != std::string_view::npos && open - j - 1 <= 16 )
                    {
                        const std::string close = ")" + std::string( s.substr( j + 1, open - j - 1 ) ) + "\"";
                        const std::size_t e     = s.find( close, open + 1 );
                        const std::size_t endAt = ( e == std::string_view::npos ) ? s.size() : e + close.size();
                        const std::size_t cEnd  = ( e == std::string_view::npos ) ? s.size() : e;
                        out.push_back( { TokKind::String, b, static_cast<std::uint32_t>( endAt ), static_cast<std::uint32_t>( open + 1 ), static_cast<std::uint32_t>( cEnd ) } );
                        i = endAt;
                        continue;
                    }
                }
                const std::size_t e = skipQuoted( s, j, '"' );
                out.push_back( { TokKind::String, b, static_cast<std::uint32_t>( e ), static_cast<std::uint32_t>( j + 1 ), static_cast<std::uint32_t>( e > j + 1 ? e - 1 : j + 1 ) } );
                i = e;
                continue;
            }
            if( isStrPrefix && word.back() != 'R' && j < s.size() && s[j] == '\'' )
            {
                const std::size_t e = skipQuoted( s, j, '\'' );
                out.push_back( { TokKind::Char, b, static_cast<std::uint32_t>( e ), b, static_cast<std::uint32_t>( e ) } );
                i = e;
                continue;
            }
            out.push_back( { TokKind::Ident, b, static_cast<std::uint32_t>( j ), b, static_cast<std::uint32_t>( j ) } );
            i = j;
            continue;
        }
        if( isDigit( c ) || ( c == '.' && i + 1 < s.size() && isDigit( s[i + 1] ) ) )
        {
            std::size_t j = i + 1;
            while( j < s.size() && ( isIdentChar( s[j] ) || s[j] == '.' || s[j] == '\''
                                     || ( ( s[j] == '+' || s[j] == '-' ) && ( s[j - 1] == 'e' || s[j - 1] == 'E' || s[j - 1] == 'p' || s[j - 1] == 'P' ) ) ) )
            {
                ++j;
            }
            out.push_back( { TokKind::Number, b, static_cast<std::uint32_t>( j ), b, static_cast<std::uint32_t>( j ) } );
            i = j;
            continue;
        }
        if( c == '"' )
        {
            const std::size_t e = skipQuoted( s, i, '"' );
            out.push_back( { TokKind::String, b, static_cast<std::uint32_t>( e ), b + 1, static_cast<std::uint32_t>( e > i + 1 ? e - 1 : i + 1 ) } );
            i = e;
            continue;
        }
        if( c == '\'' )
        {
            const std::size_t e = skipQuoted( s, i, '\'' );
            out.push_back( { TokKind::Char, b, static_cast<std::uint32_t>( e ), b, static_cast<std::uint32_t>( e ) } );
            i = e;
            continue;
        }
        const std::uint32_t n = punctLen( s, i );
        out.push_back( { TokKind::Punct, b, b + n, b, b + n } );
        i += n;
    }
    if( pp != nullptr )
    {
        std::sort( pp->macros.begin(), pp->macros.end() );
        pp->macros.erase( std::unique( pp->macros.begin(), pp->macros.end() ), pp->macros.end() );
    }
    return out;
}

// One Python string literal: its prefix starts at `b`, its opening quote sits at `q`. Single-quoted literals end at
// their quote or the line's end; a backslash escapes the next byte for the scan (raw literals included).
inline Tok lexPythonString( std::string_view s, std::uint32_t b, std::size_t q )
{
    const char        quote  = s[q];
    const bool        triple = s.substr( q, 3 ) == std::string( 3, quote );
    const std::size_t cb     = q + ( triple ? 3 : 1 );
    std::size_t       j      = cb;
    while( j < s.size() && !( triple ? s.substr( j, 3 ) == std::string( 3, quote ) : ( s[j] == quote || s[j] == '\n' ) ) )
    {
        j += ( s[j] == '\\' ) ? 2 : 1;
    }
    const std::size_t ce  = std::min( j, s.size() );
    const std::size_t end = std::min( s.size(), j + ( j < s.size() && s[j] != '\n' ? ( triple ? 3 : 1 ) : 0 ) );
    return { TokKind::String, b, static_cast<std::uint32_t>( end ), static_cast<std::uint32_t>( cb ), static_cast<std::uint32_t>( ce ) };
}

// Python tokens with comments dropped. A newline inside brackets is not a token (an implicit concat inside
// parentheses spans lines), and neither is a backslash-continued one; a newline that ENDS a logical line (outside
// every bracket) is one "\n" token, so two statements' adjacent literals are never read as one concat
// (X = "a {}" on one line, "{}".format( 1 ) on the next).
inline std::vector<Tok> lexPython( std::string_view s )
{
    std::vector<Tok> out;
    std::size_t      i     = 0;
    int              depth = 0;
    const auto       isPrefixChar = []( char c ) { return c == 'r' || c == 'R' || c == 'b' || c == 'B' || c == 'u' || c == 'U' || c == 'f' || c == 'F'; };
    while( i < s.size() )
    {
        const char c = s[i];
        if( c == '\n' && depth == 0 )
        {
            if( !out.empty() && !tokIs( s, out.back(), "\n" ) )
            {
                const std::uint32_t nl = static_cast<std::uint32_t>( i );
                out.push_back( { TokKind::Punct, nl, nl + 1, nl, nl + 1 } );   // a logical line ends
            }
            ++i;
            continue;
        }
        if( isSpace( c ) || c == '\\' )
        {
            // a backslash-continued newline is skipped with its backslash: one logical line
            i += ( c == '\\' && s.substr( i + 1, 1 ) == "\n" ) ? 2 : ( c == '\\' && s.substr( i + 1, 2 ) == "\r\n" ) ? 3 : 1;
            continue;
        }
        if( c == '#' )
        {
            while( i < s.size() && s[i] != '\n' )
            {
                ++i;
            }
            continue;
        }
        const std::uint32_t b = static_cast<std::uint32_t>( i );
        std::size_t         q = i;
        while( q < s.size() && q - i < 2 && isPrefixChar( s[q] ) )
        {
            ++q;
        }
        if( q < s.size() && ( s[q] == '"' || s[q] == '\'' ) && ( q == i || !isIdentChar( i > 0 ? s[i - 1] : ' ' ) ) )
        {
            out.push_back( lexPythonString( s, b, q ) );
            i = out.back().end;
            continue;
        }
        if( isIdentStart( c ) )
        {
            std::size_t j = i;
            while( j < s.size() && isIdentChar( s[j] ) )
            {
                ++j;
            }
            out.push_back( { TokKind::Ident, b, static_cast<std::uint32_t>( j ), b, static_cast<std::uint32_t>( j ) } );
            i = j;
            continue;
        }
        if( isDigit( c ) )
        {
            std::size_t j = i + 1;
            while( j < s.size() && ( isIdentChar( s[j] ) || s[j] == '.' ) )
            {
                ++j;
            }
            out.push_back( { TokKind::Number, b, static_cast<std::uint32_t>( j ), b, static_cast<std::uint32_t>( j ) } );
            i = j;
            continue;
        }
        const std::uint32_t n = punctLen( s, i );
        out.push_back( { TokKind::Punct, b, b + n, b, b + n } );
        if( n == 1 )
        {
            depth += ( c == '(' || c == '[' || c == '{' ) ? 1 : 0;
            depth -= ( ( c == ')' || c == ']' || c == '}' ) && depth > 0 ) ? 1 : 0;
        }
        i += n;
    }
    return out;
}

// The tokens [from, to] joined by single spaces: a site's identity text, immune to reformatting.
inline std::string joinTokens( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t to )
{
    std::string out;
    for( std::size_t k = from; k <= to && k < toks.size(); ++k )
    {
        if( !out.empty() )
        {
            out.push_back( ' ' );
        }
        out.append( tokText( src, toks[k] ) );
    }
    return out;
}

// The index of the bracket that closes the one at `open` (round, square or curly; the others nest inside),
// or toks.size() when unbalanced.
inline std::size_t matchClose( std::string_view src, const std::vector<Tok>& toks, std::size_t open ) noexcept
{
    int depth = 0;
    for( std::size_t k = open; k < toks.size(); ++k )
    {
        if( toks[k].kind != TokKind::Punct )
        {
            continue;
        }
        const char c = src[ toks[k].begin ];
        if( toks[k].end - toks[k].begin != 1 )
        {
            continue;
        }
        if( c == '(' || c == '[' || c == '{' )
        {
            ++depth;
        }
        else if( c == ')' || c == ']' || c == '}' )
        {
            --depth;
            if( depth == 0 )
            {
                return k;
            }
            if( depth < 0 )
            {
                return toks.size();
            }
        }
    }
    return toks.size();
}

// A call's arguments: token index ranges [first, last] between the parentheses at `open` and `close`, split at
// top-level commas. An empty argument (a trailing comma) is kept as first > last.
struct ArgRange
{
    std::size_t first = 0;
    std::size_t last  = 0;
    bool        empty() const noexcept { return first > last; }
};

inline std::vector<ArgRange> splitArgs( std::string_view src, const std::vector<Tok>& toks, std::size_t open, std::size_t close )
{
    std::vector<ArgRange> out;
    if( close == open + 1 )
    {
        return out;
    }
    int         depth = 0;
    std::size_t start = open + 1;
    for( std::size_t k = open + 1; k < close; ++k )
    {
        if( toks[k].kind != TokKind::Punct || toks[k].end - toks[k].begin != 1 )
        {
            continue;
        }
        const char c = src[ toks[k].begin ];
        if( c == '(' || c == '[' || c == '{' )
        {
            ++depth;
        }
        else if( c == ')' || c == ']' || c == '}' )
        {
            --depth;
        }
        else if( c == ',' && depth == 0 )
        {
            out.push_back( { start, k - 1 } );
            start = k + 1;
        }
    }
    out.push_back( { start, close - 1 } );
    return out;
}

// ─── replacement-field grammars ─────────────────────────────────────────────────────────────────────────

// What a format string asks of its argument list. ok=false: the string is not one this check can judge
// (mixed automatic and manual numbering, a lone brace, a named field where the family has none) — skipped.
struct FieldUse
{
    bool                       ok         = false;
    std::uint32_t              autoFields = 0;
    std::vector<std::uint32_t> indices;   // manual positional indices, one per use
    std::vector<std::string>   names;     // Python named fields
};

// The arg-id at s[i..]: digits → a manual index, an identifier → a name, empty → automatic. Advances i.
// Returns false on anything else.
inline bool readArgId( std::string_view s, std::size_t& i, FieldUse& use, bool allowNames, bool pythonFieldName )
{
    const std::size_t b = i;
    if( i < s.size() && isDigit( s[i] ) )
    {
        std::uint32_t v = 0;
        while( i < s.size() && isDigit( s[i] ) )
        {
            if( v > 100000 )
            {
                return false;   // not a real argument index — refuse rather than wrap
            }
            v = v * 10 + static_cast<std::uint32_t>( s[i] - '0' );
            ++i;
        }
        use.indices.push_back( v );
    }
    else if( i < s.size() && isIdentStart( s[i] ) )
    {
        if( !allowNames )
        {
            return false;
        }
        while( i < s.size() && isIdentChar( s[i] ) )
        {
            ++i;
        }
        use.names.emplace_back( s.substr( b, i - b ) );
    }
    else
    {
        ++use.autoFields;
    }
    if( pythonFieldName )
    {
        // attribute / index accessors after the arg name: .attr and [key], neither consumes an argument
        while( i < s.size() && ( s[i] == '.' || s[i] == '[' ) )
        {
            if( s[i] == '[' )
            {
                const std::size_t e = s.find( ']', i );
                if( e == std::string_view::npos )
                {
                    return false;
                }
                i = e + 1;
            }
            else
            {
                ++i;
                while( i < s.size() && isIdentChar( s[i] ) )
                {
                    ++i;
                }
            }
        }
    }
    return true;
}

// The std::format / fmt / Python str.format replacement-field grammar, over the literal's content as written
// (Python's \N{...} is skipped; a literal with an escape that spells a brace never reaches here — see
// escapeSpellsBrace). `python` selects the Python field-name and conversion syntax.
inline FieldUse parseFields( std::string_view s, bool python )
{
    FieldUse use;
    std::size_t i = 0;
    while( i < s.size() )
    {
        const char c = s[i];
        if( python && c == '\\' && i + 1 < s.size() && s[i + 1] == 'N' && i + 2 < s.size() && s[i + 2] == '{' )
        {
            const std::size_t e = s.find( '}', i + 3 );
            if( e == std::string_view::npos )
            {
                return use;
            }
            i = e + 1;
            continue;
        }
        if( c == '}' )
        {
            if( i + 1 < s.size() && s[i + 1] == '}' )
            {
                i += 2;
                continue;
            }
            return use;   // a lone '}' — not a format this check can judge
        }
        if( c != '{' )
        {
            ++i;
            continue;
        }
        if( i + 1 < s.size() && s[i + 1] == '{' )
        {
            i += 2;
            continue;
        }
        ++i;
        if( !readArgId( s, i, use, python, python ) )
        {
            return use;
        }
        if( python && i < s.size() && s[i] == '!' )
        {
            i += 2;   // !r / !s / !a
        }
        if( i < s.size() && s[i] == ':' )
        {
            ++i;
            // the spec: nested replacement fields (dynamic width / precision) each consume an argument
            while( i < s.size() && s[i] != '}' )
            {
                if( s[i] == '{' )
                {
                    ++i;
                    if( !readArgId( s, i, use, python, python ) || i >= s.size() || s[i] != '}' )
                    {
                        return use;
                    }
                }
                ++i;
            }
        }
        if( i >= s.size() || s[i] != '}' )
        {
            return use;
        }
        ++i;
    }
    use.ok = !( use.autoFields > 0 && !use.indices.empty() );   // mixed numbering is an error this check does not judge
    return use;
}

// True when `use` against `positional` arguments (and, for Python, the keyword names `kw`) is a mismatch.
inline bool fieldsMismatch( const FieldUse& use, std::uint32_t positional, const std::vector<std::string>& kw )
{
    bool bad = false;
    if( !use.indices.empty() )
    {
        std::vector<char> seen( positional, 0 );
        for( std::uint32_t ix : use.indices )
        {
            if( ix >= positional )
            {
                bad = true;   // a field with no argument
            }
            else
            {
                seen[ix] = 1;
            }
        }
        bad = bad || std::find( seen.begin(), seen.end(), char( 0 ) ) != seen.end();   // an argument no field prints
    }
    else
    {
        bad = use.autoFields != positional;
    }
    for( const std::string& n : use.names )
    {
        bad = bad || std::find( kw.begin(), kw.end(), n ) == kw.end();
    }
    for( const std::string& k : kw )
    {
        bad = bad || std::find( use.names.begin(), use.names.end(), k ) == use.names.end();
    }
    return bad;
}

// ─── format-arity, C++ ──────────────────────────────────────────────────────────────────────────────────

// The format family: (namespace, name) → the index the format argument sits at, and whether a leading
// stdout / stderr argument shifts it (the print overloads that take a FILE*). A leading std::locale(...)
// argument shifts every family by one. Nothing else moves the index: a non-literal at that position is
// skipped, never searched past (the literal there may be an ARGUMENT, as in std::format( kFmt, "{}" )).
struct FormatFamily
{
    std::string_view ns;
    std::string_view name;
    std::uint8_t     fmtIndex;
    bool             streamShift;
};
inline constexpr std::array<FormatFamily, 12> kFormatFamilies = { {
    { "std", "format", 0, false },      { "std", "format_to", 1, false }, { "std", "format_to_n", 2, false },
    { "std", "print", 0, true },        { "std", "println", 0, true },    { "fmt", "format", 0, false },
    { "fmt", "format_to", 1, false },   { "fmt", "format_to_n", 2, false }, { "fmt", "print", 0, true },
    { "fmt", "println", 0, true },      { "rw", "emitTo", 1, false },     { "rw", "formatTo", 2, false },
} };

inline const FormatFamily* formatFamilyAt( std::string_view src, const std::vector<Tok>& toks, std::size_t k ) noexcept
{
    if( k < 2 || toks[k].kind != TokKind::Ident || !tokIs( src, toks[k - 1], "::" ) || toks[k - 2].kind != TokKind::Ident )
    {
        return nullptr;
    }
    if( k >= 3 && ( tokIs( src, toks[k - 3], "." ) || tokIs( src, toks[k - 3], "->" ) ) )
    {
        return nullptr;
    }
    if( k >= 4 && tokIs( src, toks[k - 3], "::" ) && toks[k - 4].kind == TokKind::Ident && !tokIs( src, toks[k - 4], "return" )
        && !tokIs( src, toks[k - 4], "co_return" ) && !tokIs( src, toks[k - 4], "throw" ) )
    {
        return nullptr;   // other::std::format names some other namespace's std, not the family; ::std::format still is
    }
    const std::string_view ns   = tokText( src, toks[k - 2] );
    const std::string_view name = tokText( src, toks[k] );
    for( const FormatFamily& f : kFormatFamilies )
    {
        if( f.ns == ns && f.name == name )
        {
            return &f;
        }
    }
    return nullptr;
}

inline bool isAllCapsIdent( std::string_view w ) noexcept
{
    if( w.size() < 2 || !( w[0] >= 'A' && w[0] <= 'Z' ) )
    {
        return false;
    }
    return std::all_of( w.begin(), w.end(), []( char c ) { return ( c >= 'A' && c <= 'Z' ) || isDigit( c ) || c == '_'; } );
}

inline bool inSortedNames( const std::vector<std::string>* names, std::string_view w )
{
    if( names == nullptr )
    {
        return false;
    }
    const auto it = std::lower_bound( names->begin(), names->end(), w, []( const std::string& a, std::string_view b ) { return rw::sortutil::svLess( a, b ); } );
    return it != names->end() && *it == w;
}

// The macro names an argument is judged against (F1): this file's #defines (CppPreproc::macros) and the
// tree's — every macro definition the index holds in a C-family file (the C++ grammar indexes function-like
// macros; the C grammar both kinds). Either list may be absent.
struct MacroNames
{
    const std::vector<std::string>* file = nullptr;
    const std::vector<std::string>* tree = nullptr;
};

// F1: an identifier outside every bracket of the argument [first, last] that may be a macro expanding to an
// argument LIST — one this file #defines (function-like or object-like), a FUNCTION-LIKE macro the tree defines (the
// tree list is SymKind::Macro, which holds function-like macros only), or an ALL_CAPS one followed by '(' (SRC_LOC(),
// VEC3( v )) whose definition is not visible. A member or qualified name (x.f(, ns::F() is never a macro. Floor (stated
// on the legend and in the CHANGELOG): a lower-case object-like macro defined only in ANOTHER file is not seen.
inline bool argMayBeMacroList( std::string_view src, const std::vector<Tok>& toks, const ArgRange& a, const MacroNames& macros )
{
    int depth = 0;
    for( std::size_t k = a.first; k <= a.last; ++k )
    {
        const Tok& t = toks[k];
        if( t.kind == TokKind::Punct && t.end - t.begin == 1 )
        {
            const char c = src[ t.begin ];
            depth += ( c == '(' || c == '[' || c == '{' ) ? 1 : ( c == ')' || c == ']' || c == '}' ) ? -1 : 0;
        }
        const bool qualified = k > a.first && ( tokIs( src, toks[k - 1], "::" ) || tokIs( src, toks[k - 1], "." ) || tokIs( src, toks[k - 1], "->" ) );
        if( depth != 0 || t.kind != TokKind::Ident || qualified )
        {
            continue;
        }
        const std::string_view w      = tokText( src, t );
        const bool             called = k < a.last && tokIs( src, toks[k + 1], "(" );
        if( inSortedNames( macros.file, w ) || inSortedNames( macros.tree, w ) || ( called && isAllCapsIdent( w ) ) )
        {
            return true;
        }
    }
    return false;
}

// An argument whose count is unknowable here: a pack expansion, __VA_ARGS__, an all-caps identifier alone (an
// object-like macro may expand to a comma list), more '<' than '>' (a template argument list the comma split
// may have cut: std::pair<int, int>{} splits as "std::pair<int" and "int>{}"), or an identifier that may be a
// macro expanding to an argument list (argMayBeMacroList, F1). A lone '>' is a comparison (n > 0) and does not
// make the count unknowable.
inline bool argCountUnknowable( std::string_view src, const std::vector<Tok>& toks, const ArgRange& a, const MacroNames& macros )
{
    if( a.empty() )
    {
        return true;
    }
    if( tokIs( src, toks[a.last], "..." ) )
    {
        return true;
    }
    if( a.first == a.last && toks[a.first].kind == TokKind::Ident && isAllCapsIdent( tokText( src, toks[a.first] ) ) )
    {
        return true;
    }
    int angle = 0;
    for( std::size_t k = a.first; k <= a.last; ++k )
    {
        if( tokIs( src, toks[k], "__VA_ARGS__" ) )
        {
            return true;
        }
        angle += tokIs( src, toks[k], "<" ) ? 1 : 0;
        angle -= tokIs( src, toks[k], ">" ) ? 1 : 0;
    }
    return angle > 0 || argMayBeMacroList( src, toks, a, macros );
}

// True when a backslash escape in `content` (an ordinary, non-raw literal) spells a brace: \x7b, \173, \u007d,
// \N{LEFT CURLY BRACKET}, a C++23 delimited \x{..} / \o{..} / \u{..} (never decoded, assumed to). The field
// grammar reads a literal as WRITTEN, so such a literal's fields are not knowable here — the call is skipped.
// Python's \xHH takes exactly two digits; C++'s takes every hex digit that follows.
inline bool escapeSpellsBrace( std::string_view content, bool python ) noexcept
{
    const auto hexVal = []( char c ) -> int
    {
        if( c >= '0' && c <= '9' ) { return c - '0'; }
        if( c >= 'a' && c <= 'f' ) { return c - 'a' + 10; }
        if( c >= 'A' && c <= 'F' ) { return c - 'A' + 10; }
        return -1;
    };
    for( std::size_t i = 0; i + 1 < content.size(); ++i )
    {
        if( content[i] != '\\' )
        {
            continue;
        }
        const char e = content[i + 1];
        std::uint32_t v      = 0x110000;   // "no code point" unless an escape below decodes one
        std::size_t   j      = i + 2;
        std::size_t   maxLen = 0;
        int           base   = 16;
        if( ( e == 'x' || e == 'o' || e == 'u' || e == 'N' ) && j < content.size() && content[j] == '{' )
        {
            if( e != 'N' || !python )
            {
                return true;   // a delimited escape (C++23 \x{..}, \o{..}, \u{..}, \N{..})
            }
            const std::size_t close = content.find( '}', j );
            std::string        name( content.substr( j + 1, close == std::string_view::npos ? 0 : close - j - 1 ) );
            std::ranges::transform( name, name.begin(), []( char ch ) { return static_cast<char>( std::toupper( static_cast<unsigned char>( ch ) ) ); } );
            if( name == "LEFT CURLY BRACKET" || name == "RIGHT CURLY BRACKET" )
            {
                return true;
            }
            ++i;
            continue;
        }
        if( e == 'x' )
        {
            maxLen = python ? 2 : 8;
        }
        else if( e == 'u' )
        {
            maxLen = 4;
        }
        else if( e == 'U' )
        {
            maxLen = 8;
        }
        else if( e >= '0' && e <= '7' )
        {
            j      = i + 1;
            maxLen = 3;
            base   = 8;
        }
        else
        {
            ++i;   // \\, \", \n …: one escaped byte, never a brace
            continue;
        }
        std::uint32_t acc = 0;
        std::size_t   n   = 0;
        while( j < content.size() && n < maxLen )
        {
            const int d = hexVal( content[j] );
            if( d < 0 || d >= base )
            {
                break;
            }
            acc = acc * static_cast<std::uint32_t>( base ) + static_cast<std::uint32_t>( d );
            ++j;
            ++n;
        }
        if( n > 0 )
        {
            v = acc;
        }
        if( v == 0x7B || v == 0x7D )
        {
            return true;
        }
        i = j - 1;
    }
    return false;
}

// A C++ string token is raw when its prefix (the bytes before the quote) holds an R.
inline bool isRawCppLiteral( std::string_view src, const Tok& t ) noexcept
{
    return src.substr( t.begin, t.contentBegin - t.begin ).find( 'R' ) != std::string_view::npos;
}

// The argument's tokens are one or more adjacent string literals → their concatenated content; else empty
// optional-by-flag (a named constant, a macro piece such as PRIu64, a runtime_format wrapper).
inline bool literalContent( std::string_view src, const std::vector<Tok>& toks, const ArgRange& a, std::string& out )
{
    out.clear();
    if( a.empty() )
    {
        return false;
    }
    for( std::size_t k = a.first; k <= a.last; ++k )
    {
        if( toks[k].kind != TokKind::String )
        {
            return false;
        }
        if( !isRawCppLiteral( src, toks[k] ) && escapeSpellsBrace( tokContent( src, toks[k] ), false ) )
        {
            return false;   // "\x7b\x7d" is "{}": a field the as-written grammar cannot see — skipped, never guessed
        }
        out.append( tokContent( src, toks[k] ) );
    }
    return true;
}

// F2: a preprocessor directive between the call's parentheses — the tokens of every #if arm are concatenated
// here, so the argument count is no arm's count. Skipped.
inline bool callHoldsDirective( const std::vector<std::uint32_t>& directives, std::uint32_t open, std::uint32_t close ) noexcept
{
    const auto it = std::lower_bound( directives.begin(), directives.end(), open );
    return it != directives.end() && *it < close;
}

inline void scanFormatArityCpp( std::string_view src, const std::vector<Tok>& toks, const CppPreproc& pp, const std::vector<std::string>* treeMacros,
                                std::vector<Site>& out )
{
    std::string      fmt;
    const MacroNames macros{ &pp.macros, treeMacros };
    for( std::size_t k = 2; k + 1 < toks.size(); ++k )
    {
        const FormatFamily* fam = formatFamilyAt( src, toks, k );
        if( fam == nullptr || !tokIs( src, toks[k + 1], "(" ) )
        {
            continue;
        }
        const std::size_t close = matchClose( src, toks, k + 1 );
        if( close >= toks.size() || callHoldsDirective( pp.directives, toks[k + 1].begin, toks[close].begin ) )
        {
            continue;
        }
        const std::vector<ArgRange> args = splitArgs( src, toks, k + 1, close );
        std::size_t                 fi   = fam->fmtIndex;
        if( fi < args.size() && fam->streamShift && args[fi].first == args[fi].last
            && ( tokIs( src, toks[ args[fi].first ], "stdout" ) || tokIs( src, toks[ args[fi].first ], "stderr" ) ) )
        {
            ++fi;
        }
        if( fi < args.size() && !args[fi].empty() && args[fi].first + 3 <= args[fi].last && tokIs( src, toks[ args[fi].first ], "std" )
            && tokIs( src, toks[ args[fi].first + 1 ], "::" ) && tokIs( src, toks[ args[fi].first + 2 ], "locale" ) )
        {
            ++fi;
        }
        if( fi >= args.size() || !literalContent( src, toks, args[fi], fmt ) )
        {
            continue;
        }
        // every argument, the ones before the format too: a macro there may shift the format's index
        bool unknowable = false;
        for( std::size_t a = 0; a < args.size(); ++a )
        {
            unknowable = unknowable || ( a != fi && argCountUnknowable( src, toks, args[a], macros ) );
        }
        const FieldUse use = parseFields( fmt, false );
        if( unknowable || !use.ok )
        {
            continue;
        }
        const std::uint32_t positional = static_cast<std::uint32_t>( args.size() - fi - 1 );
        if( fieldsMismatch( use, positional, {} ) )
        {
            out.push_back( { Facet::FormatArity, toks[k - 2].begin, joinTokens( src, toks, k - 2, close ) } );
        }
    }
}

// ─── format-arity, Python "literal".format( ... ) ───────────────────────────────────────────────────────

inline bool pyStringPrefixOk( std::string_view src, const Tok& t ) noexcept
{
    for( std::uint32_t p = t.begin; p < t.contentBegin; ++p )
    {
        const char c = src[p];
        if( c == 'f' || c == 'F' || c == 'b' || c == 'B' )
        {
            return false;   // an f-string has no argument list; bytes have no .format
        }
    }
    return true;
}

inline bool pyStringIsRaw( std::string_view src, const Tok& t ) noexcept
{
    const std::string_view prefix = src.substr( t.begin, t.contentBegin - t.begin );
    return prefix.find( 'r' ) != std::string_view::npos || prefix.find( 'R' ) != std::string_view::npos;
}

// A keyword before '(' makes the parentheses a grouping (return ( "a" "b" ).format(…)), not a call.
inline bool isPythonKeyword( std::string_view w ) noexcept
{
    static constexpr std::array<std::string_view, 15> kKw = { "return", "yield", "in", "not", "and", "or", "if", "else", "elif", "while", "assert",
                                                              "await", "lambda", "is", "for" };
    return std::find( kKw.begin(), kKw.end(), w ) != kKw.end();
}

inline void scanFormatArityPython( std::string_view src, const std::vector<Tok>& toks, std::vector<Site>& out )
{
    std::string fmt;
    for( std::size_t k = 1; k + 2 < toks.size(); ++k )
    {
        if( !tokIs( src, toks[k], "." ) || !tokIs( src, toks[k + 1], "format" ) || !tokIs( src, toks[k + 2], "(" ) )
        {
            continue;
        }
        // the receiver: adjacent literals right before the dot, or a parenthesised group holding only literals
        std::size_t firstLit = k;
        std::size_t lastLit  = k - 1;
        std::size_t siteFrom = k;
        if( toks[k - 1].kind == TokKind::String )
        {
            firstLit = k - 1;
            while( firstLit > 0 && toks[firstLit - 1].kind == TokKind::String )
            {
                --firstLit;
            }
            siteFrom = firstLit;
        }
        else if( tokIs( src, toks[k - 1], ")" ) )
        {
            std::size_t open = k - 1;
            while( open > 0 && toks[open - 1].kind == TokKind::String )
            {
                --open;
            }
            if( open == 0 || !tokIs( src, toks[open - 1], "(" ) || open > k - 2 )
            {
                continue;
            }
            const std::size_t paren = open - 1;
            if( paren > 0 && ( ( toks[paren - 1].kind == TokKind::Ident && !isPythonKeyword( tokText( src, toks[paren - 1] ) ) )
                               || tokIs( src, toks[paren - 1], ")" ) || tokIs( src, toks[paren - 1], "]" ) ) )
            {
                continue;   // a call's parentheses, not a grouping
            }
            firstLit = open;
            lastLit  = k - 2;
            siteFrom = paren;
        }
        if( firstLit > lastLit )
        {
            continue;
        }
        fmt.clear();
        bool prefixOk = true;
        for( std::size_t p = firstLit; p <= lastLit; ++p )
        {
            prefixOk = prefixOk && pyStringPrefixOk( src, toks[p] );
            const std::string_view content = tokContent( src, toks[p] );
            if( pyStringIsRaw( src, toks[p] ) )
            {
                // a raw literal has no escapes: r"\N{a}" is a backslash, an N and the field {a} — the \N{...} skip in
                // parseFields must not see a backslash here
                const std::size_t from = fmt.size();
                fmt.append( content );
                std::replace( fmt.begin() + static_cast<std::ptrdiff_t>( from ), fmt.end(), '\\', ' ' );
            }
            else
            {
                prefixOk = prefixOk && !escapeSpellsBrace( content, true );   // "\x7b\x7d" is "{}": not judged
                fmt.append( content );
            }
        }
        const std::size_t close = matchClose( src, toks, k + 2 );
        if( !prefixOk || close >= toks.size() )
        {
            continue;
        }
        std::vector<ArgRange> args = splitArgs( src, toks, k + 2, close );
        if( !args.empty() && args.back().empty() )
        {
            args.pop_back();   // a trailing comma
        }
        std::uint32_t            positional = 0;
        std::vector<std::string> kw;
        bool                     unknowable = false;
        for( const ArgRange& a : args )
        {
            if( a.empty() || tokIs( src, toks[a.first], "*" ) || tokIs( src, toks[a.first], "**" ) )
            {
                unknowable = true;
                break;
            }
            if( a.first < a.last && toks[a.first].kind == TokKind::Ident && tokIs( src, toks[a.first + 1], "=" ) )
            {
                kw.emplace_back( tokText( src, toks[a.first] ) );
            }
            else
            {
                ++positional;
            }
        }
        const FieldUse use = parseFields( fmt, true );
        if( unknowable || !use.ok )
        {
            continue;
        }
        if( fieldsMismatch( use, positional, kw ) )
        {
            out.push_back( { Facet::FormatArity, toks[siteFrom].begin, joinTokens( src, toks, siteFrom, close ) } );
        }
    }
}

// ─── utf8-cut, C++ ──────────────────────────────────────────────────────────────────────────────────────

// An ellipsis literal: an ordinary or u8 literal whose content, spaces trimmed, is "..." or U+2026 (written
// raw or as \xE2\x80\xA6). A wide / u16 / u32 literal holds code units or points: a cut cannot split one.
inline bool isEllipsisLiteral( std::string_view src, const Tok& t ) noexcept
{
    if( t.kind != TokKind::String )
    {
        return false;
    }
    const std::string_view pre = src.substr( t.begin, t.contentBegin - t.begin );
    if( pre != "\"" && pre != "u8\"" )
    {
        return false;
    }
    std::string_view c = tokContent( src, t );
    while( !c.empty() && c.front() == ' ' )
    {
        c.remove_prefix( 1 );
    }
    while( !c.empty() && c.back() == ' ' )
    {
        c.remove_suffix( 1 );
    }
    return c == "..." || c == "\xE2\x80\xA6" || c == "\\xE2\\x80\\xA6" || c == "\\xe2\\x80\\xa6" || c == "\\u2026";
}

// A UTF-8 boundary back-off or a utf8-aware helper anywhere in the function exempts it (a precision choice:
// the guard is not proven to cover the cut): the 0xC0 / 0x80 continuation mask, or a call whose name has a
// utf8 token.
inline bool hasUtf8Guard( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t to ) noexcept
{
    bool c0 = false;
    bool c80 = false;
    for( std::size_t k = from; k < to; ++k )
    {
        const std::string_view w = tokText( src, toks[k] );
        if( toks[k].kind == TokKind::Number )
        {
            c0  = c0 || w == "0xC0" || w == "0xc0" || w == "0xC0u" || w == "0xc0u" || w == "0xC0U";
            c80 = c80 || w == "0x80" || w == "0x80u" || w == "0x80U";
        }
        if( toks[k].kind == TokKind::Ident && ( w.find( "utf8" ) != std::string_view::npos || w.find( "Utf8" ) != std::string_view::npos
                                                || w.find( "UTF8" ) != std::string_view::npos ) )
        {
            return true;
        }
    }
    return c0 && c80;
}

// V . size ( ) / V . length ( ) at k: the receiver name, or empty.
inline std::string_view sizeCallReceiver( std::string_view src, const std::vector<Tok>& toks, std::size_t k ) noexcept
{
    if( k + 4 < toks.size() && toks[k].kind == TokKind::Ident && tokIs( src, toks[k + 1], "." )
        && ( tokIs( src, toks[k + 2], "size" ) || tokIs( src, toks[k + 2], "length" ) ) && tokIs( src, toks[k + 3], "(" ) && tokIs( src, toks[k + 4], ")" ) )
    {
        return tokText( src, toks[k] );
    }
    return {};
}

inline bool isCompareOp( std::string_view src, const Tok& t ) noexcept
{
    static constexpr std::array<std::string_view, 5> kCompare = { ">", ">=", "<", "<=", "==" };
    return std::find( kCompare.begin(), kCompare.end(), tokText( src, t ) ) != kCompare.end();
}

// Name tokens of an identifier (camelCase and snake_case boundaries), lower-cased.
inline std::vector<std::string> nameTokens( std::string_view w )
{
    std::vector<std::string> out;
    std::string              cur;
    for( std::size_t i = 0; i < w.size(); ++i )
    {
        const char c = w[i];
        if( c == '_' || isDigit( c ) )
        {
            if( !cur.empty() )
            {
                out.push_back( cur );
                cur.clear();
            }
            continue;
        }
        const bool upper = c >= 'A' && c <= 'Z';
        if( upper && !cur.empty() && !( i > 0 && w[i - 1] >= 'A' && w[i - 1] <= 'Z' ) )
        {
            out.push_back( cur );
            cur.clear();
        }
        cur.push_back( upper ? static_cast<char>( c - 'A' + 'a' ) : c );
    }
    if( !cur.empty() )
    {
        out.push_back( cur );
    }
    return out;
}

inline bool isCapName( std::string_view w )
{
    for( const std::string& t : nameTokens( w ) )
    {
        if( t == "cap" || t == "max" || t == "limit" || t == "budget" )
        {
            return true;
        }
    }
    return false;
}

// Is the length text `n` (the tokens of a cut's length argument) the bound of a size comparison on `v`
// within [from, to), or a single cap-named identifier?
inline bool lengthIsSizeBound( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t to, std::string_view v,
                               const std::string& n )
{
    for( std::size_t k = from; k < to; ++k )
    {
        if( sizeCallReceiver( src, toks, k ) != v )
        {
            continue;
        }
        // V.size() OP M / M OP V.size(), where the cut length N is M, or M less the ellipsis width (1 to 3 bytes:
        // resize( 117 ) under size() > 120 leaves room for "...")
        const auto boundMatches = [ & ]( const Tok& m )
        {
            const std::string_view mt = tokText( src, m );
            if( mt == n || n == std::string( mt ) + " - 1" || n == std::string( mt ) + " - 2" || n == std::string( mt ) + " - 3" )
            {
                return true;
            }
            long nv = 0;
            long mv = 0;
            const auto plain = []( std::string_view d, long& out )
            {
                const auto r = std::from_chars( d.data(), d.data() + d.size(), out );
                return !d.empty() && d.size() <= 9 && r.ec == std::errc() && r.ptr == d.data() + d.size();
            };
            if( m.kind != TokKind::Number || !plain( n, nv ) || !plain( mt, mv ) )
            {
                return false;   // not two plain decimal lengths
            }
            return mv >= nv && mv - nv <= 3;
        };
        if( k + 6 < to && isCompareOp( src, toks[k + 5] ) && boundMatches( toks[k + 6] ) )
        {
            return true;
        }
        if( k >= 2 && isCompareOp( src, toks[k - 1] ) && boundMatches( toks[k - 2] ) )
        {
            return true;
        }
    }
    return n.find( ' ' ) == std::string::npos && isCapName( n );
}

// Does `V += ELL` / `V.append( ELL )` occur in [from, to)? Returns the index of the statement's first token,
// or `to`.
inline std::size_t ellipsisAppendOn( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t to, std::string_view v ) noexcept
{
    for( std::size_t k = from; k + 2 < to; ++k )
    {
        if( toks[k].kind != TokKind::Ident || tokText( src, toks[k] ) != v || ( k > 0 && ( tokIs( src, toks[k - 1], "." ) || tokIs( src, toks[k - 1], "->" ) ) ) )
        {
            continue;
        }
        if( tokIs( src, toks[k + 1], "+=" ) && isEllipsisLiteral( src, toks[k + 2] ) )
        {
            return k;
        }
        if( k + 4 < to && tokIs( src, toks[k + 1], "." ) && tokIs( src, toks[k + 2], "append" ) && tokIs( src, toks[k + 3], "(" ) && isEllipsisLiteral( src, toks[k + 4] ) )
        {
            return k;
        }
    }
    return to;
}

// The single-argument text of the call whose '(' is at `open`, or empty when it has more than one argument.
inline std::string singleArgText( std::string_view src, const std::vector<Tok>& toks, std::size_t open )
{
    const std::size_t close = matchClose( src, toks, open );
    if( close >= toks.size() )
    {
        return {};
    }
    const std::vector<ArgRange> args = splitArgs( src, toks, open, close );
    if( args.size() != 1 || args[0].empty() )
    {
        return {};
    }
    return joinTokens( src, toks, args[0].first, args[0].last );
}

// substr( 0 , N ) at the '(' `open`: N's text, or empty.
inline std::string substrZeroLength( std::string_view src, const std::vector<Tok>& toks, std::size_t open )
{
    const std::size_t close = matchClose( src, toks, open );
    if( close >= toks.size() )
    {
        return {};
    }
    const std::vector<ArgRange> args = splitArgs( src, toks, open, close );
    if( args.size() != 2 || args[0].empty() || args[1].empty() || args[0].first != args[0].last || !tokIs( src, toks[ args[0].first ], "0" ) )
    {
        return {};
    }
    return joinTokens( src, toks, args[1].first, args[1].last );
}

inline void scanUtf8CutFunction( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t to, std::vector<Site>& out )
{
    if( hasUtf8Guard( src, toks, from, to ) )
    {
        return;
    }
    for( std::size_t k = from; k + 3 < to; ++k )
    {
        if( toks[k].kind != TokKind::Ident || !tokIs( src, toks[k + 1], "." ) || ( k > 0 && ( tokIs( src, toks[k - 1], "." ) || tokIs( src, toks[k - 1], "->" ) ) ) )
        {
            continue;
        }
        const std::string_view v      = tokText( src, toks[k] );
        const std::string_view method = tokText( src, toks[k + 2] );
        if( !tokIs( src, toks[k + 3], "(" ) )
        {
            continue;
        }
        const std::size_t close = matchClose( src, toks, k + 3 );
        if( close >= to )
        {
            continue;
        }
        // (1) V.resize( N ) / V.erase( N ), then V += ELL / V.append( ELL ) later in the function
        if( method == "resize" || method == "erase" )
        {
            const std::string n = singleArgText( src, toks, k + 3 );
            if( n.empty() || !lengthIsSizeBound( src, toks, from, to, v, n ) )
            {
                continue;
            }
            const std::size_t ell = ellipsisAppendOn( src, toks, close + 1, to, v );
            if( ell < to )
            {
                const std::size_t ellEnd = std::min( to - 1, ell + 2 + ( tokIs( src, toks[ell + 1], "." ) ? 3 : 0 ) );
                out.push_back( { Facet::Utf8Cut, toks[ell].begin, joinTokens( src, toks, k, close ) + " ; " + joinTokens( src, toks, ell, ellEnd ) } );
            }
            continue;
        }
        if( method != "substr" )
        {
            continue;
        }
        // (2) V.substr( 0, N ) + ELL, as an expression
        const std::string n = substrZeroLength( src, toks, k + 3 );
        if( n.empty() || !lengthIsSizeBound( src, toks, from, to, v, n ) )
        {
            continue;
        }
        if( close + 2 < to && tokIs( src, toks[close + 1], "+" ) && isEllipsisLiteral( src, toks[close + 2] ) )
        {
            out.push_back( { Facet::Utf8Cut, toks[k].begin, joinTokens( src, toks, k, close + 2 ) } );
            continue;
        }
        // (3) W = V.substr( 0, N ) (or a declaration of W), then W += ELL later
        if( k >= 2 && tokIs( src, toks[k - 1], "=" ) && toks[k - 2].kind == TokKind::Ident )
        {
            const std::string_view w   = tokText( src, toks[k - 2] );
            const std::size_t      ell = ellipsisAppendOn( src, toks, close + 1, to, w );
            if( ell < to )
            {
                const std::size_t ellEnd = std::min( to - 1, ell + 2 + ( tokIs( src, toks[ell + 1], "." ) ? 3 : 0 ) );
                out.push_back( { Facet::Utf8Cut, toks[ell].begin, joinTokens( src, toks, k - 2, close ) + " ; " + joinTokens( src, toks, ell, ellEnd ) } );
            }
        }
    }
    // (4) a single-char push loop: V.push_back( c ) somewhere, and `if( V.size() OP CAP ) { … V += ELL … }`
    for( std::size_t k = from; k + 2 < to; ++k )
    {
        if( !tokIs( src, toks[k], "if" ) || !tokIs( src, toks[k + 1], "(" ) )
        {
            continue;
        }
        const std::string_view v = sizeCallReceiver( src, toks, k + 2 );
        if( v.empty() || k + 7 >= to || !isCompareOp( src, toks[k + 7] ) )
        {
            continue;
        }
        const std::size_t condClose = matchClose( src, toks, k + 1 );
        if( condClose + 1 >= to || !tokIs( src, toks[condClose + 1], "{" ) )
        {
            continue;
        }
        const std::size_t blockClose = matchClose( src, toks, condClose + 1 );
        const std::size_t ell        = ellipsisAppendOn( src, toks, condClose + 2, std::min( blockClose, to ), v );
        if( blockClose >= to || ell >= blockClose )
        {
            continue;
        }
        bool pushes = false;
        for( std::size_t p = from; p + 3 < to && !pushes; ++p )
        {
            pushes = tokText( src, toks[p] ) == v && tokIs( src, toks[p + 1], "." ) && tokIs( src, toks[p + 2], "push_back" ) && tokIs( src, toks[p + 3], "(" );
        }
        if( pushes )
        {
            const std::size_t ellEnd = std::min( to - 1, ell + 2 + ( tokIs( src, toks[ell + 1], "." ) ? 3 : 0 ) );
            out.push_back( { Facet::Utf8Cut, toks[ell].begin, joinTokens( src, toks, k, condClose ) + " { " + joinTokens( src, toks, ell, ellEnd ) } );
        }
    }
}

// ─── dedup-first, C++ ───────────────────────────────────────────────────────────────────────────────────

inline bool isSeverityName( std::string_view field )
{
    for( const std::string& t : nameTokens( field ) )
    {
        if( t == "sev" || t == "severity" || t == "priority" || t == "prio" )
        {
            return true;
        }
    }
    return false;
}

// The member fields named in `struct T { … }` / `class T { … }` bodies in this file: the severity-like ones.
// A member is an identifier followed by '=', ';', '{' or '[' at the body's top level.
inline std::vector<std::string> severityFieldsOf( std::string_view src, const std::vector<Tok>& toks, std::string_view type )
{
    std::vector<std::string> out;
    for( std::size_t k = 0; k + 2 < toks.size(); ++k )
    {
        if( !( tokIs( src, toks[k], "struct" ) || tokIs( src, toks[k], "class" ) ) || tokText( src, toks[k + 1] ) != type )
        {
            continue;
        }
        std::size_t open = k + 2;
        while( open < toks.size() && !tokIs( src, toks[open], "{" ) && !tokIs( src, toks[open], ";" ) )
        {
            ++open;
        }
        if( open >= toks.size() || !tokIs( src, toks[open], "{" ) )
        {
            continue;
        }
        const std::size_t close = matchClose( src, toks, open );
        int               depth = 0;
        for( std::size_t m = open + 1; m + 1 < close && close < toks.size(); ++m )
        {
            if( tokIs( src, toks[m], "{" ) || tokIs( src, toks[m], "(" ) )
            {
                ++depth;
            }
            else if( tokIs( src, toks[m], "}" ) || tokIs( src, toks[m], ")" ) )
            {
                --depth;
            }
            else if( depth == 0 && toks[m].kind == TokKind::Ident
                     && ( tokIs( src, toks[m + 1], "=" ) || tokIs( src, toks[m + 1], ";" ) || tokIs( src, toks[m + 1], "{" ) || tokIs( src, toks[m + 1], "[" ) )
                     && isSeverityName( tokText( src, toks[m] ) ) )
            {
                out.emplace_back( tokText( src, toks[m] ) );
            }
        }
    }
    return out;
}

// Does any `. FIELD` / `-> FIELD` for a field in `fields` occur in [from, to]?
inline bool readsAnyField( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t to, const std::vector<std::string>& fields )
{
    for( std::size_t k = from + 1; k <= to && k < toks.size(); ++k )
    {
        if( ( tokIs( src, toks[k - 1], "." ) || tokIs( src, toks[k - 1], "->" ) )
            && std::find( fields.begin(), fields.end(), tokText( src, toks[k] ) ) != fields.end() )
        {
            return true;
        }
    }
    return false;
}

// The element type of a lambda `[ … ]( const T& a, … )` starting at `lb`: T, or empty (auto, a builtin, not a
// lambda). Returns the index of the lambda's closing '}' in `bodyEnd`.
inline std::string_view lambdaElementType( std::string_view src, const std::vector<Tok>& toks, std::size_t lb, std::size_t& bodyEnd )
{
    bodyEnd = toks.size();
    if( lb >= toks.size() || !tokIs( src, toks[lb], "[" ) )
    {
        return {};
    }
    const std::size_t capClose = matchClose( src, toks, lb );
    if( capClose + 1 >= toks.size() || !tokIs( src, toks[capClose + 1], "(" ) )
    {
        return {};
    }
    const std::size_t parClose = matchClose( src, toks, capClose + 1 );
    std::size_t       body     = parClose + 1;
    while( body < toks.size() && !tokIs( src, toks[body], "{" ) && !tokIs( src, toks[body], ";" ) && !tokIs( src, toks[body], ")" ) )
    {
        ++body;
    }
    if( body >= toks.size() || !tokIs( src, toks[body], "{" ) )
    {
        return {};
    }
    bodyEnd = matchClose( src, toks, body );
    // the first parameter: the identifier right before '&' / '*' / the parameter name
    std::string_view type;
    for( std::size_t k = capClose + 2; k < parClose && !tokIs( src, toks[k], "," ); ++k )
    {
        if( toks[k].kind != TokKind::Ident )
        {
            continue;
        }
        const std::string_view w = tokText( src, toks[k] );
        if( w == "const" || w == "volatile" || w == "std" || w == "struct" )
        {
            continue;
        }
        if( type.empty() )
        {
            type = w;
        }
        else if( k + 1 < parClose && tokIs( src, toks[k - 1], "::" ) )
        {
            type = w;   // a qualified type: keep its last segment
        }
    }
    if( type == "auto" || type == "int" || type == "long" || type == "unsigned" || type == "char" || type == "double" || type == "float" || type == "bool"
        || type == "size_t" )
    {
        return {};
    }
    return type;
}

inline void scanDedupFirstFunction( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t to, std::vector<Site>& out )
{
    for( std::size_t k = from + 2; k + 1 < to; ++k )
    {
        if( !tokIs( src, toks[k], "unique" ) || !tokIs( src, toks[k - 1], "::" ) || !tokIs( src, toks[k + 1], "(" ) )
        {
            continue;
        }
        const bool ranges = tokIs( src, toks[k - 2], "ranges" );
        if( !ranges && !tokIs( src, toks[k - 2], "std" ) )
        {
            continue;
        }
        const std::size_t close = matchClose( src, toks, k + 1 );
        if( close >= to )
        {
            continue;
        }
        const std::vector<ArgRange> args   = splitArgs( src, toks, k + 1, close );
        const std::size_t           predAt = ranges ? ( args.size() == 2 ? 1 : 2 ) : 2;
        if( predAt >= args.size() || args[predAt].empty() )
        {
            continue;   // no predicate: whole values compare
        }
        std::size_t            lambdaEnd = 0;
        const std::string_view type      = lambdaElementType( src, toks, args[predAt].first, lambdaEnd );
        if( type.empty() || lambdaEnd > close )
        {
            continue;   // a named predicate, an auto / builtin element: skipped, never guessed
        }
        const std::vector<std::string> sev = severityFieldsOf( src, toks, type );
        if( sev.empty() || readsAnyField( src, toks, args[predAt].first, lambdaEnd, sev ) )
        {
            continue;
        }
        // a sort before the unique, in this function, whose arguments read the severity field (either direction)
        bool sorted = false;
        for( std::size_t s = from; s < k && !sorted; ++s )
        {
            const std::string_view w = tokText( src, toks[s] );
            if( ( w == "sort" || w == "stable_sort" ) && s + 1 < k && tokIs( src, toks[s + 1], "(" ) )
            {
                const std::size_t sc = matchClose( src, toks, s + 1 );
                sorted = sc < k && readsAnyField( src, toks, s + 1, sc, sev );
            }
        }
        if( !sorted )
        {
            out.push_back( { Facet::DedupFirst, toks[k - 2].begin, joinTokens( src, toks, k - ( ranges ? 4 : 2 ), close ) } );
        }
    }
}

// ─── vacuous-assert, Bash test scripts ──────────────────────────────────────────────────────────────────

// The site a finding names: the physical line holding byte `pos`, with the backslash-continued lines around it
// joined and a trailing comment dropped (a # after a blank, outside quotes). Its text is the site's identity.
struct ShLine
{
    std::uint32_t startByte = 0;
    std::string   text;
};

inline ShLine shSiteLine( std::string_view s, std::uint32_t pos )
{
    pos                 = std::min<std::uint32_t>( pos, static_cast<std::uint32_t>( s.size() ) );
    const auto lineOpen = [ & ]( std::size_t at )   // the first byte of the physical line holding `at`
    {
        const std::size_t nl = at == 0 ? std::string_view::npos : s.rfind( '\n', at - 1 );
        return nl == std::string_view::npos ? std::size_t{ 0 } : nl + 1;
    };
    const auto continued = [ & ]( std::size_t lineEnd ) { return lineEnd > 0 && s[lineEnd - 1] == '\\'; };
    std::size_t b = lineOpen( pos );
    while( b >= 2 && continued( b - 1 ) )
    {
        b = lineOpen( b - 1 );
    }
    std::size_t e = s.find( '\n', pos );
    while( e != std::string_view::npos && continued( e ) )
    {
        e = s.find( '\n', e + 1 );
    }
    const std::string_view raw = s.substr( b, ( e == std::string_view::npos ? s.size() : e ) - b );
    std::string            text;
    char                   quote = 0;
    for( std::size_t i = 0; i < raw.size(); ++i )
    {
        const char c = raw[i];
        if( quote == 0 && c == '#' && ( i == 0 || isSpace( raw[i - 1] ) ) )
        {
            const std::size_t nl = raw.find( '\n', i );
            if( nl == std::string_view::npos )
            {
                break;
            }
            i = nl - 1;   // a comment on a continued line ends at its newline
            continue;
        }
        if( c == '\\' && quote != '\'' && i + 1 < raw.size() )
        {
            if( raw[i + 1] == '\n' )
            {
                text.push_back( ' ' );
                ++i;
                continue;
            }
            text.push_back( c );
            text.push_back( raw[++i] );
            continue;
        }
        if( ( c == '"' || c == '\'' ) && ( quote == 0 || quote == c ) )
        {
            quote = quote == 0 ? c : 0;
        }
        text.push_back( c );
    }
    return { static_cast<std::uint32_t>( b ), std::move( text ) };
}

inline std::string collapseSpaces( std::string_view s )
{
    std::string out;
    bool        space = false;
    for( char c : s )
    {
        if( isSpace( c ) )
        {
            space = !out.empty();
            continue;
        }
        if( space )
        {
            out.push_back( ' ' );
            space = false;
        }
        out.push_back( c );
    }
    return out;
}

// ── the status-dataflow walk: every assertion names the commands whose output it reads ──────────────────────────────
// The script is parsed once by the B43 matcher's port (shstatus.h), which also says what every command's exit status
// reaches. The MODEL: a run under test that fails prints nothing (or is cut short), so the text it feeds is EMPTY. A
// producer whose status nothing reads (shstatus: unchecked) may fail silently; one whose status is read (|| no, if,
// rc=$? compared, set -e) reports its own failure and never fails silently. For a failure set S of silent producers:
//   * a judgment (an and-or list ending in reporters, an if chain, a case) DEFINITELY PASSES when every branch it can
//     take with S's outputs empty is a PASS reporter: an absence grep, [ -s F ] / [ -n "$V" ] read as failure, a parity
//     ([ "$A" = "$B" ], cmp, diff) of two empty texts;
//   * another judgment in the same scope (the function body, or the top level) GUARDS S when it definitely FAILS under
//     S (a presence check, a positive grep on the same text, an enclosing if whose condition the empty text falsifies).
// A judgment that definitely passes under some S no guard catches is a vacuous-assert site. Text flows through captures
// (V="$( … )"), files a command redirected into (> F, a function that writes "$TMP/$1.out" called with mod1), pipes,
// filters that keep an empty input empty (grep -o, sed, awk without END, tr, cut, head, tail, sort, uniq, an inline
// python3 -c), a function that only filters its argument, and a wrapper (shstatus: a function whose status IS a run's).
// Three status shapes need no assertion at all: a FAIL reporter that sets the gate's failure flag, called inside $( )
// whose status nothing reads (the flag dies with the subshell); an rc captured (rc=$?) whose value no test reads before
// it is overwritten (B43's H2, per capture: printing it in a FAIL message is not a test); and a `|| fallback` after a
// pipeline whose last stage always succeeds (head, sort, tr, …), which reads that stage's status, never the run's.
namespace va
{

namespace sh = rw::shstatus;
using sh::kNone;

enum class Rep : std::uint8_t
{
    None,
    Pass,
    Fail,
};

enum class Tri : std::uint8_t
{
    F,
    T,
    U,
};

inline Tri triNot( Tri v ) noexcept
{
    return v == Tri::T ? Tri::F : ( v == Tri::F ? Tri::T : Tri::U );
}
inline Tri triAnd( Tri a, Tri b ) noexcept
{
    if( a == Tri::F || b == Tri::F )
    {
        return Tri::F;
    }
    return ( a == Tri::T && b == Tri::T ) ? Tri::T : Tri::U;
}
inline Tri triOr( Tri a, Tri b ) noexcept
{
    if( a == Tri::T || b == Tri::T )
    {
        return Tri::T;
    }
    return ( a == Tri::F && b == Tri::F ) ? Tri::F : Tri::U;
}

// Where a text comes from: the silent-failable producers it is made of. EMPTY under S when nothing else feeds it
// (`unknown` false), some producer feeds it, and every producer is in S.
struct Prov
{
    bool                       unknown = false;
    std::vector<std::uint32_t> leaves;

    void add( const Prov& o )
    {
        unknown = unknown || o.unknown;
        leaves.insert( leaves.end(), o.leaves.begin(), o.leaves.end() );
    }
    static Prov opaque()
    {
        Prov p;
        p.unknown = true;
        return p;
    }
    bool emptyUnder( const std::vector<std::uint32_t>& s ) const
    {
        return !unknown && !leaves.empty()
            && std::all_of( leaves.begin(), leaves.end(), [ & ]( std::uint32_t l ) { return std::find( s.begin(), s.end(), l ) != s.end(); } );
    }
};

struct Env   // a function's positional arguments and its stdin, bound at a call site
{
    std::vector<Prov> args;      // $1..
    bool              bound = false;
    bool              hasIn = false;
    Prov              in;        // the caller's stdin: its pipe, its <<< or < redirect
};

struct ReachStep   // an enclosing if / case, and the body index a statement sits in
{
    std::uint32_t node;
    std::size_t   branch;
};

struct Assign
{
    std::string            name;
    std::uint32_t          node   = kNone;
    std::int32_t           word   = -1;    // index in node.words / -1 - index in node.assigns; INT32_MIN = an opaque binding (read, for)
    std::uint32_t          pos    = 0;
    std::uint32_t          scope  = kNone;
    bool                   cond   = false;   // right of && / || in its statement: it may not run
    std::vector<ReachStep> reach;            // the if / case branches it sits in
};

struct Writer
{
    std::string   target;       // normalized
    std::uint32_t scope = kNone;
    std::uint32_t pos   = 0;
    std::uint32_t node  = kNone;  // the writing command (Simple or compound)
    const sh::Item* item  = nullptr;   // its pipeline, when it is a stage of one
    std::size_t     stage = 0;
};

struct Judgment
{
    enum class Kind : std::uint8_t
    {
        AndOr,
        If,
        Case,
    };
    Kind                 kind  = Kind::AndOr;
    const sh::AndOr*     ao    = nullptr;
    std::uint32_t        node  = kNone;   // If / Case node
    std::uint32_t        pos   = 0;
    std::uint32_t        scope = kNone;
    using Reach = ReachStep;
    std::vector<Reach>   reach;
};

inline std::string normTarget( std::string_view w )
{
    std::string u = sh::detail::unq( w );
    std::string out;
    for( std::size_t i = 0; i < u.size(); ++i )
    {
        if( u[i] == '$' && i + 1 < u.size() && u[i + 1] == '{' )
        {
            const std::size_t close = u.find( '}', i + 2 );
            const std::string inner = close == std::string::npos ? std::string() : u.substr( i + 2, close - i - 2 );
            if( !inner.empty() && std::all_of( inner.begin(), inner.end(), []( char c ) { return isIdentChar( c ); } ) )
            {
                out += "$" + inner;
                i = close;
                continue;
            }
        }
        out.push_back( u[i] );
    }
    return out;
}

inline bool isStdoutRedir( const sh::Redir& r )
{
    if( r.op == ">" || r.op == ">>" || r.op == ">|" )
    {
        return r.fd == -1 || r.fd == 1;
    }
    if( r.op == "&>" || r.op == "&>>" )
    {
        return true;
    }
    return r.op == ">&" && ( r.fd == -1 || r.fd == 1 ) && r.target != "1";
}

class Script
{
public:
    Script( std::string_view src, const sh::Tree& t, const sh::Analysis& a ) : src_( src ), t_( t ), a_( a )
    {
        scope_.assign( t.nodes.size(), kNone );
        visit( t.top, kNone, {} );
        classifyReporters();
        proveRunWrappers();
    }

    std::vector<Site> sites() const;

private:
    // the five shapes; each appends the start byte of every site it finds
    void vacuousJudgmentSites( std::vector<std::uint32_t>& at ) const;
    void lostReporterSites( std::vector<std::uint32_t>& at ) const;
    void unreadRcSites( std::vector<std::uint32_t>& at ) const;
    void unreadRcFileSites( std::vector<std::uint32_t>& at ) const;
    void deadFallbackSites( std::vector<std::uint32_t>& at ) const;

private:
    std::string_view                              src_;
    const sh::Tree&                               t_;
    const sh::Analysis&                           a_;
    std::vector<std::uint32_t>                    scope_;      // per node: the enclosing function node, kNone at top level
    std::vector<std::pair<std::string, std::uint32_t>> funcs_;  // name -> Func node (the last definition)
    std::vector<std::pair<std::string, Rep>>      reporters_;
    std::vector<std::string>                      flagReporters_;   // FAIL reporters that set a failure flag
    std::vector<std::string>                      runWrappers_;     // sorted: functions whose status is a run's
    std::vector<Assign>                           assigns_;
    std::vector<Writer>                           writers_;
    std::vector<Judgment>                         judgments_;
    std::vector<std::uint32_t>                    captures_;   // assign-only `X=$?` simple commands
    std::vector<std::pair<std::uint32_t, std::uint32_t>> subCalls_;   // ( host simple, a call inside one of its $( ) )
    std::vector<const sh::AndOr*>                 andOrs_;     // every statement, for the fallback shape
    std::vector<std::uint32_t>                    andOrScope_;
    mutable bool                                  inReachCheck_ = false;   // provVar's reach check does not nest

    const sh::Node& node( std::uint32_t n ) const
    {
        return t_.nodes[n];
    }
    std::size_t cmdIdx( const sh::Node& n ) const
    {
        return n.kind == sh::NodeKind::Simple ? sh::detail::cmdWordIndex( n ) : std::string::npos;
    }
    std::string cmdWord( std::uint32_t n ) const
    {
        const sh::Node&   nd = node( n );
        const std::size_t k  = cmdIdx( nd );
        return k == std::string::npos ? std::string() : sh::detail::unq( nd.words[k].text );
    }
    std::uint32_t funcNode( std::string_view name ) const
    {
        for( auto it = funcs_.rbegin(); it != funcs_.rend(); ++it )
        {
            if( it->first == name )
            {
                return it->second;
            }
        }
        return kNone;
    }
    const sh::List* funcBody( std::uint32_t f ) const
    {
        if( f == kNone || node( f ).bodies.empty() || node( f ).bodies[0] == kNone )
        {
            return nullptr;
        }
        return &t_.lists[node( f ).bodies[0]];
    }

    // ── the index: scopes, functions, assignments, writers, judgments ──────────────────────────────────────────────
    void visit( std::uint32_t list, std::uint32_t scope, std::vector<Judgment::Reach> reach )
    {
        if( list == kNone )
        {
            return;
        }
        const sh::List& l = t_.lists[list];
        for( std::size_t k = 0; k < l.size(); ++k )
        {
            const sh::AndOr& ao = l[k];
            andOrs_.push_back( &ao );
            andOrScope_.push_back( scope );
            if( ao.size() > 1 )
            {
                judgments_.push_back( { Judgment::Kind::AndOr, &ao, kNone, posOf( ao ), scope, reach } );
            }
            for( const sh::Item& it : ao )
            {
                for( std::size_t j = 0; j < it.cmds.size(); ++j )
                {
                    visitCmd( it.cmds[j], scope, reach, &it, j, &it != &ao.front() );
                }
            }
        }
    }
    std::uint32_t posOf( const sh::AndOr& ao ) const
    {
        return ao.empty() || ao[0].cmds.empty() ? 0 : node( ao[0].cmds[0] ).pos;
    }
    // a simple command's bindings (assignments, local / declare / export, read / mapfile), its rc captures (X=$?,
    // local X=$?) and the calls inside its $( )
    void indexSimple( std::uint32_t c, const sh::Node& n, std::uint32_t scope, const std::vector<Judgment::Reach>& reach, bool cond )
    {
        for( std::size_t a = 0; a < n.assigns.size(); ++a )
        {
            const std::string& tx = n.assigns[a].text;
            assigns_.push_back( { tx.substr( 0, tx.find_first_of( "+=[" ) ), c, -1 - static_cast<std::int32_t>( a ), n.pos, scope, cond, reach } );
        }
        const std::string cw = n.words.empty() ? std::string() : sh::detail::unq( n.words[0].text );
        if( cw == "local" || cw == "declare" || cw == "export" || cw == "readonly" || cw == "typeset" )
        {
            for( std::size_t w = 1; w < n.words.size(); ++w )
            {
                const std::string& tx = n.words[w].text;
                if( !tx.empty() && tx[0] == '-' )
                {
                    continue;
                }
                const std::size_t eq = tx.find( '=' );
                if( eq != std::string::npos )
                {
                    assigns_.push_back( { tx.substr( 0, eq ), c, static_cast<std::int32_t>( w ), n.pos, scope, cond, reach } );
                }
            }
        }
        else if( cw == "read" || cw == "mapfile" || cw == "readarray" )
        {
            for( std::size_t w = 1; w < n.words.size(); ++w )
            {
                if( !n.words[w].text.empty() && n.words[w].text[0] != '-' )
                {
                    assigns_.push_back( { n.words[w].text, c, INT32_MIN, n.pos, scope, cond, reach } );
                }
            }
        }
        if( n.words.empty() && n.assigns.size() == 1 )
        {
            const std::string& tx = n.assigns[0].text;
            const std::size_t  eq = tx.find( '=' );
            const std::string  v  = sh::detail::unq( tx.substr( eq + 1 ) );
            if( v == "$?" || v == "${?}" )
            {
                captures_.push_back( c );
            }
        }
        else if( n.words.size() == 2 && cw == "local" )
        {
            const std::string& tx = n.words[1].text;
            const std::size_t  eq = tx.find( '=' );
            if( eq != std::string::npos )
            {
                const std::string v = sh::detail::unq( tx.substr( eq + 1 ) );
                if( v == "$?" || v == "${?}" )
                {
                    captures_.push_back( c );
                }
            }
        }
        for( const std::vector<sh::Word>* ws : { &n.assigns, &n.words } )
        {
            for( const sh::Word& w : *ws )
            {
                for( const sh::Sub& s : w.subs )
                {
                    visitSub( s.list, scope, c );
                }
            }
        }
    }
    void visitCmd( std::uint32_t c, std::uint32_t scope, const std::vector<Judgment::Reach>& reach, const sh::Item* item, std::size_t stage, bool cond )
    {
        scope_[c]         = scope;
        const sh::Node& n = node( c );
        for( const sh::Redir& r : n.fredirs )
        {
            if( isStdoutRedir( r ) && !r.target.empty() && r.target != "/dev/null" && r.target[0] != '&'
                && !std::all_of( r.target.begin(), r.target.end(), []( char ch ) { return ch >= '0' && ch <= '9'; } ) )
            {
                writers_.push_back( { normTarget( r.target ), scope, n.pos, c, item, stage } );
            }
        }
        switch( n.kind )
        {
            case sh::NodeKind::Simple:
            {
                indexSimple( c, n, scope, reach, cond );
                break;
            }
            case sh::NodeKind::Func:
            {
                funcs_.emplace_back( n.name, c );
                for( std::uint32_t b : n.bodies )
                {
                    visit( b, c, {} );
                }
                break;
            }
            case sh::NodeKind::If:
            {
                judgments_.push_back( { Judgment::Kind::If, nullptr, c, n.pos, scope, reach } );
                for( std::uint32_t cl : n.conds )
                {
                    visit( cl, scope, reach );
                }
                for( std::size_t b = 0; b < n.bodies.size(); ++b )
                {
                    std::vector<Judgment::Reach> r = reach;
                    r.push_back( { c, b } );
                    visit( n.bodies[b], scope, r );
                }
                break;
            }
            case sh::NodeKind::Case:
            {
                judgments_.push_back( { Judgment::Kind::Case, nullptr, c, n.pos, scope, reach } );
                for( std::size_t b = 0; b < n.bodies.size(); ++b )
                {
                    std::vector<Judgment::Reach> r = reach;
                    r.push_back( { c, b } );
                    visit( n.bodies[b], scope, r );
                }
                break;
            }
            case sh::NodeKind::For:
            {
                if( !n.name.empty() )
                {
                    assigns_.push_back( { n.name, c, INT32_MIN, n.pos, scope, cond, reach } );
                }
                for( std::uint32_t b : n.bodies )
                {
                    visit( b, scope, reach );
                }
                break;
            }
            default:
            {
                for( std::uint32_t cl : n.conds )
                {
                    visit( cl, scope, reach );
                }
                for( std::uint32_t b : n.bodies )
                {
                    visit( b, scope, reach );
                }
                break;
            }
        }
    }
    // inside a $( ): only calls are indexed (the lost-reporter shape); assertions there are not judged
    void visitSub( std::uint32_t list, std::uint32_t scope, std::uint32_t host )
    {
        if( list == kNone )
        {
            return;
        }
        for( const sh::AndOr& ao : t_.lists[list] )
        {
            andOrs_.push_back( &ao );
            andOrScope_.push_back( scope );
            for( const sh::Item& it : ao )
            {
                for( std::uint32_t c : it.cmds )
                {
                    scope_[c] = scope;
                    const sh::Node& n = node( c );
                    if( n.kind == sh::NodeKind::Simple )
                    {
                        subCalls_.emplace_back( host, c );
                        for( const std::vector<sh::Word>* ws : { &n.assigns, &n.words } )
                        {
                            for( const sh::Word& w : *ws )
                            {
                                for( const sh::Sub& s : w.subs )
                                {
                                    visitSub( s.list, scope, host );
                                }
                            }
                        }
                    }
                    else
                    {
                        for( std::uint32_t cl : n.conds )
                        {
                            visitSub( cl, scope, host );
                        }
                        for( std::uint32_t b : n.bodies )
                        {
                            visitSub( b, scope, host );
                        }
                    }
                }
            }
        }
    }

    // ── reporters ──────────────────────────────────────────────────────────────────────────────────────────────────
    static Rep repByName( std::string_view w )
    {
        for( const std::string& tk : nameTokens( w ) )
        {
            if( tk == "ok" || tk == "pass" || tk == "passed" || tk == "good" )
            {
                return Rep::Pass;
            }
            if( tk == "no" || tk == "fail" || tk == "failed" || tk == "bad" || tk == "die" )
            {
                return Rep::Fail;
            }
        }
        return Rep::None;
    }
    static bool isCheckName( std::string_view w )
    {
        for( const std::string& tk : nameTokens( w ) )
        {
            if( tk == "check" || tk == "assert" || tk == "expect" || tk == "want" || tk == "has" || tk == "match" || tk == "verify" || tk == "require" )
            {
                return true;
            }
        }
        return false;
    }
    static bool isFlagName( std::string_view lhs )
    {
        for( const std::string& tk : nameTokens( lhs ) )
        {
            if( tk == "fail" || tk == "failed" || tk == "failures" || tk == "failure" || tk == "fails" || tk == "status" || tk == "errors" || tk == "bad" )
            {
                return true;
            }
        }
        return false;
    }
    void classifyReporters()
    {
        for( const auto& [ name, f ] : funcs_ )
        {
            // a body that reports BOTH ways is a check of its own (check(){ if …; then echo PASS; else echo FAIL; fi; }),
            // not a reporter; a name that says it checks is one too (assert_no_match, expect_no_rows)
            const std::string body    = node( f ).bodies.empty() ? std::string() : sh::detail::listText( t_, node( f ).bodies[0] );
            const bool        sayFail = body.find( "FAIL" ) != std::string::npos || body.find( "fail=1" ) != std::string::npos;
            const bool        sayPass = body.find( "PASS" ) != std::string::npos;
            // (the name decides first: ok(){ printf PASS || { fail=1; printf FAIL; }; } is the PASS reporter, G1's contract)
            Rep r = isCheckName( name ) ? Rep::None : repByName( name );
            if( r == Rep::None && !( sayFail && sayPass ) && !isCheckName( name ) )
            {
                r = sayFail ? Rep::Fail : ( sayPass ? Rep::Pass : Rep::None );
            }
            reporters_.emplace_back( name, r );
            if( r == Rep::Fail && setsFlag( f ) )
            {
                flagReporters_.push_back( name );
            }
        }
    }
    bool setsFlag( std::uint32_t f ) const
    {
        bool hit = false;
        forEachSimple( node( f ).bodies.empty() ? kNone : node( f ).bodies[0], [ & ]( std::uint32_t c )
                       {
                           const sh::Node& n = node( c );
                           for( const sh::Word& a : n.assigns )
                           {
                               const std::string lhs = a.text.substr( 0, a.text.find_first_of( "+=[" ) );
                               hit = hit || isFlagName( lhs );
                           }
                           for( const sh::Word& w : n.words )
                           {
                               hit = hit || ( w.text.rfind( "((", 0 ) == 0 && isFlagName( w.text.substr( 2 ) ) );
                           }
                       } );
        return hit;
    }
    template <class F>
    void forEachSimple( std::uint32_t list, F&& f ) const
    {
        if( list == kNone )
        {
            return;
        }
        for( const sh::AndOr& ao : t_.lists[list] )
        {
            for( const sh::Item& it : ao )
            {
                for( std::uint32_t c : it.cmds )
                {
                    const sh::Node& n = node( c );
                    if( n.kind == sh::NodeKind::Simple )
                    {
                        f( c );
                    }
                    else if( n.kind != sh::NodeKind::Func )
                    {
                        for( std::uint32_t cl : n.conds )
                        {
                            forEachSimple( cl, f );
                        }
                        for( std::uint32_t b : n.bodies )
                        {
                            forEachSimple( b, f );
                        }
                    }
                }
            }
        }
    }
    // The reporter a command is: a reporter function by name, an echo / printf of PASS / FAIL, exit / return non-zero, a
    // failure-flag assignment; a { …; } group by its first command.
    Rep repOfCmd( std::uint32_t c ) const
    {
        const sh::Node& n = node( c );
        if( n.kind == sh::NodeKind::Group || n.kind == sh::NodeKind::Subshell )
        {
            return n.bodies.empty() ? Rep::None : repOfList( n.bodies[0] );
        }
        if( n.kind != sh::NodeKind::Simple )
        {
            return Rep::None;
        }
        if( n.words.empty() )
        {
            for( const sh::Word& a : n.assigns )
            {
                const std::size_t eq  = a.text.find( '=' );
                const std::string lhs = a.text.substr( 0, a.text.find_first_of( "+=[" ) );
                if( isFlagName( lhs ) && eq != std::string::npos && sh::detail::unq( a.text.substr( eq + 1 ) ) != "0" )
                {
                    return Rep::Fail;
                }
            }
            return Rep::None;
        }
        const std::string w = sh::detail::unq( n.words[0].text );
        for( const auto& [ name, r ] : reporters_ )
        {
            if( name == w && r != Rep::None )
            {
                return r;
            }
        }
        if( w == "echo" || w == "printf" )
        {
            for( std::size_t a = 1; a < n.words.size(); ++a )
            {
                std::string_view u = n.words[a].text;
                u                  = rw::namesplit::stripQuotePair( u );
                while( !u.empty() && ( u.front() == ' ' || u.front() == '[' ) )
                {
                    u.remove_prefix( 1 );
                }
                if( u.starts_with( "FAIL" ) )
                {
                    return Rep::Fail;
                }
                if( u.starts_with( "PASS" ) || u.starts_with( "ok " ) )
                {
                    return Rep::Pass;
                }
            }
            return Rep::None;
        }
        if( ( w == "exit" || w == "return" ) && n.words.size() > 1 && sh::detail::unq( n.words[1].text ) != "0" )
        {
            return Rep::Fail;
        }
        if( w.rfind( "((", 0 ) == 0 )
        {
            const std::string body = w.substr( 2 );   // ((fail++)) / (( fails += 1 ))
            const std::size_t op   = body.find_first_of( "+=" );
            return op != std::string::npos && isFlagName( body.substr( 0, op ) ) ? Rep::Fail : Rep::None;
        }
        if( funcNode( w ) == kNone && !isCheckName( w ) )
        {
            return repByName( w );   // an undefined helper named ok / fail (a sourced library's)
        }
        return Rep::None;
    }
    Rep repOfList( std::uint32_t list ) const
    {
        if( list == kNone || t_.lists[list].empty() || t_.lists[list][0].empty() || t_.lists[list][0][0].cmds.empty() )
        {
            return Rep::None;
        }
        return repOfCmd( t_.lists[list][0][0].cmds[0] );
    }
    Rep repOfItem( const sh::Item& it ) const
    {
        return it.cmds.size() == 1 ? repOfCmd( it.cmds[0] ) : Rep::None;
    }

    // ── what runs under test ───────────────────────────────────────────────────────────────────────────────────────
    // The matcher's kinds (the binary, a compiled harness, a wrapper of one), and — the facet's wider net, as before —
    // any command spelled through a variable or a path, an interpreter running a script path, and xargs of those.
    bool isRun( std::uint32_t c ) const
    {
        if( c >= a_.facts.size() || !a_.facts[c].seen )
        {
            return false;
        }
        if( isKindRun( c ) )
        {
            return true;
        }
        const sh::Node&   n = node( c );
        std::size_t       k = cmdIdx( n );
        if( k == std::string::npos )
        {
            return false;
        }
        std::string w = sh::detail::unq( n.words[k].text );
        if( w == "xargs" )
        {
            ++k;
            while( k < n.words.size() && !n.words[k].text.empty() && n.words[k].text[0] == '-' )
            {
                ++k;
            }
            if( k >= n.words.size() )
            {
                return false;
            }
            w = sh::detail::unq( n.words[k].text );
        }
        if( funcNode( w ) != kNone )
        {
            return false;
        }
        if( w == "python3" || w == "python" || w == "node" || w == "bash" || w == "sh" || w == "perl" || w == "ruby" )
        {
            for( std::size_t a = k + 1; a < n.words.size(); ++a )
            {
                const std::string u = sh::detail::unq( n.words[a].text );
                if( u == "-c" || u == "-e" || u == "-" )
                {
                    return false;   // an inline program is a filter, not a run
                }
                if( !u.empty() && u[0] == '-' )
                {
                    continue;
                }
                return u.find( '/' ) != std::string::npos || ( !u.empty() && u[0] == '$' );
            }
            return false;
        }
        return !w.empty() && ( w[0] == '$' || w.find( '/' ) != std::string::npos );
    }
    // the matcher's own kinds: the binary, a harness, an extra, or a call of a function the fixpoint proved a wrapper
    // (facts name every call of a defined function "wrapper"; Analysis::wrappers holds the proved ones)
    bool isKindRun( std::uint32_t c ) const
    {
        const std::string& kind = a_.facts[c].kind;
        return !kind.empty() && ( kind != "wrapper" || sh::detail::hasName( a_.wrappers, cmdWord( c ) ) || sh::detail::hasName( runWrappers_, cmdWord( c ) ) );
    }
    // The facet's wrappers, beside the matcher's: a function holding a run (or a call of one) that prints to its stdout
    // and whose status nothing inside reads — it IS the function's, or it is dropped — so the function's output is that
    // run's: run(){ ( cd "$FIX" || exit 1; "$BIN" "$FIX" "$@" ) 2>"$TMP/err"; }.
    void proveRunWrappers()
    {
        for( bool grew = true; grew; )
        {
            grew = false;
            for( std::uint32_t c = 0; c < a_.facts.size() && c < t_.nodes.size(); ++c )
            {
                const std::uint32_t f = scope_[c];
                const sh::Verdict v = a_.facts[c].seen ? a_.facts[c].cons.v : sh::Verdict::Checked;
                if( f == kNone || ( v != sh::Verdict::Fn && v != sh::Verdict::Unchecked ) || !isKindRun( c )
                    || std::any_of( node( c ).fredirs.begin(), node( c ).fredirs.end(), isStdoutRedir ) )
                {
                    continue;
                }
                const std::string& name = node( f ).name;
                if( !sh::detail::hasName( runWrappers_, name ) )
                {
                    runWrappers_.insert( std::lower_bound( runWrappers_.begin(), runWrappers_.end(), name ), name );
                    grew = true;
                }
            }
        }
    }
    bool silentFailable( std::uint32_t c ) const
    {
        return isRun( c ) && ( a_.facts[c].cons.v == sh::Verdict::Unchecked || a_.facts[c].cons.v == sh::Verdict::Fn );
    }

    // ── provenance ─────────────────────────────────────────────────────────────────────────────────────────────────
    static constexpr int kMaxDepth = 24;   // each hop (a word, a variable, a stage, a call) adds one

    Prov provWord( const sh::Word& w, std::uint32_t pos, std::uint32_t scope, const Env& env, int depth ) const
    {
        if( depth > kMaxDepth )
        {
            return Prov::opaque();
        }
        std::string_view x = w.text;
        if( x.size() >= 2 && x.front() == '"' && x.back() == '"' )
        {
            x = x.substr( 1, x.size() - 2 );
        }
        if( w.subs.size() == 1 && ( ( x.starts_with( "$(" ) && x.ends_with( ")" ) && x.size() == w.subs[0].inner.size() + 3 )
                                    || ( x.starts_with( "`" ) && x.ends_with( "`" ) && x.size() == w.subs[0].inner.size() + 2 ) ) )
        {
            return provList( w.subs[0].list, env, depth + 1 );
        }
        if( ( x.size() == 2 && x[0] == '$' && x[1] >= '1' && x[1] <= '9' ) || ( x.size() == 4 && x.starts_with( "${" ) && x[2] >= '1' && x[2] <= '9' && x[3] == '}' ) )
        {
            return provVar( x.substr( x.size() == 2 ? 1 : 2, 1 ), pos, scope, env, depth + 1 );
        }
        const std::string_view v = sh::detail::bareVar( x );
        if( !v.empty() )
        {
            return provVar( v, pos, scope, env, depth + 1 );
        }
        if( x == "$@" || x == "$*" || x == "${@}" || x == "${*}" )
        {
            return provVar( "1", pos, scope, env, depth + 1 );
        }
        return Prov::opaque();
    }
    Prov provVar( std::string_view name, std::uint32_t pos, std::uint32_t scope, const Env& env, int depth ) const
    {
        if( depth > kMaxDepth )
        {
            return Prov::opaque();
        }
        if( name.size() == 1 && name[0] >= '1' && name[0] <= '9' )
        {
            const std::size_t i = static_cast<std::size_t>( name[0] - '1' );
            return env.bound && i < env.args.size() ? env.args[i] : Prov::opaque();
        }
        const Assign* best = nullptr;
        for( const std::uint32_t want : { scope, kNone } )
        {
            for( const Assign& a : assigns_ )
            {
                if( a.name == name && a.scope == want && a.pos < pos && ( best == nullptr || a.pos >= best->pos ) )
                {
                    best = &a;
                }
            }
            if( best != nullptr || want == kNone )
            {
                break;
            }
        }
        if( best == nullptr || best->word == INT32_MIN )
        {
            return Prov::opaque();
        }
        const sh::Node& n   = node( best->node );
        const sh::Word& w   = best->word < 0 ? n.assigns[static_cast<std::size_t>( -1 - best->word )] : n.words[static_cast<std::size_t>( best->word )];
        const std::size_t eq = w.text.find( '=' );
        if( eq == std::string::npos || ( eq > 0 && w.text[eq - 1] == '+' ) )
        {
            return Prov::opaque();
        }
        sh::Word value;
        value.text = w.text.substr( eq + 1 );
        value.subs = w.subs;
        if( value.text.empty() )
        {
            return Prov::opaque();
        }
        Prov p = provWord( value, best->pos, best->scope, env, depth + 1 );
        // assigned only behind a check its own producers' empty text fails (if grep -q X <<<"$o"; then KEPT="$o"):
        // when they fail it is never assigned, so it never carries their empty text
        if( !best->reach.empty() && !p.unknown && !p.leaves.empty() && !inReachCheck_ )
        {
            inReachCheck_ = true;
            Eval ev;
            ev.s                = &p.leaves;
            const bool reached = reachableAt( best->reach, ev );
            inReachCheck_       = false;
            if( !reached )
            {
                return Prov::opaque();
            }
        }
        return p;
    }
    Prov provList( std::uint32_t list, const Env& env, int depth ) const
    {
        Prov out;
        if( list == kNone || depth > kMaxDepth )
        {
            return Prov::opaque();
        }
        for( const sh::AndOr& ao : t_.lists[list] )
        {
            for( const sh::Item& it : ao )
            {
                if( !it.cmds.empty() )
                {
                    out.add( provStage( it, it.cmds.size() - 1, env, depth + 1, false ) );
                }
            }
        }
        return out;
    }
    // the environment a call binds: its arguments' texts as $1.., and its stdin (a <<< / < redirect, else the pipe or
    // the caller's own stdin)
    template <class StdinOf>
    Env callEnv( std::uint32_t c, const sh::Node& n, std::size_t k, const Env& env, int depth, StdinOf&& stdinOf ) const
    {
        Env inner;
        inner.bound = true;
        for( std::size_t a = k + 1; a < n.words.size(); ++a )
        {
            if( !n.words[a].text.empty() && !isFdWord( n, n.words[a].text ) )
            {
                inner.args.push_back( provWord( n.words[a], n.pos, scope_[c], env, depth + 1 ) );
            }
        }
        inner.hasIn = true;
        bool redirected = false;
        for( const sh::Redir& r : n.fredirs )
        {
            if( r.op == "<<<" || r.op == "<" )
            {
                inner.in   = r.op == "<" ? provFile( normTarget( r.target ), n.pos, scope_[c], env, depth + 1 ) : hereString( n, r, env, depth );
                redirected = true;
            }
        }
        if( !redirected )
        {
            inner.in = stdinOf();
        }
        return inner;
    }
    Prov hereString( const sh::Node& n, const sh::Redir& r, const Env& env, int depth ) const
    {
        sh::Word hw;
        hw.text = r.target;
        for( const sh::Word& ww : n.words )
        {
            if( ww.text.empty() && ww.pos == r.targetPos )
            {
                hw.subs = ww.subs;
            }
        }
        return provWord( hw, n.pos, scopeOfPos( n ), env, depth + 1 );
    }
    static bool isFdWord( const sh::Node& n, std::string_view tx )
    {
        if( tx.empty() || tx.size() > 2 || !std::all_of( tx.begin(), tx.end(), []( char ch ) { return ch >= '0' && ch <= '9'; } ) )
        {
            return false;
        }
        const int fd = tx.size() == 1 ? tx[0] - '0' : ( tx[0] - '0' ) * 10 + ( tx[1] - '0' );
        return std::any_of( n.fredirs.begin(), n.fredirs.end(), [ & ]( const sh::Redir& r ) { return r.fd == fd; } );
    }
    static bool isSilentCmd( std::string_view w )
    {
        static constexpr std::string_view kSilent[] = { "cd", "export", "local", "set", "shift", "true", ":", "rm", "mkdir", "cp", "mv", "touch", "unset",
                                                        "declare", "readonly", "trap", "wait", "sleep", "[", "test", "chmod", "ln", "pushd", "popd", "exec" };
        return std::ranges::contains( kSilent, w );
    }
    // the output of stage j of a pipeline (its stdin is stage j-1's); `ignoreRedirect` reads a writer's own output
    Prov provStage( const sh::Item& it, std::size_t j, const Env& env, int depth, bool ignoreRedirect ) const
    {
        if( depth > kMaxDepth )
        {
            return Prov::opaque();
        }
        const std::uint32_t c = it.cmds[j];
        const sh::Node&     n = node( c );
        if( !ignoreRedirect && std::any_of( n.fredirs.begin(), n.fredirs.end(), isStdoutRedir ) )
        {
            return {};   // its output went to a file: it prints nothing here
        }
        const auto stdinOf = [ & ]() -> Prov { return j > 0 ? provStage( it, j - 1, env, depth + 1, false ) : ( env.hasIn ? env.in : Prov::opaque() ); };
        if( n.kind == sh::NodeKind::Subshell || n.kind == sh::NodeKind::Group )
        {
            return n.bodies.empty() ? Prov::opaque() : provList( n.bodies[0], env, depth + 1 );
        }
        if( n.kind != sh::NodeKind::Simple )
        {
            return Prov::opaque();
        }
        const std::size_t k = cmdIdx( n );
        if( k == std::string::npos )
        {
            return {};   // an assignment prints nothing
        }
        if( isRun( c ) )
        {
            Prov p;
            if( silentFailable( c ) || ( j + 1 < it.cmds.size() ) )
            {
                p.leaves.push_back( c );
            }
            else
            {
                p.unknown = true;   // its failure is reported: its output is never silently empty
            }
            return p;
        }
        const std::string w = sh::detail::unq( n.words[k].text );
        if( isSilentCmd( w ) )
        {
            return {};
        }
        const std::uint32_t f = funcNode( w );
        if( f != kNone )
        {
            // a function that only filters its arguments (or stdin): its output with $1.. bound here
            Env inner = callEnv( c, n, k, env, depth, stdinOf );
            const sh::Node& fn = node( f );
            return fn.bodies.empty() ? Prov::opaque() : throughCall( c, f, provList( fn.bodies[0], inner, depth + 1 ) );
        }
        if( w == "echo" || w == "printf" )
        {
            Prov        p;
            std::size_t a = k + 1;
            while( w == "echo" && a < n.words.size() && ( n.words[a].text == "-n" || n.words[a].text == "-e" || n.words[a].text == "-ne" ) )
            {
                ++a;
            }
            if( w == "printf" && a < n.words.size() )
            {
                const std::string fmt = sh::detail::unq( n.words[a].text );
                if( fmt != "%s" && fmt != "%s\\n" && fmt != "%s\\n\\n" )
                {
                    return Prov::opaque();
                }
                ++a;
            }
            for( ; a < n.words.size(); ++a )
            {
                p.add( provWord( n.words[a], n.pos, scope_[c], env, depth + 1 ) );
            }
            return p;
        }
        return provFilter( c, n, k, w, stdinOf, env, depth );
    }
    // A run inside function F whose status IS F's (the matcher's Fn verdict) fails silently only when the CALL's status
    // is dropped too: out="$( run_hook … )"; rc=$? then a test of rc reports it. The call stands in for that run.
    Prov throughCall( std::uint32_t call, std::uint32_t f, Prov p ) const
    {
        if( call >= a_.facts.size() || !a_.facts[call].seen )
        {
            return p;
        }
        const bool callSilent = a_.facts[call].cons.v == sh::Verdict::Unchecked || a_.facts[call].cons.v == sh::Verdict::Fn;
        for( std::uint32_t& l : p.leaves )
        {
            if( scope_[l] != f || a_.facts[l].cons.v != sh::Verdict::Fn )
            {
                continue;
            }
            if( !callSilent )
            {
                p.unknown = true;   // reported at the call: never silently empty
            }
            else if( isRun( call ) )
            {
                l = call;
            }
        }
        return p;
    }
    template <class StdinOf>
    Prov provFilter( std::uint32_t c, const sh::Node& n, std::size_t k, const std::string& w, StdinOf&& stdinOf, const Env& env, int depth ) const
    {
        struct F
        {
            std::string_view name;
            int              skipFirst;       // 1: the first operand is a pattern / program
            std::string_view valueOpts;       // one-letter options that take a value
        };
        static constexpr F kFilters[] = { { "grep", 1, "efmABCd" }, { "egrep", 1, "efmABC" }, { "fgrep", 1, "efmABC" }, { "sed", 1, "ef" }, { "awk", 1, "Fvf" },
                                          { "gawk", 1, "Fvf" }, { "tr", 0, "" }, { "cut", 0, "dfcb" }, { "head", 0, "nc" }, { "tail", 0, "nc" },
                                          { "sort", 0, "ktoS" }, { "uniq", 0, "fs" }, { "cat", 0, "" }, { "jq", 1, "" }, { "tee", 0, "" },
                                          { "rev", 0, "" }, { "python3", 0, "" }, { "python", 0, "" }, { "xmllint", 0, "" } };
        const F* spec = nullptr;
        for( const F& f : kFilters )
        {
            if( f.name == w )
            {
                spec = &f;
            }
        }
        if( spec == nullptr )
        {
            return Prov::opaque();
        }
        bool        inlineProg = false;
        bool        hasE       = false;
        std::vector<const sh::Word*> operands;
        for( std::size_t a = k + 1; a < n.words.size(); ++a )
        {
            const std::string& tx = n.words[a].text;
            if( tx.empty() || isFdWord( n, tx ) )
            {
                continue;   // a redirect target's substitutions, or the fd glued before a redirect (2>)
            }
            const std::string u = sh::detail::unq( tx );
            if( u.size() > 1 && u[0] == '-' && u != "--" )
            {
                if( w == "grep" && u.find( 'c' ) != std::string::npos && u[1] != '-' )
                {
                    return Prov::opaque();   // a count of an empty text is "0", not empty
                }
                if( ( w == "python3" || w == "python" ) && ( u == "-c" || u.find( 'c' ) != std::string::npos ) )
                {
                    inlineProg = true;
                    ++a;   // the program
                    continue;
                }
                if( u == "-e" || u == "-f" )
                {
                    hasE = true;
                }
                if( u.size() == 2 && spec->valueOpts.find( u[1] ) != std::string_view::npos )
                {
                    ++a;
                }
                continue;
            }
            if( u == "--" )
            {
                continue;
            }
            operands.push_back( &n.words[a] );
        }
        if( ( w == "python3" || w == "python" ) && !inlineProg )
        {
            return Prov::opaque();
        }
        if( ( w == "awk" || w == "gawk" ) && !operands.empty() && operands[0]->text.contains( "END" ) )
        {
            return Prov::opaque();
        }
        std::size_t from = ( spec->skipFirst != 0 && !hasE && !operands.empty() ) ? 1 : 0;
        Prov        p;
        bool        sawInput = false;
        if( w != "tr" && !( w == "python3" || w == "python" ) )
        {
            for( std::size_t o = from; o < operands.size(); ++o )
            {
                const std::string u = sh::detail::unq( operands[o]->text );
                if( ( w == "awk" || w == "gawk" ) && u.find( '=' ) != std::string::npos )
                {
                    continue;
                }
                p.add( provFile( normTarget( operands[o]->text ), n.pos, scope_[c], env, depth + 1 ) );
                sawInput = true;
            }
        }
        for( const sh::Redir& r : n.fredirs )
        {
            if( r.op == "<<<" )
            {
                p.add( hereString( n, r, env, depth ) );
                sawInput = true;
            }
            else if( r.op == "<" )
            {
                p.add( provFile( normTarget( r.target ), n.pos, scope_[c], env, depth + 1 ) );
                sawInput = true;
            }
        }
        if( !sawInput )
        {
            p.add( stdinOf() );
        }
        return p;
    }
    // The text a FILE holds at `pos`: its last writer before it, in this scope or at the top level, or a call of a
    // function whose writer's target, with $1.. bound to the call's arguments, spells this file.
    Prov provFile( const std::string& target, std::uint32_t pos, std::uint32_t scope, const Env& env, int depth ) const
    {
        if( depth > kMaxDepth || target.empty() )
        {
            return Prov::opaque();
        }
        const Writer* best     = nullptr;
        std::uint32_t bestPos  = 0;
        std::uint32_t callNode = kNone;
        for( const std::uint32_t want : { scope, kNone } )
        {
            for( const Writer& wr : writers_ )
            {
                if( wr.scope == want && wr.pos < pos && wr.target == target && ( best == nullptr || wr.pos >= bestPos ) )
                {
                    best     = &wr;
                    bestPos  = wr.pos;
                    callNode = kNone;
                }
            }
            // a function call that writes it: run_qd mod1 with run_qd's `> "$TMP/$1.out"`
            for( std::uint32_t c = 0; c < t_.nodes.size(); ++c )
            {
                const sh::Node& n = node( c );
                if( n.kind != sh::NodeKind::Simple || scope_[c] != want || n.pos >= pos || ( best != nullptr && n.pos < bestPos ) )
                {
                    continue;
                }
                const std::size_t k = cmdIdx( n );
                if( k == std::string::npos )
                {
                    continue;
                }
                const std::uint32_t f = funcNode( sh::detail::unq( n.words[k].text ) );
                if( f == kNone )
                {
                    continue;
                }
                std::vector<std::string> args;
                for( std::size_t a = k + 1; a < n.words.size(); ++a )
                {
                    if( !n.words[a].text.empty() && !isFdWord( n, n.words[a].text ) )
                    {
                        args.push_back( normTarget( n.words[a].text ) );
                    }
                }
                for( const Writer& wr : writers_ )
                {
                    if( wr.scope != f || wr.target.find( '$' ) == std::string::npos )
                    {
                        continue;
                    }
                    if( bindArgs( wr.target, args ) == target )
                    {
                        best     = &wr;
                        bestPos  = n.pos;
                        callNode = c;
                    }
                }
            }
            if( best != nullptr )
            {
                break;
            }
        }
        if( best == nullptr )
        {
            return Prov::opaque();
        }
        Env use = env;
        if( callNode != kNone )
        {
            const sh::Node& n = node( callNode );
            use               = callEnv( callNode, n, cmdIdx( n ), env, depth, [] { return Prov::opaque(); } );
        }
        const sh::Node& wn = node( best->node );
        if( wn.kind == sh::NodeKind::Subshell || wn.kind == sh::NodeKind::Group )
        {
            return wn.bodies.empty() ? Prov::opaque() : provList( wn.bodies[0], use, depth + 1 );
        }
        if( best->item == nullptr )
        {
            return Prov::opaque();
        }
        return provStage( *best->item, best->stage, use, depth + 1, true );
    }
    static std::string bindArgs( const std::string& pattern, const std::vector<std::string>& args )
    {
        std::string out;
        for( std::size_t i = 0; i < pattern.size(); ++i )
        {
            if( pattern[i] == '$' && i + 1 < pattern.size() && pattern[i + 1] >= '1' && pattern[i + 1] <= '9' )
            {
                const std::size_t a = static_cast<std::size_t>( pattern[i + 1] - '1' );
                if( a >= args.size() )
                {
                    return {};
                }
                out += args[a];
                ++i;
                continue;
            }
            out.push_back( pattern[i] );
        }
        return out;
    }

    // ── conditions ─────────────────────────────────────────────────────────────────────────────────────────────────
    struct Eval
    {
        const std::vector<std::uint32_t>* s       = nullptr;
        std::vector<std::uint32_t>*       collect = nullptr;   // when set: gather every producer an input reads
    };
    Tri ofInput( const Prov& p, const Eval& ev, Tri onEmpty ) const
    {
        if( ev.collect != nullptr )
        {
            ev.collect->insert( ev.collect->end(), p.leaves.begin(), p.leaves.end() );
        }
        return ( ev.s != nullptr && p.emptyUnder( *ev.s ) ) ? onEmpty : Tri::U;
    }
    Tri evalItem( const sh::Item& it, const Eval& ev, const Env& env, int depth ) const
    {
        Tri v = evalStage( it, ev, env, depth );
        return it.neg ? triNot( v ) : v;
    }
    Tri evalStage( const sh::Item& it, const Eval& ev, const Env& env, int depth ) const
    {
        if( it.cmds.empty() || depth > kMaxDepth )
        {
            return Tri::U;
        }
        const std::uint32_t c          = it.cmds.back();
        const sh::Node&     n          = node( c );
        const bool          pipeFailed = pipeFailedBefore( it, ev, c );
        if( n.kind == sh::NodeKind::Group || n.kind == sh::NodeKind::Subshell )
        {
            if( n.bodies.empty() || n.bodies[0] == kNone || t_.lists[n.bodies[0]].empty() )
            {
                return Tri::U;
            }
            return evalAndOr( t_.lists[n.bodies[0]].back(), ev, env, depth + 1 );
        }
        if( n.kind != sh::NodeKind::Simple )
        {
            return Tri::U;
        }
        const std::size_t k = cmdIdx( n );
        if( k == std::string::npos )
        {
            return Tri::U;
        }
        const std::string w = sh::detail::unq( n.words[k].text );
        Tri               v = Tri::U;
        if( w == "grep" || w == "egrep" || w == "fgrep" )
        {
            v = evalGrep( it, c, n, k, ev, env, depth );
        }
        else if( w == "[" || w == "test" )
        {
            v = evalTest( n, k, ev, env, depth );
        }
        else if( w == "cmp" || w == "diff" )
        {
            v = evalCmp( c, n, k, ev, env, depth );
        }
        else
        {
            v = evalHelperCall( it, c, n, k, w, ev, env, depth );
        }
        return pipeFailed ? Tri::F : v;
    }
    // under pipefail a failed stage before the last makes the whole pipeline false, whatever the last one reads
    bool pipeFailedBefore( const sh::Item& it, const Eval& ev, std::uint32_t last ) const
    {
        bool failed = false;
        for( std::size_t j = 0; j + 1 < it.cmds.size(); ++j )
        {
            if( !isRun( it.cmds[j] ) )
            {
                continue;
            }
            if( ev.collect != nullptr )
            {
                ev.collect->push_back( it.cmds[j] );
            }
            failed = failed || ( ev.s != nullptr && std::find( ev.s->begin(), ev.s->end(), it.cmds[j] ) != ev.s->end() && a_.facts[last].pipefail );
        }
        return failed;
    }
    // what the last stage of a pipeline reads: the stage before it, or what the caller fed in
    Prov stdinOfLast( const sh::Item& it, const Env& env, int depth ) const
    {
        return it.cmds.size() > 1 ? provStage( it, it.cmds.size() - 2, env, depth + 1, false ) : ( env.hasIn ? env.in : Prov::opaque() );
    }
    // grep -q (or grep >/dev/null) passes on found text: an empty input FAILS it; a count (-c) or list (-L) is no verdict
    Tri evalGrep( const sh::Item& it, std::uint32_t c, const sh::Node& n, std::size_t k, const Eval& ev, const Env& env, int depth ) const
    {
        bool quiet = std::any_of( n.fredirs.begin(), n.fredirs.end(), []( const sh::Redir& r ) { return isStdoutRedir( r ) && r.target == "/dev/null"; } );
        for( std::size_t a = k + 1; a < n.words.size(); ++a )
        {
            const std::string u = sh::detail::unq( n.words[a].text );
            if( u == "--quiet" || u == "--silent" || ( u.size() > 1 && u[0] == '-' && u[1] != '-' && u.find( 'q' ) != std::string::npos ) )
            {
                quiet = true;
            }
            if( u.size() > 1 && u[0] == '-' && u[1] != '-' && ( u.find( 'c' ) != std::string::npos || u.find( 'L' ) != std::string::npos ) )
            {
                return Tri::U;
            }
        }
        if( !quiet )
        {
            return Tri::U;
        }
        return ofInput( provFilter( c, n, k, "grep", [ & ]() -> Prov { return stdinOfLast( it, env, depth ); }, env, depth + 1 ), ev, Tri::F );
    }
    // cmp / diff of two files: true when both are empty under the failure set
    Tri evalCmp( std::uint32_t c, const sh::Node& n, std::size_t k, const Eval& ev, const Env& env, int depth ) const
    {
        std::vector<Prov> files;
        for( std::size_t a = k + 1; a < n.words.size(); ++a )
        {
            const std::string u = sh::detail::unq( n.words[a].text );
            if( n.words[a].text.empty() || isFdWord( n, n.words[a].text ) || ( u.size() > 1 && u[0] == '-' ) )
            {
                continue;
            }
            files.push_back( provFile( normTarget( n.words[a].text ), n.pos, scope_[c], env, depth + 1 ) );
        }
        if( files.size() != 2 )
        {
            return Tri::U;
        }
        const Tri a = ofInput( files[0], ev, Tri::T );
        const Tri b = ofInput( files[1], ev, Tri::T );
        return ( a == Tri::T && b == Tri::T ) ? Tri::T : Tri::U;
    }
    // a helper whose body is one pipeline (has(){ grep -qF -- "$2" <<<"$1"; }): judged with $1.. bound here
    Tri evalHelperCall( const sh::Item& it, std::uint32_t c, const sh::Node& n, std::size_t k, const std::string& w, const Eval& ev, const Env& env, int depth ) const
    {
        const sh::List* body = funcBody( funcNode( w ) );
        if( body == nullptr || body->size() != 1 || ( *body )[0].size() != 1 || isKindRun( c ) )
        {
            return Tri::U;
        }
        return evalItem( ( *body )[0][0], ev, callEnv( c, n, k, env, depth, [ & ]() -> Prov { return stdinOfLast( it, env, depth ); } ), depth + 1 );
    }
    Tri evalTest( const sh::Node& n, std::size_t k, const Eval& ev, const Env& env, int depth ) const
    {
        std::vector<const sh::Word*> ws;
        for( std::size_t a = k + 1; a < n.words.size(); ++a )
        {
            if( !n.words[a].text.empty() )
            {
                ws.push_back( &n.words[a] );
            }
        }
        if( !ws.empty() && ws.back()->text == "]" )
        {
            ws.pop_back();
        }
        bool neg = false;
        if( !ws.empty() && ws.front()->text == "!" )
        {
            neg = true;
            ws.erase( ws.begin() );
        }
        const std::uint32_t scope = scope_.size() > 0 ? scopeOfPos( n ) : kNone;
        const auto val = [ & ]( const sh::Word* w ) { return provWord( *w, n.pos, scope, env, depth + 1 ); };
        Tri v = Tri::U;
        if( ws.size() == 2 )
        {
            const std::string op = ws[0]->text;
            if( op == "-s" )
            {
                v = ofInput( provFile( normTarget( ws[1]->text ), n.pos, scope, env, depth + 1 ), ev, Tri::F );
            }
            else if( op == "-n" )
            {
                v = ofInput( val( ws[1] ), ev, Tri::F );
            }
            else if( op == "-z" )
            {
                v = ofInput( val( ws[1] ), ev, Tri::T );
            }
        }
        else if( ws.size() == 1 )
        {
            v = ofInput( val( ws[0] ), ev, Tri::F );
        }
        else if( ws.size() == 3 && ( ws[1]->text == "=" || ws[1]->text == "==" || ws[1]->text == "!=" ) )
        {
            const Tri  a  = ofInput( val( ws[0] ), ev, Tri::T );
            const Tri  b  = ofInput( val( ws[2] ), ev, Tri::T );
            const bool eq = a == Tri::T && b == Tri::T;   // two empty texts are equal
            v             = eq ? ( ws[1]->text == "!=" ? Tri::F : Tri::T ) : Tri::U;
        }
        return neg ? triNot( v ) : v;
    }
    std::uint32_t scopeOfPos( const sh::Node& n ) const
    {
        const std::size_t idx = static_cast<std::size_t>( &n - t_.nodes.data() );
        return idx < scope_.size() ? scope_[idx] : kNone;
    }
    Tri evalAndOr( const sh::AndOr& ao, const Eval& ev, const Env& env, int depth ) const
    {
        Tri v = Tri::U;
        for( std::size_t j = 0; j < ao.size(); ++j )
        {
            const Tri x = evalItem( ao[j], ev, env, depth );
            v           = j == 0 ? x : ( ao[j].op == sh::Link::And ? triAnd( v, x ) : triOr( v, x ) );
        }
        return v;
    }
    Tri evalCondList( std::uint32_t list, const Eval& ev ) const
    {
        if( list == kNone || t_.lists[list].empty() )
        {
            return Tri::U;
        }
        // earlier statements of a condition list are evaluated for what they read; the last one decides
        const sh::List& l = t_.lists[list];
        for( std::size_t k = 0; k + 1 < l.size(); ++k )
        {
            if( ev.collect != nullptr )
            {
                (void)evalAndOr( l[k], ev, Env{}, 0 );
            }
        }
        return evalAndOr( l.back(), ev, Env{}, 0 );
    }

    // ── judgments ──────────────────────────────────────────────────────────────────────────────────────────────────
    struct Outcomes
    {
        bool pass = false, fail = false, none = false;
        void add( Rep r )
        {
            pass = pass || r == Rep::Pass;
            fail = fail || r == Rep::Fail;
            none = none || r == Rep::None;
        }
        bool onlyPass() const
        {
            return pass && !fail && !none;
        }
        bool onlyFail() const
        {
            return fail && !pass && !none;
        }
    };
    // the reporter split of a statement: items [0, r) are the condition, r.. are reporters
    bool splitAndOr( const sh::AndOr& ao, std::size_t& r ) const
    {
        for( r = 1; r < ao.size(); ++r )
        {
            if( repOfItem( ao[r] ) != Rep::None )
            {
                break;
            }
        }
        if( r >= ao.size() || repOfItem( ao[0] ) != Rep::None )
        {
            return false;
        }
        for( std::size_t q = r; q < ao.size(); ++q )
        {
            if( repOfItem( ao[q] ) == Rep::None )
            {
                return false;
            }
        }
        return true;
    }
    Outcomes outcomes( const Judgment& j, const Eval& ev ) const
    {
        Outcomes o;
        if( j.kind == Judgment::Kind::AndOr )
        {
            std::size_t r = 0;
            if( !splitAndOr( *j.ao, r ) )
            {
                o.none = true;
                return o;
            }
            sh::AndOr cond( j.ao->begin(), j.ao->begin() + static_cast<std::ptrdiff_t>( r ) );
            const Tri v       = evalAndOr( cond, ev, Env{}, 0 );
            Rep       onTrue  = Rep::None;
            Rep       onFalse = Rep::None;
            if( ( *j.ao )[r].op == sh::Link::And )
            {
                onTrue = repOfItem( ( *j.ao )[r] );
                if( r + 1 < j.ao->size() && ( *j.ao )[r + 1].op == sh::Link::Or )
                {
                    onFalse = repOfItem( ( *j.ao )[r + 1] );
                }
            }
            else
            {
                onFalse = repOfItem( ( *j.ao )[r] );
            }
            if( v != Tri::F )
            {
                o.add( onTrue );
            }
            if( v != Tri::T )
            {
                o.add( onFalse );
            }
            return o;
        }
        const sh::Node& n = node( j.node );
        if( j.kind == Judgment::Kind::If )
        {
            bool open = true;
            for( std::size_t i = 0; i < n.conds.size() && open; ++i )
            {
                const Tri v = evalCondList( n.conds[i], ev );
                if( v != Tri::F )
                {
                    o.add( i < n.bodies.size() ? repOfList( n.bodies[i] ) : Rep::None );
                }
                open = v != Tri::T;
            }
            if( open )
            {
                o.add( n.bodies.size() > n.conds.size() ? repOfList( n.bodies.back() ) : Rep::None );
            }
            return o;
        }
        // case: an empty subject takes the first arm whose pattern matches the empty string
        const sh::Word subj{ n.caseSubject, n.line, n.pos, {} };
        const Prov     p     = provWord( subj, n.pos, j.scope, Env{}, 0 );
        const bool     empty = ofInput( p, ev, Tri::T ) == Tri::T;
        const auto     takesAll = [ & ]( std::size_t b )   // a `*)` arm: every subject, the empty one too, can reach it
        {
            return b < n.casePats.size() && std::any_of( n.casePats[b].begin(), n.casePats[b].end(), []( const std::string& pt )
                                                         {
                                                             const std::string u = sh::detail::unq( pt );
                                                             return std::all_of( u.begin(), u.end(), []( char ch ) { return ch == '*'; } );
                                                         } );
        };
        bool catchAll = false;
        for( std::size_t b = 0; b < n.bodies.size(); ++b )
        {
            if( !empty )
            {
                o.add( repOfList( n.bodies[b] ) );
                catchAll = catchAll || takesAll( b );
                continue;
            }
            if( takesAll( b ) )
            {
                o.add( repOfList( n.bodies[b] ) );
                return o;
            }
        }
        // no `*)` arm: a subject no pattern matches takes no arm and reports nothing
        if( empty || !catchAll )
        {
            o.none = true;
        }
        return o;
    }
    // Can the judgment be reached under S? Not when an enclosing if's condition takes another branch for sure, or an
    // enclosing case's empty subject takes another arm.
    bool reachable( const Judgment& j, const Eval& ev ) const
    {
        return reachableAt( j.reach, ev );
    }
    bool reachableAt( const std::vector<ReachStep>& reach, const Eval& ev ) const
    {
        for( const ReachStep& r : reach )
        {
            const sh::Node& n = node( r.node );
            if( n.kind == sh::NodeKind::If )
            {
                for( std::size_t i = 0; i < n.conds.size(); ++i )
                {
                    const Tri v = evalCondList( n.conds[i], ev );
                    if( i < r.branch && v == Tri::T )
                    {
                        return false;
                    }
                    if( i == r.branch )
                    {
                        if( v == Tri::F )
                        {
                            return false;
                        }
                        break;
                    }
                }
            }
            else if( n.kind == sh::NodeKind::Case )
            {
                const sh::Word subj{ n.caseSubject, n.line, n.pos, {} };
                const Prov     p = provWord( subj, n.pos, scope_[r.node], Env{}, 0 );
                if( ofInput( p, ev, Tri::T ) == Tri::T )
                {
                    for( std::size_t b = 0; b < n.casePats.size(); ++b )
                    {
                        const bool matches = std::any_of( n.casePats[b].begin(), n.casePats[b].end(), []( const std::string& pt )
                                                          {
                                                              const std::string u = sh::detail::unq( pt );
                                                              return std::all_of( u.begin(), u.end(), []( char ch ) { return ch == '*'; } );
                                                          } );
                        if( matches )
                        {
                            if( b != r.branch )
                            {
                                return false;
                            }
                            break;
                        }
                    }
                }
            }
        }
        return true;
    }
    bool vacuous( std::size_t ji ) const
    {
        const Judgment&            j = judgments_[ji];
        std::vector<std::uint32_t> leaves;
        Eval                       col;
        col.collect = &leaves;
        (void)outcomes( j, col );
        std::sort( leaves.begin(), leaves.end() );
        leaves.erase( std::unique( leaves.begin(), leaves.end() ), leaves.end() );
        leaves.erase( std::remove_if( leaves.begin(), leaves.end(), [ & ]( std::uint32_t l ) { return !isRun( l ); } ), leaves.end() );
        if( leaves.empty() )
        {
            return false;
        }
        const std::vector<std::uint32_t> none;
        Eval                             base;
        base.s = &none;
        if( outcomes( j, base ).onlyPass() )
        {
            return false;   // it passes whatever its producers do: no failure makes it vacuous
        }
        std::vector<std::vector<std::uint32_t>> sets;
        if( leaves.size() <= 4 )
        {
            for( std::uint32_t m = 1; m < ( 1u << leaves.size() ); ++m )
            {
                std::vector<std::uint32_t> s;
                for( std::size_t b = 0; b < leaves.size(); ++b )
                {
                    if( ( m >> b ) & 1u )
                    {
                        s.push_back( leaves[b] );
                    }
                }
                sets.push_back( std::move( s ) );
            }
        }
        else
        {
            for( std::uint32_t l : leaves )
            {
                sets.push_back( { l } );
            }
            sets.push_back( leaves );
        }
        for( const std::vector<std::uint32_t>& s : sets )
        {
            // a producer that is not silent (its status is read) is never in S: a pipe stage counts, its pipeline is the judgment
            if( std::any_of( s.begin(), s.end(), [ & ]( std::uint32_t l ) { return !silentFailable( l ) && !inOwnPipeline( j, l ); } ) )
            {
                continue;
            }
            Eval ev;
            ev.s = &s;
            if( !reachable( j, ev ) || !outcomes( j, ev ).onlyPass() )
            {
                continue;
            }
            bool guarded = false;
            for( std::size_t ki = 0; ki < judgments_.size() && !guarded; ++ki )
            {
                const Judgment& k = judgments_[ki];
                if( ki == ji || k.scope != j.scope || !reachable( k, ev ) )
                {
                    continue;
                }
                guarded = outcomes( k, ev ).onlyFail();
            }
            if( !guarded )
            {
                return true;
            }
        }
        return false;
    }
    bool inOwnPipeline( const Judgment& j, std::uint32_t l ) const
    {
        const auto inAo = [ & ]( const sh::AndOr& ao )
        {
            return std::any_of( ao.begin(), ao.end(), [ & ]( const sh::Item& it ) { return it.cmds.size() > 1 && std::find( it.cmds.begin(), it.cmds.end() - 1, l ) != it.cmds.end() - 1; } );
        };
        if( j.kind == Judgment::Kind::AndOr )
        {
            return inAo( *j.ao );
        }
        const sh::Node& n = node( j.node );
        for( std::uint32_t cl : n.conds )
        {
            if( cl != kNone && std::any_of( t_.lists[cl].begin(), t_.lists[cl].end(), inAo ) )
            {
                return true;
            }
        }
        return false;
    }

    // ── the three status shapes ────────────────────────────────────────────────────────────────────────────────────
    bool reportsByFlag( std::uint32_t f, int depth ) const
    {
        bool hit = false;
        if( f == kNone || depth > 2 )
        {
            return false;
        }
        forEachSimple( node( f ).bodies.empty() ? kNone : node( f ).bodies[0], [ & ]( std::uint32_t c )
                       {
                           const sh::Node& n = node( c );
                           if( n.words.empty() )
                           {
                               hit = hit || repOfCmd( c ) == Rep::Fail;
                               return;
                           }
                           const std::string w = sh::detail::unq( n.words[0].text );
                           if( std::find( flagReporters_.begin(), flagReporters_.end(), w ) != flagReporters_.end() )
                           {
                               // a reporter whose output is sent to stderr still sets the flag in the subshell only
                               hit = true;
                               return;
                           }
                           const std::uint32_t g = funcNode( w );
                           if( g != kNone && g != f && repOfCmd( c ) == Rep::None )
                           {
                               hit = hit || reportsByFlag( g, depth + 1 );
                           }
                       } );
        return hit;
    }
    // rc=$? at `cap`: is its value TESTED before it is overwritten? `after` is where the window opens.
    bool rcTested( const std::string& name, std::uint32_t scope, std::uint32_t after, std::uint32_t until, int depth ) const
    {
        bool tested = false;
        for( std::uint32_t c = 0; c < t_.nodes.size() && !tested; ++c )
        {
            const sh::Node& n = node( c );
            if( scope_[c] != scope || n.pos <= after || n.pos >= until )
            {
                continue;
            }
            std::vector<std::string> refs;
            std::string              text;
            if( n.kind == sh::NodeKind::Case )
            {
                text = n.name;
            }
            else if( n.kind == sh::NodeKind::Simple )
            {
                for( const sh::Word& w : n.words )
                {
                    text += w.text + " ";
                }
            }
            else
            {
                continue;
            }
            sh::detail::vrefs( text, refs );
            const bool mentions = std::find( refs.begin(), refs.end(), name ) != refs.end();
            if( n.kind == sh::NodeKind::Case )
            {
                tested = mentions;
                continue;
            }
            // an alias hands it on: r1=$rc, then a test of r1
            for( const sh::Word& a : n.assigns )
            {
                const std::size_t eq = a.text.find( '=' );
                if( eq != std::string::npos && sh::detail::quotedBareVar( a.text.substr( eq + 1 ) ) == name && depth < 2 )
                {
                    tested = tested || rcTested( a.text.substr( 0, eq ), scope, n.pos, UINT32_MAX, depth + 1 );
                }
                std::vector<std::string> ar;
                sh::detail::vrefs( a.text, ar );
                if( a.text.find( "$((" ) != std::string::npos && std::find( ar.begin(), ar.end(), name ) != ar.end() )
                {
                    tested = true;   // fail=$(( fail | rc )): accumulated into the verdict
                }
            }
            if( !mentions || n.words.empty() )
            {
                continue;
            }
            const std::string cw = sh::detail::unq( n.words[0].text );
            if( cw == "[" || cw == "test" || cw == "exit" || cw == "return" || cw.rfind( "[[", 0 ) == 0 || cw.rfind( "((", 0 ) == 0 || cw == "echo" || cw == "printf"
                || ( cw == "local" && text.find( "$((" ) != std::string::npos ) )
            {
                // echo $rc: into an rc file the gate compares later (the matcher's checked form); to the terminal it is a message
                tested = ( cw != "echo" && cw != "printf" ) || std::any_of( n.fredirs.begin(), n.fredirs.end(), isStdoutRedir );
                continue;
            }
            if( repOfCmd( c ) == Rep::None )
            {
                for( std::size_t w = 1; w < n.words.size(); ++w )
                {
                    tested = tested || sh::detail::quotedBareVar( n.words[w].text ) == name;   // a checker: expect "C4" "$rc" 1
                }
            }
        }
        return tested;
    }
    // The next assignment that surely overwrites NAME after the capture: not a conditional one (`|| rc=1`), and, when
    // the capture's branch path is known, one on that path or outside it (an if / case branch the capture is not in,
    // the other arm of its own if included, does not run after it on every path).
    std::uint32_t nextAssignPos( const std::string& name, std::uint32_t scope, std::uint32_t after, const std::vector<ReachStep>* capReach = nullptr ) const
    {
        const auto onPath = [ & ]( const Assign& a )
        {
            return capReach == nullptr
                || ( a.reach.size() <= capReach->size()
                     && std::equal( a.reach.begin(), a.reach.end(), capReach->begin(),
                                    []( const ReachStep& x, const ReachStep& y ) { return x.node == y.node && x.branch == y.branch; } ) );
        };
        std::uint32_t best = UINT32_MAX;
        for( const Assign& a : assigns_ )
        {
            if( a.name == name && a.scope == scope && a.pos > after && a.pos < best && !a.cond && onPath( a ) )
            {
                best = a.pos;
            }
        }
        return best;
    }
    const std::vector<ReachStep>* reachOf( std::uint32_t c ) const
    {
        const Assign* a = rw::findByField( assigns_, &Assign::node, c );
        return a == nullptr ? nullptr : &a->reach;
    }
    // the operands a call passes as $1.. (no redirect-target subs, no glued fds), normalized
    std::vector<std::string> callArgs( std::uint32_t c ) const
    {
        std::vector<std::string> args;
        const sh::Node&          n = node( c );
        const std::size_t        k = cmdIdx( n );
        for( std::size_t a = k == std::string::npos ? n.words.size() : k + 1; a < n.words.size(); ++a )
        {
            if( !n.words[a].text.empty() && !isFdWord( n, n.words[a].text ) )
            {
                args.push_back( normTarget( n.words[a].text ) );
            }
        }
        return args;
    }
    bool inReporterMessage( std::uint32_t d ) const
    {
        return std::any_of( subCalls_.begin(), subCalls_.end(), [ & ]( const std::pair<std::uint32_t, std::uint32_t>& hc ) { return hc.second == d && repOfCmd( hc.first ) != Rep::None; } );
    }
    std::vector<std::uint32_t> callsOf( std::uint32_t f ) const
    {
        std::vector<std::uint32_t> out;
        for( std::uint32_t c = 0; c < t_.nodes.size(); ++c )
        {
            if( node( c ).kind == sh::NodeKind::Simple && scope_[c] != f && cmdWord( c ) == node( f ).name )
            {
                out.push_back( c );
            }
        }
        return out;
    }
    // Does any command read FILE (an operand, a < redirect), directly or through a function's "$TMP/$1.rc" bound at a
    // call? A read inside a reporter's message ($( cat "$TMP/$1.rc" ) in a FAIL line) prints it; it tests nothing.
    bool fileRead( const std::string& target, std::uint32_t writer ) const
    {
        for( std::uint32_t d = 0; d < t_.nodes.size(); ++d )
        {
            const sh::Node& n = node( d );
            if( d == writer || n.kind != sh::NodeKind::Simple || inReporterMessage( d ) )
            {
                continue;
            }
            std::vector<std::string> reads = callArgs( d );
            for( const sh::Redir& r : n.fredirs )
            {
                if( r.op == "<" )
                {
                    reads.push_back( normTarget( r.target ) );
                }
            }
            for( const std::string& t : reads )
            {
                if( t == target )
                {
                    return true;
                }
                if( scope_[d] == kNone || t.find( '$' ) == std::string::npos )
                {
                    continue;
                }
                for( std::uint32_t c : callsOf( scope_[d] ) )
                {
                    if( bindArgs( t, callArgs( c ) ) == target )
                    {
                        return true;
                    }
                }
            }
        }
        return false;
    }
    std::string captureName( std::uint32_t c ) const
    {
        const sh::Node&    n  = node( c );
        const std::string& tx = n.words.empty() ? n.assigns[0].text : n.words[1].text;
        return tx.substr( 0, tx.find( '=' ) );
    }
    bool isLocalIn( const std::string& name, std::uint32_t f ) const
    {
        return std::any_of( assigns_.begin(), assigns_.end(), [ & ]( const Assign& a ) { return a.scope == f && a.name == name && a.word >= 0; } )
            || std::any_of( t_.nodes.begin(), t_.nodes.end(), [ & ]( const sh::Node& n )
                            {
                                const std::size_t idx = static_cast<std::size_t>( &n - t_.nodes.data() );
                                return scope_[idx] == f && n.kind == sh::NodeKind::Simple && n.words.size() >= 2 && n.words[0].text == "local"
                                    && std::any_of( n.words.begin() + 1, n.words.end(), [ & ]( const sh::Word& w ) { return w.text == name; } );
                            } );
    }
    bool isLastOfFunc( std::uint32_t c, std::uint32_t f ) const
    {
        const sh::List* body = funcBody( f );
        if( body == nullptr || body->empty() )
        {
            return false;
        }
        const sh::List* inner = body;
        // `run(){ …; rc=$?; }`: the body is a group; its list's last statement
        if( inner->size() == 1 && ( *inner )[0].size() == 1 && ( *inner )[0][0].cmds.size() == 1 )
        {
            const sh::Node& g = node( ( *inner )[0][0].cmds[0] );
            if( ( g.kind == sh::NodeKind::Group || g.kind == sh::NodeKind::Subshell ) && !g.bodies.empty() && g.bodies[0] != kNone )
            {
                inner = &t_.lists[g.bodies[0]];
            }
        }
        if( inner->empty() )
        {
            return false;
        }
        const sh::AndOr& last = inner->back();
        return last.size() == 1 && last[0].cmds.size() == 1 && last[0].cmds[0] == c;
    }
    bool previousRuns( std::uint32_t cap ) const   // the statement before the capture runs something under test
    {
        for( const sh::Call& call : a_.calls )
        {
            if( call.node != kNone && call.node < a_.facts.size() && call.how.find( "=$? " ) != std::string::npos
                && call.how.rfind( captureName( cap ) + "=$?", 0 ) == 0 && scope_[call.node] == scope_[cap] && node( call.node ).pos < node( cap ).pos )
            {
                return true;
            }
        }
        for( std::uint32_t c = 0; c < a_.facts.size(); ++c )
        {
            if( a_.facts[c].seen && isRun( c ) && scope_[c] == scope_[cap] && node( c ).pos < node( cap ).pos && node( c ).line + 1 >= node( cap ).line
                && a_.facts[c].cons.how.rfind( captureName( cap ) + "=$?", 0 ) == 0 )
            {
                return true;
            }
        }
        return false;
    }
};

inline void Script::vacuousJudgmentSites( std::vector<std::uint32_t>& at ) const
{
    // (1) an assertion that passes on an empty text, read off a run whose failure nothing reports
    for( std::size_t ji = 0; ji < judgments_.size(); ++ji )
    {
        if( vacuous( ji ) )
        {
            at.push_back( judgments_[ji].pos );
        }
    }
}

inline void Script::lostReporterSites( std::vector<std::uint32_t>& at ) const
{
    // (2) a FAIL reporter that sets the failure flag, called inside a $( ) whose status nothing reads
    for( const auto& [ host, call ] : subCalls_ )
    {
        const std::uint32_t f = funcNode( cmdWord( call ) );
        if( f == kNone || call >= a_.facts.size() || !a_.facts[call].seen || a_.facts[call].cons.v == sh::Verdict::Checked || repOfCmd( call ) != Rep::None )
        {
            continue;
        }
        if( reportsByFlag( f, 0 ) )
        {
            at.push_back( node( host ).pos );
        }
    }
}

inline void Script::unreadRcSites( std::vector<std::uint32_t>& at ) const
{
    // (3) rc=$? captured and never tested before it is overwritten (B43's H2, per capture)
    for( std::uint32_t cap : captures_ )
    {
        const std::string   name  = captureName( cap );
        const std::uint32_t scope = scope_[cap];
        if( !previousRuns( cap ) )
        {
            continue;
        }
        const std::uint32_t pos = node( cap ).pos;
        if( scope != kNone && isLastOfFunc( cap, scope ) && !isLocalIn( name, scope ) )
        {
            // an rc-setter (run(){ …; rc=$?; }): each call site's window, until the next call of it or the next assignment
            const std::string fname = node( scope ).name;
            for( std::uint32_t c = 0; c < t_.nodes.size(); ++c )
            {
                if( node( c ).kind != sh::NodeKind::Simple || cmdWord( c ) != fname || scope_[c] == scope )
                {
                    continue;
                }
                std::uint32_t until = nextAssignPos( name, scope_[c], node( c ).pos );
                for( std::uint32_t d = 0; d < t_.nodes.size(); ++d )
                {
                    if( d != c && node( d ).kind == sh::NodeKind::Simple && scope_[d] == scope_[c] && node( d ).pos > node( c ).pos && cmdWord( d ) == fname )
                    {
                        until = std::min( until, node( d ).pos );
                    }
                }
                if( !rcTested( name, scope_[c], node( c ).pos, until, 0 ) )
                {
                    at.push_back( node( c ).pos );
                }
            }
            continue;
        }
        if( !rcTested( name, scope, pos, nextAssignPos( name, scope, pos, reachOf( cap ) ), 0 ) )
        {
            at.push_back( pos );
        }
    }
}

inline void Script::unreadRcFileSites( std::vector<std::uint32_t>& at ) const
{
    // (3b) `echo $? > "$TMP/$1.rc"` after a run: an rc FILE no command reads (per call site of the function that writes it)
    for( std::uint32_t c = 0; c < t_.nodes.size(); ++c )
    {
        const sh::Node& n = node( c );
        const std::string cw = cmdWord( c );
        if( n.kind != sh::NodeKind::Simple || ( cw != "echo" && cw != "printf" )
            || std::none_of( n.words.begin(), n.words.end(), []( const sh::Word& w ) { const std::string u = sh::detail::unq( w.text ); return u == "$?" || u == "${?}"; } ) )
        {
            continue;
        }
        std::string target;
        for( const sh::Redir& r : n.fredirs )
        {
            if( isStdoutRedir( r ) && !r.target.empty() && r.target != "/dev/null" && r.target[0] != '&' )
            {
                target = normTarget( r.target );
            }
        }
        const std::uint32_t scope = scope_[c];
        const bool afterRun = std::any_of( a_.calls.begin(), a_.calls.end(), [ & ]( const sh::Call& call )
                                           { return call.node != kNone && scope_[call.node] == scope && call.how.rfind( "rc file", 0 ) == 0 && node( call.node ).pos < n.pos; } )
                           || [ & ]
                              {
                                  for( std::uint32_t d = 0; d < a_.facts.size(); ++d )
                                  {
                                      if( a_.facts[d].seen && scope_[d] == scope && node( d ).pos < n.pos && isRun( d ) && a_.facts[d].cons.how.rfind( "rc file", 0 ) == 0 )
                                      {
                                          return true;
                                      }
                                  }
                                  return false;
                              }();
        if( target.empty() || !afterRun )
        {
            continue;
        }
        if( scope != kNone && target.find( '$' ) != std::string::npos )
        {
            for( std::uint32_t call : callsOf( scope ) )
            {
                const std::string bound = bindArgs( target, callArgs( call ) );
                if( !bound.empty() && bound != target && !fileRead( bound, c ) )
                {
                    at.push_back( node( call ).pos );
                }
            }
            continue;
        }
        if( !fileRead( target, c ) )
        {
            at.push_back( n.pos );
        }
    }
}

inline void Script::deadFallbackSites( std::vector<std::uint32_t>& at ) const
{
    // (4) `RUN | head -1 || fallback`: the || reads the last stage's status, which always succeeds
    for( std::size_t q = 0; q < andOrs_.size(); ++q )
    {
        const sh::AndOr& ao = *andOrs_[q];
        for( std::size_t j = 0; j + 1 < ao.size(); ++j )
        {
            const sh::Item& it = ao[j];
            if( ao[j + 1].op != sh::Link::Or || it.cmds.size() < 2 || it.neg )
            {
                continue;
            }
            const std::uint32_t last = it.cmds.back();
            const std::string   lw   = cmdWord( last );
            static constexpr std::string_view kAlways[] = { "head", "tail", "tr", "cut", "sort", "uniq", "wc", "cat", "tee", "rev", "paste", "column" };
            if( last >= a_.facts.size() || a_.facts[last].pipefail || std::find( std::begin( kAlways ), std::end( kAlways ), lw ) == std::end( kAlways ) )
            {
                continue;
            }
            const bool reads = std::any_of( it.cmds.begin(), it.cmds.end() - 1, [ & ]( std::uint32_t c ) { return isRun( c ) || cmdWord( c ) == "grep"; } );
            sh::AndOr  rhs{ ao[j + 1] };
            if( reads && !sh::detail::isTrivialOr( sh::detail::itemsText( t_, rhs ) ) )
            {
                at.push_back( posOf( ao ) );
            }
        }
    }
}

inline std::vector<Site> Script::sites() const
{
    std::vector<std::uint32_t> at;   // the byte each site's statement starts at, shape by shape
    vacuousJudgmentSites( at );
    lostReporterSites( at );
    unreadRcSites( at );
    unreadRcFileSites( at );
    deadFallbackSites( at );
    std::vector<Site> out;
    for( const std::uint32_t pos : at )
    {
        const ShLine l    = shSiteLine( src_, pos );
        std::string  text = collapseSpaces( l.text );
        if( !text.empty() )
        {
            out.push_back( { Facet::VacuousAssert, l.startByte, std::move( text ) } );
        }
    }
    std::sort( out.begin(), out.end(), []( const Site& a, const Site& b ) { return a.startByte != b.startByte ? a.startByte < b.startByte : a.text < b.text; } );
    out.erase( std::unique( out.begin(), out.end(), []( const Site& a, const Site& b ) { return a.startByte == b.startByte && a.text == b.text; } ), out.end() );
    return out;
}

}   // namespace va

inline std::vector<Site> scanVacuousAssertBash( std::string_view src, const std::vector<Span>& /*spans*/ )
{
    if( src.empty() )
    {
        return {};
    }
    const rw::shstatus::Tree     tree = rw::shstatus::parse( src );
    const rw::shstatus::Analysis an   = rw::shstatus::analyze( tree, src );
    const va::Script             script( src, tree, an );
    return script.sites();
}

}   // namespace detail

// ─── the per-language entry points ──────────────────────────────────────────────────────────────────────

// C++: format-arity over the whole file; utf8-cut and dedup-first inside each function span. A site found
// in nested spans is reported once (the scan of each span is independent; the caller anchors by byte).
// `treeMacros`: the macro names the index holds across the tree (sorted, unique), for format-arity's F1 skip.
inline std::vector<Site> scanCpp( std::string_view src, const std::vector<Span>& fnSpans, const std::vector<std::string>* treeMacros = nullptr )
{
    std::vector<Site>              out;
    detail::CppPreproc             pp;
    const std::vector<detail::Tok> toks = detail::lexCpp( src, &pp );
    detail::scanFormatArityCpp( src, toks, pp, treeMacros, out );
    for( const Span& sp : fnSpans )
    {
        const auto first = std::lower_bound( toks.begin(), toks.end(), sp.begin, []( const detail::Tok& t, std::uint32_t b ) { return t.begin < b; } );
        const auto last  = std::lower_bound( toks.begin(), toks.end(), sp.end, []( const detail::Tok& t, std::uint32_t b ) { return t.begin < b; } );
        const std::size_t from = static_cast<std::size_t>( first - toks.begin() );
        const std::size_t to   = static_cast<std::size_t>( last - toks.begin() );
        if( from >= to )
        {
            continue;
        }
        detail::scanUtf8CutFunction( src, toks, from, to, out );
        detail::scanDedupFirstFunction( src, toks, from, to, out );
    }
    std::sort( out.begin(), out.end(), []( const Site& a, const Site& b ) { return a.startByte != b.startByte ? a.startByte < b.startByte : a.text < b.text; } );
    out.erase( std::unique( out.begin(), out.end(), []( const Site& a, const Site& b ) { return a.facet == b.facet && a.startByte == b.startByte && a.text == b.text; } ),
               out.end() );
    return out;
}

inline std::vector<Site> scanPython( std::string_view src )
{
    std::vector<Site> out;
    detail::scanFormatArityPython( src, detail::lexPython( src ), out );
    return out;
}

// Bash, for a test-script path only (the caller decides the path): `fnSpans` are the script's function
// definitions, the scopes a capture and its guards are matched in.
inline std::vector<Site> scanBashTestScript( std::string_view src, const std::vector<Span>& fnSpans )
{
    return detail::scanVacuousAssertBash( src, fnSpans );
}

// A cheap byte prefilter: can this C++ file hold any of the three C++ shapes at all?
inline bool cppMayHoldShapes( std::string_view src ) noexcept
{
    static constexpr std::array<std::string_view, 7> kNeedles = { "format", "print", "emitTo", "unique", "...", "\xE2\x80\xA6", "u2026" };
    // "format" also covers formatTo; the escaped ellipsis "\xE2\x80\xA6" is found through its "xE2" bytes below
    return std::any_of( kNeedles.begin(), kNeedles.end(), [ & ]( std::string_view n ) { return src.find( n ) != std::string_view::npos; } )
        || src.find( "xE2" ) != std::string_view::npos;
}

}   // namespace rw::defectshape
