#pragma once

// shstatus.h — does a shell script TEST the exit status of each command it runs under test? The C++ port of
// test/lib/exitstatus.py (B43, #626): ONE matcher, two hosts. The Python copy is the repo lint (test/gateexitcheck.sh
// arm H gates the never-optional shapes over test/*.sh); this copy is the same matcher inside the binary, where
// --quality-delta's defect-shape vacuous-assert facet reads it for an agent's own shell tests. gateexitcheck arm (H4)
// runs both over every gate and fails on any call the two classify differently, so the copies cannot drift; the
// Python docstring is the contract, and a change lands in both files with that arm green.
//
//   scan( text ) -> Call( line, cmd, verdict, how, kind ), sorted as Python sorts its tuples.
//
// A command is UNDER TEST when its command word is the ripwire binary (a variable named BIN, *_BIN, BIN_*, RIPWIRE, RW
// or HARNESS, or any variable assigned a value naming build/ripwire or $RIPWIRE_BIN), a harness the script compiled (the
// -o target of a compiler command), a word containing `harness`, or a shell function whose own status IS such a
// command's status (a wrapper, resolved to a fixpoint). "Tests its status" means: inside an if/elif/while/until
// condition; a later `||` in the same and-or list whose right side is not true/:; $? (or PIPESTATUS) read by the very
// next statement, directly in a test or into a variable / rc file some test compares; set -e in effect where errexit
// can fire; or the call is the script's last statement. A pipe stage counts only under pipefail.
//
// Beyond the contract (additive, read by the facet only; Call rows never depend on them): every redirect with its fd,
// a compound's redirects, a case's subject and arm patterns, byte positions, and the resolved consumer of EVERY simple
// command (not only the ones under test), so the facet can ask what any producer's status reaches.
//
// Regular expressions are spelled as small hand matchers (the binary links no regex engine for this); each names the
// Python pattern it implements.

#include "infra/namesplit.h"   // isIdentChar / isIdentStart — the ONE ASCII identifier-character pair
#include "infra/shellword.h"   // trimView / shellIsRedirect — shared with darkflags.h
#include "infra/sortutil.h"    // sortUnique / svLess

#include <algorithm>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw::shstatus
{

inline constexpr std::uint32_t kNone = UINT32_MAX;

struct Sub
{
    std::string   inner;
    std::uint32_t line = 0;
    std::uint32_t pos  = 0;      // byte offset of `inner` in the scanned file
    std::uint32_t list = kNone;  // the parsed inner list (Tree::lists), kNone past the nesting cap
};

struct Word
{
    std::string      text;
    std::uint32_t    line = 0;
    std::uint32_t    pos  = 0;
    std::vector<Sub> subs;
};

enum class NodeKind : std::uint8_t
{
    Simple,
    Subshell,
    Group,
    If,
    Loop,
    For,
    Case,
    Func,
};

// One redirect as the shell applies it (facet-only): the operator, the fd it redirects (-1 = the operator's default:
// stdout for > >> >| &> &>>, stdin for < <<<), and the target word as written.
struct Redir
{
    std::string op;
    int         fd = -1;
    std::string target;
    std::uint32_t targetPos = 0;
};

struct Node
{
    NodeKind                       kind = NodeKind::Simple;
    std::uint32_t                  line = 0;
    std::uint32_t                  pos  = 0;
    std::vector<Word>              words;     // Simple: the command words after the leading NAME=value assignments
    std::vector<Word>              assigns;   // Simple: the leading NAME=value words
    std::vector<std::string>       redirs;    // Simple: Python's "op target" strings (they feed _text)
    std::vector<Redir>             fredirs;   // every redirect, Simple and compound (facet)
    std::vector<std::uint32_t>     conds;     // list ids
    std::vector<std::uint32_t>     bodies;    // list ids
    std::string                    name;      // func: its name; case: subject + pattern words (Python's spelling); for: its loop variable (facet)
    std::string                    caseSubject;                 // facet
    std::vector<std::vector<std::string>> casePats;             // facet: each arm's pattern words
};

enum class Link : std::uint8_t
{
    None,
    And,
    Or,
};

struct Item   // one pipeline of an and-or list, with the operator before it
{
    Link                       op  = Link::None;
    bool                       neg = false;
    std::vector<std::uint32_t> cmds;
};
using AndOr = std::vector<Item>;
using List  = std::vector<AndOr>;

struct Tree
{
    std::vector<Node> nodes;
    std::vector<List> lists;
    std::uint32_t     top = kNone;
    bool              cut = false;   // the nesting budget (kMaxShellNest) stopped the scan: what lies past it was not parsed
};

// ONE nesting budget for the lexer and the parser (CR712-SHSTATUS-DEPTH): every recursion of either — a quote or $( ) the
// lexer skips through, a compound command or a substitution the parser descends into — takes a level, so a script nested
// past kMaxShellNest is cut there (Tree::cut) instead of exhausting the stack (20,000 nested subshells crashed the scan).
inline constexpr int kMaxShellNest = 64;
struct NestBudget
{
    int  depth = 0;
    bool cut   = false;
};
// One level of the budget for the scope of a recursion; `over` = the budget is spent (and the cut is recorded).
class NestLevel
{
public:
    explicit NestLevel( NestBudget& b ) noexcept : b_( b )
    {
        over_  = b_.depth >= kMaxShellNest;
        b_.cut = b_.cut || over_;   // the disclosure: Tree::cut, then the answer's shell_cut= (quality.h defectSitesOf)
        ++b_.depth;
    }
    ~NestLevel() { --b_.depth; }
    NestLevel( const NestLevel& )            = delete;
    NestLevel& operator=( const NestLevel& ) = delete;
    bool over() const noexcept { return over_; }

private:
    NestBudget& b_;
    bool        over_ = false;
};

namespace detail
{

using rw::namesplit::isIdentChar;    // [A-Za-z0-9_]
using rw::namesplit::isIdentStart;   // [A-Za-z_]
using rw::shellword::shellIsRedirect;
using rw::shellword::trimView;
using rw::sortutil::sortUnique;
inline bool isWordChar( char c ) noexcept   // Python's \w on str: ASCII word characters, and any non-ASCII byte
{
    return isIdentChar( c ) || static_cast<unsigned char>( c ) >= 0x80;
}
inline bool isUpperIdent( char c ) noexcept   // [A-Z0-9_]
{
    return ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_';
}
inline bool isSp( char c ) noexcept           // \s, ASCII
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}
inline bool isDigitC( char c ) noexcept
{
    return c >= '0' && c <= '9';
}
inline bool startsAt( std::string_view s, std::size_t i, std::string_view p ) noexcept
{
    return i <= s.size() && s.substr( i, p.size() ) == p;
}
inline std::size_t countNl( std::string_view s, std::size_t b, std::size_t e ) noexcept
{
    e = std::min( e, s.size() );
    return b >= e ? 0 : static_cast<std::size_t>( std::count( s.begin() + static_cast<std::ptrdiff_t>( b ), s.begin() + static_cast<std::ptrdiff_t>( e ), '\n' ) );
}
inline std::string_view sliceOf( std::string_view s, std::size_t b, std::size_t e ) noexcept   // Python s[b:e], clamped
{
    b = std::min( b, s.size() );
    e = std::min( e, s.size() );
    return e <= b ? std::string_view{} : s.substr( b, e - b );
}

// unq(s): every quote character removed.
inline std::string unq( std::string_view s )
{
    std::string out;
    out.reserve( s.size() );
    for( char c : s )
    {
        if( c != '"' && c != '\'' )
        {
            out.push_back( c );
        }
    }
    return out;
}

// ^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=
inline bool isAssign( std::string_view s ) noexcept
{
    if( s.empty() || !isIdentStart( s[0] ) )
    {
        return false;
    }
    std::size_t i = 1;
    while( i < s.size() && isIdentChar( s[i] ) )
    {
        ++i;
    }
    if( i < s.size() && s[i] == '[' )
    {
        const std::size_t close = s.find( ']', i + 1 );
        if( close != std::string_view::npos )
        {
            const std::size_t after = close + 1;
            if( ( after < s.size() && s[after] == '=' ) || ( after + 1 < s.size() && s[after] == '+' && s[after + 1] == '=' ) )
            {
                return true;
            }
        }
    }
    return ( i < s.size() && s[i] == '=' ) || ( i + 1 < s.size() && s[i] == '+' && s[i + 1] == '=' );
}

// ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$  -> the name, or empty
inline std::string_view bareVar( std::string_view w ) noexcept
{
    if( w.size() < 2 || w[0] != '$' )
    {
        return {};
    }
    std::size_t i = 1;
    if( w[i] == '{' )
    {
        ++i;
    }
    if( i >= w.size() || !isIdentStart( w[i] ) )
    {
        return {};
    }
    const std::size_t b = i;
    while( i < w.size() && isIdentChar( w[i] ) )
    {
        ++i;
    }
    const std::size_t e = i;
    if( i < w.size() && w[i] == '}' )
    {
        ++i;
    }
    return i == w.size() ? w.substr( b, e - b ) : std::string_view{};
}

// ^"?\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?"?$  -> the name, or empty
inline std::string_view quotedBareVar( std::string_view w ) noexcept
{
    std::string_view x = w;
    if( !x.empty() && x.front() == '"' )
    {
        x.remove_prefix( 1 );
    }
    std::string_view n = bareVar( x );
    if( !n.empty() )
    {
        return n;
    }
    if( !x.empty() && x.back() == '"' )
    {
        x.remove_suffix( 1 );
        return bareVar( x );
    }
    return {};
}

// BINVAR = ^(?:[A-Z0-9_]*_)?BIN(?:_?[A-Z0-9]*)?$|^RIPWIRE$|^RW$|^[A-Z_]*HARNESS[A-Z_0-9]*$
inline bool isHarnessVar( std::string_view s ) noexcept   // ^[A-Z_]*HARNESS[A-Z_0-9]*$
{
    for( std::size_t p = s.find( "HARNESS" ); p != std::string_view::npos; p = s.find( "HARNESS", p + 1 ) )
    {
        const bool pre  = std::all_of( s.begin(), s.begin() + static_cast<std::ptrdiff_t>( p ), []( char c ) { return ( c >= 'A' && c <= 'Z' ) || c == '_'; } );
        const bool post = std::all_of( s.begin() + static_cast<std::ptrdiff_t>( p + 7 ), s.end(), isUpperIdent );
        if( pre && post )
        {
            return true;
        }
    }
    return false;
}
inline bool isBinVar( std::string_view s ) noexcept
{
    if( s == "RIPWIRE" || s == "RW" || isHarnessVar( s ) )
    {
        return true;
    }
    for( std::size_t p = s.find( "BIN" ); p != std::string_view::npos; p = s.find( "BIN", p + 1 ) )
    {
        const bool pre = p == 0 || ( s[p - 1] == '_' && std::all_of( s.begin(), s.begin() + static_cast<std::ptrdiff_t>( p ), isUpperIdent ) );
        std::size_t q = p + 3;
        if( q < s.size() && s[q] == '_' )
        {
            ++q;
        }
        const bool post = std::all_of( s.begin() + static_cast<std::ptrdiff_t>( q ), s.end(), []( char c ) { return ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ); } );
        if( pre && post )
        {
            return true;
        }
    }
    return false;
}
// NOTBIN = ^(?:CC|CXX|C|CLANG|GCC|COMPILER|PY|PYTHON|GIT|REALGIT)_BIN$|^[A-Z_]*(?:CC|CXX)_BIN$
inline bool isNotBin( std::string_view s ) noexcept
{
    static constexpr std::string_view kExact[] = { "CC_BIN", "CXX_BIN", "C_BIN", "CLANG_BIN", "GCC_BIN", "COMPILER_BIN", "PY_BIN", "PYTHON_BIN", "GIT_BIN", "REALGIT_BIN" };
    for( std::string_view e : kExact )
    {
        if( s == e )
        {
            return true;
        }
    }
    for( std::string_view suf : { std::string_view( "CC_BIN" ), std::string_view( "CXX_BIN" ) } )
    {
        if( s.size() >= suf.size() && s.substr( s.size() - suf.size() ) == suf
            && std::all_of( s.begin(), s.end() - static_cast<std::ptrdiff_t>( suf.size() ), []( char c ) { return ( c >= 'A' && c <= 'Z' ) || c == '_'; } ) )
        {
            return true;
        }
    }
    return false;
}
// COMPILER = ^(?:c\+\+|g\+\+|clang\+\+|clang|cc|gcc|cl|clang-cl|xcrun|\$\{?CXX\}?|\$\{?CC\}?)$
inline bool isCompiler( std::string_view s ) noexcept
{
    static constexpr std::string_view kNames[] = { "c++", "g++", "clang++", "clang", "cc", "gcc", "cl", "clang-cl", "xcrun" };
    for( std::string_view n : kNames )
    {
        if( s == n )
        {
            return true;
        }
    }
    for( std::string_view v : { std::string_view( "CXX" ), std::string_view( "CC" ) } )
    {
        std::string_view x = s;
        if( x.empty() || x[0] != '$' )
        {
            continue;
        }
        x.remove_prefix( 1 );
        if( !x.empty() && x.front() == '{' )
        {
            x.remove_prefix( 1 );
        }
        if( !x.empty() && x.back() == '}' )
        {
            x.remove_suffix( 1 );
        }
        if( x == v )
        {
            return true;
        }
    }
    return false;
}

