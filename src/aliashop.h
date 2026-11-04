#pragma once
// aliashop.h — XF-ALIAS-HOP: the ONE place a hop that meets an alias name continues to its target (and back).
//
// WHY. `using ColumnPtr = COW<IColumn>::Ptr;` is another name: a reader who asks about ColumnPtr needs what it names (COW::Ptr,
// then `using Ptr = immutable_ptr<Derived>;`, then the class immutable_ptr) and the class it points at (IColumn, the template
// argument); a reader who asks who uses IColumn needs the sites written as ColumnPtr. INDEX-ALIAS-CONST (#520) made the alias a
// definition and recorded where its written target starts (model.h AliasTarget, defslookup.h aliasTargetText); this file walks
// that record. Every verb that wants the walk calls it here (common-code rule; the XF shared-hop layer of cards 17/19/20 is the
// later home of edge records, and this walk is one function it can call).
//
// WHAT. aliasChain(ing, alias): the alias's written target bound to definitions, hop after hop, while the bound definition is
// itself an alias row: bounded depth (kAliasHopDepth), cycle-safe (a definition met twice ends the walk, cycle=1), at most
// kAliasHopCands definitions per spelling (cands= counts them all). Template arguments of the FIRST hop's target that bind a
// type definition are the chain's args (the pointee of a smart-pointer alias). A target spelling that binds nothing in the tree
// (`std::shared_ptr`, a template parameter's member `typename T::Ptr`) is a LEAF: kept as text, never a definition.
// AliasReach: the reverse, built ONCE per answer (hoisting: never per site row) over the alias rows whose written target names
// one of the asked definitions, transitively (an alias of an alias), bounded by the same depth.
//
// LANGUAGE LAYER. The walk reads only the AliasTarget side table, so it serves the languages whose alias defs record a target:
// LangFacts::aliasTargetDefs (C/C++ today). A TS `type X = Y`, a Rust `type X = Y` / `use … as`, a Python `X = Y` module alias
// record no target yet; they join by recording one (aliasdef.h aliasShapeOf arm), with no change here.

#include "defslookup.h"    // aliasTargetText / aliasTargetRow — the written target, as --defs to= prints it
#include "graph.h"         // resolveAllByNameQualified
#include "langfacts.h"     // LangFacts::aliasTargetDefs — the languages whose alias rows record a target
#include "lexical.h"       // lexicalScanText — the reverse walk reads each alias file once
#include "mapinventory.h"  // isInventoryCodeSymbol
#include "model.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t kAliasHopDepth = 4;   // hops past the asked alias (a runaway guard; real chains are 1-3)
inline constexpr std::size_t kAliasHopCands = 3;   // definitions kept per target spelling (cands= counts them all)
static_assert( kAliasHopDepth == 4 && kAliasHopCands == 3, "kAliasHopLegend states both caps: move the sentence with the constants" );

struct AliasHopStep
{
    NodeId        def   = kNoNode;
    std::uint8_t  depth = 0;      // 1 = the asked alias's own target
    bool          arg   = false;  // a template argument of the first hop's target (the pointee), not the head
    std::uint32_t cands = 0;      // definitions the spelling bound (more than kAliasHopCands are counted, not kept)
};

struct AliasHopChain
{
    NodeId                    alias = kNoNode;
    std::vector<AliasHopStep> steps;          // walk order: head hops by depth, then the args
    std::vector<std::string>  leaves;         // target spellings that bind no definition in the tree
    bool                      cycle  = false; // a definition was met twice
    bool                      capped = false; // the walk stopped at kAliasHopDepth with an alias still to follow
};

