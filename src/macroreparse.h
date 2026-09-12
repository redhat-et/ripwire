#pragma once
// macroreparse.h — THE MEMBER-MACRO RE-PARSE (0.6.0): the scanner and the adoption rule. Wired into the ingest by
// ingest_sidecap.h (measureHealthAdoptingMemberMacroReparse). Gates: test/macroreparsecheck.sh (real parses, controls
// byte-identical to the pre-change binary) and test/macroreparse_unit.cpp (every shape below, one case per boundary).
//
// WHAT IT REPAIRS. A function-like macro invoked with NO trailing `;` as a member of a class/struct/union body —
// `NAME_OF(Foo)` right before `};` — is read by tree-sitter-cpp, tree-sitter-c and tree-sitter-objc as a field
// declaration missing its `;`. With several such structs in a row the earlier ones dissolve into an ERROR region and
// the last one's body runs on to some later `}`: free functions are filed under that struct as methods, a struct can
// become a later function's return type (its lines summed into that function's cx/ccx), and in C whole functions
// vanish into ERROR nodes. src/extentsuspect.h DISCLOSES those rows; this repairs the parse they came from.
//
// WHY NOT THE GRAMMAR. A grammar patch changes every C-family parse in every corpus. This touches only a file whose
// first parse already holds error bytes, only the invocations the scanner below names, and keeps the result only
// when the parser measurably agrees it is better.
//
// THE PASS (per file, pure, deterministic). (1) The first parse holds error BYTES and the language is C-family.
// (2) findMemberMacroInvocations names each candidate. (3) blankInvocations copies the source with exactly those bytes
// replaced by spaces — newlines never move, so every byte offset and line number of the copy is the original's.
// (4) Re-parse the copy. (5) adoptsReparse: keep the second tree only if it holds STRICTLY FEWER error bytes. The
// symbols are then extracted from the adopted tree against the ORIGINAL bytes (identical offsets), so names, spans and
// bodies read the source as written.
//
// THE CANDIDATE, all of: an ALL-CAPS identifier (`_*[A-Z][A-Z0-9_]*`) that is the first token on its line, directly
// inside a class/struct/union body (not inside parentheses there), right after a member boundary (`;` `{` `}` `:` or a
// previous candidate); its `(…)` balanced and closed on the same line; nothing after it on the line but a comment; and
// the next token starting a member: `}`, `~`, `[[`, or an identifier that does not continue a declarator (noexcept,
// override, final, throw, requires, try). Comments, string/char/raw-string literals and preprocessor lines are skipped.
//
// WHY THESE BOUNDS — measured, not assumed (a Python prototype of this scanner over every errorful C-family file of
// three corpora: a BSL-licensed graph database, llvm/lib, this repo):
//   * ALL-CAPS. Allowing any identifier found ZERO extra class-body candidates on all three (331, 69 and 83 candidates,
//     every one ALL-CAPS). The lowercase shape does derail the grammar, but in valid code a lone lowercase `f(x)` line
//     is also how a constructor-shaped declarator continues onto a next line; nothing measured pays for that risk.
//     test/extentfix keeps a lowercase run on purpose, so the extent detector still has a live producer.
//   * CLASS BODIES ONLY. Namespace-scope invocations (`DEFINE_X(a)` runs) recover as a zero-width MISSING `;` with the
//     structure intact. Admitting them added adoptions but removed NO extent_suspect flag on either external corpus
//     (1,465 -> 93 and 589 -> 479 with or without them), and it would have re-parsed this repo's own
//     src/infra/dynamic_map.hpp.
//   * ERROR BYTES, NOT ERROR NODES. One whole-file ERROR counts as ONE node. On the file that motivated this pass the
//     repaired parse measured 1 -> 50 error nodes (small residual errors now visible) while error bytes fell
//     271,971 -> 376. A node rule rejects exactly the file it exists for: node-strict left 1,153 of 1,465 flags, the
//     byte rule 93. A MISSING-only first parse has zero error bytes, so it is never re-parsed — and its structure is
//     intact by the same measurement.
//
// COST. The scan runs only on a file whose first parse holds error bytes (one linear pass, a small scope stack); the
// second parse only when the scan names at least one candidate.