// fnmatch.fnmatchcase: * ? [seq] [!seq], everything else literal.
inline bool globMatch( std::string_view s, std::string_view p ) noexcept
{
    std::size_t si = 0, pi = 0, starP = std::string_view::npos, starS = 0;
    const auto classAt = [ & ]( std::size_t at, char c, std::size_t& next ) -> int   // -1 no class here, 0 no match, 1 match
    {
        if( p[at] != '[' )
        {
            return -1;
        }
        std::size_t j = at + 1;
        bool        negate = false;
        if( j < p.size() && p[j] == '!' )
        {
            negate = true;
            ++j;
        }
        if( j < p.size() && p[j] == ']' )
        {
            ++j;
        }
        while( j < p.size() && p[j] != ']' )
        {
            ++j;
        }
        if( j >= p.size() )
        {
            return -1;   // no closing ]: a literal [
        }
        bool        hit = false;
        std::size_t k   = at + 1 + ( negate ? 1 : 0 );
        const std::size_t end = j;
        bool first = true;
        while( k < end )
        {
            if( !first && p[k] == ']' )
            {
                break;
            }
            first = false;
            if( k + 2 < end && p[k + 1] == '-' )
            {
                hit = hit || ( c >= p[k] && c <= p[k + 2] );
                k += 3;
            }
            else
            {
                hit = hit || c == p[k];
                ++k;
            }
        }
        next = end + 1;
        return ( hit != negate ) ? 1 : 0;
    };
    while( si < s.size() )
    {
        std::size_t next = 0;
        if( pi < p.size() && p[pi] == '*' )
        {
            starP = pi++;
            starS = si;
            continue;
        }
        if( pi < p.size() )
        {
            const int cls = classAt( pi, s[si], next );
            if( cls == 1 || ( cls == -1 && ( p[pi] == '?' || p[pi] == s[si] ) ) )
            {
                pi = cls == 1 ? next : pi + 1;
                ++si;
                continue;
            }
        }
        if( starP != std::string_view::npos )
        {
            pi = starP + 1;
            si = ++starS;
            continue;
        }
        return false;
    }
    while( pi < p.size() && p[pi] == '*' )
    {
        ++pi;
    }
    return pi == p.size();
}

// ── lexer ───────────────────────────────────────────────────────────────────────────────────────────────────────────
enum class TokKind : std::uint8_t
{
    Word,
    Op,
    Nl,
    Eof,
};

struct Tok
{
    TokKind       kind = TokKind::Eof;
    std::string   op;      // Op: the operator text
    Word          word;    // Word
    std::uint32_t line  = 0;
    std::uint32_t pos   = 0;
    bool          glued = false;   // no blank between this token and the previous one (an fd digit before a redirect)
};

inline constexpr std::string_view kOps[] = { "&&", "||", ";;&", ";;", ";&", "|&", "<<<", "<<-", "<<", ">>", "&>>", "&>", ">&", "<&", "<>", ">|",
                                             ";",  "|",  "&",   "(",  ")",  "<",  ">" };
inline bool isOpChar( char c ) noexcept
{
    return c == '&' || c == '|' || c == ';' || c == '(' || c == ')' || c == '<' || c == '>';
}
inline bool isRedirOp( std::string_view o ) noexcept
{
    return o == "<" || o == ">" || o == ">>" || o == "&>" || o == "&>>" || o == ">&" || o == "<&" || o == "<>" || o == ">|" || o == "<<<" || o == "<<";
}

std::size_t skipParen( std::string_view s, std::size_t i, NestBudget& nb );
inline std::size_t skipQuote( std::string_view s, std::size_t i, char q, NestBudget& nb )   // s[i] is the opening quote
{
    const NestLevel level( nb );
    if( level.over() )
    {
        return s.size();   // past the budget: the rest is one unscanned word (Tree::cut says so)
    }
    ++i;
    while( i < s.size() )
    {
        const char c = s[i];
        if( q == '"' && c == '\\' )
        {
            i += 2;
            continue;
        }
        if( q == '"' && c == '$' && startsAt( s, i, "$(" ) )
        {
            i = skipParen( s, i + 1, nb );
            continue;
        }
        if( q == '"' && c == '`' )
        {
            const std::size_t j = s.find( '`', i + 1 );
            i = j == std::string_view::npos ? s.size() : j + 1;
            continue;
        }
        if( c == q )
        {
            return i + 1;
        }
        ++i;
    }
    return i;
}
inline std::size_t skipParen( std::string_view s, std::size_t i, NestBudget& nb )   // s[i] == '('
{
    const NestLevel level( nb );
    if( level.over() )
    {
        return s.size();
    }
    int depth = 0;
    while( i < s.size() )
    {
        const char c = s[i];
        if( c == '\\' )
        {
            i += 2;
            continue;
        }
        if( c == '\'' || c == '"' )
        {
            i = skipQuote( s, i, c, nb );
            continue;
        }
        if( c == '#' && ( i == 0 || s[i - 1] == ' ' || s[i - 1] == '\t' || s[i - 1] == '\n' || s[i - 1] == ';' || s[i - 1] == '(' ) )
        {
            const std::size_t j = s.find( '\n', i );
            i = j == std::string_view::npos ? s.size() : j;
            continue;
        }
        if( c == '(' )
        {
            ++depth;
        }
        else if( c == ')' )
        {
            --depth;
            if( depth == 0 )
            {
                return i + 1;
            }
        }
        ++i;
    }
    return i;
}
inline std::size_t skipBrace( std::string_view s, std::size_t i, NestBudget& nb )   // s[i] == '{' of a ${...}
{
    const NestLevel level( nb );
    if( level.over() )
    {
        return s.size();
    }
    int depth = 0;
    while( i < s.size() )
    {
        const char c = s[i];
        if( c == '\\' )
        {
            i += 2;
            continue;
        }
        if( c == '\'' || c == '"' )
        {
            i = skipQuote( s, i, c, nb );
            continue;
        }
        if( c == '{' )
        {
            ++depth;
        }
        else if( c == '}' )
        {
            --depth;
            if( depth == 0 )
            {
                return i + 1;
            }
        }
        ++i;
    }
    return i;
}

// A double-quoted text with its own single quotes blanked: they are literal there ("don't"), but a quote inside a $( )
// or ` ` it holds is live ("$( grep -o '<r ' f )" keeps '<r ' one word, not a < redirect). exitstatus.py's
// _dq_literal_quotes.
inline std::string dqLiteralQuotes( std::string_view s, NestBudget& nb )
{
    std::string out( s );
    std::size_t i = 0;
    while( i < s.size() )
    {
        const char c = s[i];
        if( c == '\\' )
        {
            i += 2;
            continue;
        }
        if( startsAt( s, i, "$(" ) )
        {
            i = skipParen( s, i + 1, nb );
            continue;
        }
        if( c == '`' )
        {
            const std::size_t j = s.find( '`', i + 1 );
            i                   = j == std::string_view::npos ? s.size() : j + 1;
            continue;
        }
        if( c == '\'' )
        {
            out[i] = ' ';
        }
        ++i;
    }
    return out;
}

// Command substitutions $( ... ) and ` ... ` inside one word (outside single quotes), with their lines and positions.
inline void subsIn( std::string_view raw, std::uint32_t line, std::uint32_t base, std::vector<Sub>& out, NestBudget& nb )
{
    std::size_t i = 0;
    while( i < raw.size() )
    {
        const char c = raw[i];
        if( c == '\\' )
        {
            i += 2;
            continue;
        }
        if( c == '\'' )
        {
            i = skipQuote( raw, i, '\'', nb );
            continue;
        }
        if( startsAt( raw, i, "$((" ) )
        {
            i = skipParen( raw, i + 1, nb );
            continue;
        }
        if( startsAt( raw, i, "$(" ) )
        {
            const std::size_t j = skipParen( raw, i + 1, nb );
            out.push_back( { std::string( sliceOf( raw, i + 2, j - 1 ) ), static_cast<std::uint32_t>( line + countNl( raw, 0, i ) ), static_cast<std::uint32_t>( base + i + 2 ), kNone } );
            i = j;
            continue;
        }
        if( c == '`' )
        {
            std::size_t j = raw.find( '`', i + 1 );
            j             = j == std::string_view::npos ? raw.size() : j;
            out.push_back( { std::string( sliceOf( raw, i + 1, j ) ), static_cast<std::uint32_t>( line + countNl( raw, 0, i ) ), static_cast<std::uint32_t>( base + i + 1 ), kNone } );
            i = j + 1;
            continue;
        }
        if( c == '"' )
        {
            // descend: substitutions inside double quotes are live (single quotes inside them are not quotes)
            const std::size_t j     = skipQuote( raw, i, '"', nb );
            const NestLevel   level( nb );   // the descent is a recursion of its own
            if( level.over() )
            {
                return;
            }
            subsIn( dqLiteralQuotes( sliceOf( raw, i + 1, j - 1 ), nb ), static_cast<std::uint32_t>( line + countNl( raw, 0, i ) ), static_cast<std::uint32_t>( base + i + 1 ), out, nb );
            i = j;
            continue;
        }
        ++i;
    }
}

// ['"]?\\?([A-Za-z_][A-Za-z0-9_]*)\1 at s[k]: the heredoc delimiter; returns its end (relative) or npos.
inline std::size_t heredocDelim( std::string_view s, std::size_t k, std::string& name ) noexcept
{
    const auto tryQuote = [ & ]( char q ) -> std::size_t
    {
        std::size_t i = k;
        if( q != 0 )
        {
            if( i >= s.size() || s[i] != q )
            {
                return std::string_view::npos;
            }
            ++i;
        }
        if( i < s.size() && s[i] == '\\' )
        {
            ++i;
        }
        if( i >= s.size() || !isIdentStart( s[i] ) )
        {
            return std::string_view::npos;
        }
        const std::size_t b = i;
        while( i < s.size() && isIdentChar( s[i] ) )
        {
            ++i;
        }
        // the backreference: the closing quote must follow (greedy ident; a shorter one would leave an ident char)
        if( q != 0 )
        {
            if( i >= s.size() || s[i] != q )
            {
                return std::string_view::npos;
            }
            name = std::string( s.substr( b, i - b ) );
            return i + 1;
        }
        name = std::string( s.substr( b, i - b ) );
        return i;
    };
    for( char q : { '\'', '"' } )
    {
        const std::size_t e = tryQuote( q );
        if( e != std::string_view::npos )
        {
            return e;
        }
    }
    return tryQuote( 0 );
}

// The tokenizer: one step per token class, heredoc bodies skipped as DATA at the end of their line.
class Lexer
{
public:
    Lexer( std::string_view src, std::uint32_t line0, std::uint32_t base, NestBudget& nb ) : src_( src ), n_( src.size() ), line_( line0 ), base_( base ), nb_( nb ) {}

    std::vector<Tok> run()
    {
        while( i_ < n_ )
        {
            step();
        }
        Tok t;
        t.kind = TokKind::Nl;
        t.line = line_;
        t.pos  = posAt( n_ );
        toks_.push_back( std::move( t ) );
        return std::move( toks_ );
    }

private:
    std::string_view                          src_;
    std::size_t                               n_;
    std::size_t                               i_ = 0;
    std::uint32_t                             line_;
    std::uint32_t                             base_;
    NestBudget&                               nb_;
    std::vector<std::pair<bool, std::string>> pending_;   // heredoc delimiters waiting for the end of this line
    bool                                      prevBlank_ = true;
    std::vector<Tok>                          toks_;

    std::uint32_t posAt( std::size_t at ) const noexcept
    {
        return static_cast<std::uint32_t>( base_ + at );
    }
    void push( Tok t )
    {
        t.glued    = !prevBlank_;
        prevBlank_ = false;
        toks_.push_back( std::move( t ) );
    }
    void pushOp( std::string op )
    {
        Tok t;
        t.kind = TokKind::Op;
        t.op   = std::move( op );
        t.line = line_;
        t.pos  = posAt( i_ );
        push( std::move( t ) );
    }
    // the word src[b, e) starting on line sl; its $( ) / backtick bodies are indexed when withSubs
    void pushWord( std::size_t b, std::size_t e, bool withSubs )
    {
        Tok t;
        t.kind      = TokKind::Word;
        t.word.text = std::string( src_.substr( b, e - b ) );
        t.word.line = line_;
        t.word.pos  = posAt( b );
        if( withSubs )
        {
            subsIn( t.word.text, line_, t.word.pos, t.word.subs, nb_ );
        }
        t.line = line_;
        t.pos  = t.word.pos;
        push( std::move( t ) );
        line_ += static_cast<std::uint32_t>( countNl( src_, b, e ) );
    }

