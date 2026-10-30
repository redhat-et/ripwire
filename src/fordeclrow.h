#pragma once
// fordeclrow.h — DECL-ROW: a --for task about ONE C/C++/Go function's signature carries that function's declaration rows, the
// rows --defs computes (a header prototype, a forward declaration, an interface contract), so the agent changing the signature
// sees every place that must change in step. (CLI src/verbs_for.h appendForTaskRowBlocks, MCP `for` src/mcpverbs.h forTaskText —
// one renderer.)
//
// WHY. mf1-tmux-03 asks which prototypes change when server_start takes a new argument: --for prints the definition in
// server.c and never the tmux.h prototype, while --defs prints both.
//
// WHEN (present-only). Either arm, and the subject must have a non-test declaration row that is a function or method in C, C++ or Go:
//   - TASK WORD: outside code spans the task says signature / prototype / new|extra|additional [required] argument|parameter;
//     the subject is the first code span or identifier-shaped word that resolves to such a row.
//   - BARE SUBJECT: the whole task is one symbol spelling (`--for=server_start`), and that WHOLE spelling resolves to a function
//     whose pick is provably unique. A symbol alone has no task word to read; a name that binds several definitions stays silent
//     here, and a qualifier that does not resolve (`api.c`, `Nope::f`) is no function: it never falls to its last segment.
//   - A name with a macro definition is not a function here (`PyAPI_FUNC(int) f(int)` names f, not the macro).
//   - A token budget holds the block: <decl_rows held="budget" next=...> names the call, as the sibling graph_verb block does.
// The block reads what the index holds: no new analysis, and the ordinary answer before it is unchanged. A name that has no
// declaration prints nothing: a definition row alone would repeat the answer. --defs folds a tied prototype into its definition's
// row; this block unfolds it, because that prototype is the row asked for.
#include "defslookup.h"    // lookupDefs / defRowXml / defPickProvablyUnique — the --defs lookup
#include "forcallerhop.h"  // forTaskIdentWords — the one word split of a --for task
#include "nextverb.h"      // nextFlag / nextAttrXml
#include "resolve.h"       // trimWs
#include "serialize.h"     // escapeXml

#include <algorithm>
#include <array>
#include <cctype>
#include <cstddef>
#include <string>
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

// signature(s) | prototype(s) | (new|extra|additional) [required] (argument|arg|parameter|param)(s)
inline bool forDeclTaskWord( std::string_view task )
{
    static constexpr std::array<std::string_view, 4> kShape{ "signature", "signatures", "prototype", "prototypes" };
    static constexpr std::array<std::string_view, 3> kAdded{ "new", "extra", "additional" };
    static constexpr std::array<std::string_view, 8> kArg{ "argument", "arguments", "arg", "args", "parameter", "parameters", "param", "params" };
    const std::vector<std::string> w = forTaskMaskedLowerWords( task );
    for( std::size_t i = 0; i < w.size(); ++i )
    {
        if( std::ranges::contains( kShape, w[i] ) )
        {
            return true;
        }
        if( !std::ranges::contains( kAdded, w[i] ) || i + 1 >= w.size() )
        {
            continue;
        }
        const std::size_t next = w[ i + 1 ] == "required" ? i + 2 : i + 1;
        if( next < w.size() && std::ranges::contains( kArg, w[next] ) )
        {
            return true;
        }
    }
    return false;
}

inline bool forIsSymbolChar( char c ) noexcept
{
    return std::isalnum( static_cast<unsigned char>( c ) ) != 0 || c == '_' || c == ':' || c == '.' || c == '~' || c == '#';
}

inline bool forIsSymbolSpelling( std::string_view s ) noexcept
{
    for( const char c : s )
    {
        if( !forIsSymbolChar( c ) )
        {
            return false;
        }
    }
    return !s.empty();
}

// A prose word that can only be a code name: an underscore, a scope, or a capital after its first letter.
inline bool forIsIdentShaped( std::string_view s ) noexcept
{
    return s.find( '_' ) != std::string_view::npos || s.find( "::" ) != std::string_view::npos
        || std::ranges::any_of( s.substr( s.empty() ? 0 : 1 ), [ ]( char c ) { return std::isupper( static_cast<unsigned char>( c ) ) != 0; } );
}

