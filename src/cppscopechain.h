#pragma once
// cppscopechain.h — the C/C++ SCOPE-CHAIN reader shared by --edit-check's declaration identity (editcheckdecl.h) and
// the written-spelling seed tier (graph.h resolveAllByWrittenSpelling). Moved here VERBATIM from editcheckdecl.h
// (lane qn-input) so graph.h can read a definition's full chain (every enclosing namespace and class, plus the
// declarator's written qualifier) without including editcheckdecl.h, which includes graph.h. The editCheck* names
// are kept so the edit-check side is a pure move; the contracts are the ones written beside each piece.

#include "infra/namesplit.h"    // namesplit::isIdentChar — the ONE ASCII identifier-byte test

#include <algorithm>
#include <cstddef>
#include <optional>
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

// Where `name` sits in a signature's text and where its parameter list opens: the first whole-word occurrence followed
// (whitespace allowed) by '('. {npos, npos} when there is none.
inline std::pair<std::size_t, std::size_t> editCheckParamOpen( std::string_view text, std::string_view name )
{
    for( std::size_t at = name.empty() ? std::string_view::npos : text.find( name ); at != std::string_view::npos; at = text.find( name, at + 1 ) )
    {
        const std::size_t after = text.find_first_not_of( " \t\r\n", at + name.size() );
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
        return i + 1;
    }

    // a '{' pushes the pending head's labels, a '}' pops; ';', '(' and '=' cancel a pending head
    void punctuation( char c )
    {
        if( c == '{' )
        {
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

}   // namespace rw