    void step()
    {
        const char c = src_[i_];
        if( c == '\n' )
        {
            newline();
            return;
        }
        if( c == ' ' || c == '\t' )
        {
            prevBlank_ = true;
            ++i_;
            return;
        }
        if( c == '\\' && i_ + 1 < n_ && src_[i_ + 1] == '\n' )
        {
            prevBlank_ = true;
            i_ += 2;
            ++line_;
            return;
        }
        if( c == '#' )
        {
            const std::size_t j = src_.find( '\n', i_ );
            i_                  = j == std::string_view::npos ? n_ : j;
            return;
        }
        const std::string_view op = opAt();
        if( !op.empty() )
        {
            operatorTok( op );
            return;
        }
        word();
    }

    void newline()
    {
        Tok t;
        t.kind = TokKind::Nl;
        t.line = line_;
        t.pos  = posAt( i_ );
        push( std::move( t ) );
        prevBlank_ = true;
        ++line_;
        ++i_;
        skipHeredocBodies();
    }
    void skipHeredocBodies()   // heredoc bodies are DATA
    {
        for( const auto& [ strip, delim ] : pending_ )
        {
            while( i_ < n_ )
            {
                std::size_t j = src_.find( '\n', i_ );
                j             = j == std::string_view::npos ? n_ : j;
                std::string_view body = src_.substr( i_, j - i_ );
                i_ = j + 1;
                ++line_;
                if( strip )
                {
                    while( !body.empty() && body.front() == '\t' )
                    {
                        body.remove_prefix( 1 );
                    }
                }
                if( body == delim )
                {
                    break;
                }
            }
        }
        pending_.clear();
    }

    std::string_view opAt() const noexcept
    {
        if( !isOpChar( src_[i_] ) )
        {
            return {};
        }
        for( std::string_view o : kOps )
        {
            if( startsAt( src_, i_, o ) )
            {
                return o;
            }
        }
        return {};
    }
    void operatorTok( std::string_view op )
    {
        if( ( op == "<<" || op == "<<-" ) && heredocStart( op ) )
        {
            return;
        }
        if( op == "(" && startsAt( src_, i_, "((" ) )   // arithmetic command (( ... ))
        {
            closedWord( "))", false );
            return;
        }
        pushOp( std::string( op ) );
        i_ += op.size();
    }
    bool heredocStart( std::string_view op )
    {
        std::size_t k = i_ + op.size();
        while( k < n_ && ( src_[k] == ' ' || src_[k] == '\t' ) )
        {
            ++k;
        }
        std::string       name;
        const std::size_t e = heredocDelim( src_, k, name );
        if( e == std::string_view::npos )
        {
            return false;
        }
        pending_.emplace_back( op == "<<-", name );
        pushOp( "<<" );
        i_ = e;
        return true;
    }
    // (( ... )) and [[ ... ]]: one word through the closer (or to the end)
    void closedWord( std::string_view closer, bool withSubs )
    {
        std::size_t j = src_.find( closer, i_ );
        j             = j == std::string_view::npos ? n_ : j + closer.size();
        const std::size_t b = i_;
        i_                  = j;
        pushWord( b, j, withSubs );
    }

    void word()
    {
        if( startsAt( src_, i_, "[[" ) && ( i_ + 2 >= n_ || src_[i_ + 2] == ' ' || src_[i_ + 2] == '\t' ) )
        {
            closedWord( "]]", true );
            return;
        }
        const std::size_t start = i_;
        i_                      = std::min( wordEnd( start ), n_ );
        pushWord( start, i_, true );
    }
    std::size_t wordEnd( std::size_t start ) const
    {
        std::size_t i = start;
        while( i < n_ )
        {
            const char d = src_[i];
            if( d == ' ' || d == '\t' || d == '\n' || ( isOpChar( d ) && !( d == '(' && i > start && src_[i - 1] == '=' ) ) )
            {
                break;
            }
            i = wordStep( i, start );
        }
        return i;
    }
    // past the word byte at i: a quote, backtick, $( ), ${ } or an array X=( ... ) as a whole
    std::size_t wordStep( std::size_t i, std::size_t start ) const
    {
        const char d = src_[i];
        if( d == '\\' )
        {
            return i + 2;
        }
        if( d == '\'' || d == '"' )
        {
            return skipQuote( src_, i, d, nb_ );
        }
        if( d == '`' )
        {
            const std::size_t j = src_.find( '`', i + 1 );
            return j == std::string_view::npos ? n_ : j + 1;
        }
        if( startsAt( src_, i, "$(" ) )
        {
            return skipParen( src_, i + 1, nb_ );
        }
        if( startsAt( src_, i, "${" ) )
        {
            return skipBrace( src_, i + 1, nb_ );
        }
        if( d == '(' && i > start && src_[i - 1] == '=' )   // array assignment X=( ... )
        {
            return skipParen( src_, i, nb_ );
        }
        return i + 1;
    }
};

inline std::vector<Tok> lex( std::string_view src, std::uint32_t line0, std::uint32_t base, NestBudget& nb )
{
    return Lexer( src, line0, base, nb ).run();
}

// ── parser ──────────────────────────────────────────────────────────────────────────────────────────────────────────

struct Stops
{
    std::vector<std::string_view> s;
    bool has( std::string_view x ) const noexcept
    {
        return std::find( s.begin(), s.end(), x ) != s.end();
    }
};

class Parser
{
public:
    Parser( Tree& tree, std::vector<Tok> toks, NestBudget& nb ) : t_( std::move( toks ) ), tree_( tree ), nb_( nb ) {}

    std::uint32_t parseAll()
    {
        List out;
        while( peek().kind != TokKind::Eof )
        {
            List part = parseList( Stops{} );
            for( AndOr& ao : part )
            {
                out.push_back( std::move( ao ) );
            }
            if( peek().kind != TokKind::Eof )
            {
                ++i_;   // a stray closer: skip it
            }
        }
        return addList( std::move( out ) );
    }

private:
    std::vector<Tok> t_;
    std::size_t      i_ = 0;
    Tree&            tree_;
    NestBudget&      nb_;   // shared with the lexer and every nested Parser: one budget for the whole script
    Tok              eof_{};

    const Tok& peek() const noexcept
    {
        return i_ < t_.size() ? t_[i_] : eof_;
    }
    const Tok* at( std::size_t k ) const noexcept
    {
        return k < t_.size() ? &t_[k] : nullptr;
    }
    bool peekIs( TokKind kind, std::string_view text ) const noexcept   // the next token is this word / this operator
    {
        const Tok& p = peek();
        return p.kind == kind && ( kind == TokKind::Op ? p.op : p.word.text ) == text;
    }
    bool kw( std::string_view a ) const noexcept
    {
        return peekIs( TokKind::Word, a );
    }
    bool isOp( std::string_view o ) const noexcept
    {
        return peekIs( TokKind::Op, o );
    }
    bool stopped( const Stops& stops ) const noexcept
    {
        const Tok& p = peek();
        return ( p.kind == TokKind::Word && stops.has( p.word.text ) ) || ( p.kind == TokKind::Op && stops.has( p.op ) );
    }
    void skipNl() noexcept
    {
        while( peek().kind == TokKind::Nl || isOp( ";" ) )
        {
            ++i_;
        }
    }
    void skipOnlyNl() noexcept
    {
        while( peek().kind == TokKind::Nl )
        {
            ++i_;
        }
    }
    std::uint32_t addList( List l )
    {
        tree_.lists.push_back( std::move( l ) );
        return static_cast<std::uint32_t>( tree_.lists.size() - 1 );
    }
    std::uint32_t addNode( Node n )
    {
        tree_.nodes.push_back( std::move( n ) );
        return static_cast<std::uint32_t>( tree_.nodes.size() - 1 );
    }
    void parseSubs( Word& w )
    {
        for( Sub& s : w.subs )
        {
            const NestLevel level( nb_ );
            if( level.over() )
            {
                continue;   // past the budget: an empty list (Tree::cut says so)
            }
            Parser p( tree_, lex( s.inner, s.line, s.pos, nb_ ), nb_ );
            s.list = p.parseAll();
        }
    }