namespace aliashop_detail
{

inline bool identByte( char c ) noexcept
{
    return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_' || c == '$';
}

// The head name of a written target (template arguments dropped: `COW<IColumn>::Ptr` -> COW::Ptr) and the identifier chains of
// its top-level template arguments (`std::shared_ptr<const Foo>` -> Foo). Leading `typename` / `const` / `::` are not names.
struct TargetSpelling
{
    std::string              head;
    std::vector<std::string> args;
};
inline std::string_view skipWords( std::string_view s )
{
    for( bool again = true; again; )
    {
        again = false;
        while( !s.empty() && s.front() == ' ' )
        {
            s.remove_prefix( 1 );
        }
        for( std::string_view w : { std::string_view( "typename" ), std::string_view( "const" ), std::string_view( "volatile" ), std::string_view( "struct" ),
                                    std::string_view( "class" ), std::string_view( "enum" ) } )
        {
            if( s.starts_with( w ) && ( s.size() == w.size() || !identByte( s[ w.size() ] ) ) )
            {
                s.remove_prefix( w.size() );
                again = true;
            }
        }
        if( s.starts_with( "::" ) )
        {
            s.remove_prefix( 2 );
            again = true;
        }
    }
    return s;
}
inline TargetSpelling parseTarget( std::string_view text )
{
    TargetSpelling out;
    text  = skipWords( text );
    int  depth = 0;
    bool headDone = false;
    std::string arg;
    bool        argOpen = false;   // reading the current depth-1 argument's leading identifier chain
    const auto  closeArg = [ & ]
    {
        while( !arg.empty() && arg.back() == ':' )
        {
            arg.pop_back();
        }
        if( !arg.empty() )
        {
            out.args.push_back( arg );
        }
        arg.clear();
        argOpen = false;
    };
    for( std::size_t i = 0; i < text.size(); ++i )
    {
        const char c = text[ i ];
        if( c == '<' )
        {
            if( depth == 0 )
            {
                argOpen = true;
                const std::string_view rest = skipWords( text.substr( i + 1 ) );
                i                           = text.size() - rest.size() - 1;
            }
            else if( depth == 1 )
            {
                argOpen = false;   // `Outer<Inner<X>>`: the argument's own arguments are not followed
            }
            ++depth;
            continue;
        }
        if( c == '>' )
        {
            if( depth == 1 )
            {
                closeArg();
            }
            depth = depth > 0 ? depth - 1 : 0;
            continue;
        }
        if( depth == 0 )
        {
            if( headDone )
            {
                continue;
            }
            if( identByte( c ) || c == ':' )
            {
                out.head += c;
            }
            else
            {
                headDone = !out.head.empty();
            }
            continue;
        }
        if( depth == 1 )
        {
            if( c == ',' )
            {
                closeArg();
                argOpen                     = true;
                const std::string_view rest = skipWords( text.substr( i + 1 ) );
                i                           = text.size() - rest.size() - 1;
                continue;
            }
            if( argOpen && ( identByte( c ) || c == ':' ) )
            {
                arg += c;
            }
            else if( argOpen && !arg.empty() )
            {
                closeArg();
            }
        }
    }
    while( !out.head.empty() && out.head.back() == ':' )
    {
        out.head.pop_back();
    }
    return out;
}

// Does the written qualifier `q` (`DB`, `COW`, `a::b`) end the scope path of `s` (or name its file-scope owner)? A segment match on
// the scope's tail, never a substring.
inline bool scopeEndsWith( const Symbol& s, std::string_view q )
{
    const std::string_view sc = s.scope;
    if( q.empty() )
    {
        return true;
    }
    if( !sc.ends_with( q ) )
    {
        return false;
    }
    return sc.size() == q.size() || ( sc.size() > q.size() + 1 && sc.substr( sc.size() - q.size() - 2, 2 ) == "::" );
}

// A C/C++ translation-unit source (not a header): what it defines is visible only inside it (an `#include "x.cpp"` is the rare
// exception, so the bind below drops such a definition only when another one remains; cands= counts what is left).
inline bool cxxSourceFile( std::string_view path ) noexcept
{
    const std::size_t dot = path.rfind( '.' );
    if( dot == std::string_view::npos || path.find( '/', dot ) != std::string_view::npos )
    {
        return false;
    }
    const std::string_view ext = path.substr( dot );
    for( std::string_view e : { ".c", ".cc", ".cpp", ".cxx", ".c++", ".cu", ".m", ".mm", ".C" } )
    {
        if( ext == e )
        {
            return true;
        }
    }
    return false;
}

// Is `seg` one whole `::` segment of the scope path `sc`?
inline bool scopeHasSegment( std::string_view sc, std::string_view seg )
{
    for( std::size_t from = 0; from <= sc.size(); )
    {
        const std::size_t cut = std::min( sc.find( "::", from ), sc.size() );
        if( sc.substr( from, cut - from ) == seg )
        {
            return true;
        }
        from = cut + 2;
    }
    return false;
}

// The definitions a written spelling binds: the leaf's code definitions whose scope ends with the written qualifier (an owner
// class or a namespace), bodied before bodyless (a forward declaration `class X;` only when nothing else binds), the alias's own
// file first, then id order. `types`: only type definitions (a template argument). `std::` / an empty or numeric head: none.
// The namespace verdict per qualifier segment, read once per answer (the scan is over every symbol's scope).
struct BindCache
{
    HashMap<std::string, char> isNamespace;
};
inline std::vector<NodeId> bindSpelling( const IngestResult& ing, std::string_view spelling, std::uint32_t fromFile, bool types, BindCache& cache )
{
    std::vector<NodeId> out;
    if( spelling.empty() || spelling.starts_with( "std::" ) || spelling == "std" || ( spelling[ 0 ] >= '0' && spelling[ 0 ] <= '9' ) )
    {
        return out;
    }
    const std::size_t      cut  = spelling.rfind( "::" );
    const std::string_view leaf = cut == std::string_view::npos ? spelling : spelling.substr( cut + 2 );
    const std::string_view q    = cut == std::string_view::npos ? std::string_view{} : spelling.substr( 0, cut );
    std::vector<NodeId>    leafOnly;   // the leaf's definitions whose scope does not end with q
    for( const NodeId n : resolveAllByNameQualified( ing, leaf ) )
    {
        const Symbol& s = ing.symbols[ n ];
        if( s.name != leaf || !isInventoryCodeSymbol( s ) || !langFacts( s.lang ).aliasTargetDefs )
        {
            continue;
        }
        if( types && !( s.kind == SymKind::Class || s.kind == SymKind::Interface || isStructOrNamedType( s.kind ) ) )
        {
            continue;
        }
        if( s.kind == SymKind::Method || s.kind == SymKind::Function || s.kind == SymKind::Var || s.kind == SymKind::Field || s.kind == SymKind::Macro )
        {
            continue;   // a type position names a type, a namespace alias a namespace: never a callable or a value
        }
        if( scopeEndsWith( s, q ) )
        {
            out.push_back( n );
        }
        else
        {
            leafOnly.push_back( n );
        }
    }
    // a NAMESPACE qualifier: a C++ type's scope is its own name (no namespace path), so `DB::IColumn` cannot be checked on the
    // scope. The qualifier's last segment is a namespace when it names no type definition and some definition's scope has it as a
    // segment (`DB` on a function's sc=); then the leaf's definitions bind. A template parameter's member (`typename T::Ptr`) has
    // neither, so it stays a leaf.
    if( out.empty() && !leafOnly.empty() && !q.empty() )
    {
        const std::size_t      qc    = q.rfind( "::" );
        const std::string_view qLast = qc == std::string_view::npos ? q : q.substr( qc + 2 );
        const bool             isType = std::ranges::any_of( resolveAllByNameQualified( ing, qLast ), [ & ]( NodeId n )
                                                             {
                                                                 const Symbol& t = ing.symbols[ n ];
                                                                 return t.name == qLast && ( t.kind == SymKind::Class || t.kind == SymKind::Interface || isStructOrNamedType( t.kind ) );
                                                             } );
        bool isNamespace = false;
        if( !isType )
        {
            const auto [ at, fresh ] = cache.isNamespace.try_emplace( std::string( qLast ), '\0' );
            if( fresh )
            {
                at->second = std::ranges::any_of( ing.symbols, [ & ]( const Symbol& t ) { return scopeHasSegment( t.scope, qLast ); } ) ? '\1' : '\0';
            }
            isNamespace = at->second != '\0';
        }
        if( isNamespace )
        {
            out = std::move( leafOnly );
        }
    }
    // a definition inside another translation unit's source file cannot be what this alias names (`class IColumn` in an example
    // .cpp beside the real one in a header): dropped while another definition remains
    const auto visible = [ & ]( NodeId n ) { const Symbol& s = ing.symbols[ n ]; return s.fileId == fromFile || !cxxSourceFile( ing.files[ s.fileId ] ); };
    if( std::ranges::any_of( out, visible ) )
    {
        std::erase_if( out, [ & ]( NodeId n ) { return !visible( n ); } );
    }
    const auto bodied = [ & ]( NodeId n ) { const Symbol& s = ing.symbols[ n ]; return s.endByte > s.sigEndByte || aliasTargetRow( ing, s ); };
    if( std::ranges::any_of( out, bodied ) )
    {
        std::erase_if( out, [ & ]( NodeId n ) { return !bodied( n ); } );
    }
    std::ranges::stable_sort( out, [ & ]( NodeId a, NodeId b )
                              {
                                  const bool fa = ing.symbols[ a ].fileId == fromFile, fb = ing.symbols[ b ].fileId == fromFile;
                                  return fa != fb ? fa : a < b;
                              } );
    return out;
}

}   // namespace aliashop_detail