// The callee a code span names: the identifier just before its LAST top-level `(`, so a macro wrapper or a return type is not it
// (`PyAPI_FUNC(int) PyObject_Print(PyObject *, FILE *, int)` -> PyObject_Print, `int server_start(struct tmuxproc *)` ->
// server_start). A span with no top-level `(` is returned whole.
inline std::string_view forSpanCallee( std::string_view span ) noexcept
{
    span = trimWs( span );
    std::size_t last = std::string_view::npos;
    int         depth = 0;
    for( std::size_t i = 0; i < span.size(); ++i )
    {
        if( span[i] == '(' )
        {
            last = depth == 0 ? i : last;
            ++depth;
        }
        else if( span[i] == ')' && depth > 0 )
        {
            --depth;
        }
    }
    if( last == std::string_view::npos )
    {
        return span;
    }
    std::string_view head = trimWs( span.substr( 0, last ) );
    std::size_t      b    = head.size();
    while( b > 0 && forIsSymbolChar( head[ b - 1 ] ) )
    {
        --b;
    }
    head = head.substr( b );
    while( !head.empty() && ( head.front() == ':' || head.front() == '.' ) )
    {
        head.remove_prefix( 1 );
    }
    return head;
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
        appendForSymbolSpellings( out, forSpanCallee( task.substr( open + 1, close - open - 1 ) ) );
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
    const std::string_view t = trimWs( task );
    return forIsSymbolSpelling( t ) ? t : std::string_view{};
}