    List parseList( const Stops& stops )
    {
        List out;
        while( true )
        {
            skipNl();
            const Tok& p = peek();
            if( p.kind == TokKind::Eof || stopped( stops ) )
            {
                break;
            }
            AndOr ao = parseAndOr( stops );
            if( !ao.empty() )
            {
                out.push_back( std::move( ao ) );
            }
            else
            {
                ++i_;   // unparseable token: skip it, never loop
            }
            if( isOp( ";" ) || isOp( "&" ) )
            {
                ++i_;
            }
        }
        return out;
    }
    AndOr parseAndOr( const Stops& stops )
    {
        AndOr ao;
        Link  op = Link::None;
        while( true )
        {
            Item it;
            if( !parsePipeline( stops, it ) )
            {
                break;
            }
            it.op = op;
            ao.push_back( std::move( it ) );
            if( isOp( "&&" ) || isOp( "||" ) )
            {
                op = peek().op == "&&" ? Link::And : Link::Or;
                ++i_;
                skipOnlyNl();
                continue;
            }
            break;
        }
        return ao;
    }
    bool parsePipeline( const Stops& stops, Item& it )
    {
        bool neg = false;
        if( kw( "!" ) )
        {
            neg = true;
            ++i_;
        }
        while( true )
        {
            const std::uint32_t c = parseCommand( stops );
            if( c == kNone )
            {
                break;
            }
            it.cmds.push_back( c );
            if( isOp( "|" ) || isOp( "|&" ) )
            {
                ++i_;
                skipOnlyNl();
                continue;
            }
            break;
        }
        it.neg = neg;
        return !it.cmds.empty();
    }
    std::uint32_t parseCommand( const Stops& stops )
    {
        const NestLevel level( nb_ );   // every nested list (subshell, group, if, loop, case, function body) is reached through here
        if( level.over() )
        {
            i_ = t_.size();   // past the budget: the rest of this token stream is not parsed (Tree::cut says so)
            return kNone;
        }
        const Tok& p = peek();
        if( p.kind == TokKind::Eof || stopped( stops ) )
        {
            return kNone;
        }
        const std::uint32_t ln  = p.line;
        const std::uint32_t pos = p.pos;
        if( p.kind == TokKind::Op && p.op == "(" )
        {
            ++i_;
            Node n;
            n.kind = NodeKind::Subshell;
            n.line = ln;
            n.pos  = pos;
            n.bodies.push_back( addList( parseList( Stops{ { ")" } } ) ) );
            if( isOp( ")" ) )
            {
                ++i_;
            }
            redirs( n );
            return addNode( std::move( n ) );
        }
        if( p.kind == TokKind::Word )
        {
            const std::string tx = p.word.text;
            if( tx == "{" )
            {
                ++i_;
                Node n;
                n.kind = NodeKind::Group;
                n.line = ln;
                n.pos  = pos;
                n.bodies.push_back( addList( parseList( Stops{ { "}" } } ) ) );
                if( kw( "}" ) )
                {
                    ++i_;
                }
                redirs( n );
                return addNode( std::move( n ) );
            }
            if( tx == "if" || tx == "while" || tx == "until" )
            {
                return parseIfLoop( tx, ln, pos );
            }
            if( tx == "for" || tx == "select" )
            {
                ++i_;
                // the loop variable (facet-only: it binds a name the facet must not trace through)
                std::string var = peek().kind == TokKind::Word ? peek().word.text : std::string();
                while( !( kw( "do" ) || peek().kind == TokKind::Eof ) )
                {
                    ++i_;
                }
                ++i_;
                Node n;
                n.kind = NodeKind::For;
                n.line = ln;
                n.pos  = pos;
                n.name = std::move( var );
                n.bodies.push_back( addList( parseList( Stops{ { "done" } } ) ) );
                if( kw( "done" ) )
                {
                    ++i_;
                }
                redirs( n );
                return addNode( std::move( n ) );
            }
            if( tx == "case" )
            {
                return parseCase( ln, pos );
            }
            if( tx == "function" )
            {
                ++i_;
                std::string name = peek().kind == TokKind::Word ? peek().word.text : std::string( "?" );
                ++i_;
                if( isOp( "(" ) )
                {
                    i_ += 2;
                }
                skipOnlyNl();
                return funcNode( std::move( name ), ln, pos, parseCommand( stops ) );
            }
            // name() { ... }
            const Tok* nx  = at( i_ + 1 );
            const Tok* nx2 = at( i_ + 2 );
            if( isFuncName( tx ) && nx != nullptr && nx->kind == TokKind::Op && nx->op == "(" && nx2 != nullptr && nx2->kind == TokKind::Op && nx2->op == ")" )
            {
                i_ += 3;
                skipOnlyNl();
                return funcNode( tx, ln, pos, parseCommand( stops ) );
            }
            if( tx == "then" || tx == "do" || tx == "done" || tx == "fi" || tx == "else" || tx == "elif" || tx == "esac" || tx == "}" )
            {
                return kNone;
            }
        }
        return parseSimple();
    }
    static bool isFuncName( std::string_view t ) noexcept   // ^[A-Za-z_][\w.:-]*$
    {
        if( t.empty() || !isIdentStart( t[0] ) )
        {
            return false;
        }
        return std::all_of( t.begin() + 1, t.end(), []( char c ) { return isWordChar( c ) || c == '.' || c == ':' || c == '-'; } );
    }
    std::uint32_t funcNode( std::string name, std::uint32_t ln, std::uint32_t pos, std::uint32_t body )
    {
        Node n;
        n.kind = NodeKind::Func;
        n.line = ln;
        n.pos  = pos;
        n.name = std::move( name );
        List l;
        if( body != kNone )
        {
            Item it;
            it.cmds.push_back( body );
            l.push_back( AndOr{ std::move( it ) } );
        }
        n.bodies.push_back( addList( std::move( l ) ) );
        return addNode( std::move( n ) );
    }
    // A compound's trailing redirects: Python skips them; the facet keeps them (a subshell's `) > out` is its writer).
    void redirs( Node& n )
    {
        while( peek().kind == TokKind::Op && isRedirOp( peek().op ) )
        {
            Redir r;
            r.op = peek().op;
            ++i_;
            if( peek().kind == TokKind::Word )
            {
                r.target    = peek().word.text;
                r.targetPos = peek().pos;
                ++i_;
            }
            n.fredirs.push_back( std::move( r ) );
        }
        while( peek().kind == TokKind::Word && shellIsRedirect( peek().word.text ) )
        {
            ++i_;
        }
    }
    std::uint32_t parseSimple()
    {
        Node n;
        n.kind = NodeKind::Simple;
        n.line = peek().line;
        n.pos  = peek().pos;
        while( true )
        {
            const Tok& p = peek();
            if( p.kind == TokKind::Word )
            {
                Word w = p.word;
                parseSubs( w );
                if( n.words.empty() && isAssign( w.text ) )
                {
                    n.assigns.push_back( std::move( w ) );
                }
                else
                {
                    n.words.push_back( std::move( w ) );
                }
                ++i_;
                continue;
            }
            if( p.kind == TokKind::Op && isRedirOp( p.op ) )
            {
                Redir r;
                r.op = p.op;
                // an fd glued before the operator (`2>`): the lexer split it into a word of digits, which Python keeps as an
                // argument; the facet reads it as the fd
                if( p.glued && !n.words.empty() && !n.words.back().text.empty()
                    && std::all_of( n.words.back().text.begin(), n.words.back().text.end(), isDigitC ) && n.words.back().text.size() <= 2 )
                {
                    const std::string& fd = n.words.back().text;
                    (void)std::from_chars( fd.data(), fd.data() + fd.size(), r.fd );   // 1-2 digits: no overflow, no error
                }
                ++i_;
                if( peek().kind == TokKind::Word )
                {
                    Word tw = peek().word;
                    ++i_;
                    n.redirs.push_back( r.op + " " + tw.text );
                    r.target    = tw.text;
                    r.targetPos = tw.pos;
                    // a redirect target's substitutions still run: keep them as ARGUMENT subs
                    if( !tw.subs.empty() )
                    {
                        Word sw;
                        sw.line = tw.line;
                        sw.pos  = tw.pos;
                        sw.subs = std::move( tw.subs );
                        parseSubs( sw );
                        n.words.push_back( std::move( sw ) );
                    }
                }
                n.fredirs.push_back( std::move( r ) );
                continue;
            }
            break;
        }
        if( n.words.empty() && n.assigns.empty() )
        {
            return kNone;
        }
        return addNode( std::move( n ) );
    }
    std::uint32_t parseIfLoop( const std::string& t, std::uint32_t ln, std::uint32_t pos )
    {
        ++i_;
        Node n;
        n.line = ln;
        n.pos  = pos;
        if( t == "if" )
        {
            n.kind = NodeKind::If;
            n.conds.push_back( addList( parseList( Stops{ { "then" } } ) ) );
            ++i_;
            n.bodies.push_back( addList( parseList( Stops{ { "elif", "else", "fi" } } ) ) );
            while( kw( "elif" ) )
            {
                ++i_;
                n.conds.push_back( addList( parseList( Stops{ { "then" } } ) ) );
                ++i_;
                n.bodies.push_back( addList( parseList( Stops{ { "elif", "else", "fi" } } ) ) );
            }
            if( kw( "else" ) )
            {
                ++i_;
                n.bodies.push_back( addList( parseList( Stops{ { "fi" } } ) ) );
            }
            if( kw( "fi" ) )
            {
                ++i_;
            }
            redirs( n );
            return addNode( std::move( n ) );
        }
        n.kind = NodeKind::Loop;
        n.conds.push_back( addList( parseList( Stops{ { "do" } } ) ) );
        ++i_;
        n.bodies.push_back( addList( parseList( Stops{ { "done" } } ) ) );
        if( kw( "done" ) )
        {
            ++i_;
        }
        redirs( n );
        return addNode( std::move( n ) );
    }
    std::uint32_t parseCase( std::uint32_t ln, std::uint32_t pos )
    {
        ++i_;
        Node n;
        n.kind = NodeKind::Case;
        n.line = ln;
        n.pos  = pos;
        std::string subject = peek().kind == TokKind::Word ? peek().word.text : std::string();
        n.caseSubject       = subject;
        while( !( kw( "in" ) || peek().kind == TokKind::Eof ) )
        {
            ++i_;
        }
        ++i_;
        while( true )
        {
            skipNl();
            if( kw( "esac" ) || peek().kind == TokKind::Eof )
            {
                break;
            }
            std::vector<std::string> pats;
            while( !( isOp( ")" ) || peek().kind == TokKind::Eof ) )
            {
                if( peek().kind == TokKind::Word )
                {
                    subject += " " + peek().word.text;   // patterns: `*" $rc "*)` tests $rc
                    pats.push_back( peek().word.text );
                }
                ++i_;
            }
            ++i_;
            n.casePats.push_back( std::move( pats ) );
            n.bodies.push_back( addList( parseList( Stops{ { ";;", ";&", ";;&", "esac" } } ) ) );
            if( isOp( ";;" ) || isOp( ";&" ) || isOp( ";;&" ) )
            {
                ++i_;
            }
        }
        if( kw( "esac" ) )
        {
            ++i_;
        }
        redirs( n );
        n.name = std::move( subject );
        return addNode( std::move( n ) );
    }
};

}   // namespace detail

inline Tree parse( std::string_view src )
{
    Tree           t;
    NestBudget     nb;
    detail::Parser p( t, detail::lex( src, 1, 0, nb ), nb );
    t.top = p.parseAll();
    t.cut = nb.cut;
    return t;
}

// ── the status walk ─────────────────────────────────────────────────────────────────────────────────────────────────
enum class Verdict : std::uint8_t
{
    Checked,
    Unchecked,
    Errexit,   // unresolved: the status reaches nothing but set -e
    Fn,        // the status IS the enclosing function's (how = its name)
};

struct Consumer
{
    Verdict     v = Verdict::Errexit;
    std::string how;
};

struct Call
{
    std::uint32_t line = 0;
    std::string   cmd;
    std::string   verdict;   // "checked" | "unchecked"
    std::string   how;
    std::string   kind;      // "ripwire" | "harness" | "extra" | "wrapper"
    std::uint32_t node = kNone;   // facet: the simple command
};

// What the final walk knew about every simple command with a command word (facet).
struct NodeFacts
{
    bool     seen     = false;
    Consumer cons;               // resolved (never Errexit); Fn when its status is the enclosing function's
    bool     pipefail = false;
    bool     errexit  = false;
    std::string func;            // enclosing function, empty at top level
    std::string kind;            // under-test kind, "wrapper", or empty
};

struct Analysis
{
    std::vector<Call>        calls;      // the contract's rows
    std::vector<NodeFacts>   facts;      // per node (facet)
    std::vector<std::string> wrappers;   // sorted
    std::vector<std::string> compared;   // sorted: names some test reads (and "file:SUF")
    std::vector<std::string> targets;    // compiled-harness patterns
};

