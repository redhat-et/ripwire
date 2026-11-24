#pragma once

// defectshape.h — the scanners behind --quality-delta's defect-shape kind: six shapes of a REAL defect that
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
//   unchecked-status C/C++: a call whose return IS an I/O or child status — pclose, rename, write, system,
//                   fflush, fclose on a stream this function wrote, close on a descriptor it wrote, waitpid
//                   with the child's status dropped too — made as a whole statement, so the status reaches
//                   nothing ((void) is a stated decision: no site). Python: subprocess.run with no check=,
//                   subprocess.call and os.system, as a whole statement or bound to a name no later line
//                   reads, and subprocess.run( ... ).stdout / .stderr (the output read, the status not).
//   unhandled-arm   a classifier over a closed set that gives a value it does not name no outcome: a C/C++ switch
//                   with no default: over an in-tree enum that leaves an enumerator out, a shell case with no *) arm
//                   whose result is read, a Python if/elif chain or match that ends a value-returning function with
//                   no else (an unmatched value returns None). The site's why= names what is left out.
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
#include <iterator>
#include <optional>
#include <utility>
#include <span>
#include <system_error>

#include <cctype>

#include "infra/Diagnostics.h"
#include "infra/enumcount.h"    // enumCountIsExact — kPyStatusDisplay has one row per PyStatus value
#include "infra/namesplit.h"   // the ONE ASCII identifier-character pair and the quote-pair strip
#include "infra/sortutil.h"    // svLess: the string_view order a comparator lambda may use (portablebuildcheck #6c)
#include "infra/tablelookup.h"  // findByField: an assignment by its node
#include "shstatus.h"          // vacuous-assert: the B43 exit-status matcher (one matcher, common code)