// The row a signature change concerns: a non-test function or method in C, C++ or Go. A forward-declared class is callable by
// name but has no signature of its own; a type, a macro or a data row is not it.
inline bool forDeclRowCounts( const IngestResult& ing, const DefRow& r ) noexcept
{
    const Symbol& s = ing.symbols[ r.rep ];
    return !r.test && ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && ( s.lang == Lang::C || s.lang == Lang::Cpp || s.lang == Lang::Go );
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

// A function the task could mean is a function row, never a macro: `PyAPI_FUNC(int) f(int);` is filed under the macro's name too, and
// the macro's own prototype rows are not a prototype of anything the task asks about.
inline bool forDeclNameIsMacro( const IngestResult& ing, const DefLookup& L ) noexcept
{
    return std::ranges::any_of( L.matches, [ & ]( NodeId n ) { return ing.symbols[n].kind == SymKind::Macro; } );
}

// A row the block keeps that is its own function: a function or method row, not an untied prototype (a definition with its
// declarations is one function; an untied prototype is none until the index ties it).
inline bool forDeclOwnFunction( const IngestResult& ing, const DefLookup& L, const DefRow& r ) noexcept
{
    return forDeclRowCounts( ing, r ) && L.groups.untied[ r.group ] == 0;
}

// One counted row: the defs row's spelling; an empty sel= (past lookupDefs's proof window) takes the unproven spelling it falls back
// to, and a prototype the index cannot tie to a definition says so.
inline std::string forDeclRowXml( const IngestResult& ing, const DefLookup& L, const DefRow& r, const MemberOwners& owners )
{
    DefRow row = r;
    if( row.sel.empty() )
    {
        const Symbol& s = ing.symbols[ r.rep ];
        row.sel         = std::string( rootRelPath( ing, s.fileId ) ) + ":" + std::string( qualifiedMemberName( owners, s ) );
    }
    std::string one;
    defRowXml( one, ing, L, row, owners, /*compact=*/false );
    if( L.groups.untied[ r.group ] != 0 )
    {
        one.insert( one.size() - 2, " untied=\"1\"" );
    }
    return one;
}

inline constexpr std::string_view kForDeclLegend =
    "<!-- ripwire for decl_rows: of= (matched by name) may change its signature; its non-test definition and declaration rows in the index follow, "
    "so a change reaches them in step. <d> n= name, t= kind, p=file:line, sel= the spelling that picks this row alone (absent on a decl_only row "
    "that follows the definition it declares; a decl_only row with sel= declares none of them), sel_proven=\"0\": no spelling was proven to, lang=, "
    "class=, in= graph callers (a floor), decl_only=\"1\": no body (a header prototype, forward declaration or interface contract), untied=\"1\": "
    "its link to a definition is unproven (it may be another function). rows= counts them; functions=N only when of= names N separate functions (a static "
    "elsewhere, an overload, another scope): a change reaches its own definition row and the decl_only rows right after it, not another "
    "function's; shown=, capped=\"1\" and next= only when the list is cut (next= lists definitions, prototypes folded in). Call sites, and the implementations "
    "of a contract (lego), are not listed; the answer above is unchanged, and these bytes are not in est_tokens -->";

// A token budget is a request the block must obey: the rows are not printed, the tag names the call that prints them.
inline std::string forDeclHeldXml( std::string_view spell, const std::string& next )
{
    std::vector<char> esc;
    return "<!-- ripwire for decl_rows: held=\"budget\": a token budget is set, so the declaration rows of of= are not printed here; "
           "next= is the call that lists them; the answer above is unchanged -->"
           "<decl_rows of=\"" + std::string( escapeXml( spell, esc ) ) + "\" held=\"budget\"" + next + "/>";
}

inline std::string forDeclRowsXml( const IngestResult& ing, const DefLookup& L, std::string_view spell, bool held )
{
    const std::string next = nextAttrXml( nextFlag( "--defs=", spell ) );
    if( held )
    {
        return forDeclHeldXml( spell, next );
    }
    const MemberOwners owners( ing );
    std::string        rows;
    std::size_t        total = 0, shown = 0;
    const auto         counted = [ & ]( const auto& render )
    {
        ++total;
        if( shown < kForDeclRowsCap )
        {
            rows += render();
            ++shown;
        }
    };
    std::size_t functions = 0;
    for( const DefRow& r : L.rows )
    {
        if( !forDeclRowCounts( ing, r ) )
        {
            continue;
        }
        functions += forDeclOwnFunction( ing, L, r ) ? 1 : 0;
        counted( [ & ] { return forDeclRowXml( ing, L, r, owners ); } );
        for( const NodeId n : forDeclFoldedPrototypes( ing, L, r ) )
        {
            counted( [ & ] { return forDeclFoldedRowXml( ing, owners, n ); } );
        }
    }
    std::vector<char> esc;
    std::string       out( kForDeclLegend );
    out += "<decl_rows of=\"" + std::string( escapeXml( spell, esc ) ) + "\" rows=\"" + std::to_string( total ) + "\"";
    if( functions > 1 )
    {
        out += " functions=\"" + std::to_string( functions ) + "\"";
    }
    if( shown < total )
    {
        out += " shown=\"" + std::to_string( shown ) + "\" capped=\"1\"" + next;
    }
    return out + ">" + rows + "</decl_rows>";
}

// The <decl_rows> block of this task, or "" (see WHEN above). `held`: a token budget is set; the block that would have fired is named, not printed.
inline std::string renderForDeclRows( const IngestResult& ing, const Graph& g, std::string_view task, bool held = false )
{
    const std::string_view   bare = forBareSymbolTask( task );
    std::vector<std::string> subjects;
    if( !bare.empty() )
    {
        subjects.emplace_back( bare );   // the whole spelling only: `api.c` is a file, `Nope::f` names no function, neither is its last segment
    }
    else if( forDeclTaskWord( task ) )
    {
        subjects = forDeclSubjects( task );
    }
    for( std::size_t i = 0; i < subjects.size() && i < kForDeclSubjectTries; ++i )
    {
        const DefLookup L = lookupDefs( ing, g, subjects[i] );
        if( forDeclNameIsMacro( ing, L ) || std::ranges::none_of( L.rows, [ & ]( const DefRow& r ) { return forDeclRowCounts( ing, r ); } ) )
        {
            continue;   // not a function here (a macro, a qualifier, a word): the next spelling
        }
        const bool fires = forDeclHasDeclRow( ing, L ) && ( bare.empty() || defPickProvablyUnique( L ) );
        return fires ? forDeclRowsXml( ing, L, subjects[i], held ) : std::string();   // the first function named is the subject: a later name is not it
    }
    return {};
}
}   // namespace rw