namespace detail
{

inline bool hasName( const std::vector<std::string>& sorted, std::string_view n )
{
    return std::binary_search( sorted.begin(), sorted.end(), n, rw::sortutil::svLess );
}

inline std::string textOf( const Tree& t, std::uint32_t node );
inline std::string listText( const Tree& t, std::uint32_t list );
inline std::string itemsText( const Tree& t, const AndOr& ao )   // one and-or: its commands joined by spaces (ops dropped)
{
    std::string out;
    bool        first = true;
    for( const Item& it : ao )
    {
        for( std::uint32_t c : it.cmds )
        {
            if( !first )
            {
                out.push_back( ' ' );
            }
            first = false;
            out += textOf( t, c );
        }
    }
    return out;
}
inline std::string listTextOf( const Tree& t, const List& l )
{
    std::string out;
    for( std::size_t k = 0; k < l.size(); ++k )
    {
        if( k > 0 )
        {
            out += " ; ";
        }
        out += itemsText( t, l[k] );
    }
    return out;
}
inline std::string listText( const Tree& t, std::uint32_t list )
{
    return list == kNone ? std::string() : listTextOf( t, t.lists[list] );
}
inline std::string textOf( const Tree& t, std::uint32_t node )   // Python _text
{
    const Node& n = t.nodes[node];
    std::string out;
    bool        first = true;
    const auto  add   = [ & ]( std::string_view s )
    {
        if( !first )
        {
            out.push_back( ' ' );
        }
        first = false;
        out.append( s );
    };
    if( n.kind == NodeKind::Simple )
    {
        for( const Word& w : n.assigns )
        {
            add( w.text );
        }
        for( const Word& w : n.words )
        {
            add( w.text );
        }
        for( const std::string& r : n.redirs )
        {
            add( r );
        }
        return out;
    }
    for( std::uint32_t l : n.conds )
    {
        add( listText( t, l ) );
    }
    for( std::uint32_t l : n.bodies )
    {
        add( listText( t, l ) );
    }
    return out;
}

// _BARE_REDIRECT = ^\s*(?:\d*\s*>+\s*&?\s*\S+\s*|\d*\s*<\s*\S+\s*)+$
inline bool isBareRedirect( std::string_view s )
{
    std::size_t i = 0;
    while( i < s.size() && isSp( s[i] ) )
    {
        ++i;
    }
    // every end of one unit starting at p; a breadth-first walk over unit boundaries decides the match
    const auto unitEnds = [ & ]( std::size_t p, std::vector<std::size_t>& ends )
    {
        std::size_t q = p;
        while( q < s.size() && isDigitC( s[q] ) )
        {
            ++q;
        }
        while( q < s.size() && isSp( s[q] ) )
        {
            ++q;
        }
        const auto tailFrom = [ & ]( std::size_t r )   // \S+\s*: every possible end
        {
            std::size_t e = r;
            while( e < s.size() && !isSp( s[e] ) )
            {
                ++e;
                std::size_t f = e;
                ends.push_back( f );
                while( f < s.size() && isSp( s[f] ) )
                {
                    ++f;
                    ends.push_back( f );
                }
            }
        };
        if( q < s.size() && s[q] == '<' )
        {
            std::size_t r = q + 1;
            while( r < s.size() && isSp( s[r] ) )
            {
                ++r;
            }
            tailFrom( r );
        }
        std::size_t g = q;
        while( g < s.size() && s[g] == '>' )
        {
            ++g;
        }
        for( std::size_t gEnd = q + 1; gEnd <= g; ++gEnd )   // >+ of any length
        {
            std::size_t r = gEnd;
            while( r < s.size() && isSp( s[r] ) )
            {
                ++r;
            }
            std::size_t r2 = r;
            if( r2 < s.size() && s[r2] == '&' )
            {
                ++r2;
                while( r2 < s.size() && isSp( s[r2] ) )
                {
                    ++r2;
                }
                tailFrom( r2 );
            }
            tailFrom( r );
        }
    };
    std::vector<char>        reached( s.size() + 1, 0 );
    bool                     ok = false;
    // BFS over unit boundaries; a boundary at s.size() reached after >= 1 unit is a match
    std::vector<std::size_t> frontier{ i };
    while( !frontier.empty() && !ok )
    {
        std::vector<std::size_t> next;
        for( std::size_t p : frontier )
        {
            std::vector<std::size_t> ends;
            unitEnds( p, ends );
            for( std::size_t e : ends )
            {
                if( e == s.size() )
                {
                    ok = true;
                }
                if( e > p && !reached[e] )
                {
                    reached[e] = 1;
                    next.push_back( e );
                }
            }
        }
        frontier.swap( next );
    }
    return ok;
}

inline std::string firstPipelineText( const Tree& t, const AndOr& ao )
{
    for( const Item& it : ao )
    {
        AndOr one{ it };
        const std::string tx = itemsText( t, one );
        if( !isBareRedirect( tx ) )
        {
            return tx;
        }
    }
    return {};
}

// ^\s*(?:true|:)\s*$
inline bool isTrivialOr( std::string_view s ) noexcept
{
    const std::string_view m = trimView( s );
    return m == "true" || m == ":";
}

inline std::string strip( std::string_view s )
{
    return std::string( trimView( s ) );
}

// \$\{?([A-Za-z_][A-Za-z0-9_]*)  findall
inline void vrefs( std::string_view s, std::vector<std::string>& out )
{
    for( std::size_t i = 0; i < s.size(); ++i )
    {
        if( s[i] != '$' )
        {
            continue;
        }
        std::size_t j = i + 1;
        if( j < s.size() && s[j] == '{' )
        {
            ++j;
        }
        if( j < s.size() && isIdentStart( s[j] ) )
        {
            const std::size_t b = j;
            while( j < s.size() && isIdentChar( s[j] ) )
            {
                ++j;
            }
            out.emplace_back( s.substr( b, j - b ) );
            i = j - 1;
        }
    }
}
// \b([A-Za-z_][A-Za-z0-9_]*)\b  findall
inline void boundedIdents( std::string_view s, std::vector<std::string>& out )
{
    std::size_t i = 0;
    while( i < s.size() )
    {
        if( !isWordChar( s[i] ) )
        {
            ++i;
            continue;
        }
        std::size_t j = i;
        while( j < s.size() && isWordChar( s[j] ) )
        {
            ++j;
        }
        const std::string_view run = s.substr( i, j - i );
        if( isIdentStart( run[0] ) && std::all_of( run.begin(), run.end(), isIdentChar ) )
        {
            out.emplace_back( run );
        }
        i = j;
    }
}
// after a '.', [A-Za-z0-9_]+ then "?\s*\) : the suffix, or empty
inline std::string_view rcSuffixClose( std::string_view s, std::size_t dot, std::size_t& endOut ) noexcept
{
    std::size_t k = dot + 1;
    while( k < s.size() && isIdentChar( s[k] ) )
    {
        ++k;
    }
    if( k == dot + 1 )
    {
        return {};
    }
    std::size_t m = k;
    if( m < s.size() && s[m] == '"' )
    {
        ++m;
    }
    while( m < s.size() && isSp( s[m] ) )
    {
        ++m;
    }
    if( m < s.size() && s[m] == ')' )
    {
        endOut = m + 1;
        return s.substr( dot + 1, k - dot - 1 );
    }
    return {};
}
// \bcat\s+[^)]*?\.([A-Za-z0-9_]+)"?\s*\)  findall
inline void catSuffixes( std::string_view s, std::vector<std::string>& out )
{
    std::size_t i = 0;
    while( ( i = s.find( "cat", i ) ) != std::string_view::npos )
    {
        const bool bnd = i == 0 || !isWordChar( s[i - 1] );
        std::size_t j  = i + 3;
        if( !bnd || j >= s.size() || !isSp( s[j] ) )
        {
            ++i;
            continue;
        }
        while( j < s.size() && isSp( s[j] ) )
        {
            ++j;
        }
        // the lazy [^)]*? begins right after \s+ (backtracking \s+ to fewer blanks only lets [^)] eat them: same result)
        bool        hit = false;
        std::size_t end = 0;
        for( std::size_t k = i + 4; k < s.size() && s[k] != ')'; ++k )
        {
            if( s[k] == '.' )
            {
                const std::string_view suf = rcSuffixClose( s, k, end );
                if( !suf.empty() )
                {
                    out.emplace_back( suf );
                    hit = true;
                    break;
                }
            }
        }
        i = hit ? end : i + 1;
    }
}

struct Walker
{
    const Tree&                             tree;
    std::string_view                        src;
    std::vector<std::string>                vars;       // sorted binvars
    std::vector<std::string>                targets;
    const std::vector<std::string>*         compared = nullptr;
    bool                                    errexit  = false;
    bool                                    pipefail = false;
    int                                     substDepth = 0;
    struct Raw
    {
        std::uint32_t line;
        std::string   cmd;
        Consumer      cons;
        std::string   via;
        std::uint32_t node;
    };
    std::vector<Raw>                        calls{};
    std::vector<std::string>                funcs{};    // names seen so far (and the seeded wrappers)
    std::vector<std::string>                funcStack{};
    std::vector<NodeFacts>*                 facts = nullptr;

    bool isFunc( std::string_view n ) const
    {
        return std::find( funcs.begin(), funcs.end(), n ) != funcs.end();
    }

    // None, or the kind of command `word` names. A compiled target wins over a name.
    std::string underTest( std::string_view word ) const
    {
        const std::string w = unq( word );
        for( const std::string& p : targets )
        {
            if( w == p || globMatch( w, p ) )
            {
                return "harness";
            }
        }
        std::string lower = w;
        std::transform( lower.begin(), lower.end(), lower.begin(), []( char c ) { return ( c >= 'A' && c <= 'Z' ) ? static_cast<char>( c - 'A' + 'a' ) : c; } );
        if( lower.contains( "harness" ) && ( w.contains( "/" ) || w.contains( "$" ) ) )
        {
            return "harness";
        }
        const std::string_view v = bareVar( w );
        if( !v.empty() && !isNotBin( v ) && ( hasName( vars, v ) || isBinVar( v ) ) )
        {
            return isHarnessVar( v ) ? "harness" : "ripwire";
        }
        // (?:^|/)build[^/ ]*/ripwire$
        if( w.size() >= 8 && w.substr( w.size() - 8 ) == "/ripwire" )
        {
            const std::string_view head = std::string_view( w ).substr( 0, w.size() - 8 );
            const std::size_t      slash = head.rfind( '/' );
            const std::string_view seg   = slash == std::string_view::npos ? head : head.substr( slash + 1 );
            if( seg.rfind( "build", 0 ) == 0 && seg.find( ' ' ) == std::string_view::npos )
            {
                return "ripwire";
            }
        }
        return {};
    }