// The alias chain of `alias` (empty steps and leaves when `alias` records no written target).
inline AliasHopChain aliasChain( const IngestResult& ing, NodeId alias, aliashop_detail::BindCache& cache )
{
    using namespace aliashop_detail;
    AliasHopChain c{ .alias = alias };
    if( alias >= ing.symbols.size() || !aliasTargetRow( ing, ing.symbols[ alias ] ) )
    {
        return c;
    }
    std::vector<NodeId> seen{ alias };
    std::vector<NodeId> frontier{ alias };
    std::vector<std::string> firstArgs;
    for( std::size_t depth = 1; !frontier.empty(); ++depth )
    {
        if( depth > kAliasHopDepth )
        {
            c.capped = true;
            break;
        }
        std::vector<NodeId> next;
        for( const NodeId from : frontier )
        {
            const AliasTargetText t = aliasTargetText( ing, ing.symbols[ from ] );
            if( t.unread )
            {
                continue;
            }
            TargetSpelling sp = parseTarget( t.text );
            if( depth == 1 )
            {
                firstArgs = std::move( sp.args );
            }
            std::vector<NodeId> bound = bindSpelling( ing, sp.head, ing.symbols[ from ].fileId, /*types=*/false, cache );
            if( bound.empty() )
            {
                if( !sp.head.empty() )
                {
                    c.leaves.push_back( sp.head );
                }
                continue;
            }
            const std::uint32_t cands = std::uint32_t( bound.size() );
            bound.resize( std::min( bound.size(), kAliasHopCands ) );
            for( const NodeId n : bound )
            {
                if( std::ranges::find( seen, n ) != seen.end() )
                {
                    c.cycle = true;
                    continue;
                }
                seen.push_back( n );
                c.steps.push_back( { n, std::uint8_t( depth ), false, cands } );
                if( aliasTargetRow( ing, ing.symbols[ n ] ) )
                {
                    next.push_back( n );
                }
            }
        }
        frontier = std::move( next );
    }
    for( const std::string& a : firstArgs )
    {
        std::vector<NodeId> bound = bindSpelling( ing, a, ing.symbols[ alias ].fileId, /*types=*/true, cache );
        if( bound.empty() )
        {
            c.leaves.push_back( a );
            continue;
        }
        const std::uint32_t cands = std::uint32_t( bound.size() );
        bound.resize( std::min( bound.size(), kAliasHopCands ) );
        for( const NodeId n : bound )
        {
            if( std::ranges::find( seen, n ) == seen.end() )
            {
                seen.push_back( n );
                c.steps.push_back( { n, 1, true, cands } );
            }
        }
    }
    return c;
}

