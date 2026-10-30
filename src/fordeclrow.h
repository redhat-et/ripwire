#pragma once
// fordeclrow.h — DECL-ROW: a --for task about ONE C/C++/Go function's signature carries that function's declaration rows, the
// rows --defs computes (a header prototype, a forward declaration, an interface contract), so the agent changing the signature
// sees every place that must change in step. (CLI src/verbs_for.h appendForTaskRowBlocks, MCP `for` src/mcpverbs.h forTaskText —
// one renderer.)
//
// WHY. mf1-tmux-03 asks which prototypes change when server_start takes a new argument: --for prints the definition in
// server.c and never the tmux.h prototype, while --defs prints both.
//
// WHEN (present-only). Either arm, and the subject must have a non-test declaration row that is callable and in C, C++ or Go:
//   - TASK WORD: outside code spans the task says signature / prototype / new|extra|additional [required] argument|parameter;
//     the subject is the first code span or identifier-shaped word that resolves to such a row.
//   - BARE SUBJECT: the whole task is one symbol spelling (`--for=server_start`), and its pick is provably unique. A symbol
//     alone has no task word to read; a name that binds several definitions stays silent here.
// The block reads what the index holds: no new analysis, and the ordinary answer before it is unchanged. A name that has no
// declaration prints nothing: a definition row alone would repeat the answer. --defs folds a tied prototype into its definition's
// row; this block unfolds it, because that prototype is the row asked for.
#include "defslookup.h"    // lookupDefs / defRowXml / defPickProvablyUnique — the --defs lookup
#include "forcallerhop.h"  // forTaskIdentWords — the one word split of a --for task
#include "nextverb.h"      // nextFlag / nextAttrXml
#include "serialize.h"     // escapeXml / isCallableKind

#include <algorithm>
#include <array>
#include <cctype>
#include <cstddef>
#include <string>
#include <span>
#include <string_view>
#include <vector>