#include "extentsuspect.h"        // extent::inSet — the declarative membership test this header's language set reads
#include "infra/jsonesc.h"        // isJsonWs — horizontal space is its set minus the newline, plus \f and \v
#include "infra/namesplit.h"      // namesplit::isIdentStart / isIdentChar — the ONE ASCII identifier byte class
#include "model.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw::macroreparse
{

// ── the decisions a caller composes ──────────────────────────────────────────────────────────────────────────────────

// One candidate invocation: [startByte, endByte) is the name through its closing `)`; nameEndByte ends the name.
struct BlankSpan
{
    std::uint32_t startByte   = 0;
    std::uint32_t endByte     = 0;
    std::uint32_t nameEndByte = 0;
    std::uint32_t line        = 0;   // 1-based
};

// The C-family set: C++ (incl. .cu/.cuh on tree_sitter_cuda and .metal), C, and Objective-C(++). All three grammars
// derail on the shape and are repaired by the blank (test/macroreparsefix holds one fixture per grammar).
inline constexpr std::array<Lang, 3> kMacroReparseLangs = { Lang::Cpp, Lang::C, Lang::ObjC };

inline bool isMacroReparseLang( Lang lang ) noexcept
{
    return extent::inSet( kMacroReparseLangs, lang );
}

// The adoption rule: strictly fewer error bytes (see WHY THESE BOUNDS).
inline bool adoptsReparse( std::uint32_t firstErrorBytes, std::uint32_t reparsedErrorBytes ) noexcept
{
    return reparsedErrorBytes < firstErrorBytes;
}

// `_*[A-Z][A-Z0-9_]*` — the house spelling of a macro name.
inline bool isMacroShapedName( std::string_view name ) noexcept
{
    std::size_t index = 0;
    while( index < name.size() && name[ index ] == '_' )
    {
        ++index;
    }
    if( index == name.size() || name[ index ] < 'A' || name[ index ] > 'Z' )
    {
        return false;
    }
    return std::all_of( name.begin() + std::ptrdiff_t( index ), name.end(),
                        []( char c ) { return ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_'; } );
}

// ── the lexer: just enough C/C++ to know what is code ─────────────────────────────────────────────────────────────

enum class TokenKind : std::uint8_t { End, Ident, Punct, Literal };

struct Token
{
    TokenKind     kind  = TokenKind::End;
    char          punct = 0;   // a one-byte Punct token's byte; 0 on every other token, `::` and `->` included
    std::uint32_t start = 0;
    std::uint32_t end   = 0;
    std::uint32_t line  = 0;   // 1-based line of `start`
};

// A position in the source. A value type: a lookahead is a copy that is simply dropped.
struct Lexer
{
    std::string_view src;
    std::uint32_t    pos         = 0;
    std::uint32_t    line        = 1;
    bool             isLineStart = true;   // no token yet on this line (a `#` here opens a directive)
};

// Whitespace that does not end a line: JSON's set without the newline, plus the form feed and vertical tab C allows.
inline bool isHorizontalSpace( char c ) noexcept
{
    return ( isJsonWs( c ) && c != '\n' ) || c == '\f' || c == '\v';
}

inline bool startsWith( std::string_view src, std::uint32_t pos, std::string_view text ) noexcept
{
    return pos <= src.size() && src.substr( pos ).starts_with( text );
}

// A one-byte punctuator test. Sound as a bare compare because `punct` is 0 on every token that is not one (callers
// never ask about byte 0).
inline bool isPunct( const Token& t, char c ) noexcept
{
    return t.punct == c;
}

inline std::uint32_t countNewlines( std::string_view src, std::uint32_t from, std::uint32_t to ) noexcept
{
    return std::uint32_t( std::count( src.begin() + std::ptrdiff_t( from ), src.begin() + std::ptrdiff_t( to ), '\n' ) );
}

// A backslash-newline at pos (`\` LF or `\` CR LF): its length, or 0.
inline std::uint32_t lineSpliceLength( std::string_view src, std::uint32_t pos ) noexcept
{
    if( startsWith( src, pos, "\\\n" ) )
    {
        return 2;
    }
    return startsWith( src, pos, "\\\r\n" ) ? 3u : 0u;
}

// Past the first `closer` at or after `searchFrom` — or to the end of the source — counting the newlines crossed. The
// one skip block comments and raw strings share.
inline void skipPast( Lexer& lx, std::string_view closer, std::size_t searchFrom ) noexcept
{
    const std::size_t   close = lx.src.find( closer, searchFrom );
    const std::uint32_t end   = close == std::string_view::npos ? std::uint32_t( lx.src.size() ) : std::uint32_t( close + closer.size() );
    lx.line += countNewlines( lx.src, lx.pos, end );
    lx.pos = end;
}

// To the next unspliced newline (left unconsumed). A directive also carries on through a block comment.
inline void skipToLineEnd( Lexer& lx, bool isDirective ) noexcept
{
    while( lx.pos < lx.src.size() && lx.src[ lx.pos ] != '\n' )
    {
        const std::uint32_t splice = lineSpliceLength( lx.src, lx.pos );
        if( splice != 0 )
        {
            lx.pos += splice;
            ++lx.line;
        }
        else if( isDirective && startsWith( lx.src, lx.pos, "/*" ) )
        {
            skipPast( lx, "*/", std::size_t( lx.pos ) + 2 );
        }
        else
        {
            ++lx.pos;
        }
    }
}

// One piece of trivia at the cursor (newline, space, splice, comment, directive): consumed → true; code → false.
inline bool skipOneTrivia( Lexer& lx ) noexcept
{
    const char c = lx.src[ lx.pos ];
    if( c == '\n' )
    {
        ++lx.pos;
        ++lx.line;
        lx.isLineStart = true;
        return true;
    }
    if( isHorizontalSpace( c ) || lineSpliceLength( lx.src, lx.pos ) != 0 )
    {
        const std::uint32_t splice = lineSpliceLength( lx.src, lx.pos );
        lx.pos  += splice != 0 ? splice : 1u;
        lx.line += splice != 0 ? 1u : 0u;
        return true;
    }
    const bool isLineComment = startsWith( lx.src, lx.pos, "//" );
    if( isLineComment || ( c == '#' && lx.isLineStart ) )
    {
        skipToLineEnd( lx, !isLineComment );
        return true;
    }
    if( startsWith( lx.src, lx.pos, "/*" ) )
    {
        skipPast( lx, "*/", std::size_t( lx.pos ) + 2 );
        return true;
    }
    return false;
}

// A quoted literal: to its closing quote (escapes honoured) or, unterminated, up to — not past — the newline.
inline void skipQuoted( Lexer& lx ) noexcept
{
    const char    quote = lx.src[ lx.pos ];
    std::uint32_t p     = lx.pos + 1;
    while( p < lx.src.size() && lx.src[ p ] != quote && lx.src[ p ] != '\n' )
    {
        const bool isEscape = lx.src[ p ] == '\\' && p + 1 < lx.src.size();
        lx.line += ( isEscape && lx.src[ p + 1 ] == '\n' ) ? 1u : 0u;
        p       += isEscape ? 2u : 1u;
    }
    lx.pos = ( p < lx.src.size() && lx.src[ p ] == quote ) ? p + 1 : p;
}

// `R"delim(` with an optional u8/u/U/L prefix at pos: the offset just past its `(` and the delimiter; 0 if not one.
struct RawOpen
{
    std::uint32_t    bodyStart = 0;
    std::string_view delimiter;
};

inline RawOpen rawStringOpen( std::string_view src, std::uint32_t pos ) noexcept
{
    std::uint32_t p = pos + ( startsWith( src, pos, "u8" ) ? 2u : ( startsWith( src, pos, "u" ) || startsWith( src, pos, "U" ) || startsWith( src, pos, "L" ) ) ? 1u : 0u );
    if( !startsWith( src, p, "R\"" ) )
    {
        return {};
    }
    const std::uint32_t delimStart = p + 2;
    const std::size_t   open       = src.find_first_of( "()\\ \"\n", delimStart );
    if( open == std::string_view::npos || src[ open ] != '(' || open - delimStart > 16 )
    {
        return {};
    }
    return { std::uint32_t( open + 1 ), src.substr( delimStart, open - delimStart ) };
}

inline void skipRawString( Lexer& lx, const RawOpen& raw )
{
    const std::string closer = ")" + std::string( raw.delimiter ) + "\"";
    skipPast( lx, closer, raw.bodyStart );
}

// An identifier — or, when it is a literal prefix (L u U u8) glued to a quote, that literal.
inline TokenKind lexWord( Lexer& lx ) noexcept
{
    const std::uint32_t start = lx.pos;
    while( lx.pos < lx.src.size() && namesplit::isIdentChar( lx.src[ lx.pos ] ) )
    {
        ++lx.pos;
    }
    const std::string_view word       = lx.src.substr( start, lx.pos - start );
    const bool             isQuoteNext = lx.pos < lx.src.size() && ( lx.src[ lx.pos ] == '"' || lx.src[ lx.pos ] == '\'' );
    if( isQuoteNext && ( word == "L" || word == "u" || word == "U" || word == "u8" ) )
    {
        skipQuoted( lx );
        return TokenKind::Literal;
    }
    return TokenKind::Ident;
}

inline void lexPunct( Lexer& lx, Token& t ) noexcept
{
    const bool isDouble = startsWith( lx.src, lx.pos, "::" ) || startsWith( lx.src, lx.pos, "->" );
    t.kind  = TokenKind::Punct;
    t.punct = isDouble ? '\0' : lx.src[ lx.pos ];   // `::` and `->` must match no one-byte test (`:` is a boundary)
    lx.pos += isDouble ? 2u : 1u;
}

inline Token nextToken( Lexer& lx )
{
    while( lx.pos < lx.src.size() && skipOneTrivia( lx ) )
    {
    }
    Token t;
    t.start = lx.pos;
    t.line  = lx.line;
    if( lx.pos >= lx.src.size() )
    {
        t.end = lx.pos;
        return t;
    }
    lx.isLineStart = false;
    const char    c   = lx.src[ lx.pos ];
    const RawOpen raw = rawStringOpen( lx.src, lx.pos );
    if( raw.bodyStart != 0 )
    {
        skipRawString( lx, raw );
        t.kind = TokenKind::Literal;
    }
    else if( namesplit::isIdentStart( c ) )
    {
        t.kind = lexWord( lx );
    }
    else if( c == '"' || c == '\'' )
    {
        skipQuoted( lx );
        t.kind = TokenKind::Literal;
    }
    else if( c >= '0' && c <= '9' )
    {
        while( lx.pos < lx.src.size() && ( namesplit::isIdentChar( lx.src[ lx.pos ] ) || lx.src[ lx.pos ] == '.' || lx.src[ lx.pos ] == '\'' ) )
        {
            ++lx.pos;
        }
        t.kind = TokenKind::Literal;
    }
    else
    {
        lexPunct( lx, t );
    }
    t.end = lx.pos;
    return t;
}

// ── the scope a `{` opens ─────────────────────────────────────────────────────────────────────────────────────────────

enum class ScopeKind : std::uint8_t { Namespace, ClassBody, Other };

struct ScopeFrame
{
    ScopeKind     kind       = ScopeKind::Namespace;
    std::uint32_t parenDepth = 0;   // `(` / `[` open directly inside this body
};

enum class HeadDecision : std::uint8_t { Undecided, ClassBody, Other };

// The tokens since the last `;` `{` `}` — what the next `{` will open. Decided by the FIRST decisive token: `(`, `=`
// or `enum` ⇒ not a class body (a function, an initializer, an enum); a single `:` after a class key ⇒ a class body
// (the base clause, where parentheses are template arguments). `namespace` or a leading `extern "…"` ⇒ namespace-like.
struct HeadState
{
    std::uint32_t tokenCount       = 0;
    bool          hasNamespace     = false;
    bool          hasClassKey      = false;
    bool          isFirstExtern    = false;
    bool          isExternLinkage  = false;
    HeadDecision  decision         = HeadDecision::Undecided;
};

inline void decideHead( HeadState& head, HeadDecision decision ) noexcept
{
    head.decision = head.decision == HeadDecision::Undecided ? decision : head.decision;
}

inline void feedHeadWord( HeadState& head, std::string_view word, std::uint32_t index ) noexcept
{
    head.hasNamespace  = head.hasNamespace || word == "namespace";
    head.isFirstExtern = index == 0 ? word == "extern" : head.isFirstExtern;
    head.hasClassKey   = head.hasClassKey || word == "struct" || word == "class" || word == "union";
    if( word == "enum" )
    {
        decideHead( head, HeadDecision::Other );
    }
}

inline void feedHead( HeadState& head, const Token& t, std::string_view src ) noexcept
{
    const std::uint32_t index = head.tokenCount++;
    if( t.kind == TokenKind::Ident )
    {
        feedHeadWord( head, src.substr( t.start, t.end - t.start ), index );
    }
    else if( t.kind == TokenKind::Literal )
    {
        head.isExternLinkage = head.isExternLinkage || ( index == 1 && head.isFirstExtern );
    }
    else if( isPunct( t, '(' ) || isPunct( t, '=' ) )
    {
        decideHead( head, HeadDecision::Other );
    }
    else if( isPunct( t, ':' ) && head.hasClassKey )
    {
        decideHead( head, HeadDecision::ClassBody );
    }
}

inline ScopeKind classifyHead( const HeadState& head ) noexcept
{
    if( head.tokenCount == 0 )
    {
        return ScopeKind::Other;
    }
    if( head.hasNamespace || head.isExternLinkage )
    {
        return ScopeKind::Namespace;
    }
    if( head.decision != HeadDecision::Undecided )
    {
        return head.decision == HeadDecision::ClassBody ? ScopeKind::ClassBody : ScopeKind::Other;
    }
    return head.hasClassKey ? ScopeKind::ClassBody : ScopeKind::Other;
}

// Braces open and close scopes, `;` ends a head, `(` `[` nest inside the current body; every other token feeds the head.
inline void applyStructure( const Token& t, std::string_view src, std::vector<ScopeFrame>& scopes, HeadState& head )
{
    if( isPunct( t, '{' ) || isPunct( t, '}' ) || isPunct( t, ';' ) )
    {
        if( isPunct( t, '{' ) )
        {
            scopes.push_back( { classifyHead( head ), 0 } );
        }
        else if( isPunct( t, '}' ) && scopes.size() > 1 )
        {
            scopes.pop_back();
        }
        head = HeadState{};
        return;
    }
    if( isPunct( t, '(' ) || isPunct( t, '[' ) )
    {
        ++scopes.back().parenDepth;
    }
    else if( ( isPunct( t, ')' ) || isPunct( t, ']' ) ) && scopes.back().parenDepth > 0 )
    {
        --scopes.back().parenDepth;
    }
    feedHead( head, t, src );
}

// ── the candidate ─────────────────────────────────────────────────────────────────────────────────────────────────────

// What the previous significant token lets the next one be: a member can start after a boundary or a candidate.
enum class PrevToken : std::uint8_t { FileStart, MemberBoundary, Invocation, Other };

inline PrevToken prevTokenOf( const Token& t ) noexcept
{
    return ( isPunct( t, ';' ) || isPunct( t, '{' ) || isPunct( t, '}' ) || isPunct( t, ':' ) ) ? PrevToken::MemberBoundary : PrevToken::Other;
}

inline bool isFirstOnLine( std::string_view src, std::uint32_t pos ) noexcept
{
    std::uint32_t p = pos;
    while( p > 0 && isHorizontalSpace( src[ p - 1 ] ) )
    {
        --p;
    }
    return p == 0 || src[ p - 1 ] == '\n';
}

inline constexpr std::array<std::string_view, 6> kDeclaratorContinuations = { "noexcept", "override", "final", "throw", "requires", "try" };

inline bool isCandidateName( const Token& t, PrevToken prev, const ScopeFrame& frame, std::string_view src ) noexcept
{
    return t.kind == TokenKind::Ident && frame.kind == ScopeKind::ClassBody && frame.parenDepth == 0 && prev != PrevToken::Other
        && isFirstOnLine( src, t.start ) && isMacroShapedName( src.substr( t.start, t.end - t.start ) );
}

// After the name: `(`, then tokens to the balancing `)` — all on the name's line, with no `;` `{` `}` among them.
inline std::optional<Token> matchArguments( Lexer& lx, std::uint32_t line )
{
    if( !isPunct( nextToken( lx ), '(' ) || lx.line != line )
    {
        return std::nullopt;
    }
    std::uint32_t depth = 1;
    for( Token t = nextToken( lx ); t.kind != TokenKind::End && t.line == line && lx.line == line; t = nextToken( lx ) )
    {
        if( isPunct( t, ';' ) || isPunct( t, '{' ) || isPunct( t, '}' ) )
        {
            return std::nullopt;
        }
        depth += isPunct( t, '(' ) ? 1u : 0u;
        depth -= isPunct( t, ')' ) ? 1u : 0u;
        if( depth == 0 )
        {
            return t;
        }
    }
    return std::nullopt;
}

// From `pos` to the newline: only horizontal space, then optionally block comments closed on this line and a line comment.
inline bool isRestOfLineBlank( std::string_view src, std::uint32_t pos ) noexcept
{
    std::uint32_t p = pos;
    while( p < src.size() && src[ p ] != '\n' && !startsWith( src, p, "//" ) )
    {
        if( isHorizontalSpace( src[ p ] ) )
        {
            ++p;
            continue;
        }
        const std::size_t close = startsWith( src, p, "/*" ) ? src.find( "*/", std::size_t( p ) + 2 ) : std::string_view::npos;
        if( close == std::string_view::npos || src.find( '\n', p ) < close )
        {
            return false;
        }
        p = std::uint32_t( close + 2 );
    }
    return true;
}

// The token after the invocation starts a member: `}`, `~`, `[[`, or an identifier that does not continue a declarator.
inline bool startsMember( Lexer lx, std::string_view src )
{
    const Token next = nextToken( lx );
    if( next.kind == TokenKind::Ident )
    {
        const std::string_view word = src.substr( next.start, next.end - next.start );
        return std::find( kDeclaratorContinuations.begin(), kDeclaratorContinuations.end(), word ) == kDeclaratorContinuations.end();
    }
    if( isPunct( next, '}' ) || isPunct( next, '~' ) )
    {
        return true;
    }
    return isPunct( next, '[' ) && isPunct( nextToken( lx ), '[' );
}

// `lx` sits just past the candidate name. On a match it is left just past the `)`.
inline std::optional<BlankSpan> matchInvocation( Lexer& lx, const Token& name, std::string_view src )
{
    Lexer                      cursor = lx;
    const std::optional<Token> close  = matchArguments( cursor, name.line );
    if( !close || !isRestOfLineBlank( src, close->end ) || !startsMember( cursor, src ) )
    {
        return std::nullopt;
    }
    lx = cursor;
    return BlankSpan{ name.start, close->end, name.end, name.line };
}

// The per-file scope stack, reused across files so a worker allocates it once.
struct ScanScratch
{
    std::vector<ScopeFrame> scopes;
};

// Every candidate in `src`, in source order (see THE CANDIDATE). Deterministic in the bytes alone.
inline void findMemberMacroInvocations( std::string_view src, std::vector<BlankSpan>& out, ScanScratch& scratch )
{
    out.clear();
    if( src.size() >= 0xFFFFFFFFull )
    {
        return;   // offsets are 32-bit; the crawl's size ceiling keeps every indexed file far below this
    }
    scratch.scopes.assign( 1, ScopeFrame{} );   // the file scope
    Lexer     lx{ src };
    HeadState head;
    PrevToken prev = PrevToken::FileStart;
    for( Token t = nextToken( lx ); t.kind != TokenKind::End; t = nextToken( lx ) )
    {
        const std::optional<BlankSpan> span = isCandidateName( t, prev, scratch.scopes.back(), src ) ? matchInvocation( lx, t, src ) : std::nullopt;
        if( span )
        {
            out.push_back( *span );
            head = HeadState{};
            prev = PrevToken::Invocation;
            continue;
        }
        applyStructure( t, src, scratch.scopes, head );
        prev = prevTokenOf( t );
    }
}

// `out` = `src` with every span's bytes replaced by spaces. Same length, same newlines, so every offset carries over.
inline void blankInvocations( std::string_view src, std::span<const BlankSpan> spans, std::string& out )
{
    out.assign( src.data(), src.size() );
    for( const BlankSpan& span : spans )
    {
        const std::uint32_t end = std::min<std::uint32_t>( span.endByte, std::uint32_t( out.size() ) );
        for( std::uint32_t index = span.startByte; index < end; ++index )
        {
            out[ index ] = out[ index ] == '\n' ? '\n' : ' ';
        }
    }
}

}   // namespace rw::macroreparse