// The reverse walk: which alias rows reach the definitions `targets` (as head or template argument), transitively. Built once
// per answer; `names()` / `via()` read it. A pre-filter on the target NAME bytes keeps the walk off the alias rows that cannot
// name a target (most of them), so the cost is one text read per candidate alias row, not one chain per alias row.
struct AliasReach
{
    struct Row
    {
        NodeId alias  = kNoNode;
        NodeId target = kNoNode;   // the asked definition it reaches
    };
    std::vector<Row> rows;         // alias id order (one row per alias; the first asked target its chain reaches)
    bool             capped = false;
    std::size_t      unread = 0;   // alias rows whose file could not be read (their reach is unknown)

    AliasReach( const IngestResult& ing, const std::vector<NodeId>& targets )
    {
        if( targets.empty() || ing.aliasTargets.empty() )
        {
            return;
        }
        // what an alias row may name: the asked definitions, then each alias found (an alias of an alias); keyed by name, so a row's
        // identifier tokens are tested by hash, never by a substring search per name
        HashMap<std::string_view, std::vector<NodeId>> want;
        std::vector<NodeId> standsFor( ing.symbols.size(), kNoNode );   // an asked definition (itself) or an alias reached: what it stands for
        for( const NodeId t : targets )
        {
            want[ ing.symbols[ t ].name ].push_back( t );
            standsFor[ t ] = t;
        }
        aliashop_detail::BindCache cache;
        // every alias row's written target, folded ONCE (one read per file; the rounds below re-test them in memory, never re-read)
        std::vector<std::string> folded( ing.aliasTargets.size() );
        {
            std::uint32_t      textOf = kNoFile;   // the alias rows ascend by id, so by file
            std::string        scratch;
            const std::string* text = nullptr;
            for( std::size_t k = 0; k < ing.aliasTargets.size(); ++k )
            {
                const AliasTarget& a = ing.aliasTargets[ k ];
                if( a.id >= ing.symbols.size() || standsFor[ a.id ] != kNoNode || !aliasTargetRow( ing, ing.symbols[ a.id ] ) )
                {
                    continue;
                }
                const Symbol& s = ing.symbols[ a.id ];
                if( textOf != s.fileId )
                {
                    text   = lexicalScanText( ing, s.fileId, scratch );
                    textOf = s.fileId;
                }
                if( text == nullptr || s.endByte > text->size() )
                {
                    ++unread;   // could not read is never "reaches none": counted, the verb discloses it
                    continue;
                }
                folded[ k ] = foldAliasTarget( std::string_view( *text ).substr( a.start, s.endByte - a.start ) );
            }
        }
        for( std::size_t round = 0; round < kAliasHopDepth; ++round )
        {
            bool grew = false;
            for( std::size_t k = 0; k < ing.aliasTargets.size(); ++k )
            {
                const AliasTarget& a = ing.aliasTargets[ k ];
                if( folded[ k ].empty() || standsFor[ a.id ] != kNoNode )
                {
                    continue;
                }
                const Symbol& s = ing.symbols[ a.id ];
                // the cheap test first: no identifier of the target names a wanted definition (most rows): no parse, no resolve
                const std::string_view raw   = folded[ k ];
                bool                   named = false;
                for( std::size_t i = 0; i < raw.size() && !named; )
                {
                    if( !aliashop_detail::identByte( raw[ i ] ) )
                    {
                        ++i;
                        continue;
                    }
                    std::size_t e = i;
                    while( e < raw.size() && aliashop_detail::identByte( raw[ e ] ) )
                    {
                        ++e;
                    }
                    named = want.find( raw.substr( i, e - i ) ) != want.end();
                    i     = e;
                }
                if( !named )
                {
                    continue;
                }
                const aliashop_detail::TargetSpelling sp      = aliashop_detail::parseTarget( raw );
                NodeId                                reached = kNoNode;
                const auto probe = [ & ]( std::string_view spelling, bool types )
                {
                    for( const NodeId n : aliashop_detail::bindSpelling( ing, spelling, s.fileId, types, cache ) )
                    {
                        const auto w = want.find( ing.symbols[ n ].name );
                        if( w != want.end() && std::ranges::find( w->second, n ) != w->second.end() )
                        {
                            reached = n;
                            return;
                        }
                    }
                };
                probe( sp.head, false );
                for( std::size_t k = 0; reached == kNoNode && k < sp.args.size(); ++k )
                {
                    probe( sp.args[ k ], true );
                }
                if( reached == kNoNode )
                {
                    continue;
                }
                standsFor[ a.id ] = standsFor[ reached ];   // an alias of an alias stands for the asked definition its target stands for
                rows.push_back( { a.id, standsFor[ a.id ] } );
                want[ s.name ].push_back( a.id );
                grew = true;
            }
            if( !grew )
            {
                break;
            }
            capped = round + 1 == kAliasHopDepth;
        }
        std::ranges::sort( rows, []( const Row& a, const Row& b ) { return a.alias < b.alias; } );
    }
    bool empty() const noexcept { return rows.empty(); }
};