namespace rw
{
inline constexpr std::size_t kForDeclRowsCap     = 8;   // <d> rows in one <decl_rows> (runaway guard; a cut says shown= and next=)
inline constexpr std::size_t kForDeclSubjectTries = 4;  // subject spellings resolved per task

// The task with every closed `code span` blanked: a word quoted as code is a name, not what the task says.
inline std::string forTaskMaskCodeSpans( std::string_view task )
{
    std::string out( task );
    for( std::size_t open = out.find( '`' ); open != std::string::npos; open = out.find( '`', open + 1 ) )
    {
        const std::size_t close = out.find( '`', open + 1 );
        if( close == std::string::npos )
        {
            break;
        }
        std::fill( out.begin() + std::ptrdiff_t( open ), out.begin() + std::ptrdiff_t( close ) + 1, ' ' );
        open = close;
    }
    return out;
}

// The task's masked words, lowercased, in order.
inline std::vector<std::string> forTaskMaskedLowerWords( std::string_view task )
{
    std::vector<std::string> words = forTaskIdentWords( forTaskMaskCodeSpans( task ) );
    for( std::string& w : words )
    {
        w = routeLower( w );
    }
    return words;
}

inline bool forWordIsOneOf( std::string_view w, std::span<const std::string_view> set ) noexcept
{
    return std::ranges::find( set, w ) != set.end();
}

// signature(s) | prototype(s) | (new|extra|additional) [required] (argument|arg|parameter|param)(s)
inline bool forDeclTaskWord( std::string_view task )
{
    static constexpr std::array<std::string_view, 4> kShape{ "signature", "signatures", "prototype", "prototypes" };
    static constexpr std::array<std::string_view, 3> kAdded{ "new", "extra", "additional" };
    static constexpr std::array<std::string_view, 8> kArg{ "argument", "arguments", "arg", "args", "parameter", "parameters", "param", "params" };
    const std::vector<std::string> w = forTaskMaskedLowerWords( task );
    for( std::size_t i = 0; i < w.size(); ++i )
    {
        if( forWordIsOneOf( w[i], kShape ) )
        {
            return true;
        }
        if( !forWordIsOneOf( w[i], kAdded ) || i + 1 >= w.size() )
        {
            continue;
        }
        const std::size_t next = w[ i + 1 ] == "required" ? i + 2 : i + 1;
        if( next < w.size() && forWordIsOneOf( w[next], kArg ) )
        {
            return true;
        }
    }
    return false;
}

inline bool forIsSymbolSpelling( std::string_view s ) noexcept
{
    return !s.empty() && std::ranges::all_of( s, [ ]( char c )
                                              { return std::isalnum( static_cast<unsigned char>( c ) ) != 0 || c == '_' || c == ':' || c == '.' || c == '~' || c == '#'; } );
}

// A prose word that can only be a code name: an underscore, a scope, or a capital after its first letter.
inline bool forIsIdentShaped( std::string_view s ) noexcept
{
    return s.find( '_' ) != std::string_view::npos || s.find( "::" ) != std::string_view::npos
        || std::ranges::any_of( s.substr( s.empty() ? 0 : 1 ), [ ]( char c ) { return std::isupper( static_cast<unsigned char>( c ) ) != 0; } );
}

// `Foo::bar(int)` -> Foo::bar, then bar: the qualified spelling first, then its last segment.
inline void appendForSymbolSpellings( std::vector<std::string>& out, std::string_view token )
{
    token = token.substr( 0, token.find( '(' ) );
    if( !forIsSymbolSpelling( token ) )
    {
        return;
    }
    out.emplace_back( token );
    const std::size_t sep = token.find_last_of( ":.#" );
    if( sep != std::string_view::npos && sep + 1 < token.size() )
    {
        out.emplace_back( token.substr( sep + 1 ) );
    }
}

// The subject spellings of a task-word task, in preference order: code spans first, then identifier-shaped prose words.
inline std::vector<std::string> forDeclSubjects( std::string_view task )
{
    std::vector<std::string> out;
    for( std::size_t open = task.find( '`' ); open != std::string_view::npos; open = task.find( '`', open + 1 ) )
    {
        const std::size_t close = task.find( '`', open + 1 );
        if( close == std::string_view::npos )
        {
            break;
        }
        appendForSymbolSpellings( out, task.substr( open + 1, close - open - 1 ) );
        open = close;
    }
    const std::string masked = forTaskMaskCodeSpans( task );
    std::string_view  rest   = masked;
    static constexpr std::string_view kSpace = " \t\n\r", kEdge = " \t\n\r,;:?!()[]'\"";
    while( !rest.empty() )
    {
        const std::size_t end   = rest.find_first_of( kSpace );
        std::string_view  token = rest.substr( 0, end );
        rest                    = end == std::string_view::npos ? std::string_view{} : rest.substr( end + 1 );
        const std::size_t a     = token.find_first_not_of( kEdge );
        if( a == std::string_view::npos )
        {
            continue;
        }
        token = token.substr( a );
        token = token.substr( 0, token.find( '(' ) );
        while( !token.empty() && ( kEdge.find( token.back() ) != std::string_view::npos || token.back() == '.' ) )
        {
            token.remove_suffix( 1 );
        }
        if( forIsIdentShaped( token ) )
        {
            appendForSymbolSpellings( out, token );
        }
    }
    return out;
}

// The whole task when it is one symbol spelling, trimmed; empty otherwise.
inline std::string_view forBareSymbolTask( std::string_view task ) noexcept
{
    const std::size_t a = task.find_first_not_of( " \t\n\r" );
    if( a == std::string_view::npos )
    {
        return {};
    }
    const std::string_view t = task.substr( a, task.find_last_not_of( " \t\n\r" ) - a + 1 );
    return forIsSymbolSpelling( t ) ? t : std::string_view{};
}

// The row a signature change concerns: a non-test callable in C, C++ or Go. A same-named type or a data row is not it.
inline bool forDeclRowCounts( const IngestResult& ing, const DefRow& r ) noexcept
{
    const Symbol& s = ing.symbols[ r.rep ];
    return !r.test && isCallableKind( s.kind ) && ( s.lang == Lang::C || s.lang == Lang::Cpp || s.lang == Lang::Go );
}

// A prototype the definition group folded in: --defs prints the group's one row ("a prototype with its definition is one"), and the
// row a signature change needs is exactly this one. Test paths stay out, as test rows do.
inline std::vector<NodeId> forDeclFoldedPrototypes( const IngestResult& ing, const DefLookup& L, const DefRow& r )
{
    std::vector<NodeId> out;
    for( std::size_t i = 0; i < L.matches.size(); ++i )
    {
        const NodeId n = L.matches[i];
        if( L.groups.ofMatch[i] == r.group && n != r.rep && !isDefinitionNotDeclaration( ing.symbols[n] ) && !pathDefInTests( ing, n ) )
        {
            out.push_back( n );
        }
    }
    return out;
}

inline bool forDeclHasDeclRow( const IngestResult& ing, const DefLookup& L )
{
    return std::ranges::any_of( L.rows, [ & ]( const DefRow& r )
                                { return forDeclRowCounts( ing, r ) && ( L.groups.bodyless[ r.group ] != 0 || !forDeclFoldedPrototypes( ing, L, r ).empty() ); } );
}

// A folded prototype's row: the defs row's spelling, less what belongs to the group (sel=, in=).
inline std::string forDeclFoldedRowXml( const IngestResult& ing, const MemberOwners& owners, NodeId n )
{
    std::vector<char> esc;
    const Symbol&     s   = ing.symbols[n];
    std::string       out = "<d n=\"" + std::string( escapeXml( qualifiedMemberName( owners, s ), esc ) ) + "\" t=\"" + symTag( s.kind ) + "\"";
    out += " p=\"" + std::string( escapeXml( rootRelPath( ing, s.fileId ), esc ) ) + ":" + std::to_string( s.line ) + "\"";
    return out + std::string( " lang=\"" ) + langTag( s.lang ) + "\" class=\"source\" decl_only=\"1\"/>";
}

inline std::string forDeclRowsXml( const IngestResult& ing, const DefLookup& L, std::string_view spell )
{
    const MemberOwners owners( ing );
    std::string        rows;
    std::size_t        total = 0, shown = 0;
    const auto         counted = [ & ]( const auto& render )
    {
        ++total;
        if( shown < kForDeclRowsCap )
        {
            render();
            ++shown;
        }
    };
    for( const DefRow& r : L.rows )
    {
        if( !forDeclRowCounts( ing, r ) )
        {
            continue;
        }
        counted( [ & ] { defRowXml( rows, ing, L, r, owners, /*compact=*/false ); } );
        for( const NodeId n : forDeclFoldedPrototypes( ing, L, r ) )
        {
            counted( [ & ] { rows += forDeclFoldedRowXml( ing, owners, n ); } );
        }
    }
    std::vector<char> esc;
    std::string       out = "<!-- ripwire for decl_rows: the task is about the signature of of= (matched by name), so every definition and "
                            "declaration of it follows: a change to its signature must reach each row. <d> p=file:line, "
                            "sel= the spelling that picks this row alone (absent on a prototype of the row before it), sel_proven=\"0\": no spelling was proven to, lang=, class=, "
                            "in= graph callers (a floor), decl_only=\"1\": no body, a header prototype or interface contract; rows= counts them, shown= and next= only when the list is cut; "
                            "a call site is not listed here; the answer above is unchanged, and these bytes are not in est_tokens -->";
    out += "<decl_rows of=\"" + std::string( escapeXml( spell, esc ) ) + "\" rows=\"" + std::to_string( total ) + "\"";
    if( shown < total )
    {
        out += " shown=\"" + std::to_string( shown ) + "\"" + nextAttrXml( nextFlag( "--defs=", spell ) );
    }
    return out + ">" + rows + "</decl_rows>";
}

// The <decl_rows> block of this task, or "" (see WHEN above).
inline std::string renderForDeclRows( const IngestResult& ing, const Graph& g, std::string_view task )
{
    const std::string_view   bare = forBareSymbolTask( task );
    std::vector<std::string> subjects;
    if( !bare.empty() )
    {
        appendForSymbolSpellings( subjects, bare );
    }
    else if( forDeclTaskWord( task ) )
    {
        subjects = forDeclSubjects( task );
    }
    for( std::size_t i = 0; i < subjects.size() && i < kForDeclSubjectTries; ++i )
    {
        const DefLookup L = lookupDefs( ing, g, subjects[i] );
        if( forDeclHasDeclRow( ing, L ) && ( bare.empty() || defPickProvablyUnique( L ) ) )
        {
            return forDeclRowsXml( ing, L, subjects[i] );
        }
    }
    return {};
}
}   // namespace rw