    void collectTargets( std::uint32_t list );
    void walkList( std::uint32_t list, const Consumer* consumer, bool toplevel );
    std::optional<Consumer> capture( const std::string& nxt, const std::string& first ) const;
    void walkAndOr( const AndOr& ao, const Consumer& consumer );
    void walkPipeline( const Item& it, Consumer consumer );
    void walkCmd( std::uint32_t node, Consumer consumer );
    void walkCompound( const Node& c, const Consumer& consumer );
    void applySet( const Node& c );
    void walkSubstitutions( const Node& c, std::size_t k, const Consumer& consumer );
    void recordCall( std::uint32_t node, const Node& c, const std::string& cw, const Consumer& consumer );
    Consumer resolve( const Consumer& c ) const
    {
        if( c.v == Verdict::Errexit )
        {
            return errexit ? Consumer{ Verdict::Checked, "set -e" } : Consumer{ Verdict::Unchecked, "output only" };
        }
        return c;
    }
};

// ^\$\{?[A-Z_]*TIMEOUT[A-Z_]*\}?$ : a timeout wrapper held in a variable
inline bool isTimeoutVarWord( std::string_view w ) noexcept
{
    if( w.empty() || w[0] != '$' )
    {
        return false;
    }
    w.remove_prefix( 1 );
    if( !w.empty() && w.front() == '{' )
    {
        w.remove_prefix( 1 );
    }
    if( !w.empty() && w.back() == '}' )
    {
        w.remove_suffix( 1 );
    }
    const std::size_t p = w.find( "TIMEOUT" );
    return p != std::string_view::npos && std::all_of( w.begin(), w.end(), []( char c ) { return ( c >= 'A' && c <= 'Z' ) || c == '_'; } );
}

// ^"?\$\{?(?:@|\*|[A-Za-z_]\w*\[[@*]\])\}?"?$ : a spread ("$@", ${ARGS[@]}) whose first word is the command
inline bool isSpreadPrefixWord( std::string_view w ) noexcept
{
    if( !w.empty() && w.front() == '"' )
    {
        w.remove_prefix( 1 );
    }
    if( !w.empty() && w.back() == '"' )
    {
        w.remove_suffix( 1 );
    }
    if( w.empty() || w[0] != '$' )
    {
        return false;
    }
    w.remove_prefix( 1 );
    if( !w.empty() && w.front() == '{' )
    {
        w.remove_prefix( 1 );
    }
    if( !w.empty() && w.back() == '}' )
    {
        w.remove_suffix( 1 );
    }
    if( w == "@" || w == "*" )
    {
        return true;
    }
    if( w.size() < 4 || !isIdentStart( w[0] ) || w.back() != ']' || ( w[w.size() - 2] != '@' && w[w.size() - 2] != '*' ) || w[w.size() - 3] != '[' )
    {
        return false;
    }
    return std::all_of( w.begin() + 1, w.end() - 3, isWordChar );
}

inline bool isRunPrefixWord( std::string_view w ) noexcept   // env/command/exec/nice/time/nohup/stdbuf/caffeinate
{
    return w == "env" || w == "command" || w == "exec" || w == "nice" || w == "time" || w == "nohup" || w == "stdbuf" || w == "caffeinate";
}

// past the options (and env's NAME=value words) of the run prefix `w` at ws[k - 1]
inline std::size_t skipRunPrefixArgs( const std::vector<Word>& ws, std::size_t k, std::string_view w )
{
    while( k < ws.size() )
    {
        const std::string& a  = ws[k].text;
        bool               go = !a.empty() && a[0] == '-';
        go                    = go || isAssign( a );
        if( !go && w == "env" )
        {
            const std::string ua = unq( a );
            go                   = ua.substr( 0, ua.find( '/' ) ).find( '=' ) != std::string::npos;
        }
        if( !go )
        {
            break;
        }
        if( ( a == "-u" || a == "-C" || a == "-S" ) && k + 1 < ws.size() )
        {
            ++k;
        }
        ++k;
    }
    return k;
}

// The command word of a simple command, skipping env/timeout/command/exec/nice/time/sudo/stdbuf prefixes; npos if none.
inline std::size_t cmdWordIndex( const Node& s )
{
    const std::vector<Word>& ws = s.words;
    std::size_t              k  = 0;
    while( k < ws.size() )
    {
        const std::string w = unq( ws[k].text );
        if( isRunPrefixWord( w ) )
        {
            k = skipRunPrefixArgs( ws, k + 1, w );
            continue;
        }
        if( w == "timeout" || w == "gtimeout" || isTimeoutVarWord( w ) )
        {
            ++k;
            while( k < ws.size() && !ws[k].text.empty() && ws[k].text[0] == '-' )
            {
                ++k;
            }
            ++k;   // the duration
            continue;
        }
        if( isAssign( ws[k].text ) || ( isSpreadPrefixWord( ws[k].text ) && k + 1 < ws.size() ) )
        {
            ++k;
            continue;
        }
        return k;
    }
    return std::string::npos;
}

// Every command of a list in source order, each before what it encloses ($( ) bodies, conditions, bodies):
// visit( node, fn ), fn the name of the function the command sits in (empty at top level).
template<class Visit>
inline void forEachCmd( const Tree& t, std::uint32_t list, const std::string& fn, Visit& visit )
{
    if( list == kNone )
    {
        return;
    }
    for( const AndOr& ao : t.lists[list] )
    {
        for( const Item& it : ao )
        {
            for( std::uint32_t c : it.cmds )
            {
                const Node& n = t.nodes[c];
                visit( c, fn );
                if( n.kind == NodeKind::Simple )
                {
                    for( const std::vector<Word>* ws : { &n.words, &n.assigns } )
                    {
                        for( const Word& w : *ws )
                        {
                            for( const Sub& s : w.subs )
                            {
                                forEachCmd( t, s.list, fn, visit );
                            }
                        }
                    }
                    continue;
                }
                const std::string& inner = n.kind == NodeKind::Func ? n.name : fn;
                for( std::uint32_t l : n.conds )
                {
                    forEachCmd( t, l, inner, visit );
                }
                for( std::uint32_t l : n.bodies )
                {
                    forEachCmd( t, l, inner, visit );
                }
            }
        }
    }
}

// \.(?:o|obj|ll|s|bc|pch|gch|d)$|^/dev/null$ : a compiler output that is not a runnable binary
inline bool isObjectOutput( std::string_view tgt ) noexcept
{
    bool skip = tgt == "/dev/null";
    for( std::string_view ext : { ".o", ".obj", ".ll", ".s", ".bc", ".pch", ".gch", ".d" } )
    {
        skip = skip || ( tgt.size() >= ext.size() && tgt.compare( tgt.size() - ext.size(), ext.size(), ext ) == 0 );
    }
    return skip;
}

// re.sub( \$\{?[A-Za-z_0-9@*#?]+\}?, "*" ): every variable in a target path a glob star
inline std::string varsAsGlob( std::string_view tgt )
{
    const auto  inCls = []( char ch ) { return isIdentChar( ch ) || ch == '@' || ch == '*' || ch == '#' || ch == '?'; };
    std::string pat;
    for( std::size_t q = 0; q < tgt.size(); )
    {
        if( tgt[q] == '$' )
        {
            std::size_t       r  = q + 1;
            const std::size_t r0 = r;
            if( r < tgt.size() && tgt[r] == '{' )
            {
                ++r;
            }
            std::size_t e = r;
            while( e < tgt.size() && inCls( tgt[e] ) )
            {
                ++e;
            }
            if( e == r && r != r0 )
            {
                r = r0;   // `\{?` backtracks: '{' is not in the class either
                e = r;
            }
            if( e > r )
            {
                if( e < tgt.size() && tgt[e] == '}' )
                {
                    ++e;
                }
                pat.push_back( '*' );
                q = e;
                continue;
            }
        }
        pat.push_back( tgt[q] );
        ++q;
    }
    return pat;
}

// the -o / -oFILE outputs of one compiler command, as the names (or globs) that later run them
inline void compilerOutputs( const Node& n, std::vector<std::string>& targets )
{
    std::vector<std::string> ws;
    ws.reserve( n.words.size() );
    for( const Word& w : n.words )
    {
        ws.push_back( unq( w.text ) );
    }
    for( std::size_t j = 0; j < ws.size(); ++j )
    {
        std::string tgt;
        if( ws[j] == "-o" && j + 1 < ws.size() )
        {
            tgt = ws[j + 1];
        }
        else if( ws[j].rfind( "-o", 0 ) == 0 && ws[j].size() > 2 )
        {
            tgt = ws[j].substr( 2 );
        }
        if( tgt.empty() || isObjectOutput( tgt ) )
        {
            continue;
        }
        const std::string pat  = varsAsGlob( tgt );
        const std::size_t sl   = pat.rfind( '/' );
        const std::string base = sl == std::string::npos ? pat : pat.substr( sl + 1 );
        const bool        lit  = std::all_of( base.begin(), base.end(), []( char ch ) { return ch == '*' || ch == '/'; } );
        targets.push_back( lit ? tgt : pat );
    }
}

inline void Walker::collectTargets( std::uint32_t list )
{
    auto visit = [ & ]( std::uint32_t c, const std::string& )
    {
        const Node& n = tree.nodes[c];
        if( n.kind != NodeKind::Simple )
        {
            return;
        }
        const std::size_t k = cmdWordIndex( n );
        if( k != std::string::npos && isCompiler( unq( n.words[k].text ) ) )
        {
            compilerOutputs( n, targets );
        }
    };
    forEachCmd( tree, list, std::string(), visit );
}

// capture regexes ------------------------------------------------------------------------------------------------------
// \s*(?:local\s+)?NAME=  then R1 ["]?\$ / R2 "?\$\{?\?   -> NAME when both match
inline std::string rcCaptureName( std::string_view h )
{
    std::size_t i = 0;
    while( i < h.size() && isSp( h[i] ) )
    {
        ++i;
    }
    const auto tryAt = [ & ]( std::size_t p ) -> std::string
    {
        if( p >= h.size() || !isIdentStart( h[p] ) )
        {
            return {};
        }
        std::size_t q = p;
        while( q < h.size() && isIdentChar( h[q] ) )
        {
            ++q;
        }
        if( q >= h.size() || h[q] != '=' )
        {
            return {};
        }
        std::size_t r = q + 1;
        if( r < h.size() && h[r] == '"' )
        {
            ++r;
        }
        if( r >= h.size() || h[r] != '$' )
        {
            return {};
        }
        std::size_t r2 = r + 1;
        if( r2 < h.size() && h[r2] == '{' )
        {
            ++r2;
        }
        if( r2 >= h.size() || h[r2] != '?' )
        {
            return {};
        }
        return std::string( h.substr( p, q - p ) );
    };
    if( startsAt( h, i, "local" ) && i + 5 < h.size() && isSp( h[i + 5] ) )
    {
        std::size_t p = i + 5;
        while( p < h.size() && isSp( h[p] ) )
        {
            ++p;
        }
        std::string n = tryAt( p );
        if( !n.empty() )
        {
            return n;
        }
    }
    return tryAt( i );
}
// echo\s+"?\$\??"?\s*>+\s*"?[^"\s]*?\.([A-Za-z0-9_]+)"?   (search) -> the suffix, or empty
inline std::string rcFileSuffix( std::string_view h )
{
    for( std::size_t e = h.find( "echo" ); e != std::string_view::npos; e = h.find( "echo", e + 1 ) )
    {
        std::size_t i = e + 4;
        if( i >= h.size() || !isSp( h[i] ) )
        {
            continue;
        }
        while( i < h.size() && isSp( h[i] ) )
        {
            ++i;
        }
        if( i < h.size() && h[i] == '"' )
        {
            ++i;
        }
        if( i >= h.size() || h[i] != '$' )
        {
            continue;
        }
        ++i;
        if( i < h.size() && h[i] == '?' )
        {
            ++i;
        }
        if( i < h.size() && h[i] == '"' )
        {
            ++i;
        }
        while( i < h.size() && isSp( h[i] ) )
        {
            ++i;
        }
        if( i >= h.size() || h[i] != '>' )
        {
            continue;
        }
        while( i < h.size() && h[i] == '>' )
        {
            ++i;
        }
        while( i < h.size() && isSp( h[i] ) )
        {
            ++i;
        }
        if( i < h.size() && h[i] == '"' )
        {
            ++i;
        }
        for( std::size_t k = i; k < h.size() && h[k] != '"' && !isSp( h[k] ); ++k )
        {
            if( h[k] == '.' && k + 1 < h.size() && isIdentChar( h[k + 1] ) )
            {
                std::size_t m = k + 1;
                while( m < h.size() && isIdentChar( h[m] ) )
                {
                    ++m;
                }
                return std::string( h.substr( k + 1, m - k - 1 ) );
            }
        }
    }
    return {};
}
// (?<![&>])>+(?!\s*&\s*[12]\b)(?!\s*/dev/null\b)\s*\S   (search)
inline bool toFile( std::string_view f )
{
    const auto lookOk = [ & ]( std::size_t e ) -> bool
    {
        std::size_t k = e;
        while( k < f.size() && isSp( f[k] ) )
        {
            ++k;
        }
        if( k < f.size() && f[k] == '&' )
        {
            std::size_t m = k + 1;
            while( m < f.size() && isSp( f[m] ) )
            {
                ++m;
            }
            if( m < f.size() && ( f[m] == '1' || f[m] == '2' ) && ( m + 1 >= f.size() || !isWordChar( f[m + 1] ) ) )
            {
                return false;
            }
        }
        if( startsAt( f, k, "/dev/null" ) && ( k + 9 >= f.size() || !isWordChar( f[k + 9] ) ) )
        {
            return false;
        }
        // \s*\S
        return k < f.size();
    };
    for( std::size_t p = 0; p < f.size(); ++p )
    {
        if( f[p] != '>' || ( p > 0 && ( f[p - 1] == '&' || f[p - 1] == '>' ) ) )
        {
            continue;
        }
        std::size_t run = p;
        while( run < f.size() && f[run] == '>' )
        {
            ++run;
        }
        for( std::size_t e = run; e > p; --e )
        {
            if( lookOk( e ) )
            {
                return true;
            }
        }
    }
    return false;
}
// \s*(?:echo|printf)\b
inline bool startsEchoPrintf( std::string_view f )
{
    std::size_t i = 0;
    while( i < f.size() && isSp( f[i] ) )
    {
        ++i;
    }
    for( std::string_view w : { std::string_view( "echo" ), std::string_view( "printf" ) } )
    {
        if( startsAt( f, i, w ) && ( i + w.size() >= f.size() || !isWordChar( f[i + w.size()] ) ) )
        {
            return true;
        }
    }
    return false;
}
// \s*(?:echo|printf\s+(?:'%s'|"%s"|%s))\s+"?\$\{?\?\}?"?\s*$
inline bool isBareStatusEcho( std::string_view f )
{
    std::size_t i = 0;
    while( i < f.size() && isSp( f[i] ) )
    {
        ++i;
    }
    if( startsAt( f, i, "echo" ) )
    {
        i += 4;
    }
    else if( startsAt( f, i, "printf" ) )
    {
        i += 6;
        if( i >= f.size() || !isSp( f[i] ) )
        {
            return false;
        }
        while( i < f.size() && isSp( f[i] ) )
        {
            ++i;
        }
        if( startsAt( f, i, "'%s'" ) || startsAt( f, i, "\"%s\"" ) )
        {
            i += 4;
        }
        else if( startsAt( f, i, "%s" ) )
        {
            i += 2;
        }
        else
        {
            return false;
        }
    }
    else
    {
        return false;
    }
    if( i >= f.size() || !isSp( f[i] ) )
    {
        return false;
    }
    while( i < f.size() && isSp( f[i] ) )
    {
        ++i;
    }
    if( i < f.size() && f[i] == '"' )
    {
        ++i;
    }
    if( i >= f.size() || f[i] != '$' )
    {
        return false;
    }
    ++i;
    if( i < f.size() && f[i] == '{' )
    {
        ++i;
    }
    if( i >= f.size() || f[i] != '?' )
    {
        return false;
    }
    ++i;
    if( i < f.size() && f[i] == '}' )
    {
        ++i;
    }
    if( i < f.size() && f[i] == '"' )
    {
        ++i;
    }
    while( i < f.size() && isSp( f[i] ) )
    {
        ++i;
    }
    return i == f.size();
}

inline std::optional<Consumer> Walker::capture( const std::string& nxt, const std::string& first ) const
{
    const std::size_t      cut  = nxt.find( " ; " );
    const std::string_view head = cut == std::string::npos ? std::string_view( nxt ) : std::string_view( nxt ).substr( 0, cut );
    if( head.contains( "PIPESTATUS" ) )
    {
        return Consumer{ Verdict::Checked, "PIPESTATUS read" };
    }
    if( !head.contains( "$?" ) && !head.contains( "${?}" ) )
    {
        return std::nullopt;
    }
    const std::string v = rcCaptureName( head );
    if( !v.empty() )
    {
        return hasName( *compared, v ) ? Consumer{ Verdict::Checked, v + "=$? compared" } : Consumer{ Verdict::Unchecked, v + "=$? captured, never compared" };
    }
    const std::string suf = rcFileSuffix( head );
    if( !suf.empty() )
    {
        return hasName( *compared, "file:" + suf ) ? Consumer{ Verdict::Checked, "rc file ." + suf + " compared" }
                                                   : Consumer{ Verdict::Unchecked, "rc file ." + suf + " written, never compared" };
    }
    if( !first.contains( "$?" ) && !first.contains( "${?}" ) )
    {
        return std::nullopt;
    }
    if( startsEchoPrintf( first ) && !toFile( first ) && substDepth == 0 && !isBareStatusEcho( first ) )
    {
        return Consumer{ Verdict::Unchecked, "$? printed, not tested" };
    }
    return Consumer{ Verdict::Checked, "$? tested by the next statement" };
}

inline void Walker::walkList( std::uint32_t list, const Consumer* consumer, bool toplevel )
{
    if( list == kNone )
    {
        return;
    }
    const List& lst = tree.lists[list];
    for( std::size_t k = 0; k < lst.size(); ++k )
    {
        const bool last = k + 1 == lst.size();
        if( last && consumer != nullptr )
        {
            walkAndOr( lst[k], *consumer );
            continue;
        }
        if( last && toplevel )
        {
            walkAndOr( lst[k], Consumer{ Verdict::Checked, "exit status (the script's last statement)" } );
            continue;
        }
        std::optional<Consumer> cap;
        if( !last )
        {
            List one{ lst[k + 1] };
            cap = capture( listTextOf( tree, one ), firstPipelineText( tree, lst[k + 1] ) );
        }
        else
        {
            cap = capture( std::string(), std::string() );
        }
        walkAndOr( lst[k], cap ? *cap : Consumer{ Verdict::Errexit, {} } );
    }
}

inline void Walker::walkAndOr( const AndOr& ao, const Consumer& consumer )
{
    const std::size_t n = ao.size();
    for( std::size_t j = 0; j < n; ++j )
    {
        std::size_t orAt = n;
        for( std::size_t m = j + 1; m < n; ++m )
        {
            if( ao[m].op == Link::Or )
            {
                orAt = m;
                break;
            }
        }
        Consumer c;
        if( orAt < n )
        {
            AndOr one{ ao[orAt] };
            const std::string rhs = itemsText( tree, one );
            if( isTrivialOr( rhs ) )
            {
                c = Consumer{ Verdict::Unchecked, "discarded by || " + strip( rhs ) };
            }
            else
            {
                c = Consumer{ Verdict::Checked, ( j + 1 < n && ao[j + 1].op == Link::And ) ? "&& .. || X" : "|| X" };
            }
        }
        else if( j + 1 < n )
        {
            // followed only by && links: a failure here IS the list's status, but errexit never fires here
            c = consumer.v == Verdict::Errexit ? Consumer{ Verdict::Unchecked, "left of && (errexit does not fire)" } : consumer;
        }
        else
        {
            c = consumer;
        }
        walkPipeline( ao[j], c );
    }
}

inline void Walker::walkPipeline( const Item& it, Consumer consumer )
{
    if( it.neg && consumer.v == Verdict::Errexit )
    {
        consumer = Consumer{ Verdict::Unchecked, "negated (errexit does not fire)" };
    }
    for( std::size_t j = 0; j < it.cmds.size(); ++j )
    {
        if( j + 1 < it.cmds.size() && !pipefail )
        {
            walkCmd( it.cmds[j], Consumer{ Verdict::Unchecked, "status discarded in a pipe (no pipefail)" } );
        }
        else
        {
            walkCmd( it.cmds[j], consumer );
        }
    }
}

// ^[-+][a-zA-Z]*e : a `set` flag word (sign '-' sets, '+' clears) that names errexit
inline bool setFlagsHaveE( std::string_view a, char sign ) noexcept
{
    if( a.size() < 2 || a[0] != sign )
    {
        return false;
    }
    for( std::size_t q = 1; q < a.size(); ++q )
    {
        if( a[q] == 'e' )
        {
            return true;
        }
        if( !( ( a[q] >= 'a' && a[q] <= 'z' ) || ( a[q] >= 'A' && a[q] <= 'Z' ) ) )
        {
            return false;
        }
    }
    return false;
}

// a `set` naming pipefail: on when a ^-[a-z]*o$ word sets an option and no +o clears one
inline bool setsPipefail( const Node& c )
{
    bool dashO = false;
    for( std::size_t a = 1; a < c.words.size(); ++a )
    {
        const std::string u = unq( c.words[a].text );
        if( u.size() >= 2 && u[0] == '-' && u.back() == 'o' && std::all_of( u.begin() + 1, u.end(), []( char ch ) { return ch >= 'a' && ch <= 'z'; } ) )
        {
            dashO = true;
        }
    }
    const bool plusO = std::any_of( c.words.begin(), c.words.end(), []( const Word& w ) { return w.text == "+o"; } );
    return dashO && !plusO;
}

// `set -e` / `set +e` / `set -o errexit|pipefail` / `set +o ...`: the options later commands run under
inline void Walker::applySet( const Node& c )
{
    for( std::size_t a = 1; a < c.words.size(); ++a )
    {
        const std::string a2 = unq( c.words[a].text );
        if( setFlagsHaveE( a2, '-' ) )
        {
            errexit = true;
        }
        if( setFlagsHaveE( a2, '+' ) )
        {
            errexit = false;
        }
    }
    if( std::any_of( c.words.begin(), c.words.end(), []( const Word& w ) { return w.text.contains( "pipefail" ); } ) )
    {
        pipefail = setsPipefail( c );
    }
    for( std::size_t j = 1; j < c.words.size(); ++j )
    {
        const std::string u = unq( c.words[j].text );
        if( u == "-o" && j + 1 < c.words.size() && unq( c.words[j + 1].text ) == "errexit" )
        {
            errexit = true;
        }
        if( u == "+o" && j + 1 < c.words.size() && unq( c.words[j + 1].text ) == "errexit" )
        {
            errexit = false;
        }
    }
}

// a function definition, or a compound command: conditions are checked, bodies pass the consumer on (or not)
inline void Walker::walkCompound( const Node& c, const Consumer& consumer )
{
    if( c.kind == NodeKind::Func )
    {
        if( !isFunc( c.name ) )
        {
            funcs.push_back( c.name );
        }
        const bool savedE = errexit, savedP = pipefail;
        funcStack.push_back( c.name );
        for( std::uint32_t l : c.bodies )
        {
            const Consumer fn{ Verdict::Fn, c.name };
            walkList( l, &fn, false );
        }
        funcStack.pop_back();
        errexit  = savedE;
        pipefail = savedP;
        return;
    }
    for( std::uint32_t l : c.conds )
    {
        const Consumer cc = c.kind == NodeKind::If ? Consumer{ Verdict::Checked, "if" } : Consumer{ Verdict::Checked, "while/until" };
        walkList( l, &cc, false );
    }
    const bool passes = c.kind == NodeKind::If || c.kind == NodeKind::Case || c.kind == NodeKind::Subshell || c.kind == NodeKind::Group
                     || c.kind == NodeKind::Loop || c.kind == NodeKind::For;
    for( std::uint32_t l : c.bodies )
    {
        const Consumer bc = passes ? consumer : Consumer{ Verdict::Errexit, {} };
        walkList( l, &bc, false );
    }
}

// the $( ) bodies of a simple command: an assignment-only command carries its $( )'s status; anywhere else it is discarded
inline void Walker::walkSubstitutions( const Node& c, std::size_t k, const Consumer& consumer )
{
    const bool        assignOnly  = k == std::string::npos && std::none_of( c.words.begin(), c.words.end(), []( const Word& w ) { return w.text.empty(); } );
    const std::string w0          = c.words.empty() ? std::string() : unq( c.words[0].text );
    const bool        localAssign = !c.words.empty() && ( w0 == "local" || w0 == "export" || w0 == "declare" || w0 == "readonly" || w0 == "typeset" );
    const Consumer    inWord      = localAssign ? Consumer{ Verdict::Unchecked, w0 + " x=$(...) (status masked)" } : Consumer{ Verdict::Unchecked, "$(...) argument (status discarded)" };
    const Consumer    inAssign    = assignOnly ? consumer : inWord;
    const auto        walkSubs    = [ & ]( const Word& w, const Consumer& sc )
    {
        for( const Sub& s : w.subs )
        {
            ++substDepth;
            walkList( s.list, &sc, false );
            --substDepth;
        }
    };
    for( const Word& w : c.assigns )
    {
        walkSubs( w, inAssign );
    }
    for( const Word& w : c.words )
    {
        walkSubs( w, inWord );
    }
}

// a run of the code under test (or of a wrapper around it) is a call; every command's facts are noted
inline void Walker::recordCall( std::uint32_t node, const Node& c, const std::string& cw, const Consumer& consumer )
{
    std::string kind = underTest( cw );
    std::string call;
    if( !kind.empty() )
    {
        call = cw;
    }
    else if( isFunc( unq( cw ) ) )
    {
        kind = "wrapper";
        call = unq( cw );
    }
    if( !kind.empty() )
    {
        calls.push_back( { c.line, call, consumer, kind, node } );
    }
    if( facts != nullptr )
    {
        NodeFacts& f = ( *facts )[node];
        f.seen       = true;
        f.cons       = consumer;
        f.pipefail   = pipefail;
        f.errexit    = errexit;
        f.func       = funcStack.empty() ? std::string() : funcStack.back();
        f.kind       = kind;
    }
}

inline void Walker::walkCmd( std::uint32_t node, Consumer consumer )
{
    const Node& c = tree.nodes[node];
    if( c.kind != NodeKind::Simple )
    {
        walkCompound( c, consumer );
        return;
    }
    if( !c.words.empty() && unq( c.words[0].text ) == "set" )
    {
        applySet( c );
    }
    const std::size_t k = cmdWordIndex( c );
    walkSubstitutions( c, k, consumer );
    if( k == std::string::npos )
    {
        return;
    }
    if( consumer.v == Verdict::Errexit )
    {
        consumer = resolve( consumer );
    }
    recordCall( node, c, c.words[k].text, consumer );
}

// One command comparedNames reads: a simple command, or the synthetic `case SUBJECT` a case statement tests.
struct CmdSite
{
    std::uint32_t node;   // kNone: a synthetic `case SUBJECT` command
    std::string   synthetic;
    std::string   fn;
};
using RcFuncs = std::vector<std::pair<std::string, std::string>>;   // FN -> rc-file suffix, insertion order

// every simple command (and case subject) in source order with its function, and the names of the functions defined
inline void collectCmdSites( const Tree& t, std::vector<CmdSite>& allc, std::vector<std::string>& funcs )
{
    auto visit = [ & ]( std::uint32_t c, const std::string& fn )
    {
        const Node& n = t.nodes[c];
        if( n.kind == NodeKind::Simple )
        {
            allc.push_back( { c, {}, fn } );
            return;
        }
        if( n.kind == NodeKind::Func )
        {
            funcs.push_back( n.name );
        }
        if( n.kind == NodeKind::Case && !n.name.empty() )
        {
            allc.push_back( { kNone, "case " + n.name, fn } );
        }
    };
    forEachCmd( t, t.top, std::string(), visit );
}

// \.([A-Za-z0-9_]+)"?$ : the suffix of the file a word names, or empty
inline std::string trailingSuffix( std::string_view word )
{
    std::string_view body = word;
    if( !body.empty() && body.back() == '"' )
    {
        body.remove_suffix( 1 );
    }
    const std::size_t dot = body.rfind( '.' );
    if( dot == std::string_view::npos || dot + 1 >= body.size() || !std::all_of( body.begin() + static_cast<std::ptrdiff_t>( dot + 1 ), body.end(), isIdentChar ) )
    {
        return {};
    }
    return std::string( body.substr( dot + 1 ) );
}

// the functions whose body cats a status file (`cat "$d/x.rc"`): a test of `$( FN )` reads that file (last cat wins)
inline RcFuncs rcFileFuncs( const Tree& t, const std::vector<CmdSite>& allc )
{
    RcFuncs rcfuncs;
    for( const CmdSite& s : allc )
    {
        if( s.node == kNone || s.fn.empty() )
        {
            continue;
        }
        const Node& n = t.nodes[s.node];
        if( n.words.empty() || unq( n.words[0].text ) != "cat" )
        {
            continue;
        }
        const std::string suf = trailingSuffix( n.words.back().text );
        if( suf.empty() )
        {
            continue;
        }
        bool found = false;
        for( auto& [ fn, sf ] : rcfuncs )
        {
            if( fn == s.fn )
            {
                sf    = suf;
                found = true;
            }
        }
        if( !found )
        {
            rcfuncs.emplace_back( s.fn, suf );
        }
    }
    return rcfuncs;
}

// \$\(\s*FN\b : the text runs FN in a substitution
inline bool runsInSubst( std::string_view text, std::string_view fn )
{
    for( std::size_t p = text.find( "$(" ); p != std::string_view::npos; p = text.find( "$(", p + 1 ) )
    {
        std::size_t q = p + 2;
        while( q < text.size() && isSp( text[q] ) )
        {
            ++q;
        }
        if( startsAt( text, q, fn ) && ( q + fn.size() >= text.size() || !isWordChar( text[q + fn.size()] ) ) )
        {
            return true;
        }
    }
    return false;
}

inline bool isTestWord( std::string_view cw ) noexcept   // [ test case exit return [[ ((
{
    return cw == "[" || cw == "test" || cw == "case" || cw == "exit" || cw == "return" || cw.starts_with( "[[" ) || cw.starts_with( "((" );
}

// the names a test command reads: $VARS, (( bare idents )), cat'd rc files, and the files an rc-reading FN returns
inline void namesInTest( std::string_view text, std::string_view cw, const RcFuncs& rcfuncs, std::vector<std::string>& names )
{
    vrefs( text, names );
    if( cw.starts_with( "((" ) )
    {
        boundedIdents( text, names );
    }
    std::vector<std::string> sufs;
    catSuffixes( text, sufs );
    for( const std::string& suf : sufs )
    {
        names.push_back( "file:" + suf );
    }
    for( const auto& [ fn, suf ] : rcfuncs )
    {
        if( runsInSubst( text, fn ) )
        {
            names.push_back( "file:" + suf );
        }
    }
}

// a call of a script function (a checker): its "$VAR" arguments, and the $VARS of a single-quoted code argument it evals
inline void namesPassedToChecker( const std::vector<std::string_view>& words, std::vector<std::string>& names )
{
    for( std::size_t k = 1; k < words.size(); ++k )
    {
        const std::string_view n = quotedBareVar( words[k] );
        if( !n.empty() )
        {
            names.emplace_back( n );
        }
        else if( !words[k].empty() && words[k][0] == '\'' )
        {
            vrefs( words[k], names );   // code the checker evals
        }
    }
}

inline void namesOfSite( const Tree& t, const CmdSite& s, const std::vector<std::string>& funcs, const RcFuncs& rcfuncs, std::vector<std::string>& names )
{
    std::vector<std::string_view> words;
    const std::string             subject = s.node == kNone ? s.synthetic.substr( 5 ) : std::string();
    if( s.node == kNone )
    {
        words = { std::string_view( "case" ), std::string_view( subject ) };
    }
    else
    {
        for( const Word& w : t.nodes[s.node].words )
        {
            words.push_back( w.text );
        }
    }
    if( words.empty() )
    {
        return;
    }
    const std::string cw = unq( words[0] );
    if( isTestWord( cw ) )
    {
        std::string text;
        for( std::size_t k = 0; k < words.size(); ++k )
        {
            if( k > 0 )
            {
                text.push_back( ' ' );
            }
            text.append( words[k] );
        }
        namesInTest( text, cw, rcfuncs, names );
    }
    else if( std::find( funcs.begin(), funcs.end(), cw ) != funcs.end() )
    {
        namesPassedToChecker( words, names );
    }
}

// ="?\$\(\s*cat\s+[^)]*?\.([A-Za-z0-9_]+)"?\s*\)"?$ : the suffix of the status file an assignment value cats, or empty
inline std::string catAssignSuffix( std::string_view v )
{
    if( !v.empty() && v.front() == '"' )
    {
        v.remove_prefix( 1 );
    }
    if( v.substr( 0, 2 ) != "$(" )
    {
        return {};
    }
    std::size_t i = 2;
    while( i < v.size() && isSp( v[i] ) )
    {
        ++i;
    }
    if( !startsAt( v, i, "cat" ) || i + 3 >= v.size() || !isSp( v[i + 3] ) )
    {
        return {};
    }
    for( std::size_t k = i + 4; k < v.size() && v[k] != ')'; ++k )
    {
        if( v[k] != '.' )
        {
            continue;
        }
        std::size_t            end = 0;
        const std::string_view suf = rcSuffixClose( v, k, end );
        if( suf.empty() )
        {
            continue;
        }
        std::size_t e = end;
        if( e < v.size() && v[e] == '"' )
        {
            ++e;
        }
        if( e == v.size() )
        {
            return std::string( suf );
        }
    }
    return {};
}

// an alias `rcFull=$rcDef` (or `rc=$(cat x.rc)`) hands the status on: ( source, alias ) pairs in source order
inline std::vector<std::pair<std::string, std::string>> statusAliases( const Tree& t, const std::vector<CmdSite>& allc )
{
    std::vector<std::pair<std::string, std::string>> alias;   // ( src, dst )
    for( const CmdSite& s : allc )
    {
        if( s.node == kNone )
        {
            continue;
        }
        for( const Word& a : t.nodes[s.node].assigns )
        {
            const std::string_view tx = a.text;
            const std::size_t      eq = tx.find( '=' );
            if( eq == std::string_view::npos || eq == 0 || !isIdentStart( tx[0] ) || !std::all_of( tx.begin(), tx.begin() + static_cast<std::ptrdiff_t>( eq ), isIdentChar ) )
            {
                continue;
            }
            const std::string      dst( tx.substr( 0, eq ) );
            const std::string_view val = tx.substr( eq + 1 );
            const std::string_view sv  = quotedBareVar( val );
            if( !sv.empty() )
            {
                alias.emplace_back( std::string( sv ), dst );
            }
            const std::string suf = catAssignSuffix( val );
            if( !suf.empty() )
            {
                alias.emplace_back( "file:" + suf, dst );
            }
        }
    }
    return alias;
}

// a test of the alias is a test of the original: add each source whose alias is read (4 rounds, as Python does)
inline void closeOverAliases( std::vector<std::string>& names, const std::vector<std::pair<std::string, std::string>>& alias )
{
    std::vector<std::string> order;   // alias sources in first-insertion order (Python's dict order)
    for( const auto& [ src, dst ] : alias )
    {
        (void)dst;
        if( std::find( order.begin(), order.end(), src ) == order.end() )
        {
            order.push_back( src );
        }
    }
    for( int round = 0; round < 4; ++round )
    {
        for( const std::string& src : order )
        {
            const bool hit = std::any_of( alias.begin(), alias.end(), [ & ]( const std::pair<std::string, std::string>& a ) { return a.first == src && hasName( names, a.second ); } );
            if( hit && !hasName( names, src ) )
            {
                names.push_back( src );
                sortUnique( names );
            }
        }
    }
}

// Variables, and rc-file suffixes, that some TEST in the script reads (Python Walker._compared_names).
inline std::vector<std::string> comparedNames( const Tree& t )
{
    std::vector<CmdSite>     allc;
    std::vector<std::string> funcs;
    collectCmdSites( t, allc, funcs );
    const RcFuncs            rcfuncs = rcFileFuncs( t, allc );
    std::vector<std::string> names;
    for( const CmdSite& s : allc )
    {
        namesOfSite( t, s, funcs, rcfuncs, names );
    }
    sortUnique( names );
    closeOverAliases( names, statusAliases( t, allc ) );
    return names;
}

// ^\s*(?:(?:local|export|readonly)\s+)?NAME= : the assignment a line opens with, as ( NAME, value ); empty NAME if none
inline std::pair<std::string_view, std::string_view> lineAssignment( std::string_view l )
{
    std::size_t i = 0;
    while( i < l.size() && isSp( l[i] ) )
    {
        ++i;
    }
    for( std::string_view kwd : { std::string_view( "local" ), std::string_view( "export" ), std::string_view( "readonly" ) } )
    {
        if( startsAt( l, i, kwd ) && i + kwd.size() < l.size() && isSp( l[i + kwd.size()] ) )
        {
            std::size_t j = i + kwd.size();
            while( j < l.size() && isSp( l[j] ) )
            {
                ++j;
            }
            // (?:kw\s+)? is optional: keep it only when an assignment follows
            std::size_t q = j;
            if( q < l.size() && isIdentStart( l[q] ) )
            {
                while( q < l.size() && isIdentChar( l[q] ) )
                {
                    ++q;
                }
                if( q < l.size() && l[q] == '=' )
                {
                    i = j;
                }
            }
            break;
        }
    }
    if( i >= l.size() || !isIdentStart( l[i] ) )
    {
        return {};
    }
    std::size_t q = i;
    while( q < l.size() && isIdentChar( l[q] ) )
    {
        ++q;
    }
    if( q >= l.size() || l[q] != '=' )
    {
        return {};
    }
    return { l.substr( i, q - i ), l.substr( q + 1 ) };
}

// build[^ ]*/ripwire\b | RIPWIRE_BIN | ^"?\$\{?BIN\}?"?$ : a value that names the binary
inline bool valueNamesBinary( std::string_view val )
{
    bool hit = val.contains( "RIPWIRE_BIN" );
    for( std::size_t p = val.find( "build" ); !hit && p != std::string_view::npos; p = val.find( "build", p + 1 ) )
    {
        for( std::size_t r = val.find( "/ripwire", p + 5 ); r != std::string_view::npos; r = val.find( "/ripwire", r + 1 ) )
        {
            if( val.substr( p + 5, r - ( p + 5 ) ).find( ' ' ) != std::string_view::npos )
            {
                break;
            }
            if( r + 8 >= val.size() || !isWordChar( val[r + 8] ) )
            {
                hit = true;
                break;
            }
        }
    }
    if( hit )
    {
        return true;
    }
    std::string_view v = val;
    if( !v.empty() && v.front() == '"' )
    {
        v.remove_prefix( 1 );
    }
    if( !v.empty() && v.back() == '"' )
    {
        v.remove_suffix( 1 );
    }
    return bareVar( v ) == "BIN" || v == "$BIN}" || v == "${BIN";
}

// /ripwire/ or a \.(xml|out|txt|log)\b : a value that names an OUTPUT of the binary, not the binary
inline bool valueNamesOutput( std::string_view val )
{
    bool veto = val.contains( "/ripwire/" );
    for( std::string_view ext : { std::string_view( ".xml" ), std::string_view( ".out" ), std::string_view( ".txt" ), std::string_view( ".log" ) } )
    {
        for( std::size_t p = val.find( ext ); !veto && p != std::string_view::npos; p = val.find( ext, p + 1 ) )
        {
            veto = p + ext.size() >= val.size() || !isWordChar( val[p + ext.size()] );
        }
    }
    return veto;
}

// binvars: names assigned a value that names the binary (never one that RUNS it)
inline std::vector<std::string> binVars( std::string_view src )
{
    std::vector<std::string> out;
    std::size_t              b = 0;
    while( b <= src.size() )
    {
        std::size_t e = src.find( '\n', b );
        if( e == std::string_view::npos )
        {
            e = src.size();
        }
        const auto [ name, val ] = lineAssignment( src.substr( b, e - b ) );
        b                        = e + 1;
        if( !name.empty() && !val.contains( "$(" ) && !val.contains( "`" ) && !isNotBin( name )
            && ( isBinVar( name ) || ( valueNamesBinary( val ) && !valueNamesOutput( val ) ) ) )
        {
            out.emplace_back( name );
        }
        if( e >= src.size() )
        {
            break;
        }
    }
    sortUnique( out );
    return out;
}

}   // namespace detail