// The uses verb's disclosure of the sites written through an alias (present-only: "" / no attribute when none).
inline std::string aliasUsesLegend( bool on )
{
    return on ? "via=\"alias\" alias=A: the site is written as the alias A, whose written target reaches SYM (as the head or a template "
                "argument, up to 4 alias hops), never a call edge; these rows follow the direct ones and count in count=; via_alias=N such "
                "rows; alias_namesakes=K: K definitions share a listed alias's name and reach none of SYM (their sites are name-matched in "
                "too, a hedge); alias_sites_held=N: the columnar form keeps those N sites out of its rows; alias_unread=N: N alias "
                "declarations could not be read, so their reach is unknown (a floor). These rows are the aliased spellings the role=\"type\" "
                "sentence above leaves out. "
              : "";
}
inline std::string aliasUsesAttrXml( std::size_t viaAlias, std::size_t namesakes, std::size_t unread, bool held )
{
    std::string out;
    if( viaAlias > 0 )
    {
        out.append( held ? " alias_sites_held=\"" : " via_alias=\"" ).append( std::to_string( viaAlias ) ).append( "\"" );
    }
    if( viaAlias > 0 && namesakes > 0 )
    {
        out.append( " alias_namesakes=\"" ).append( std::to_string( namesakes ) ).append( "\"" );
    }
    if( unread > 0 )
    {
        out.append( " alias_unread=\"" ).append( std::to_string( unread ) ).append( "\"" );
    }
    return out;
}

// The alias rows a definition list holds, in list order (the answer's own order): what the for verb's alias block walks.
inline std::vector<NodeId> aliasRowsAmong( const IngestResult& ing, const std::vector<NodeId>& ids )
{
    std::vector<NodeId> out;
    for( const NodeId n : ids )
    {
        if( n < ing.symbols.size() && aliasTargetRow( ing, ing.symbols[ n ] ) && std::ranges::find( out, n ) == out.end() )
        {
            out.push_back( n );
        }
    }
    return out;
}

}   // namespace rw