namespace rw::defectshape
{

enum class Facet : std::uint8_t
{
    FormatArity     = 0,
    Utf8Cut         = 1,
    DedupFirst      = 2,
    VacuousAssert   = 3,
    UncheckedStatus = 4,
    UnhandledArm    = 5,
};
inline constexpr std::size_t kFacetCount = 6;
inline constexpr std::array<std::string_view, kFacetCount> kFacetNames = { "format-arity", "utf8-cut", "dedup-first", "vacuous-assert", "unchecked-status",
                                                                           "unhandled-arm" };

inline constexpr std::string_view facetName( Facet f ) noexcept
{
    return kFacetNames[ static_cast<std::size_t>( f ) ];
}

// The one facet whose rows gate, on ANY origin: a placeholder/argument mismatch on a literal format has no
// legitimate intent (an argument the format never prints is dropped output; a field with no argument is a
// compile error or a run-time exception), so it is a defect, not debt. The others are report-only.
inline constexpr bool facetGatesOnAnyOrigin( Facet f ) noexcept
{
    return f == Facet::FormatArity;
}

// The facets whose row names its SITE (p= the site's line, plus call= / why=), not the enclosing definition: one bit
// per facet.
inline constexpr unsigned kSiteFacetBits = ( 1u << static_cast<unsigned>( Facet::UncheckedStatus ) ) | ( 1u << static_cast<unsigned>( Facet::UnhandledArm ) );
inline constexpr bool facetNamesSite( Facet f ) noexcept
{
    return ( ( kSiteFacetBits >> static_cast<unsigned>( f ) ) & 1u ) != 0;
}

struct Site
{
    Facet            facet     = Facet::FormatArity;
    std::uint32_t    startByte = 0;
    std::string      text;
    std::string_view call;   // unchecked-status: the call whose status is dropped (a static spelling); empty otherwise
    std::string      why;    // unhandled-arm: the values the classifier leaves without an outcome; empty otherwise
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
        rw::sortutil::sortUnique( pp->macros );
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
    void visit( std::uint32_t list, std::uint32_t scope, const std::vector<Judgment::Reach>& reach )
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
        rw::sortutil::sortUnique( leaves );
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
        const auto ranRcFileBefore = [ & ]   // a run node before this one, in its scope, that ran an rc file
        {
            for( std::uint32_t d = 0; d < a_.facts.size(); ++d )
            {
                if( a_.facts[d].seen && scope_[d] == scope && node( d ).pos < n.pos && isRun( d ) && a_.facts[d].cons.how.rfind( "rc file", 0 ) == 0 )
                {
                    return true;
                }
            }
            return false;
        };
        const bool afterRun = std::any_of( a_.calls.begin(), a_.calls.end(), [ & ]( const sh::Call& call )
                                           { return call.node != kNone && scope_[call.node] == scope && call.how.rfind( "rc file", 0 ) == 0 && node( call.node ).pos < n.pos; } )
                           || ranRcFileBefore();
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

// One shell parse for a Bash facet scan; `cut` (optional) is set when the nesting budget (shstatus kMaxShellNest) stopped it,
// so the sites past that point were not judged.
inline rw::shstatus::Tree parseShellScan( std::string_view src, bool* cut )
{
    rw::shstatus::Tree tree = rw::shstatus::parse( src );
    if( cut != nullptr )
    {
        *cut = *cut || tree.cut;
    }
    return tree;
}

inline std::vector<Site> scanVacuousAssertBash( std::string_view src, const std::vector<Span>& /*spans*/, bool* cut = nullptr )
{
    if( src.empty() )
    {
        return {};
    }
    const rw::shstatus::Tree tree = parseShellScan( src, cut );
    if( tree.cut )
    {
        // CR721: a guard PAST the cut (a presence test after the absence assertion it protects) is invisible to the prefix,
        // so the prefix alone would call that assertion vacuous. A cut tree is not judged; shell_cut= already says so.
        return {};
    }
    const rw::shstatus::Analysis an = rw::shstatus::analyze( tree, src );
    const va::Script             script( src, tree, an );
    return script.sites();
}

// ─── unchecked-status, C/C++ and Python ─────────────────────────────────────────────────────────────────
//
// A call whose return value IS the status of an I/O or child operation, made where that value reaches nothing:
// a failed write, rename, flush or close, or a child that exited non-zero, reads exactly like success. The shape
// is a DATAFLOW fact about one value, decided from tokens: the call is the whole expression statement (C/C++,
// Python), or (Python) it is bound to a name no later token of the function reads, or only its output is read.
// An explicit `(void)` cast and a `_ =` binding are stated decisions, not this shape. A call wrapped in a macro
// or a helper is an argument, not a statement, so it is never judged (the helper's own `return close( fd );`
// hands the status on).

enum class StatusNeed : std::uint8_t
{
    Always,          // the return is the only report of the failure
    WrittenStream,   // fclose: only on a stream this function wrote (closing a read stream loses nothing)
    WrittenFd,       // close: only on a descriptor this function wrote
    ChildStatus,     // waitpid: only when the child's status is dropped too (a null status, or one never read)
};

struct StatusCall
{
    std::string_view name;
    std::size_t      arity;   // the libc arity: a same-named project function of another arity is not this call
    StatusNeed       need;
};

inline constexpr std::array<StatusCall, 8> kCStatusCalls = { {
    { "pclose", 1, StatusNeed::Always },        { "fclose", 1, StatusNeed::WrittenStream }, { "rename", 2, StatusNeed::Always },
    { "write", 3, StatusNeed::Always },         { "waitpid", 3, StatusNeed::ChildStatus },  { "system", 1, StatusNeed::Always },
    { "fflush", 1, StatusNeed::Always },        { "close", 1, StatusNeed::WrittenFd },
} };

// The calls whose arguments name a stream or a descriptor this function WROTE.
// (emitTo / emitRaw / print: the std::print family and ripwire's own rw::emitTo, which take the FILE* first.)
inline constexpr std::array<std::string_view, 14> kStreamWriters = { "fprintf", "vfprintf", "fputs", "fputc", "putc", "fwrite", "fflush", "fputws",
                                                                     "fwprintf", "putwc", "print", "println", "emitTo", "emitRaw" };
inline constexpr std::array<std::string_view, 9>  kFdWriters     = { "write", "pwrite", "writev", "pwritev", "send", "sendto", "sendmsg", "dprintf", "ftruncate" };

// The '(' that the ')' at `close` closes (round brackets only), or toks.size().
inline std::size_t matchOpenParen( std::string_view src, const std::vector<Tok>& toks, std::size_t close ) noexcept
{
    int depth = 0;
    for( std::size_t k = close + 1; k-- > 0; )
    {
        depth += tokIs( src, toks[k], ")" ) ? 1 : tokIs( src, toks[k], "(" ) ? -1 : 0;
        if( depth == 0 )
        {
            return k;
        }
    }
    return toks.size();
}

inline bool isStmtBoundary( std::string_view src, const Tok& t ) noexcept
{
    return tokIs( src, t, ";" ) || tokIs( src, t, "{" ) || tokIs( src, t, "}" );
}

// Does the ':' at `colon` end a label (`name:`, `default:`, `case X:`), not a ternary's or an initializer's?
inline bool cppLabelEndsAt( std::string_view src, const std::vector<Tok>& toks, std::size_t colon ) noexcept
{
    std::size_t b = colon;
    while( b > 0 && !isStmtBoundary( src, toks[b - 1] ) )
    {
        --b;
    }
    if( b == colon )
    {
        return false;
    }
    if( tokIs( src, toks[b], "case" ) )
    {
        return std::none_of( toks.begin() + static_cast<std::ptrdiff_t>( b ), toks.begin() + static_cast<std::ptrdiff_t>( colon ),
                             [ & ]( const Tok& t ) { return tokIs( src, t, "?" ); } );
    }
    return colon - b == 1 && toks[b].kind == TokKind::Ident;
}

// Does a C/C++ expression statement start at token `k`? After `;`, a brace, `else`, `do`, a label, or the
// closing parenthesis of an if / while / for head. Any other ')' — a `(void)` cast above all — is not.
inline bool cppStatementStartsAt( std::string_view src, const std::vector<Tok>& toks, std::size_t k ) noexcept
{
    if( k == 0 )
    {
        return true;
    }
    const Tok& p = toks[k - 1];
    if( isStmtBoundary( src, p ) || tokIs( src, p, "else" ) || tokIs( src, p, "do" ) )
    {
        return true;
    }
    if( tokIs( src, p, ")" ) )
    {
        const std::size_t open = matchOpenParen( src, toks, k - 1 );
        return open > 0 && open < toks.size() && ( tokIs( src, toks[open - 1], "if" ) || tokIs( src, toks[open - 1], "while" ) || tokIs( src, toks[open - 1], "for" ) );
    }
    return tokIs( src, p, ":" ) && cppLabelEndsAt( src, toks, k - 1 );
}

// The status call named at token `k` (`name (`, `::name (`, `std::name (`, or an OS shim's `os::name (` /
// `rw::os::name (`, the thin libc layer a portable tree calls through), with `head` set to the first token of its
// spelling; nullptr for a member call, another namespace's or class's function, or no such name.
inline const StatusCall* cStatusCallAt( std::string_view src, const std::vector<Tok>& toks, std::size_t k, std::size_t& head ) noexcept
{
    if( toks[k].kind != TokKind::Ident || k + 1 >= toks.size() || !tokIs( src, toks[k + 1], "(" ) )
    {
        return nullptr;
    }
    const StatusCall* call = rw::findByField( kCStatusCalls, &StatusCall::name, tokText( src, toks[k] ) );
    head                   = k;
    if( call == nullptr || k == 0 )
    {
        return call;
    }
    if( tokIs( src, toks[k - 1], "." ) || tokIs( src, toks[k - 1], "->" ) )
    {
        return nullptr;   // obj.close(), stream->write( … ): a method
    }
    if( !tokIs( src, toks[k - 1], "::" ) )
    {
        return call;
    }
    if( k >= 2 && toks[k - 2].kind == TokKind::Ident && !tokIs( src, toks[k - 2], "std" ) && !tokIs( src, toks[k - 2], "os" ) )
    {
        return nullptr;   // ns::close( … ), Class::write( … ): not libc's
    }
    while( head >= 2 && tokIs( src, toks[head - 1], "::" ) && toks[head - 2].kind == TokKind::Ident )
    {
        head -= 2;   // rw::os::close: the spelling starts at its first qualifier
    }
    head -= ( head >= 1 && tokIs( src, toks[head - 1], "::" ) ) ? 1 : 0;   // ::close, ::std::fclose
    return call;
}

// Does a call to one of `writers` in tokens [from, to) take `arg` (normalized text) as a whole argument?
template<std::size_t N>
inline bool writtenThrough( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t to, const std::string& arg,
                            const std::array<std::string_view, N>& writers )
{
    for( std::size_t k = from; k + 1 < to; ++k )
    {
        if( toks[k].kind != TokKind::Ident || !tokIs( src, toks[k + 1], "(" ) || !rw::inSet( writers, tokText( src, toks[k] ) ) )
        {
            continue;
        }
        const std::size_t close = matchClose( src, toks, k + 1 );
        if( close >= to )
        {
            continue;
        }
        const std::vector<ArgRange> args = splitArgs( src, toks, k + 1, close );
        if( std::any_of( args.begin(), args.end(), [ & ]( const ArgRange& a ) { return !a.empty() && joinTokens( src, toks, a.first, a.last ) == arg; } ) )
        {
            return true;
        }
    }
    return false;
}

// Is `name` assigned, in tokens [from, to), from an fopen / fdopen whose mode literal writes ("w", "a", "+")? A
// written FILE*'s fclose flushes its buffer, whatever wrote into it. (An open(2) flag is not evidence: a lock file
// or /dev/null is opened for writing and never written.)
inline bool fopenedForWrite( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t to, std::string_view name )
{
    for( std::size_t k = from + 2; k + 1 < to; ++k )
    {
        const std::size_t eq = ( tokIs( src, toks[k - 1], "::" ) && k >= from + 4 && tokIs( src, toks[k - 2], "std" ) ) ? k - 3 : k - 1;
        const bool opens = tokIs( src, toks[k], "fopen" ) || tokIs( src, toks[k], "fdopen" );
        if( !opens || !tokIs( src, toks[k + 1], "(" ) || eq == 0 || !tokIs( src, toks[eq], "=" ) || !tokIs( src, toks[eq - 1], name ) )
        {
            continue;
        }
        const std::size_t close = matchClose( src, toks, k + 1 );
        if( close < to && toks[close - 1].kind == TokKind::String && tokContent( src, toks[close - 1] ).find_first_of( "wa+" ) != std::string_view::npos )
        {
            return true;
        }
    }
    return false;
}

// The '{' that opens the innermost block holding token `k` within [from, k), or `from` when there is none.
inline std::size_t enclosingBlockOpen( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t k ) noexcept
{
    int depth = 0;
    for( std::size_t j = k; j-- > from; )
    {
        depth += tokIs( src, toks[j], "}" ) ? 1 : 0;
        if( tokIs( src, toks[j], "{" ) && depth-- == 0 )
        {
            return j;
        }
    }
    return from;
}

// Is the statement at `head` the branch of an `if` whose condition already tested a write through one of
// `writers` — `if( fwrite( … ) != n ) { fclose( f ); return; }` — so the failure is reported and the close is
// cleanup? Braced and braceless branches both.
template<std::size_t N>
inline bool inWriteFailureBranch( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t head,
                                  const std::array<std::string_view, N>& writers )
{
    if( head <= from )
    {
        return false;
    }
    const std::size_t open  = enclosingBlockOpen( src, toks, from, head );
    const std::size_t close = tokIs( src, toks[head - 1], ")" ) ? head - 1 : ( open > from && tokIs( src, toks[open - 1], ")" ) ) ? open - 1 : 0;
    if( close == 0 )
    {
        return false;
    }
    const std::size_t cond = matchOpenParen( src, toks, close );
    if( cond == 0 || cond >= toks.size() || !tokIs( src, toks[cond - 1], "if" ) )
    {
        return false;
    }
    return std::any_of( toks.begin() + static_cast<std::ptrdiff_t>( cond ), toks.begin() + static_cast<std::ptrdiff_t>( close ),
                        [ & ]( const Tok& t ) { return t.kind == TokKind::Ident && rw::inSet( writers, tokText( src, t ) ); } );
}

// waitpid( pid, STATUS, options ): is the child's status dropped too — STATUS a null pointer, or the address of a
// name no token after the call (to `to`) reads?
inline bool childStatusDropped( std::string_view src, const std::vector<Tok>& toks, const ArgRange& status, std::size_t close, std::size_t to )
{
    if( status.first == status.last )
    {
        const std::string_view w = tokText( src, toks[status.first] );
        return w == "NULL" || w == "nullptr" || w == "0";
    }
    if( status.last != status.first + 1 || !tokIs( src, toks[status.first], "&" ) || toks[status.last].kind != TokKind::Ident )
    {
        return false;
    }
    const std::string_view name = tokText( src, toks[status.last] );
    return std::none_of( toks.begin() + static_cast<std::ptrdiff_t>( close ), toks.begin() + static_cast<std::ptrdiff_t>( to ),
                         [ & ]( const Tok& t ) { return tokIs( src, t, name ); } );
}

// Does this discarded call lose a status that matters? `head` is the call's first token, [from, to) its function.
inline bool cStatusMatters( std::string_view src, const std::vector<Tok>& toks, const StatusCall& call, const std::vector<ArgRange>& args, std::size_t from,
                            std::size_t head, std::size_t close, std::size_t to )
{
    const std::string arg0 = joinTokens( src, toks, args[0].first, args[0].last );
    const bool        name = args[0].first == args[0].last && toks[args[0].first].kind == TokKind::Ident;
    switch( call.need )
    {
        case StatusNeed::Always:   // a flush of the standard streams is not judged: stderr has nowhere left to report, and a
                                   // CLI's stdout flush is a progress point whose failure the exit path sees
            return !( call.name == "fflush" && ( arg0 == "stderr" || arg0 == "stdout" ) );
        case StatusNeed::WrittenStream:   // the cleanup close inside `if( fwrite( … ) != n ) { … }` follows a failure already seen
            return ( writtenThrough( src, toks, from, head, arg0, kStreamWriters ) || ( name && fopenedForWrite( src, toks, from, head, arg0 ) ) )
                && !inWriteFailureBranch( src, toks, from, head, kStreamWriters );
        case StatusNeed::WrittenFd:
            return writtenThrough( src, toks, from, head, arg0, kFdWriters ) && !inWriteFailureBranch( src, toks, from, head, kFdWriters );
        case StatusNeed::ChildStatus:
            return childStatusDropped( src, toks, args[1], close, to );
    }
    return false;
}

// One function's tokens [from, to): every discarded status call in it.
inline void scanUncheckedStatusCpp( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t to, std::vector<Site>& out )
{
    for( std::size_t k = from; k + 1 < to; ++k )
    {
        std::size_t             head = k;
        const StatusCall* const call = cStatusCallAt( src, toks, k, head );
        if( call == nullptr || head < from || !cppStatementStartsAt( src, toks, head ) )
        {
            continue;
        }
        const std::size_t close = matchClose( src, toks, k + 1 );
        if( close + 1 >= to || !tokIs( src, toks[close + 1], ";" ) )
        {
            continue;   // the value feeds an operator, a comma or a cast: read, or not decidable here
        }
        const std::vector<ArgRange> args = splitArgs( src, toks, k + 1, close );
        if( args.size() == call->arity && cStatusMatters( src, toks, *call, args, from, head, close, to ) )
        {
            out.push_back( { Facet::UncheckedStatus, toks[head].begin, joinTokens( src, toks, head, close ), call->name } );
        }
    }
}

// ── Python ──

enum class PyStatus : std::uint8_t
{
    None,
    Run,      // subprocess.run: a CompletedProcess whose returncode is the status; check= raises instead
    Call,     // subprocess.call: the exit code itself
    System,   // os.system: the wait status itself
};

struct PyStatusName
{
    std::string_view name;
    PyStatus         call;
};

inline constexpr std::size_t kPyStatusCount = 4;
static_assert( enumCountIsExact<PyStatus, kPyStatusCount>(), "kPyStatusCount must equal the PyStatus count — raise it with the append" );
inline constexpr std::array kPyStatusDisplay = { std::string_view{}, std::string_view{ "subprocess.run" }, std::string_view{ "subprocess.call" },
                                                 std::string_view{ "os.system" } };   // indexed by PyStatus
static_assert( kPyStatusDisplay.size() == kPyStatusCount, "one kPyStatusDisplay row per PyStatus value (the extent is deduced from the rows)" );

// The spellings this file reaches the three calls by: the modules (`subprocess`, `os`, or an `import … as X`
// alias) and the bare names a `from subprocess import run [as r]` / `from os import system` binds.
struct PyStatusNames
{
    std::vector<std::string_view> subprocessMods = { "subprocess" };
    std::vector<std::string_view> osMods         = { "os" };
    std::vector<PyStatusName>     bare;
};

inline PyStatus pyMemberStatus( std::string_view module, std::string_view member ) noexcept
{
    if( module == "subprocess" )
    {
        return member == "run" ? PyStatus::Run : member == "call" ? PyStatus::Call : PyStatus::None;
    }
    return module == "os" && member == "system" ? PyStatus::System : PyStatus::None;
}

// The names one `from M import a [as b], …` line (tokens from `k`, at `import`) binds to a status call of M.
inline void pyFromImports( std::string_view src, const std::vector<Tok>& toks, std::size_t k, std::string_view module, PyStatusNames& names )
{
    for( std::size_t j = k + 1; j < toks.size() && !tokIs( src, toks[j], "\n" ) && !tokIs( src, toks[j], ";" ); ++j )
    {
        const PyStatus call = toks[j].kind == TokKind::Ident ? pyMemberStatus( module, tokText( src, toks[j] ) ) : PyStatus::None;
        if( call == PyStatus::None )
        {
            continue;
        }
        const bool aliased = j + 2 < toks.size() && tokIs( src, toks[j + 1], "as" ) && toks[j + 2].kind == TokKind::Ident;
        names.bare.push_back( { tokText( src, toks[aliased ? j + 2 : j] ), call } );
        j += aliased ? 2 : 0;
    }
}

inline PyStatusNames pyStatusNames( std::string_view src, const std::vector<Tok>& toks )
{
    PyStatusNames names;
    for( std::size_t k = 0; k + 3 < toks.size(); ++k )
    {
        const bool lineStart = k == 0 || tokIs( src, toks[k - 1], "\n" ) || tokIs( src, toks[k - 1], ";" );
        if( !lineStart )
        {
            continue;
        }
        const std::string_view m = tokText( src, toks[k + 1] );
        if( tokIs( src, toks[k], "import" ) && ( m == "subprocess" || m == "os" ) && tokIs( src, toks[k + 2], "as" ) )
        {
            ( m == "os" ? names.osMods : names.subprocessMods ).push_back( tokText( src, toks[k + 3] ) );
        }
        else if( tokIs( src, toks[k], "from" ) && ( m == "subprocess" || m == "os" ) && tokIs( src, toks[k + 2], "import" ) )
        {
            pyFromImports( src, toks, k + 2, m, names );
        }
    }
    return names;
}

// The status call spelled at token `k` (`MOD.run (`, `MOD.system (`, or a bare imported name), with `open` set
// to its '(' — PyStatus::None for anything else, an attribute of another object included.
inline PyStatus pyStatusCallAt( std::string_view src, const std::vector<Tok>& toks, const PyStatusNames& names, std::size_t k, std::size_t& open ) noexcept
{
    if( toks[k].kind != TokKind::Ident || ( k > 0 && ( tokIs( src, toks[k - 1], "." ) || tokIs( src, toks[k - 1], "def" ) ) ) )
    {
        return PyStatus::None;
    }
    const std::string_view w = tokText( src, toks[k] );
    if( k + 1 < toks.size() && tokIs( src, toks[k + 1], "(" ) )
    {
        const PyStatusName* hit = rw::findByField( names.bare, &PyStatusName::name, w );
        open                    = k + 1;
        return hit != nullptr ? hit->call : PyStatus::None;
    }
    if( k + 3 >= toks.size() || !tokIs( src, toks[k + 1], "." ) || !tokIs( src, toks[k + 3], "(" ) )
    {
        return PyStatus::None;
    }
    open                         = k + 3;
    const std::string_view member = tokText( src, toks[k + 2] );
    const bool isSub = std::find( names.subprocessMods.begin(), names.subprocessMods.end(), w ) != names.subprocessMods.end();
    const bool isOs  = std::find( names.osMods.begin(), names.osMods.end(), w ) != names.osMods.end();
    return isSub ? pyMemberStatus( "subprocess", member ) : isOs ? pyMemberStatus( "os", member ) : PyStatus::None;
}

// Does a Python statement start at token `k`? After a logical line's end or `;`, or after the ':' of a one-line
// compound statement (`if x: f()`), never a lambda's.
inline bool pyStatementStartsAt( std::string_view src, const std::vector<Tok>& toks, std::size_t k ) noexcept
{
    if( k == 0 || tokIs( src, toks[k - 1], "\n" ) || tokIs( src, toks[k - 1], ";" ) )
    {
        return true;
    }
    if( !tokIs( src, toks[k - 1], ":" ) )
    {
        return false;
    }
    std::size_t b = k - 1;
    while( b > 0 && !tokIs( src, toks[b - 1], "\n" ) )
    {
        --b;
    }
    static constexpr std::array<std::string_view, 9> kCompound = { "if", "elif", "else", "for", "while", "with", "try", "except", "finally" };
    const bool lambda = std::any_of( toks.begin() + static_cast<std::ptrdiff_t>( b ), toks.begin() + static_cast<std::ptrdiff_t>( k ),
                                     [ & ]( const Tok& t ) { return tokIs( src, t, "lambda" ); } );
    return rw::inSet( kCompound, tokText( src, toks[b] ) ) && !lambda;
}

inline bool pyStatementEndsAt( std::string_view src, const std::vector<Tok>& toks, std::size_t k ) noexcept
{
    return k >= toks.size() || tokIs( src, toks[k], "\n" ) || tokIs( src, toks[k], ";" );
}

// A `check=` keyword (any value: check=False is a stated decision) or a `**kwargs` that may carry one.
inline bool pyCallStatesCheck( std::string_view src, const std::vector<Tok>& toks, std::size_t open, std::size_t close )
{
    const std::vector<ArgRange> args = splitArgs( src, toks, open, close );
    return std::any_of( args.begin(), args.end(), [ & ]( const ArgRange& a )
                        { return !a.empty() && ( tokIs( src, toks[a.first], "**" ) || ( tokIs( src, toks[a.first], "check" ) && a.first < a.last && tokIs( src, toks[a.first + 1], "=" ) ) ); } );
}

// Is the attribute at `dot` (a '.' token) one that reads a CompletedProcess's output, never its status?
inline bool pyOutputAttrAt( std::string_view src, const std::vector<Tok>& toks, std::size_t dot ) noexcept
{
    return dot + 1 < toks.size() && tokIs( src, toks[dot], "." )
        && ( tokIs( src, toks[dot + 1], "stdout" ) || tokIs( src, toks[dot + 1], "stderr" ) || tokIs( src, toks[dot + 1], "args" ) );
}

// `name` bound to the call's result at the statement ending at `from`: does no token in [from, to) read its
// status — every later use (until a rebinding) an output attribute of a subprocess.run result, or none at all?
inline bool pyNameStatusUnread( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t to, std::string_view name, PyStatus call )
{
    for( std::size_t k = from; k < to; ++k )
    {
        if( !tokIs( src, toks[k], name ) || tokIs( src, toks[k - 1], "." ) )
        {
            continue;
        }
        if( call == PyStatus::Run && pyOutputAttrAt( src, toks, k + 1 ) )
        {
            continue;
        }
        return pyStatementStartsAt( src, toks, k ) && k + 1 < to && tokIs( src, toks[k + 1], "=" );   // rebound before any read, or read
    }
    return true;
}

// The token index one past the innermost definition span holding byte `at` (toks.size() at top level).
inline std::size_t pyScopeEnd( const std::vector<Tok>& toks, const std::vector<Span>& fnSpans, std::uint32_t at )
{
    std::uint32_t end = UINT32_MAX;
    for( const Span& sp : fnSpans )
    {
        if( sp.begin <= at && at < sp.end && sp.end < end )
        {
            end = sp.end;
        }
    }
    const auto it = std::lower_bound( toks.begin(), toks.end(), end, []( const Tok& t, std::uint32_t b ) { return t.begin < b; } );
    return static_cast<std::size_t>( it - toks.begin() );
}

// Is the status of the call at [k, close] dropped — the whole statement, `.stdout`/`.stderr` read off a
// subprocess.run, or `name = call` with the name never read for its status? Sets the site text's first and last
// token when it is.
inline bool pyStatusSiteAt( std::string_view src, const std::vector<Tok>& toks, const std::vector<Span>& fnSpans, PyStatus call, std::size_t k, std::size_t close,
                            std::size_t& first, std::size_t& last )
{
    first = k;
    last  = close;
    if( pyStatementStartsAt( src, toks, k ) && pyStatementEndsAt( src, toks, close + 1 ) )
    {
        return true;
    }
    if( call == PyStatus::Run && pyOutputAttrAt( src, toks, close + 1 ) && !tokIs( src, toks[close + 2], "args" ) )
    {
        last = close + 2;
        return true;
    }
    const bool bound = k >= 2 && tokIs( src, toks[k - 1], "=" ) && toks[k - 2].kind == TokKind::Ident && !tokIs( src, toks[k - 2], "_" )
                    && pyStatementStartsAt( src, toks, k - 2 ) && pyStatementEndsAt( src, toks, close + 1 );
    if( !bound )
    {
        return false;
    }
    first = k - 2;
    return pyNameStatusUnread( src, toks, close + 1, pyScopeEnd( toks, fnSpans, toks[k].begin ), tokText( src, toks[k - 2] ), call );
}

inline void scanUncheckedStatusPython( std::string_view src, const std::vector<Tok>& toks, const std::vector<Span>& fnSpans, std::vector<Site>& out )
{
    const PyStatusNames names = pyStatusNames( src, toks );
    for( std::size_t k = 0; k + 1 < toks.size(); ++k )
    {
        std::size_t    open = 0;
        const PyStatus call = pyStatusCallAt( src, toks, names, k, open );
        if( call == PyStatus::None )
        {
            continue;
        }
        const std::size_t close = matchClose( src, toks, open );
        std::size_t       first = k;
        std::size_t       last  = close;
        if( close < toks.size() && !pyCallStatesCheck( src, toks, open, close ) && pyStatusSiteAt( src, toks, fnSpans, call, k, close, first, last ) )
        {
            out.push_back( { Facet::UncheckedStatus, toks[first].begin, joinTokens( src, toks, first, last ), kPyStatusDisplay[ static_cast<std::size_t>( call ) ] } );
        }
    }
}

// ─── unhandled-arm, C/C++, Python and shell ─────────────────────────────────────────────────────────────
//
// A classifier — a switch, a case, an if/elif chain or a match that maps a CLOSED set of values to outcomes — that
// gives a value it does not name NO outcome: C/C++ falls out of the switch, shell's case takes no arm (status 0,
// nothing printed, the variable left unset), Python's function falls off its end and returns None. The reader of
// the outcome cannot tell that value from a decided one. Three forms, each decided from tokens:
//   C/C++   a switch with no `default:` whose every case label is an enumerator of ONE in-tree enum (the tree-wide
//           table cEnumsOf builds) and that names fewer than all of its enumerators, when the switch decides a value
//           (an arm returns one, or every arm assigns the same name). A count sentinel (kFooCount, NUM_X, _Last) and
//           an alias (Last = C) are owed no arm.
//   shell   a case with two or more arms and no `*)` arm that is its function's last command, every arm ending in
//           return / echo / printf / exit; or one whose every arm is one assignment to the same name, read after
//           esac and written nowhere else in the file.
//   Python  a function whose last statement is an if/elif chain or a match over ONE subject compared with constants,
//           every arm ending in a return of a value (or a raise), with no else / `case _:`, and no bare return,
//           return None, yield or None/Optional return annotation anywhere: a value the chain does not name returns
//           None. Members of an Enum this file defines are checked for coverage; an enum defined elsewhere is not
//           decided (no site).
// Not this shape: a default / `*)` / else; an enum covered in full; a comment in the switch that states the omission
// (fall through, not handled, ignored, an omitted enumerator's name); a switch that decides nothing (a void
// dispatcher); a directive inside the switch or the enum; generated code (the caller drops it, looksGenerated).

// One enum whose enumerators are written out in its body (no directive, no macro expansion inside it).
struct EnumDef
{
    std::string              name;    // its own name (a typedef's for `typedef enum { … } T;`); empty when anonymous
    std::vector<std::string> all;     // every enumerator, sorted, unique: a case label must name one of these
    std::vector<std::string> owed;    // the ones a switch must decide: count sentinels and aliases left out; sorted
    std::vector<std::string> scope;   // the named namespaces / classes around it, outermost first
    bool                     scoped = false;   // enum class / enum struct: a label must spell its name
};

// A count sentinel or an internal marker: kFooCount, FOO_COUNT, NUM_FOO, kNumFoo, MAX_FOO, FooLast, _Foo.
inline bool isEnumSentinel( std::string_view m )
{
    const std::vector<std::string> t = nameTokens( m );
    if( m.empty() || m[0] == '_' || t.empty() )
    {
        return true;
    }
    static constexpr std::array<std::string_view, 7> kLast  = { "count", "max", "last", "num", "end", "sentinel", "total" };
    static constexpr std::array<std::string_view, 2> kFirst = { "num", "max" };
    const bool kNum = t.size() >= 2 && t[0] == "k" && t[1] == "num";
    return rw::inSet( kLast, std::string_view( t.back() ) ) || rw::inSet( kFirst, std::string_view( t.front() ) ) || kNum;
}

// The '{' that opens the body of the enum declared at token `k` (`enum`), or toks.size() for an opaque declaration,
// an elaborated type specifier or anything else; `name` receives the enum's name.
inline std::size_t enumBodyOpen( std::string_view src, const std::vector<Tok>& toks, std::size_t k, std::string& name, bool& scoped )
{
    bool sawColon = false;
    scoped        = k + 1 < toks.size() && ( tokIs( src, toks[k + 1], "class" ) || tokIs( src, toks[k + 1], "struct" ) );
    for( std::size_t j = k + 1; j < toks.size() && j < k + 40; ++j )
    {
        const Tok& t = toks[j];
        if( tokIs( src, t, "{" ) )
        {
            return j;
        }
        if( tokIs( src, t, "[" ) || ( tokIs( src, t, "__attribute__" ) && j + 1 < toks.size() ) )
        {
            j = matchClose( src, toks, tokIs( src, t, "[" ) ? j : j + 1 );   // [[nodiscard]], __attribute__(( … ))
            continue;
        }
        if( t.kind == TokKind::Punct && !tokIs( src, t, "::" ) && !tokIs( src, t, ":" ) )
        {
            return toks.size();   // ; ( ) = , < >: not a definition
        }
        sawColon = sawColon || tokIs( src, t, ":" );
        if( t.kind == TokKind::Ident && !sawColon && !tokIs( src, t, "class" ) && !tokIs( src, t, "struct" ) )
        {
            name = std::string( tokText( src, t ) );   // A::B::E: the last component
        }
    }
    return toks.size();
}

// The enumerators between `open` and `close`; false when the body is not a plain list (a macro, a non-name).
inline bool enumMembers( std::string_view src, const std::vector<Tok>& toks, std::size_t open, std::size_t close, EnumDef& def )
{
    std::vector<std::pair<std::string_view, ArgRange>> members;   // name, its initializer's tokens (empty: none)
    for( const ArgRange& a : splitArgs( src, toks, open, close ) )
    {
        if( a.empty() )
        {
            continue;   // a trailing comma
        }
        if( toks[a.first].kind != TokKind::Ident || ( a.first < a.last && tokIs( src, toks[a.first + 1], "(" ) ) )
        {
            return false;   // X( … ) inside an enum is a macro list: its enumerators are not written here
        }
        std::size_t eq = a.first + 1;
        while( eq <= a.last && !tokIs( src, toks[eq], "=" ) )
        {
            ++eq;
        }
        members.push_back( { tokText( src, toks[a.first] ), eq < a.last ? ArgRange{ eq + 1, a.last } : ArgRange{ 1, 0 } } );
    }
    for( const auto& [ m, init ] : members )
    {
        const bool alias = !init.empty() && std::any_of( toks.begin() + static_cast<std::ptrdiff_t>( init.first ), toks.begin() + static_cast<std::ptrdiff_t>( init.last + 1 ),
                                                         [ & ]( const Tok& t ) { return t.kind == TokKind::Ident && std::any_of( members.begin(), members.end(),
                                                                                    [ & ]( const auto& o ) { return o.first == tokText( src, t ); } ); } );
        def.all.emplace_back( m );
        if( !alias && !isEnumSentinel( m ) )
        {
            def.owed.emplace_back( m );
        }
    }
    rw::sortutil::sortUnique( def.all );
    rw::sortutil::sortUnique( def.owed );
    return !def.owed.empty();
}


// The names a '{' at `open` opens a scope for: `namespace A::B {` gives A, B; `class C … {` / `struct C … {` / `union C
// … {` gives C; any other brace (a function body, an initializer, a lambda) gives none.
inline std::vector<std::string> braceScopeNames( std::string_view src, const std::vector<Tok>& toks, std::size_t open )
{
    std::size_t b = open;
    while( b > 0 && !isStmtBoundary( src, toks[b - 1] ) )
    {
        --b;
    }
    std::size_t kw = toks.size();
    for( std::size_t j = b; j < open; ++j )
    {
        const bool key = tokIs( src, toks[j], "namespace" ) || tokIs( src, toks[j], "class" ) || tokIs( src, toks[j], "struct" ) || tokIs( src, toks[j], "union" );
        kw             = key ? j : kw;   // the LAST one: `template <class T> struct S {` is S
    }
    std::vector<std::string> names;
    if( kw == toks.size() )
    {
        return names;
    }
    const bool ns = tokIs( src, toks[kw], "namespace" );
    for( std::size_t j = kw + 1; j < open; ++j )
    {
        if( tokIs( src, toks[j], "(" ) || ( !ns && ( tokIs( src, toks[j], ":" ) || tokIs( src, toks[j], "<" ) ) ) )
        {
            break;   // a function head (`template <class T> void f() {`), or a class's base list
        }
        if( toks[j].kind == TokKind::Ident && !tokIs( src, toks[j], "final" ) && !tokIs( src, toks[j], "inline" ) )
        {
            if( !ns )
            {
                names.clear();   // class [[attr]] EXPORT Name: the last name
            }
            names.emplace_back( tokText( src, toks[j] ) );
        }
    }
    const bool fnHead = std::any_of( toks.begin() + static_cast<std::ptrdiff_t>( kw ), toks.begin() + static_cast<std::ptrdiff_t>( open ),
                                     [ & ]( const Tok& t ) { return tokIs( src, t, "(" ); } );
    return fnHead ? std::vector<std::string>{} : names;
}

}   // namespace detail

// Every enum a C/C++ file defines with its enumerators written out — the tree-wide table a switch is checked against —
// with the named scopes around it, so a label's qualifiers can be held to them.
inline std::vector<detail::EnumDef> cEnumsOf( std::string_view src )
{
    using namespace detail;
    std::vector<EnumDef> out;
    if( src.find( "enum" ) == std::string_view::npos )
    {
        return out;
    }
    CppPreproc                 pp;
    const std::vector<Tok>     toks = lexCpp( src, &pp );
    std::vector<std::string>   scope;
    std::vector<std::size_t>   pushed;   // per open brace: how many names it pushed onto `scope`
    for( std::size_t k = 0; k + 1 < toks.size(); ++k )
    {
        if( tokIs( src, toks[k], "{" ) )
        {
            const std::vector<std::string> names = braceScopeNames( src, toks, k );
            scope.insert( scope.end(), names.begin(), names.end() );
            pushed.push_back( names.size() );
            continue;
        }
        if( tokIs( src, toks[k], "}" ) )
        {
            const std::size_t n = pushed.empty() ? 0 : pushed.back();
            scope.resize( scope.size() - std::min( n, scope.size() ) );
            pushed.erase( pushed.end() - ( pushed.empty() ? 0 : 1 ), pushed.end() );
            continue;
        }
        EnumDef           def;
        const std::size_t open  = tokIs( src, toks[k], "enum" ) ? enumBodyOpen( src, toks, k, def.name, def.scoped ) : toks.size();
        const std::size_t close = open < toks.size() ? matchClose( src, toks, open ) : toks.size();
        if( close >= toks.size() || callHoldsDirective( pp.directives, toks[open].begin, toks[close].begin ) )
        {
            continue;   // an #if inside the body: which enumerators exist depends on the build
        }
        if( def.name.empty() && k > 0 && tokIs( src, toks[k - 1], "typedef" ) && close + 1 < toks.size() && toks[close + 1].kind == TokKind::Ident )
        {
            def.name = std::string( tokText( src, toks[close + 1] ) );
        }
        def.scope = scope;
        if( enumMembers( src, toks, open, close, def ) )
        {
            out.push_back( std::move( def ) );
        }
        k = close;
    }
    return out;
}

// The tree's enums, indexed by enumerator name.
class EnumTable
{
public:
    void add( detail::EnumDef&& d ) { defs_.push_back( std::move( d ) ); }
    void seal()
    {
        byMember_.clear();
        for( std::uint32_t d = 0; d < defs_.size(); ++d )
        {
            for( std::uint32_t m = 0; m < defs_[d].all.size(); ++m )
            {
                byMember_.push_back( { d, m } );
            }
        }
        std::sort( byMember_.begin(), byMember_.end(), [ this ]( const Ref& a, const Ref& b ) { return rw::sortutil::svLess( memberOf( a ), memberOf( b ) ); } );
    }
    // The enums that hold enumerator `m` (def indices, ascending).
    std::vector<std::uint32_t> holding( std::string_view m ) const
    {
        const auto lo = std::lower_bound( byMember_.begin(), byMember_.end(), m, [ this ]( const Ref& r, std::string_view w ) { return rw::sortutil::svLess( memberOf( r ), w ); } );
        std::vector<std::uint32_t> out;
        for( auto it = lo; it != byMember_.end() && memberOf( *it ) == m; ++it )
        {
            out.push_back( it->first );
        }
        return out;
    }
    const detail::EnumDef& def( std::uint32_t d ) const { return defs_[d]; }
    std::size_t            size() const noexcept { return defs_.size(); }

private:
    using Ref = std::pair<std::uint32_t, std::uint32_t>;   // def index, index in its `all`
    std::string_view memberOf( const Ref& r ) const { return defs_[ r.first ].all[ r.second ]; }
    std::vector<detail::EnumDef> defs_;
    std::vector<Ref>             byMember_;
};

namespace detail
{

// One switch's arms, as far as the check needs them.
struct SwitchLabel
{
    std::vector<std::string_view> quals;   // the qualifiers before the enumerator (`A::E::X` gives A, E)
    std::string_view              name;
};

struct SwitchArms
{
    std::vector<SwitchLabel>                         labels;
    std::vector<std::pair<std::size_t, std::size_t>> ranges;    // each arm's statements [first, end): after its last label
    bool                                             decides   = false;   // every arm returns a value (or does not return), or assigns one name
    bool                                             undecided = false;   // a default:, a label that is no enumerator, an #if
};

// The label `case …:` starting at `k` (`case`): its qualifiers and enumerator, `colon` set to its ':'. False for a
// label that is not a (qualified) name — a number, a character, an expression.
inline bool enumLabelAt( std::string_view src, const std::vector<Tok>& toks, std::size_t k, std::size_t end, SwitchLabel& label, std::size_t& colon )
{
    std::size_t j = k + 1;
    j += ( j < end && tokIs( src, toks[j], "::" ) ) ? 1 : 0;
    label = {};
    while( j < end && toks[j].kind == TokKind::Ident )
    {
        if( !label.name.empty() )
        {
            label.quals.push_back( label.name );
        }
        label.name = tokText( src, toks[j] );
        if( j + 1 < end && tokIs( src, toks[j + 1], "::" ) )
        {
            j += 2;
            continue;
        }
        ++j;
        break;
    }
    colon = j;
    return !label.name.empty() && j < end && tokIs( src, toks[j], ":" );
}

enum class ArmEnd : std::uint8_t
{
    Value,      // return <expr>;
    NoReturn,   // throw, [[fallthrough]], abort / exit / unreachable, an ALL_CAPS macro (PANIC, NOT_REACHED)
    Other,      // break, a call, nothing: control leaves the switch without a decided value
};

// How the arm [first, end) ends: its last statement (inside the arm's own block when the arm is one `{ … }`).
inline ArmEnd armEndOf( std::string_view src, const std::vector<Tok>& toks, std::size_t first, std::size_t end )
{
    while( end > first + 1 && tokIs( src, toks[first], "{" ) && matchClose( src, toks, first ) == end - 1 )
    {
        ++first;
        --end;
    }
    if( end <= first || !tokIs( src, toks[end - 1], ";" ) )
    {
        return ArmEnd::Other;
    }
    std::size_t b = end - 1;
    int         depth = 0;
    while( b > first )
    {
        const Tok& t = toks[b - 1];
        depth += ( tokIs( src, t, ")" ) || tokIs( src, t, "]" ) ) ? 1 : ( tokIs( src, t, "(" ) || tokIs( src, t, "[" ) ) ? -1 : 0;
        if( depth == 0 && isStmtBoundary( src, t ) )
        {
            break;
        }
        --b;
    }
    const std::string_view w = tokText( src, toks[b] );
    if( w == "return" )
    {
        return b + 1 < end - 1 ? ArmEnd::Value : ArmEnd::Other;
    }
    static constexpr std::array<std::string_view, 7> kNoReturn = { "throw", "abort", "exit", "_exit", "unreachable", "__builtin_unreachable", "std" };
    const bool fallthrough = w == "[" && b + 2 < end && tokIs( src, toks[b + 2], "fallthrough" );
    const bool macro       = toks[b].kind == TokKind::Ident && isAllCapsIdent( w ) && w.size() > 2;
    const bool stdNoReturn = w == "std" && b + 2 < end && ( tokIs( src, toks[b + 2], "abort" ) || tokIs( src, toks[b + 2], "unreachable" ) || tokIs( src, toks[b + 2], "terminate" ) );
    return ( fallthrough || macro || stdNoReturn || ( w != "std" && rw::inSet( kNoReturn, w ) ) ) ? ArmEnd::NoReturn : ArmEnd::Other;
}

// The arms of the switch whose body is (open, close): labels, whether it decides a value, whether it is undecidable.
// A nested switch's body is skipped whole (its labels are its own).
inline SwitchArms switchArmsOf( std::string_view src, const std::vector<Tok>& toks, const CppPreproc& pp, std::size_t open, std::size_t close )
{
    SwitchArms                                  arms;
    std::vector<std::vector<std::string_view>> assigned;   // per arm: the names a statement of it assigns
    bool                                        atStmt   = true;
    bool                                        afterLbl = false;
    arms.undecided = callHoldsDirective( pp.directives, toks[open].begin, toks[close].begin );
    for( std::size_t j = open + 1; j < close && !arms.undecided; ++j )
    {
        const Tok& t = toks[j];
        if( tokIs( src, t, "switch" ) && j + 1 < close && tokIs( src, toks[j + 1], "(" ) )
        {
            const std::size_t c = matchClose( src, toks, j + 1 );
            j                   = ( c + 1 < close && tokIs( src, toks[c + 1], "{" ) ) ? matchClose( src, toks, c + 1 ) : c;
            atStmt              = true;
            continue;
        }
        if( tokIs( src, t, "case" ) )
        {
            SwitchLabel label;
            std::size_t colon = j;
            arms.undecided    = !enumLabelAt( src, toks, j, close, label, colon );
            arms.labels.push_back( std::move( label ) );
            if( !afterLbl )
            {
                if( !arms.ranges.empty() )
                {
                    arms.ranges.back().second = j;
                }
                arms.ranges.push_back( { colon + 1, close } );
                assigned.emplace_back();
            }
            arms.ranges.back().first = colon + 1;
            j        = colon;
            atStmt   = true;
            afterLbl = true;
            continue;
        }
        if( tokIs( src, t, "default" ) && j + 1 < close && tokIs( src, toks[j + 1], ":" ) )
        {
            arms.undecided = true;
            break;
        }
        if( atStmt && t.kind == TokKind::Ident && j + 1 < close && tokIs( src, toks[j + 1], "=" ) && !assigned.empty() )
        {
            assigned.back().push_back( tokText( src, t ) );
        }
        atStmt   = isStmtBoundary( src, t );
        afterLbl = false;
    }
    std::vector<ArmEnd> ends;
    ends.reserve( arms.ranges.size() );
    for( const auto& [ first, end ] : arms.ranges )
    {
        ends.push_back( armEndOf( src, toks, first, end ) );
    }
    const bool returns = !ends.empty() && std::none_of( ends.begin(), ends.end(), []( ArmEnd e ) { return e == ArmEnd::Other; } )
                      && std::any_of( ends.begin(), ends.end(), []( ArmEnd e ) { return e == ArmEnd::Value; } );
    const auto everyArm = [ & ]( std::string_view v )
    {
        return std::all_of( assigned.begin(), assigned.end(), [ & ]( const std::vector<std::string_view>& a ) { return std::find( a.begin(), a.end(), v ) != a.end(); } );
    };
    arms.decides = returns || ( !assigned.empty() && std::any_of( assigned[0].begin(), assigned[0].end(), everyArm ) );
    return arms;
}

// Can `label` name an enumerator of `e`? A scoped enum's label spells its name (`E::X`, `ns::E::X`); an unscoped one's
// may, or may name the scope around it (`C::X`) or nothing. Whatever qualifies past the enum's own name must be the
// innermost scopes the enum was declared in, so an out-of-tree `Http::CodecType` is not an in-tree class member's
// `CodecType`.
inline bool labelFits( const SwitchLabel& label, const EnumDef& e )
{
    std::size_t n = label.quals.size();
    if( n > 0 && label.quals[n - 1] == e.name )
    {
        --n;
    }
    else if( e.scoped )
    {
        return false;
    }
    if( n > e.scope.size() )
    {
        return false;
    }
    for( std::size_t i = 0; i < n; ++i )
    {
        if( label.quals[n - 1 - i] != e.scope[ e.scope.size() - 1 - i ] )
        {
            return false;
        }
    }
    return true;
}

// The enumerators of the one enum every label names that no label names, displayed as the labels spell them
// (`E::X` when the labels qualify, `X` when they do not); empty when no single enum holds every label, when two
// candidate enums disagree on what is missing, or when every owed enumerator has an arm.
inline std::vector<std::string> missingEnumerators( const SwitchArms& arms, const EnumTable& enums )
{
    std::vector<std::uint32_t> cands = enums.holding( arms.labels[0].name );
    const auto holdsAll = [ & ]( std::uint32_t d )
    {
        const EnumDef& e = enums.def( d );
        return std::all_of( arms.labels.begin(), arms.labels.end(), [ & ]( const SwitchLabel& l )
                            { return labelFits( l, e ) && std::binary_search( e.all.begin(), e.all.end(), l.name, rw::sortutil::svLess ); } );
    };
    std::erase_if( cands, [ & ]( std::uint32_t d ) { return !holdsAll( d ); } );
    const std::vector<std::string_view>& quals  = arms.labels[0].quals;
    const std::string                    prefix = quals.empty() ? std::string() : std::string( quals.back() ) + "::";   // E::X, not ns::C::E::X
    std::vector<std::string> missing;
    bool                     first = true;
    for( const std::uint32_t d : cands )
    {
        std::vector<std::string> m;
        for( const std::string& e : enums.def( d ).owed )
        {
            if( std::none_of( arms.labels.begin(), arms.labels.end(), [ & ]( const SwitchLabel& l ) { return l.name == e; } ) )
            {
                m.push_back( prefix + e );
            }
        }
        if( !first && m != missing )
        {
            return {};   // two enums of the same enumerator names disagree: undecided
        }
        missing = std::move( m );
        first   = false;
    }
    return missing;
}

// A comment in [b, e) that states the omission: falling through on purpose, not handled, ignored, or an omitted
// enumerator by name. Raw bytes: the lexer drops comments.
inline bool commentStatesOmission( std::string_view src, std::size_t b, std::size_t e, const std::vector<std::string>& missing )
{
    static constexpr std::array<std::string_view, 14> kPhrases = { "fall through", "fallthrough", "fall-through", "falls through", "not handled", "unhandled", "ignore",
                                                                   "intentional", "deliberate", "on purpose", "nothing to do", "no-op", "handled elsewhere", "other" };
    for( std::size_t i = src.find( '/', b ); i != std::string_view::npos && i + 1 < e; i = src.find( '/', i + 1 ) )
    {
        if( src[i + 1] != '/' && src[i + 1] != '*' )
        {
            continue;
        }
        const std::size_t stop = src[i + 1] == '/' ? src.find( '\n', i ) : src.find( "*/", i + 2 );
        const std::string_view text = src.substr( i, ( stop == std::string_view::npos ? src.size() : stop ) - i );
        std::string lower( text );
        std::ranges::transform( lower, lower.begin(), []( unsigned char c ) { return static_cast<char>( std::tolower( c ) ); } );
        const bool phrase = std::any_of( kPhrases.begin(), kPhrases.end(), [ & ]( std::string_view p ) { return lower.find( p ) != std::string::npos; } );
        const bool names  = std::any_of( missing.begin(), missing.end(), [ & ]( const std::string& m )
                                         { return rw::namesplit::containsWordBoundedBy( text, std::string_view( m ).substr( m.rfind( ':' ) == std::string::npos ? 0 : m.rfind( ':' ) + 1 ), isIdentChar ); } );
        if( phrase || names )
        {
            return true;
        }
        i += text.size();
    }
    return false;
}

// "A, B, C, D +3": the first four names of a why= list and how many more there are.
inline std::string capList( const std::vector<std::string>& names )
{
    std::string out;
    for( std::size_t i = 0; i < names.size() && i < 4; ++i )
    {
        out += ( i == 0 ? "" : ", " ) + names[i];
    }
    if( names.size() > 4 )
    {
        out += " +" + std::to_string( names.size() - 4 );
    }
    return out;
}

// One function's tokens [from, to): every switch over an in-tree enum that leaves an owed enumerator without an arm.
inline void scanUnhandledArmCpp( std::string_view src, const std::vector<Tok>& toks, const CppPreproc& pp, std::size_t from, std::size_t to, const EnumTable& enums,
                                 std::vector<Site>& out )
{
    for( std::size_t k = from; k + 1 < to; ++k )
    {
        if( !tokIs( src, toks[k], "switch" ) || !tokIs( src, toks[k + 1], "(" ) )
        {
            continue;
        }
        const std::size_t cond  = matchClose( src, toks, k + 1 );
        const std::size_t open  = cond + 1;
        const std::size_t close = ( open < to && tokIs( src, toks[open], "{" ) ) ? matchClose( src, toks, open ) : toks.size();
        if( close >= to )
        {
            continue;
        }
        const SwitchArms arms = switchArmsOf( src, toks, pp, open, close );
        if( arms.undecided || arms.labels.empty() || !arms.decides )
        {
            continue;
        }
        const std::vector<std::string> missing = missingEnumerators( arms, enums );
        const std::size_t              lineEnd = src.find( '\n', toks[close].end );
        if( missing.empty() || commentStatesOmission( src, toks[open].begin, lineEnd == std::string_view::npos ? src.size() : lineEnd, missing ) )
        {
            continue;
        }
        std::string text = joinTokens( src, toks, k, cond ) + " missing";
        for( const std::string& m : missing )
        {
            text += " " + m;
        }
        out.push_back( { Facet::UnhandledArm, toks[k].begin, std::move( text ), {}, "no default: " + capList( missing ) + " not handled" } );
    }
}

// ── Python ──

// The column of token `t`: its byte offset from the start of its line.
inline std::uint32_t pyCol( std::string_view src, const Tok& t ) noexcept
{
    const std::size_t nl = src.rfind( '\n', t.begin == 0 ? 0 : t.begin - 1 );
    return t.begin - ( nl == std::string_view::npos || ( t.begin == 0 ) ? 0 : static_cast<std::uint32_t>( nl + 1 ) );
}

inline bool pyLineStart( std::string_view src, const std::vector<Tok>& toks, std::size_t k ) noexcept
{
    return k == 0 || tokIs( src, toks[k - 1], "\n" );
}

// The ':' that ends the compound-statement header at `k` (the first one outside brackets), or toks.size().
inline std::size_t pyHeaderColon( std::string_view src, const std::vector<Tok>& toks, std::size_t k, std::size_t to ) noexcept
{
    int depth = 0;
    for( std::size_t j = k; j < to && !tokIs( src, toks[j], "\n" ); ++j )
    {
        const std::string_view w = tokText( src, toks[j] );
        depth += ( w == "(" || w == "[" || w == "{" ) ? 1 : ( w == ")" || w == "]" || w == "}" ) ? -1 : 0;
        if( depth == 0 && w == ":" )
        {
            return j;
        }
    }
    return toks.size();
}

// The logical-line starts in [from, to) at column `col`, stopping at the first line that dedents below it.
inline std::vector<std::size_t> pyStatementsAt( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t to, std::uint32_t col )
{
    std::vector<std::size_t> out;
    for( std::size_t k = from; k < to; ++k )
    {
        if( !pyLineStart( src, toks, k ) || tokIs( src, toks[k], "\n" ) )
        {
            continue;
        }
        const std::uint32_t c = pyCol( src, toks[k] );
        if( c < col )
        {
            break;
        }
        if( c == col )
        {
            out.push_back( k );
        }
    }
    return out;
}

// One constant a chain compares its subject with: its text, and for `E.M` the enum's name and the member.
struct PyConst
{
    std::string      text;
    std::string_view enumName;
    std::string_view member;
};

// The constant [a, b]: a string or number literal, -N, None / True / False, or a dotted name; false otherwise
// (a bare name in a match is a capture: irrefutable).
inline bool pyConstOf( std::string_view src, const std::vector<Tok>& toks, std::size_t a, std::size_t b, PyConst& c )
{
    c = PyConst{ joinTokens( src, toks, a, b ), {}, {} };
    if( a == b )
    {
        const std::string_view w = tokText( src, toks[a] );
        return toks[a].kind == TokKind::String || toks[a].kind == TokKind::Number || w == "None" || w == "True" || w == "False";
    }
    if( b == a + 1 && tokIs( src, toks[a], "-" ) && toks[b].kind == TokKind::Number )
    {
        return true;
    }
    for( std::size_t j = a; j <= b; ++j )
    {
        const bool want = ( j - a ) % 2 == 0;   // name . name . name
        if( want ? toks[j].kind != TokKind::Ident : !tokIs( src, toks[j], "." ) )
        {
            return false;
        }
    }
    if( ( b - a ) % 2 != 0 )
    {
        return false;
    }
    c.enumName = tokText( src, toks[b - 2] );
    c.member   = tokText( src, toks[b] );
    return true;
}

// The comparison `subject == C`, `subject is C`, `subject in ( C, … )` at [a, b] (one `or` operand): appends the
// constants and checks the subject against `subject` (set on the first operand); false for any other test.
inline bool pyCompareOf( std::string_view src, const std::vector<Tok>& toks, std::size_t a, std::size_t b, std::string& subject, std::vector<PyConst>& consts )
{
    std::size_t op = a;
    int         depth = 0;
    for( ; op <= b; ++op )
    {
        const std::string_view w = tokText( src, toks[op] );
        depth += ( w == "(" || w == "[" || w == "{" ) ? 1 : ( w == ")" || w == "]" || w == "}" ) ? -1 : 0;
        if( depth == 0 && ( w == "==" || w == "is" || w == "in" ) )
        {
            break;
        }
    }
    if( op <= a || op >= b || tokIs( src, toks[op + 1], "not" ) || tokIs( src, toks[op - 1], "not" ) )
    {
        return false;
    }
    const std::string subj = joinTokens( src, toks, a, op - 1 );
    if( !subject.empty() && subj != subject )
    {
        return false;
    }
    subject = subj;
    if( !tokIs( src, toks[op], "in" ) )
    {
        PyConst c;
        const bool ok = pyConstOf( src, toks, op + 1, b, c );
        consts.push_back( std::move( c ) );
        return ok;
    }
    const std::string_view o = tokText( src, toks[op + 1] );
    if( ( o != "(" && o != "[" && o != "{" ) || matchClose( src, toks, op + 1 ) != b )
    {
        return false;
    }
    for( const ArgRange& r : splitArgs( src, toks, op + 1, b ) )
    {
        PyConst c;
        if( !r.empty() && !pyConstOf( src, toks, r.first, r.last, c ) )
        {
            return false;
        }
        if( !r.empty() )
        {
            consts.push_back( std::move( c ) );
        }
    }
    return true;
}

// [a, b] split at the depth-0 tokens spelled `sep` (`or` in a condition, `|` in a match pattern).
inline std::vector<ArgRange> pySplitAt( std::string_view src, const std::vector<Tok>& toks, std::size_t a, std::size_t b, std::string_view sep )
{
    std::vector<ArgRange> out;
    int                   depth = 0;
    std::size_t           start = a;
    for( std::size_t j = a; j <= b; ++j )
    {
        const std::string_view w = tokText( src, toks[j] );
        depth += ( w == "(" || w == "[" || w == "{" ) ? 1 : ( w == ")" || w == "]" || w == "}" ) ? -1 : 0;
        if( depth == 0 && w == sep )
        {
            out.push_back( { start, j - 1 } );
            start = j + 1;
        }
    }
    out.push_back( { start, b } );
    return out;
}

// Does the arm whose header ends at `colon` end in a return of a value or a raise? `armCol` is the header's column.
// Sets `valued` when it returns a value.
inline bool pyArmEnds( std::string_view src, const std::vector<Tok>& toks, std::size_t colon, std::size_t to, std::uint32_t armCol, bool& valued )
{
    std::size_t last = colon + 1;
    if( colon + 1 < to && tokIs( src, toks[colon + 1], "\n" ) )
    {
        if( colon + 2 >= to || pyCol( src, toks[colon + 2] ) <= armCol )
        {
            return false;
        }
        const std::vector<std::size_t> body = pyStatementsAt( src, toks, colon + 2, to, pyCol( src, toks[colon + 2] ) );
        last                                = body.empty() ? to : body.back();
    }
    else
    {
        for( std::size_t j = colon + 1; j < to && !tokIs( src, toks[j], "\n" ); ++j )
        {
            last = tokIs( src, toks[j], ";" ) ? j + 1 : last;   // `if x: f(); return 1`: the last simple statement
        }
    }
    if( last >= to )
    {
        return false;
    }
    if( tokIs( src, toks[last], "raise" ) )
    {
        return true;
    }
    const bool ret = tokIs( src, toks[last], "return" ) && last + 1 < to && !pyStatementEndsAt( src, toks, last + 1 ) && !tokIs( src, toks[last + 1], "None" );
    valued         = valued || ret;
    return ret;
}

// The Enum classes this file defines: name and members (sorted), an alias of another member left out.
struct PyEnum
{
    std::string_view              name;
    std::vector<std::string_view> members;
};

inline std::vector<PyEnum> pyEnumsOf( std::string_view src, const std::vector<Tok>& toks )
{
    std::vector<PyEnum> out;
    for( std::size_t k = 0; k + 3 < toks.size(); ++k )
    {
        if( !pyLineStart( src, toks, k ) || !tokIs( src, toks[k], "class" ) || !tokIs( src, toks[k + 2], "(" ) )
        {
            continue;
        }
        const std::size_t close = matchClose( src, toks, k + 2 );
        const bool        isEnum = close < toks.size() && std::any_of( toks.begin() + static_cast<std::ptrdiff_t>( k + 3 ), toks.begin() + static_cast<std::ptrdiff_t>( close ),
                                                                    [ & ]( const Tok& t ) { const std::string_view w = tokText( src, t ); return w.ends_with( "Enum" ) || w.ends_with( "Flag" ); } );
        if( !isEnum || close + 3 >= toks.size() || !tokIs( src, toks[close + 1], ":" ) || !tokIs( src, toks[close + 2], "\n" ) )
        {
            continue;
        }
        PyEnum e{ tokText( src, toks[k + 1] ), {} };
        for( const std::size_t s : pyStatementsAt( src, toks, close + 3, toks.size(), pyCol( src, toks[close + 3] ) ) )
        {
            const bool member = toks[s].kind == TokKind::Ident && s + 1 < toks.size() && tokIs( src, toks[s + 1], "=" ) && tokText( src, toks[s] )[0] != '_';
            const bool alias  = member && s + 3 < toks.size() && toks[s + 2].kind == TokKind::Ident && pyStatementEndsAt( src, toks, s + 3 )
                             && std::find( e.members.begin(), e.members.end(), tokText( src, toks[s + 2] ) ) != e.members.end();
            if( member && !alias )
            {
                e.members.push_back( tokText( src, toks[s] ) );
            }
        }
        rw::sortutil::sortUnique( e.members, rw::sortutil::svLess );
        out.push_back( std::move( e ) );
    }
    return out;
}

// The chain the function body [first, to) ends with, as arm header tokens: an if/elif run (`isMatch` false) or the
// `case` lines of a match (`isMatch` true, `head` the match). Empty when the body ends some other way.
struct PyChain
{
    std::size_t              head    = 0;
    bool                     isMatch = false;
    std::vector<std::size_t> arms;
};

inline PyChain pyTrailingChain( std::string_view src, const std::vector<Tok>& toks, std::size_t first, std::size_t to )
{
    PyChain                        ch;
    const std::vector<std::size_t> top = pyStatementsAt( src, toks, first, to, pyCol( src, toks[first] ) );
    if( top.empty() )
    {
        return ch;
    }
    const std::size_t last = top.back();
    if( tokIs( src, toks[last], "match" ) )
    {
        const std::size_t colon = pyHeaderColon( src, toks, last, to );
        if( colon + 2 < to && tokIs( src, toks[colon + 1], "\n" ) )
        {
            ch.head    = last;
            ch.isMatch = true;
            ch.arms    = pyStatementsAt( src, toks, colon + 2, to, pyCol( src, toks[colon + 2] ) );
            std::erase_if( ch.arms, [ & ]( std::size_t a ) { return !tokIs( src, toks[a], "case" ); } );
        }
        return ch;
    }
    std::size_t i = top.size() - 1;
    while( i > 0 && tokIs( src, toks[ top[i] ], "elif" ) )
    {
        --i;
    }
    if( tokIs( src, toks[ top[i] ], "if" ) )
    {
        ch.head = top[i];
        ch.arms.assign( top.begin() + static_cast<std::ptrdiff_t>( i ), top.end() );
    }
    return ch;
}

// Does the function body [first, to) state None as an outcome anywhere — a bare return, return None, a yield —
// outside the nested definitions `inner`?
inline bool pyBodyStatesNone( std::string_view src, const std::vector<Tok>& toks, std::size_t first, std::size_t to, const std::vector<Span>& inner )
{
    for( std::size_t k = first; k < to; ++k )
    {
        const std::uint32_t at = toks[k].begin;
        if( std::any_of( inner.begin(), inner.end(), [ & ]( const Span& s ) { return s.begin <= at && at < s.end; } ) )
        {
            continue;
        }
        if( tokIs( src, toks[k], "yield" ) || ( tokIs( src, toks[k], "return" ) && ( pyStatementEndsAt( src, toks, k + 1 ) || tokIs( src, toks[k + 1], "None" ) ) ) )
        {
            return true;
        }
    }
    return false;
}

// The tokens of span `sp`: [first, last) indices into `toks` (sorted by byte).
inline std::pair<std::size_t, std::size_t> tokRangeOf( const std::vector<Tok>& toks, const Span& sp )
{
    const auto first = std::lower_bound( toks.begin(), toks.end(), sp.begin, []( const Tok& t, std::uint32_t b ) { return t.begin < b; } );
    const auto last  = std::lower_bound( toks.begin(), toks.end(), sp.end, []( const Tok& t, std::uint32_t b ) { return t.begin < b; } );
    return { static_cast<std::size_t>( first - toks.begin() ), static_cast<std::size_t>( last - toks.begin() ) };
}

// The body of a value-returning def in [from, to): the token after its header's newline, or `to` when there is no
// def, it is a one-liner, its return is annotated None/Optional, or its body states None itself.
inline std::size_t pyValuedBodyOf( std::string_view src, const std::vector<Tok>& toks, std::size_t from, std::size_t to, const std::vector<Span>& inner )
{
    std::size_t d = from;
    while( d < to && !tokIs( src, toks[d], "def" ) )
    {
        ++d;
    }
    if( d + 2 >= to || !tokIs( src, toks[d + 2], "(" ) )
    {
        return to;
    }
    const std::size_t sigClose = matchClose( src, toks, d + 2 );
    const std::size_t colon    = sigClose < to ? pyHeaderColon( src, toks, sigClose + 1, to ) : toks.size();
    const bool noneAnnotated   = colon < to && std::any_of( toks.begin() + static_cast<std::ptrdiff_t>( sigClose ), toks.begin() + static_cast<std::ptrdiff_t>( colon ),
                                                            [ & ]( const Tok& t ) { return tokIs( src, t, "None" ) || tokIs( src, t, "Optional" ); } );
    if( colon + 2 >= to || !tokIs( src, toks[colon + 1], "\n" ) || noneAnnotated || pyBodyStatesNone( src, toks, colon + 2, to, inner ) )
    {
        return to;
    }
    return colon + 2;
}

// The constants a chain's arms test, when every arm ends in a return or raise, one at least returns a value, and each
// test compares `subject` (an if chain fills it from its first test) with a constant of one kind (literals, or one
// Enum's members); empty otherwise (a guard, a capture or class pattern, a test that is no such comparison).
inline std::vector<PyConst> pyChainConsts( std::string_view src, const std::vector<Tok>& toks, const PyChain& ch, std::size_t to, std::string& subject )
{
    std::vector<PyConst> consts;
    bool                 valued = false;
    for( const std::size_t a : ch.arms )
    {
        const std::size_t c = pyHeaderColon( src, toks, a, to );
        if( c >= to || c == a + 1 || !pyArmEnds( src, toks, c, to, pyCol( src, toks[a] ), valued ) )
        {
            return {};
        }
        for( const ArgRange& part : pySplitAt( src, toks, a + 1, c - 1, ch.isMatch ? "|" : "or" ) )
        {
            PyConst    k;
            const bool guarded = ch.isMatch && std::any_of( toks.begin() + static_cast<std::ptrdiff_t>( part.first ), toks.begin() + static_cast<std::ptrdiff_t>( part.last + 1 ),
                                                           [ & ]( const Tok& t ) { return tokIs( src, t, "if" ); } );
            const bool ok = !part.empty() && !guarded
                         && ( ch.isMatch ? ( pyConstOf( src, toks, part.first, part.last, k ) && ( consts.push_back( k ), true ) )
                                         : pyCompareOf( src, toks, part.first, part.last, subject, consts ) );
            if( !ok )
            {
                return {};
            }
        }
    }
    const std::string_view enumName = consts.empty() ? std::string_view() : consts[0].enumName;
    const bool sameEnum = std::all_of( consts.begin(), consts.end(), [ & ]( const PyConst& c ) { return c.enumName == enumName; } );
    if( !valued || !sameEnum )
    {
        return {};
    }
    return consts;
}

// The site text and why= of a chain over `consts` that falls off its function: an Enum's members with no arm, or the
// constants an unmatched value falls past. Empty text when the arms cover the set (True and False, every member) or
// the Enum is defined in another file (its members are not known here).
inline std::pair<std::string, std::string> pyUnhandledOutcome( bool isMatch, std::string_view subject, const std::vector<PyConst>& consts, const std::vector<PyEnum>& enums )
{
    std::vector<std::string> named;
    named.reserve( consts.size() );
    for( const PyConst& c : consts )
    {
        named.push_back( c.text );
    }
    rw::sortutil::sortUnique( named );
    if( std::binary_search( named.begin(), named.end(), "True", rw::sortutil::svLess ) && std::binary_search( named.begin(), named.end(), "False", rw::sortutil::svLess ) )
    {
        return {};
    }
    std::string text = ( isMatch ? "match " : "if " ) + std::string( subject ) + " in";
    for( const std::string& n : named )
    {
        text += " " + n;
    }
    const std::string_view enumName = consts[0].enumName;
    if( enumName.empty() )
    {
        return { std::move( text ), "no else: returns None for a value other than " + capList( named ) };
    }
    const PyEnum* e = rw::findByField( enums, &PyEnum::name, enumName );
    if( e == nullptr )
    {
        return {};
    }
    std::vector<std::string> missing;
    for( const std::string_view m : e->members )
    {
        if( std::none_of( consts.begin(), consts.end(), [ & ]( const PyConst& c ) { return c.member == m; } ) )
        {
            missing.push_back( std::string( enumName ) + "." + std::string( m ) );
        }
    }
    if( missing.empty() )
    {
        return {};
    }
    text += " missing";
    for( const std::string& m : missing )
    {
        text += " " + m;
    }
    return { std::move( text ), "no else: returns None for " + capList( missing ) };
}

// One function span: its trailing chain's site, when every arm returns and nothing names the value it leaves out.
inline std::optional<Site> unhandledArmPyFunction( std::string_view src, const std::vector<Tok>& toks, const Span& fn, const std::vector<Span>& inner,
                                                   const std::vector<PyEnum>& enums )
{
    const auto [ from, to ] = tokRangeOf( toks, fn );
    const std::size_t body  = pyValuedBodyOf( src, toks, from, to, inner );
    const PyChain     ch    = body < to ? pyTrailingChain( src, toks, body, to ) : PyChain{};
    if( ch.arms.size() < 2 )
    {
        return std::nullopt;
    }
    std::string                subject = ch.isMatch ? joinTokens( src, toks, ch.head + 1, pyHeaderColon( src, toks, ch.head, to ) - 1 ) : std::string();
    const std::vector<PyConst> consts  = pyChainConsts( src, toks, ch, to, subject );
    if( consts.empty() )
    {
        return std::nullopt;
    }
    auto [ text, why ] = pyUnhandledOutcome( ch.isMatch, subject, consts, enums );
    if( text.empty() )
    {
        return std::nullopt;
    }
    return Site{ Facet::UnhandledArm, toks[ch.head].begin, std::move( text ), {}, std::move( why ) };
}

inline void scanUnhandledArmPython( std::string_view src, const std::vector<Tok>& toks, const std::vector<Span>& fnSpans, std::vector<Site>& out )
{
    const std::vector<PyEnum> enums = pyEnumsOf( src, toks );
    for( const Span& sp : fnSpans )
    {
        std::vector<Span> inner;
        std::copy_if( fnSpans.begin(), fnSpans.end(), std::back_inserter( inner ), [ & ]( const Span& s ) { return s.begin > sp.begin && s.end <= sp.end; } );
        if( std::optional<Site> site = unhandledArmPyFunction( src, toks, sp, inner, enums ) )
        {
            out.push_back( std::move( *site ) );
        }
    }
}

// ── shell ──

namespace uash
{

namespace sh = rw::shstatus;

// The single command a list ends with (its last and-or, one pipeline of one command), or kNone.
inline std::uint32_t lastCommandOf( const sh::Tree& t, std::uint32_t list )
{
    if( list == sh::kNone || list >= t.lists.size() || t.lists[list].empty() )
    {
        return sh::kNone;
    }
    const sh::AndOr& ao = t.lists[list].back();
    return ( ao.size() == 1 && ao[0].cmds.size() == 1 && !ao[0].neg ) ? ao[0].cmds[0] : sh::kNone;
}

// A `*)` arm (any all-star pattern): every subject reaches it.
inline bool hasCatchAll( const sh::Node& n )
{
    return std::any_of( n.casePats.begin(), n.casePats.end(), []( const std::vector<std::string>& pats )
                        {
                            return std::any_of( pats.begin(), pats.end(), []( const std::string& p )
                                                {
                                                    const std::string u = sh::detail::unq( p );
                                                    return !u.empty() && std::all_of( u.begin(), u.end(), []( char c ) { return c == '*'; } );
                                                } );
                        } );
}

// A function whose last command is this case, every arm ending in return / echo / printf / exit (one of them a result).
inline bool resultArms( const sh::Tree& t, const sh::Node& c )
{
    bool result = false;
    for( const std::uint32_t body : c.bodies )
    {
        const std::uint32_t last = lastCommandOf( t, body );
        if( last == sh::kNone || t.nodes[last].kind != sh::NodeKind::Simple || t.nodes[last].words.empty() )
        {
            return false;
        }
        const std::string& w = t.nodes[last].words[0].text;
        if( w != "return" && w != "echo" && w != "printf" && w != "exit" )
        {
            return false;
        }
        result = result || w != "exit";
    }
    return result;
}

// The one name every arm of the case assigns, each arm being that single assignment; empty otherwise.
inline std::string assignedName( const sh::Tree& t, const sh::Node& c, std::vector<std::uint32_t>& at )
{
    std::string name;
    for( const std::uint32_t body : c.bodies )
    {
        const std::uint32_t only = ( body < t.lists.size() && t.lists[body].size() == 1 ) ? lastCommandOf( t, body ) : sh::kNone;
        if( only == sh::kNone || t.nodes[only].kind != sh::NodeKind::Simple || !t.nodes[only].words.empty() || t.nodes[only].assigns.size() != 1 )
        {
            return {};
        }
        const sh::Word&   a  = t.nodes[only].assigns[0];
        const std::string v  = a.text.substr( 0, a.text.find_first_of( "+=[" ) );
        if( !name.empty() && v != name )
        {
            return {};
        }
        name = v;
        at.push_back( a.pos );
    }
    return name;
}

inline bool isNameByte( char c ) noexcept
{
    return isIdentChar( c );
}

// `name` written anywhere in `src` but at the arm positions `armAt` (an assignment, a read, a for, a ${name:=…});
// a $name / ${name} read is not a write.
inline bool writtenElsewhere( std::string_view src, std::string_view name, const std::vector<std::uint32_t>& armAt )
{
    for( std::size_t i = src.find( name ); i != std::string_view::npos; i = src.find( name, i + 1 ) )
    {
        const std::size_t e = i + name.size();
        if( ( i > 0 && isNameByte( src[i - 1] ) ) || ( e < src.size() && isNameByte( src[e] ) ) || std::find( armAt.begin(), armAt.end(), i ) != armAt.end() )
        {
            continue;
        }
        const bool read    = i > 0 && ( src[i - 1] == '$' || ( src[i - 1] == '{' && i > 1 && src[i - 2] == '$' ) );
        const bool default_ = read && e + 1 < src.size() && ( src.substr( e, 2 ) == ":=" || src[e] == '=' );
        if( !read || default_ )
        {
            return true;
        }
    }
    return false;
}

// Is `name` read ($name, ${name…}) in src[b, e)?
inline bool readIn( std::string_view src, std::string_view name, std::size_t b, std::size_t e )
{
    for( std::size_t i = src.find( name, b ); i != std::string_view::npos && i < e; i = src.find( name, i + 1 ) )
    {
        const std::size_t end = i + name.size();
        const bool        ref = i > 0 && ( src[i - 1] == '$' || ( src[i - 1] == '{' && i > 1 && src[i - 2] == '$' ) );
        if( ref && ( end >= src.size() || !isNameByte( src[end] ) ) )
        {
            return true;
        }
    }
    return false;
}

// The literal words of the `for` loop at node `f` (`for v in a b c; do`), read off the source; empty when a word is not
// a plain literal (an expansion, a glob, a substitution) or the loop has no `in` list.
inline std::vector<std::string> forWords( std::string_view src, const sh::Node& f )
{
    std::vector<std::string> words;
    std::size_t              i = f.pos;
    const std::size_t        stop = src.find_first_of( ";\n", i );
    const std::string_view   head = src.substr( i, ( stop == std::string_view::npos ? src.size() : stop ) - i );
    const std::size_t        in   = head.find( " in " );
    if( in == std::string_view::npos )
    {
        return words;
    }
    std::string_view rest = head.substr( in + 4 );
    while( !rest.empty() )
    {
        const std::size_t b = rest.find_first_not_of( " \t" );
        if( b == std::string_view::npos )
        {
            break;
        }
        const std::size_t e = rest.find_first_of( " \t", b );
        const std::string w = sh::detail::unq( rest.substr( b, e == std::string_view::npos ? std::string_view::npos : e - b ) );
        if( w.empty() || w.find_first_of( "$`*?[(" ) != std::string::npos )
        {
            return {};
        }
        words.push_back( w );
        rest = e == std::string_view::npos ? std::string_view() : rest.substr( e );
    }
    return words;
}

// Is the case's subject the variable of a `for` loop before it whose every literal word some arm's pattern matches —
// a case over the loop's own list, exhaustive by construction?
inline bool coversForList( std::string_view src, const sh::Tree& t, const sh::Node& c )
{
    std::string v = sh::detail::unq( c.caseSubject );
    v.erase( 0, v.starts_with( '$' ) ? 1 : 0 );
    if( v.size() > 2 && v.front() == '{' && v.back() == '}' )
    {
        v = v.substr( 1, v.size() - 2 );
    }
    for( const sh::Node& f : t.nodes )
    {
        if( f.kind != sh::NodeKind::For || f.name != v || f.pos >= c.pos )
        {
            continue;
        }
        const std::vector<std::string> words = forWords( src, f );
        const bool all = !words.empty() && std::all_of( words.begin(), words.end(), [ & ]( const std::string& w )
                         {
                             return std::any_of( c.casePats.begin(), c.casePats.end(), [ & ]( const std::vector<std::string>& pats )
                                                 { return std::any_of( pats.begin(), pats.end(), [ & ]( const std::string& p ) { return sh::detail::globMatch( w, sh::detail::unq( p ) ); } ); } );
                         } );
        if( all )
        {
            return true;
        }
    }
    return false;
}

// The byte after the `esac` that closes a case whose last arm starts at `lastArm` (the arms are single commands, so
// the first esac word after it is the case's own).
inline std::size_t esacAfter( std::string_view src, std::size_t lastArm )
{
    for( std::size_t i = src.find( "esac", lastArm ); i != std::string_view::npos; i = src.find( "esac", i + 1 ) )
    {
        if( ( i == 0 || !isNameByte( src[i - 1] ) ) && ( i + 4 >= src.size() || !isNameByte( src[i + 4] ) ) )
        {
            return i + 4;
        }
    }
    return src.size();
}

// How a row names the case's subject.
inline std::string subjectOf( const sh::Node& c )
{
    return c.caseSubject.empty() ? std::string( "the subject" ) : c.caseSubject;
}

// Form 1: a function whose last command is a case with no *) arm whose arms give its result (return/echo/printf).
inline void endingCaseSites( std::string_view src, const sh::Tree& t, std::vector<Site>& out )
{
    for( const sh::Node& f : t.nodes )
    {
        const std::uint32_t body = f.kind == sh::NodeKind::Func && !f.bodies.empty() ? lastCommandOf( t, f.bodies[0] ) : sh::kNone;
        const bool          grouped = body != sh::kNone && ( t.nodes[body].kind == sh::NodeKind::Group || t.nodes[body].kind == sh::NodeKind::Subshell ) && !t.nodes[body].bodies.empty();
        const std::uint32_t c = grouped ? lastCommandOf( t, t.nodes[body].bodies[0] ) : sh::kNone;
        if( c == sh::kNone || t.nodes[c].kind != sh::NodeKind::Case )
        {
            continue;
        }
        const sh::Node& cs = t.nodes[c];
        if( cs.bodies.size() >= 2 && !hasCatchAll( cs ) && resultArms( t, cs ) && !coversForList( src, t, cs ) )
        {
            out.push_back( { Facet::UnhandledArm, cs.pos, "case " + collapseSpaces( cs.name ) + " ends " + f.name, {},
                             "no *) arm: an unmatched " + subjectOf( cs ) + " returns 0 and prints nothing" } );
        }
    }
}

// Form 2: a case with no *) arm whose every arm sets one name, read after esac within the enclosing function.
inline void assignedCaseSites( std::string_view src, const sh::Tree& t, const std::vector<Span>& fnSpans, std::vector<Site>& out )
{
    for( const sh::Node& cs : t.nodes )
    {
        std::vector<std::uint32_t> at;
        const std::string          v = cs.kind == sh::NodeKind::Case && cs.bodies.size() >= 2 && !hasCatchAll( cs ) ? assignedName( t, cs, at ) : std::string();
        if( v.empty() || at.size() != cs.bodies.size() || writtenElsewhere( src, v, at ) || coversForList( src, t, cs ) )
        {
            continue;
        }
        std::size_t scopeEnd = src.size();
        for( const Span& sp : fnSpans )
        {
            scopeEnd = ( sp.begin <= cs.pos && cs.pos < sp.end && sp.end < scopeEnd ) ? sp.end : scopeEnd;
        }
        const std::size_t esac = esacAfter( src, at.back() );
        if( esac < scopeEnd && readIn( src, v, esac, scopeEnd ) )
        {
            out.push_back( { Facet::UnhandledArm, cs.pos, "case " + collapseSpaces( cs.name ) + " sets " + v, {},
                             "no *) arm: an unmatched " + subjectOf( cs ) + " leaves " + v + " unset" } );
        }
    }
}

}   // namespace uash

// Bash: a case with no *) arm whose result is read, in either form.
inline void scanUnhandledArmBash( std::string_view src, const std::vector<Span>& fnSpans, std::vector<Site>& out, bool* cut = nullptr )
{
    if( src.find( "esac" ) == std::string_view::npos )
    {
        return;
    }
    const rw::shstatus::Tree t = parseShellScan( src, cut );
    if( t.cut )
    {
        // CR721: a cut inside a quoted substitution makes the rest of the file one word, so a *) arm and its esac past the
        // cut are lost and the prefix reads as a case with no catch-all. A cut tree is not judged (as scanVacuousAssertBash).
        return;
    }
    uash::endingCaseSites( src, t, out );
    uash::assignedCaseSites( src, t, fnSpans, out );
}

// What a C-family scan reads beside the file: the tree's macro names (format-arity's F1 skip), whether the C++
// shapes apply, and the tree's enums (unhandled-arm's closed sets; null or empty: no unhandled-arm scan).
struct CFamilyScan
{
    const std::vector<std::string>* treeMacros = nullptr;
    bool                            cppShapes  = false;
    const EnumTable*                enums      = nullptr;
};

// The C family's scan: format-arity over the whole file and utf8-cut / dedup-first inside each function span when
// `how.cppShapes` (C++), unchecked-status and unhandled-arm inside each span always. A site found in nested spans is
// reported once (the scan of each span is independent; the caller anchors by byte).
inline std::vector<Site> scanCFamily( std::string_view src, const std::vector<Span>& fnSpans, const CFamilyScan& how )
{
    const auto [ treeMacros, cppShapes, enums ] = how;
    std::vector<Site>      out;
    CppPreproc             pp;
    const std::vector<Tok> toks = lexCpp( src, &pp );
    if( cppShapes )
    {
        scanFormatArityCpp( src, toks, pp, treeMacros, out );
    }
    for( const Span& sp : fnSpans )
    {
        const auto [ from, to ] = tokRangeOf( toks, sp );
        if( from >= to )
        {
            continue;
        }
        if( cppShapes )
        {
            scanUtf8CutFunction( src, toks, from, to, out );
            scanDedupFirstFunction( src, toks, from, to, out );
        }
        scanUncheckedStatusCpp( src, toks, from, to, out );
        if( enums != nullptr && enums->size() != 0 )
        {
            scanUnhandledArmCpp( src, toks, pp, from, to, *enums, out );
        }
    }
    std::sort( out.begin(), out.end(), []( const Site& a, const Site& b ) { return a.startByte != b.startByte ? a.startByte < b.startByte : a.text < b.text; } );
    out.erase( std::unique( out.begin(), out.end(), []( const Site& a, const Site& b ) { return a.facet == b.facet && a.startByte == b.startByte && a.text == b.text; } ),
               out.end() );
    return out;
}

// Does `src` hold any of `needles` (a byte prefilter)?
inline bool holdsAnyOf( std::string_view src, std::span<const std::string_view> needles ) noexcept
{
    return std::any_of( needles.begin(), needles.end(), [ & ]( std::string_view n ) { return src.find( n ) != std::string_view::npos; } );
}

}   // namespace detail

// ─── the per-language entry points ──────────────────────────────────────────────────────────────────────

// C++: format-arity over the whole file; utf8-cut, dedup-first, unchecked-status and unhandled-arm inside each function
// span. `treeMacros`: the macro names the index holds across the tree (sorted, unique), for format-arity's F1 skip;
// `enums`: the tree's enums (cEnumsOf over every C-family file), the closed sets unhandled-arm checks a switch against.
inline std::vector<Site> scanCpp( std::string_view src, const std::vector<Span>& fnSpans, const std::vector<std::string>* treeMacros = nullptr,
                                  const EnumTable* enums = nullptr )
{
    return detail::scanCFamily( src, fnSpans, { treeMacros, /*cppShapes=*/true, enums } );
}

// C: unchecked-status and unhandled-arm, inside each function span (the C++ shapes name C++ library calls).
inline std::vector<Site> scanC( std::string_view src, const std::vector<Span>& fnSpans, const EnumTable* enums = nullptr )
{
    return detail::scanCFamily( src, fnSpans, { .enums = enums } );   // no C++ shapes, no tree macros
}

// Python: format-arity over the whole file; unchecked-status reads `fnSpans` for the scope a bound name lives in.
inline std::vector<Site> scanPython( std::string_view src, const std::vector<Span>& fnSpans = {} )
{
    std::vector<Site>              out;
    const std::vector<detail::Tok> toks = detail::lexPython( src );
    if( src.find( ".format" ) != std::string_view::npos )
    {
        detail::scanFormatArityPython( src, toks, out );
    }
    if( src.find( "subprocess" ) != std::string_view::npos || src.find( "system" ) != std::string_view::npos )
    {
        detail::scanUncheckedStatusPython( src, toks, fnSpans, out );
    }
    if( src.find( "elif" ) != std::string_view::npos || src.find( "match" ) != std::string_view::npos )
    {
        detail::scanUnhandledArmPython( src, toks, fnSpans, out );
    }
    return out;
}

// Bash, for a test-script path only (the caller decides the path): `fnSpans` are the script's function
// definitions, the scopes a capture and its guards are matched in. `cut` (optional) is set when the shell nesting budget
// (shstatus kMaxShellNest) stopped the parse.
inline std::vector<Site> scanBashTestScript( std::string_view src, const std::vector<Span>& fnSpans, bool* cut = nullptr )
{
    return detail::scanVacuousAssertBash( src, fnSpans, cut );
}

// Bash, any path: unhandled-arm (a case with no *) arm whose result is read), appended to `out`.
using detail::scanUnhandledArmBash;

inline constexpr std::array<std::string_view, 6> kGeneratedMarks = { "DO NOT EDIT", "@generated", "Code generated", "generated by", "Generated by", "auto-generated" };

// Generated code (a header marker in its first 2 KB, or a generated-file path): unhandled-arm judges none of it —
// its switches are the generator's, and the fix is in the generator.
inline bool looksGenerated( std::string_view rel, std::string_view src ) noexcept
{
    return detail::holdsAnyOf( src.substr( 0, 2048 ), kGeneratedMarks ) || rel.find( "/generated/" ) != std::string_view::npos || rel.starts_with( "generated/" )
        || rel.find( ".pb." ) != std::string_view::npos
        || rel.ends_with( "_pb2.py" );
}

// A cheap byte prefilter for unchecked-status: does the file name any of its calls? ("close" covers fclose and
// pclose, "write" its own.)
inline bool mayHoldStatusCalls( std::string_view src ) noexcept
{
    return src.find( "close" ) != std::string_view::npos || src.find( "rename" ) != std::string_view::npos || src.find( "write" ) != std::string_view::npos
        || src.find( "waitpid" ) != std::string_view::npos || src.find( "system" ) != std::string_view::npos || src.find( "fflush" ) != std::string_view::npos;
}

// A cheap byte prefilter: can this C++ file hold any of the C++ shapes at all?
inline bool cppMayHoldShapes( std::string_view src ) noexcept
{
    static constexpr std::array<std::string_view, 7> kNeedles = { "format", "print", "emitTo", "unique", "...", "\xE2\x80\xA6", "u2026" };
    // "format" also covers formatTo; the escaped ellipsis "\xE2\x80\xA6" is found through its "xE2" bytes below
    return detail::holdsAnyOf( src, kNeedles ) || src.find( "xE2" ) != std::string_view::npos || mayHoldStatusCalls( src ) || src.find( "switch" ) != std::string_view::npos;
}

}   // namespace rw::defectshape
