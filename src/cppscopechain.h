#pragma once
// cppscopechain.h — the C/C++ SCOPE-CHAIN reader shared by --edit-check's declaration identity (editcheckdecl.h) and
// the written-spelling seed tier (graph.h resolveAllByWrittenSpelling). Moved here VERBATIM from editcheckdecl.h
// (lane qn-input) so graph.h can read a definition's full chain (every enclosing namespace and class, plus the
// declarator's written qualifier) without including editcheckdecl.h, which includes graph.h. The editCheck* names
// are kept so the edit-check side is a pure move; the contracts are the ones written beside each piece.
// The PARAMETER-LIST readers (editCheckTokens .. editCheckMemberQualifiers) moved here VERBATIM from editcheckdecl.h too
// (lane overload-split), so graph.h's argument-type overload pick (argtypepick.h) reads a parameter's written type with
// the same tokens --edit-check compares declarations by.

#include "infra/namesplit.h"    // namesplit::isIdentChar — the ONE ASCII identifier-byte test

#include <algorithm>
#include <cstddef>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// The chain label of a namespace written with no name (`namespace {`): no spelling writes it, name lookup skips it.
inline constexpr std::string_view kAnonymousNamespaceLabel = "(anonymous)";

// ── the source, with comments blanked ─────────────────────────────────────────────────────────────────────────
// Comments become spaces, BYTE FOR BYTE, so every recorded span still indexes the same text: a `/* = 2 */` reminder no
// longer reads as a default and a trailing `// (a, b)` no longer splits a parameter (review S1). String and character
// literals are skipped whole, so a `"//"` inside one is not a comment.
inline void editCheckBlankComments( std::string& text )
{
    std::size_t i = 0;
    while( i < text.size() )
    {
        const char c    = text[i];
        const char next = ( i + 1 < text.size() ) ? text[ i + 1 ] : '\0';
        if( c == '"' || c == '\'' )
        {
            std::size_t j = i + 1;
            while( j < text.size() && text[j] != c && text[j] != '\n' )
            {
                j += ( text[j] == '\\' ) ? 2u : 1u;
            }
            i = j + 1;
            continue;
        }
        if( c != '/' || ( next != '/' && next != '*' ) )
        {
            ++i;
            continue;
        }
        const std::size_t close = ( next == '/' ) ? text.find( '\n', i ) : text.find( "*/", i + 2 );
        const std::size_t end   = ( close == std::string::npos ) ? text.size() : ( next == '/' ? close : close + 2 );
        for( std::size_t k = i; k < end; ++k )
        {
            text[k] = ( text[k] == '\n' ) ? '\n' : ' ';
        }
        i = end;
    }
}

// Past a generic parameter list opening at `i` (Rust `<…>`, Go `[…]`), at the next non-blank byte; `i` itself when none opens
// there, npos when it never closes. A `->` inside Rust generics (`F: Fn() -> T`) closes nothing.
inline std::size_t editCheckSkipGenerics( std::string_view text, std::size_t i ) noexcept
{
    if( i == std::string_view::npos || ( text[i] != '<' && text[i] != '[' ) )
    {
        return i;
    }
    const char open = text[i], close = ( open == '<' ) ? '>' : ']';
    int        depth = 0;
    for( ; i < text.size(); ++i )
    {
        const bool arrow = close == '>' && i > 0 && text[ i - 1 ] == '-';
        depth += ( text[i] == open ) ? 1 : ( text[i] == close && !arrow ) ? -1 : 0;
        if( depth == 0 )
        {
            return text.find_first_not_of( " \t\r\n", i + 1 );
        }
    }
    return std::string_view::npos;
}

// Where `name` sits in a signature's text and where its parameter list opens: the first whole-word occurrence followed
// (whitespace allowed) by '(' — or, with `skipGenerics` (the Rust/Go arity reader, editcheckarity.h), by a generic
// parameter list and then '('. {npos, npos} when there is none.
inline std::pair<std::size_t, std::size_t> editCheckParamOpen( std::string_view text, std::string_view name, bool skipGenerics = false )
{
    for( std::size_t at = name.empty() ? std::string_view::npos : text.find( name ); at != std::string_view::npos; at = text.find( name, at + 1 ) )
    {
        const std::size_t blank = text.find_first_not_of( " \t\r\n", at + name.size() );
        const std::size_t after = skipGenerics ? editCheckSkipGenerics( text, blank ) : blank;
        if( ( at == 0 || !namesplit::isIdentChar( text[ at - 1 ] ) ) && after != std::string_view::npos && text[after] == '(' )
        {
            return { at, after };
        }
    }
    return { std::string_view::npos, std::string_view::npos };
}