// The contract: every call under test with its verdict, plus (facet) what the final walk knew about every command.
inline Analysis analyze( const Tree& tree, std::string_view src )
{
    Analysis a;
    a.compared = detail::comparedNames( tree );
    const std::vector<std::string> vars = detail::binVars( src );
    detail::Walker                 w{ tree, src, vars, {}, &a.compared };
    w.collectTargets( tree.top );
    std::vector<std::string>      wrappers;
    std::vector<NodeFacts>        facts;
    std::optional<detail::Walker> last;
    for( int round = 0; round < 6; ++round )
    {
        last.emplace( detail::Walker{ tree, src, vars, w.targets, &a.compared } );
        detail::Walker& w2 = *last;
        w2.funcs           = wrappers;
        facts.assign( tree.nodes.size(), NodeFacts{} );
        w2.facts = &facts;
        w2.walkList( tree.top, nullptr, true );
        std::vector<std::string> next = wrappers;
        for( const detail::Walker::Raw& r : w2.calls )
        {
            if( r.cons.v == Verdict::Fn && ( r.via != "wrapper" || detail::hasName( wrappers, r.cmd ) ) )
            {
                next.push_back( r.cons.how );
            }
        }
        detail::sortUnique( next );
        if( next == wrappers )
        {
            break;
        }
        wrappers = std::move( next );
    }
    const detail::Walker& w2 = *last;
    for( const detail::Walker::Raw& r : w2.calls )
    {
        if( r.via == "wrapper" && !detail::hasName( wrappers, r.cmd ) )
        {
            continue;
        }
        Consumer cons = r.cons;
        if( cons.v == Verdict::Fn )
        {
            if( detail::hasName( wrappers, cons.how ) )
            {
                continue;   // reported at the wrapper's call sites instead
            }
            cons = Consumer{ Verdict::Unchecked, "output only" };
        }
        cons = w2.resolve( cons );
        a.calls.push_back( { r.line, r.via == "wrapper" ? r.cmd + "()" : r.cmd, cons.v == Verdict::Checked ? "checked" : "unchecked", cons.how, r.via, r.node } );
    }
    std::sort( a.calls.begin(), a.calls.end(), []( const Call& x, const Call& y )
               {
                   if( x.line != y.line )
                   {
                       return x.line < y.line;
                   }
                   if( x.cmd != y.cmd )
                   {
                       return x.cmd < y.cmd;
                   }
                   if( x.verdict != y.verdict )
                   {
                       return x.verdict < y.verdict;
                   }
                   if( x.how != y.how )
                   {
                       return x.how < y.how;
                   }
                   return x.kind < y.kind;
               } );
    a.facts    = std::move( facts );
    a.wrappers = std::move( wrappers );
    a.targets  = w.targets;
    return a;
}

inline std::vector<Call> scan( std::string_view src )
{
    const Tree t = parse( src );
    return analyze( t, src ).calls;
}

}   // namespace rw::shstatus