// ── macros that may open or close a scope (the brace counter cannot see through them) ──────────────────────────
// A namespace opened by a macro (`#define NS_BEGIN namespace outer {` … `NS_BEGIN` … `NS_END`) leaves the braces balanced
// and the chain reading GLOBAL — a false pairing. So a file's chain is UNREADABLE when, at namespace scope, a statement
// starts with (1) a macro the file #defines with a brace or `namespace` in its body, (2) an ALL-CAPS identifier standing
// alone on its line (an argument list allowed): the shape of a scope macro defined in another header, or (3) an ALL-CAPS
// identifier naming NAMESPACE, BEGIN or END. Each over-reads (a lone `Q_DECLARE_METATYPE( X )` trips it too); every
// over-read fails CLOSED and is disclosed (defaults_untied=).
inline bool editCheckAllCaps( std::string_view w ) noexcept
{
    const auto lower = std::find_if( w.begin(), w.end(), []( char c ) { return !( ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_' ); } );
    return w.size() >= 2 && lower == w.end() && !( w[0] >= '0' && w[0] <= '9' );
}

inline bool editCheckLineStartsAt( std::string_view text, std::size_t i ) noexcept
{
    const std::size_t lineStart = ( i == 0 ) ? std::string_view::npos : text.rfind( '\n', i - 1 );
    const std::size_t from      = ( lineStart == std::string_view::npos ) ? 0 : lineStart + 1;
    return text.substr( from, i - from ).find_first_not_of( " \t" ) == std::string_view::npos;
}

// does the identifier [i, end) stand alone on its line (an argument list after it allowed)?
inline bool editCheckAloneOnLine( std::string_view text, std::size_t i, std::size_t end ) noexcept
{
    std::size_t after = text.find_first_not_of( " \t", end );
    if( after != std::string_view::npos && text[ after ] == '(' )
    {
        const std::size_t close = text.find( ')', after );
        after = ( close == std::string_view::npos ) ? close : text.find_first_not_of( " \t", close + 1 );
    }
    const bool lineEnds = after == std::string_view::npos || text[ after ] == '\n' || text[ after ] == '\r' || text[ after ] == ';';
    return lineEnds && editCheckLineStartsAt( text, i );
}

// the NAME of a `#define NAME body` line whose body opens or closes a scope, else empty
inline std::string_view editCheckScopeDefine( std::string_view line ) noexcept
{
    const std::size_t def  = line.find( "define" );
    const std::size_t name = ( def == std::string_view::npos ) ? def : line.find_first_not_of( " \t", def + 6 );
    std::size_t       end  = name;
    while( end != std::string_view::npos && end < line.size() && namesplit::isIdentChar( line[ end ] ) )
    {
        ++end;
    }
    const std::string_view body = ( end == std::string_view::npos ) ? std::string_view{} : line.substr( end );
    const bool opensScope = body.find_first_of( "{}" ) != std::string_view::npos || body.find( "namespace" ) != std::string_view::npos;
    return ( end != name && opensScope ) ? line.substr( name, end - name ) : std::string_view{};
}

// What EditCheckBraceLexer( file ).chainAt( offset ) and its usingDirectiveBefore() answer, for EVERY offset of one file,
// from one pass (lane PF2, SCOPE-INDEX). chainAt lexes the whole file per call (the final balance decides any answer), so a
// caller asking once per definition paid symbols x file size: the argument-type overload pick read every candidate's chain
// that way, the hottest frame of llvm-project/clang's resolve loop after the narrowing walks were kept. The chain only
// changes at a '{' or '}' that pushes or pops labels, so the pass keeps those points and the chain after each; an offset's
// chain is the one after the last such point before it, exactly the state chainAt snapshots there.
struct EditCheckScopeIndex
{
    bool                                  ok = false;   // the braces balance, close, and no macro opens a scope: chainAt's answers stand
    std::vector<std::size_t>              changeAt;     // ascending positions of the label-moving '{' / '}'
    std::vector<std::vector<std::string>> chainAfter;   // parallel: the chain after each
    std::vector<std::size_t>              usingAt;      // ascending starts of the `namespace` of each `using namespace`

    std::optional<std::vector<std::string>> chainAt( std::size_t offset ) const
    {
        if( !ok )
        {
            return std::nullopt;
        }
        const std::size_t before = std::size_t( std::lower_bound( changeAt.begin(), changeAt.end(), offset ) - changeAt.begin() );
        return before == 0 ? std::vector<std::string>{} : chainAfter[ before - 1 ];
    }
    bool usingDirectiveBefore( std::size_t offset ) const noexcept
    {
        return !usingAt.empty() && usingAt.front() < offset;
    }
};

// ── the full scope chain ──────────────────────────────────────────────────────────────────────────────────────
// The ENCLOSING half: a brace lexer over the comment-blanked file. Every '{' pushes the labels that a `namespace A::B`,
// `namespace` (anonymous), `struct S`, `class S` or `union S` head left pending (an `enum class` and every other block
// push none); ';', '(' and '=' cancel a pending head. String and character literals and preprocessor lines are
// skipped. The chain at `offset` is the stack's labels, outermost first. UNKNOWN (nullopt) when the file's braces do not
// balance — the shape a macro-opened namespace or an `#if { #else { #endif` pair leaves — because then the stack cannot
// be trusted.
class EditCheckBraceLexer
{
public:
    explicit EditCheckBraceLexer( std::string_view source ) : text( source ) {}

    std::optional<std::vector<std::string>> chainAt( std::size_t offset )
    {
        std::optional<std::vector<std::string>> snapshot;
        std::size_t                             i = 0;
        askedOffset                               = offset;
        while( i < text.size() && balanced )
        {
            if( !snapshot && i >= offset )
            {
                snapshot = current();
            }
            i = step( i );
        }
        if( !snapshot && balanced && offset >= text.size() )
        {
            snapshot = current();
        }
        return ( balanced && stack.empty() && !scopeMacro ) ? snapshot : std::nullopt;
    }

    // chainAt for several offsets in ONE pass over the file (XF-ALIAS-HOP: every site of a file at once, never one scan per
    // site). `sorted` ascends; each answer is what chainAt( offset ) returns (all nullopt when the braces do not balance).
    // `allowScopeMacro`: keep the chains of a file whose braces balance although a macro may open a scope (the reader then
    // fails closed by itself: a namespace the braces do not show only shortens the chain, so a qualifier or prefix it would
    // have proven stays unproven).
    std::vector<std::optional<std::vector<std::string>>> chainsAt( const std::vector<std::size_t>& sorted, bool allowScopeMacro = false )
    {
        std::vector<std::optional<std::vector<std::string>>> out( sorted.size() );
        std::size_t                                          next = 0;
        std::size_t                                          i    = 0;
        askedOffset                                               = sorted.empty() ? 0 : sorted.back();
        while( i < text.size() && balanced )
        {
            while( next < sorted.size() && i >= sorted[ next ] )
            {
                out[ next++ ] = current();
            }
            i = step( i );
        }
        while( balanced && next < sorted.size() )
        {
            out[ next++ ] = current();
        }
        if( !( balanced && stack.empty() && ( allowScopeMacro || !scopeMacro ) ) )
        {
            for( auto& o : out )
            {
                o.reset();
            }
        }
        return out;
    }

    // the one pass that answers chainAt / usingDirectiveBefore for every offset (EditCheckScopeIndex above)
    EditCheckScopeIndex scopeIndex()
    {
        EditCheckScopeIndex index;
        recording   = &index;
        askedOffset = text.size();
        for( std::size_t i = 0; i < text.size() && balanced; )
        {
            i = step( i );
        }
        recording = nullptr;
        index.ok  = balanced && stack.empty() && !scopeMacro;
        return index;
    }

    // a `using namespace X;` came before the offset asked about: a QUALIFIED definition there (`int S::f`) may name a
    // member of X, so its written chain is not certain (the caller then reads the chain as unknown)
    bool usingDirectiveBefore() const noexcept { return usingBefore; }

private:
    std::vector<std::string> current() const
    {
        std::vector<std::string> chain;
        for( const std::vector<std::string>& labels : stack )
        {
            chain.insert( chain.end(), labels.begin(), labels.end() );
        }
        return chain;
    }

    // one lexical step from `i`; returns where the next one starts
    std::size_t step( std::size_t i )
    {
        const char c = text[i];
        if( c == '"' || ( c == '\'' && !( i > 0 && namesplit::isIdentChar( text[ i - 1 ] ) ) ) )
        {
            return skipLiteral( i );
        }
        if( c == '#' && editCheckLineStartsAt( text, i ) )
        {
            stmtStart = true;
            return skipDirective( i );
        }
        if( namesplit::isIdentChar( c ) )
        {
            const std::size_t end = word( i );
            stmtStart             = false;
            return end;
        }
        punctuation( c );
        if( recording != nullptr && ( c == '{' || c == '}' ) && labelsMoved )
        {
            recording->changeAt.push_back( i );
            recording->chainAfter.push_back( current() );
        }
        return i + 1;
    }

    // a '{' pushes the pending head's labels, a '}' pops; ';', '(' and '=' cancel a pending head
    void punctuation( char c )
    {
        labelsMoved = false;
        if( c == '{' )
        {
            labelsMoved = pending.has_value() && !pending->empty();
            stack.push_back( pending.value_or( std::vector<std::string>{} ) );
            stackIsNamespace.push_back( char( pending.has_value() && pendingNamespace ? 1 : 0 ) );
            pending.reset();
        }
        else if( c == '}' && stack.empty() )
        {
            balanced = false;   // a close with nothing open: the file cannot be read
        }
        else if( c == '}' )
        {
            labelsMoved = !stack.back().empty();
            stack.pop_back();
            stackIsNamespace.pop_back();
        }
        pending  = ( c == ';' || c == '(' || c == '=' ) ? std::nullopt : pending;
        stmtStart = ( c == ';' || c == '{' || c == '}' ) || ( stmtStart && std::string_view( " \t\r\n" ).find( c ) != std::string_view::npos );
    }

    // see editCheckScopeDefine above for the three shapes; only at namespace scope, only at a statement's start
    bool scopeMacroAt( std::string_view w, std::size_t i, std::size_t end ) const
    {
        const bool atNamespaceScope = std::find( stackIsNamespace.begin(), stackIsNamespace.end(), char( 0 ) ) == stackIsNamespace.end();
        const bool namesScope       = w.find( "NAMESPACE" ) != std::string_view::npos || w.find( "BEGIN" ) != std::string_view::npos
                                   || w.find( "END" ) != std::string_view::npos;
        return stmtStart && atNamespaceScope
            && ( std::find( braceMacros.begin(), braceMacros.end(), w ) != braceMacros.end()
                 || ( editCheckAllCaps( w ) && ( namesScope || editCheckAloneOnLine( text, i, end ) ) ) );
    }

    std::size_t skipDirective( std::size_t i )
    {
        const std::size_t start = i;
        while( i < text.size() && !( text[i] == '\n' && text[ i - 1 ] != '\\' ) )
        {
            ++i;
        }
        if( const std::string_view name = editCheckScopeDefine( text.substr( start, i - start ) ); !name.empty() )
        {
            braceMacros.push_back( name );   // a `#define NAME body` whose body opens or closes a scope
        }
        return i;
    }

    // past the balanced parenthesised group that starts at the first non-blank byte from `i` (none: `i` itself)
    std::size_t skipParenGroup( std::size_t i ) const
    {
        const std::size_t open = text.find_first_not_of( " \t\r\n", i );
        if( open == std::string_view::npos || text[open] != '(' )
        {
            return i;
        }
        std::size_t depth = 0;
        for( std::size_t j = open; j < text.size(); ++j )
        {
            depth += ( text[j] == '(' ) ? 1u : 0u;
            depth -= ( text[j] == ')' ) ? 1u : 0u;
            if( depth == 0 )
            {
                return j + 1;
            }
        }
        return text.size();
    }

    std::size_t skipLiteral( std::size_t i ) const
    {
        const char  quote = text[i];
        std::size_t j     = i + 1;
        if( quote == '"' && i > 0 && text[ i - 1 ] == 'R' )
        {   // a raw string: R"delim( … )delim"
            const std::size_t paren = text.find( '(', j );
            const std::string close = ")" + std::string( text.substr( j, paren == std::string_view::npos ? 0 : paren - j ) ) + "\"";
            const std::size_t end   = ( paren == std::string_view::npos ) ? std::string_view::npos : text.find( close, paren );
            return ( end == std::string_view::npos ) ? text.size() : end + close.size();
        }
        while( j < text.size() && text[j] != quote && text[j] != '\n' )
        {
            j += ( text[j] == '\\' ) ? 2u : 1u;
        }
        return j + 1;
    }

    // an identifier; a scope head records the labels the next '{' pushes
    std::size_t word( std::size_t i )
    {
        std::size_t end = i;
        while( end < text.size() && namesplit::isIdentChar( text[end] ) )
        {
            ++end;
        }
        const std::string_view w = text.substr( i, end - i );
        if( pending && ( w == "alignas" || w == "__attribute__" || w == "__declspec" ) )
        {
            lastWord = w;
            return skipParenGroup( end );   // an attribute group inside a class head is part of the head, not a '(' cancel
        }
        scopeMacro  = scopeMacro || scopeMacroAt( w, i, end );
        usingBefore = usingBefore || ( lastWord == "using" && w == "namespace" && i < askedOffset );
        if( recording != nullptr && lastWord == "using" && w == "namespace" )
        {
            recording->usingAt.push_back( i );
        }
        if( ( w == "namespace" && lastWord != "using" ) || ( ( w == "struct" || w == "class" || w == "union" ) && lastWord != "enum" ) )
        {
            pending          = headLabels( end, w == "namespace" );
            pendingNamespace = w == "namespace";
        }
        else if( ( w == "struct" || w == "class" ) && lastWord == "enum" )
        {
            pending          = std::vector<std::string>{};
            pendingNamespace = false;
        }
        lastWord = w;
        return end;
    }

    // The labels a head keyword opens: the LAST qualified name before the head ends at '{', a base-clause ':', a template
    // argument list '<', ';' or '=' — so an export macro or attribute in front (`class API_EXPORT S`, `struct
    // alignas( 8 ) S`) does not become the label, and `namespace A::B` / `struct A::B` give {A, B}. A parenthesised or
    // bracketed group is skipped whole. Nothing named: one anonymous label for a namespace, none for a struct.
    std::vector<std::string> headLabels( std::size_t from, bool isNamespace ) const
    {
        std::vector<std::string> labels;
        bool                     joined = false;   // the previous token was `::`
        for( std::size_t i = from; i < text.size(); )
        {
            const char c = text[i];
            if( text.substr( i, 2 ) == "::" )
            {
                joined = true;
                i += 2;
            }
            else if( namesplit::isIdentChar( c ) )
            {
                std::size_t end = i;
                while( end < text.size() && namesplit::isIdentChar( text[end] ) )
                {
                    ++end;
                }
                const std::string_view w = text.substr( i, end - i );
                if( !joined && w != "final" )
                {
                    labels.clear();
                }
                if( w != "final" )
                {
                    labels.emplace_back( w );
                }
                joined = false;
                i      = end;
            }
            else if( c == '(' || c == '[' )
            {
                const std::size_t close = text.find( c == '(' ? ')' : ']', i );
                i = ( close == std::string_view::npos ) ? text.size() : close + 1;
            }
            else if( c == '{' || c == ':' || c == '<' || c == ';' || c == '=' )
            {
                break;
            }
            else
            {
                ++i;
            }
        }
        if( labels.empty() && isNamespace )
        {
            labels.emplace_back( kAnonymousNamespaceLabel );
        }
        return labels;
    }

    std::string_view                        text;
    std::vector<std::vector<std::string>>   stack;
    std::vector<char>                       stackIsNamespace;   // parallel to `stack`: 1 = a namespace's braces
    std::optional<std::vector<std::string>> pending;
    std::vector<std::string_view>           braceMacros;        // this file's #defines whose body opens or closes a scope
    std::string_view                        lastWord;
    std::size_t                             askedOffset = 0;
    bool                                    pendingNamespace = false;
    bool                                    balanced         = true;
    bool                                    stmtStart        = true;
    bool                                    scopeMacro       = false;
    bool                                    usingBefore      = false;
    bool                                    labelsMoved      = false;     // the last punctuation pushed or popped labels
    EditCheckScopeIndex*                    recording        = nullptr;   // scopeIndex's pass: where it keeps what it saw
};

// The WRITTEN half: the qualifier spelled before the declarator's name, read backwards from `nameAt` — `outer::detail::`
// in `int outer::detail::f(`. `absolute` when it starts with `::`; nullopt for a template-qualified one (`S<T>::f`),
// which this reader does not resolve.
struct EditCheckWrittenQualifier
{
    std::vector<std::string> names;
    bool                     absolute;
};

inline std::optional<EditCheckWrittenQualifier> editCheckWrittenQualifier( std::string_view text, std::size_t nameAt )
{
    // the last non-blank byte strictly before `limit`, or npos
    const auto before = [ & ]( std::size_t limit ) { return limit == 0 ? std::string_view::npos : text.find_last_not_of( " \t\r\n", limit - 1 ); };
    EditCheckWrittenQualifier q{};
    for( std::size_t at = nameAt;; )
    {
        const std::size_t colon = before( at );
        if( colon == std::string_view::npos || colon == 0 || text.substr( colon - 1, 2 ) != "::" )
        {
            return q;
        }
        const std::size_t last = before( colon - 1 );
        if( last == std::string_view::npos || !namesplit::isIdentChar( text[ last ] ) )
        {
            if( last != std::string_view::npos && text[ last ] == '>' )
            {
                return std::nullopt;   // `S<T>::f`: not resolved here
            }
            q.absolute = true;         // a leading `::`
            return q;
        }
        std::size_t start = last;
        while( start > 0 && namesplit::isIdentChar( text[ start - 1 ] ) )
        {
            --start;
        }
        q.names.insert( q.names.begin(), std::string( text.substr( start, last + 1 - start ) ) );
        at = start;
    }
}

// ── one parameter's type ──────────────────────────────────────────────────────────────────────────────────────
// Tokens: identifiers (with `::` kept inside them) and single punctuation bytes, so whitespace never decides equality. An
// attribute (`[[maybe_unused]]`) is not part of the type and is skipped.
inline std::vector<std::string> editCheckTokens( std::string_view param )
{
    const auto identAt = [ & ]( std::size_t i )
    {
        return namesplit::isIdentChar( param[i] ) || ( param[i] == ':' && i + 1 < param.size() && param[ i + 1 ] == ':' );
    };
    std::vector<std::string> toks;
    std::size_t              i = 0;
    while( i < param.size() )
    {
        if( param.substr( i, 2 ) == "[[" )
        {
            const std::size_t close = param.find( "]]", i + 2 );
            i = ( close == std::string_view::npos ) ? param.size() : close + 2;
            continue;
        }
        if( !identAt( i ) )
        {
            if( param[i] != ' ' && param[i] != '\t' && param[i] != '\n' && param[i] != '\r' )
            {
                toks.emplace_back( 1, param[i] );
            }
            ++i;
            continue;
        }
        std::string tok;
        while( i < param.size() && identAt( i ) )
        {
            const std::size_t step = ( param[i] == ':' ) ? 2u : 1u;
            tok.append( param.substr( i, step ) );
            i += step;
        }
        toks.push_back( std::move( tok ) );
    }
    return toks;
}

// One parameter's TYPE: its tokens minus the declarator name, which is dropped when it is the last identifier (before an
// array suffix, if any) and a type token precedes it — `int x` -> `int`, `const Foo& f` -> `const Foo &`, `int a[3]` ->
// `int [ 3 ]`. A keyword type is never mistaken for a name (`unsigned long` keeps both), and a lone qualifier is not a
// type (`const Foo` keeps `Foo`).
inline std::vector<std::string> editCheckTypeTokens( std::string_view param )
{
    static constexpr std::string_view kTypeWords[] = { "int", "long", "short", "char", "unsigned", "signed", "double", "float", "bool",
                                                       "void", "auto", "wchar_t", "char8_t", "char16_t", "char32_t" };
    static constexpr std::string_view kQualWords[] = { "const", "volatile", "struct", "class", "enum", "union", "typename", "register",
                                                       "restrict", "__restrict" };
    const auto in = []( const std::string& t, std::span<const std::string_view> set ) { return std::find( set.begin(), set.end(), t ) != set.end(); };

    std::vector<std::string> toks   = editCheckTokens( param );
    const auto               suffix = std::find( toks.begin(), toks.end(), std::string( "[" ) );
    const std::size_t        nameAt = ( !toks.empty() && toks.back() == "]" ) ? std::size_t( suffix - toks.begin() ) : toks.size();
    if( nameAt < 2 )
    {
        return toks;
    }
    const std::string& name       = toks[ nameAt - 1 ];
    const bool         typeBefore = std::any_of( toks.begin(), toks.begin() + std::ptrdiff_t( nameAt - 1 ),
                                                 [ & ]( const std::string& t ) { return !in( t, kQualWords ); } );
    if( namesplit::isIdentChar( name[0] ) && !in( name, kTypeWords ) && !in( name, kQualWords ) && typeBefore )
    {
        toks.erase( toks.begin() + std::ptrdiff_t( nameAt - 1 ) );
    }
    return toks;
}

// The raw parameters between the '(' at `open` and its matching ')' (at `closeAt`), each with whether it carries a
// default. Split at depth-0 commas; '<'/'>' nest only in a TYPE, never after its '=' (a default value may compare).
struct EditCheckRawParams
{
    std::vector<std::string_view> text;
    std::vector<char>             defaulted;
    std::size_t                   closeAt;
    bool                          closed;
};

inline EditCheckRawParams editCheckSplitParams( std::string_view text, std::size_t open )
{
    EditCheckRawParams raw{};
    int                depth = 0, angle = 0;
    bool               inDefault = false;
    std::size_t        start     = open + 1;
    for( std::size_t i = open + 1; i < text.size() && !raw.closed; ++i )
    {
        const char c        = text[i];
        const bool atTop    = depth == 0 && ( angle == 0 || inDefault );
        const bool assigns  = c == '=' && depth == 0 && angle == 0 && text.substr( i - 1, 3 ).find( "==" ) == std::string_view::npos
                           && std::string_view( "!<>" ).find( text[ i - 1 ] ) == std::string_view::npos;
        if( atTop && ( c == ')' || c == ',' ) )
        {
            raw.text.push_back( text.substr( start, i - start ) );
            raw.defaulted.push_back( char( inDefault ? 1 : 0 ) );
            start       = i + 1;
            inDefault   = false;
            angle       = 0;
            raw.closed  = ( c == ')' );
            raw.closeAt = i;
            continue;
        }
        depth     += ( c == '(' || c == '[' || c == '{' ) ? 1 : ( c == ')' || c == ']' || c == '}' ) ? -1 : 0;
        angle     += ( inDefault || depth != 0 ) ? 0 : ( c == '<' ) ? 1 : ( c == '>' && angle > 0 ) ? -1 : 0;
        inDefault  = inDefault || assigns;
    }
    return raw;
}

// The member's cv/ref qualifiers after its parameter list, up to the body, a ';', an '=' (`= 0`, `= default`), a
// ctor-initializer ':' or a trailing return type: `const`, `volatile`, `&`, `&&`, in order.
inline std::string editCheckMemberQualifiers( std::string_view text, std::size_t afterParams )
{
    std::string quals;
    for( std::size_t i = afterParams; i < text.size(); ++i )
    {
        const char c = text[i];
        if( c == '{' || c == ';' || c == '=' || ( c == ':' && text.substr( i, 2 ) != "::" ) || text.substr( i, 2 ) == "->" )
        {
            break;
        }
        if( c == '&' )
        {
            quals += '&';
        }
        else if( namesplit::isIdentChar( c ) && ( i == 0 || !namesplit::isIdentChar( text[ i - 1 ] ) ) )
        {
            const std::size_t end  = text.find_first_not_of( "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_", i );
            const std::string_view w = text.substr( i, ( end == std::string_view::npos ? text.size() : end ) - i );
            quals += ( w == "const" || w == "volatile" ) ? std::string( w ) + " " : std::string();
        }
    }
    return quals;
}

}   // namespace rw
