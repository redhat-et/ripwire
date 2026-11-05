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

#include "cppscopechain.h" // EditCheckBraceLexer — the namespaces and classes around a declaration (C++ records no namespace body)
#include "defslookup.h"    // aliasTargetText / aliasTargetRow — the written target, as --defs to= prints it
#include "graph.h"         // resolveAllByNameQualified
#include "infra/hashutil.h" // packPair — the (file, byte) chain key
#include "infra/namesplit.h" // isIdentChar / anyField — the shared identifier byte class and field splitter
#include "langfacts.h"     // LangFacts::aliasTargetDefs — the languages whose alias rows record a target
#include "lexical.h"       // lexicalScanText — the reverse walk reads each alias file once
#include "mapinventory.h"  // isInventoryCodeSymbol
#include "model.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t kAliasHopDepth = 4;   // hops past the asked alias (a runaway guard; real chains are 1-3)
inline constexpr std::size_t kAliasHopCands = 3;   // definitions kept per target spelling (cands= counts them all)
static_assert( kAliasHopDepth == 4 && kAliasHopCands == 3, "aliasHopLegend states both caps: move the sentence with the constants" );

struct AliasHopStep
{
    NodeId        def   = kNoNode;
    std::uint8_t  depth = 0;      // 1 = the asked alias's own target
    bool          arg   = false;  // a template argument of the first hop's target (the pointee), not the head
    std::uint32_t cands = 0;      // definitions the spelling bound (more than kAliasHopCands are counted, not kept)
    bool          hedged = false; // the spelling's qualifier or lookup could not be proven on the definition (bound="name")
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

// an identifier byte of a written C++ target: the shared ASCII class plus `$` (a GNU identifier byte)
inline bool identByte( char c ) noexcept
{
    return namesplit::isIdentChar( c ) || c == '$';
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

// The per-answer caches the binds share: each file's lexical scope chains (cppscopechain.h's brace lexer; C++ records no namespace
// body in the index: CallResultFamily::Cpp is off), keyed by (file, byte), and the namespace verdict per qualifier segment.
struct BindCache
{
    HashMap<std::string, char>                       isNamespace;
    HashMap<std::uint64_t, std::vector<std::string>> chains;   // hashutil::packPair( file, byte ) -> the namespaces and classes around it
    HashMap<std::uint64_t, char>                     unknown;  // the keys whose file could not be read or did not balance
};

// The lexical chains at the declaration starts of `ids`, read ONE pass per file (hoisting: a --uses answer's thousands of sites
// share their files' passes). An unreadable file, or one whose braces do not balance (`#if … {` `#else … {`), records an empty
// chain: the scope alone then speaks for the symbol. A file whose braces balance keeps its chain even beside a scope-like macro
// (`REGISTER_FUNCTION( X )` alone on its line, all over ClickHouse): an unseen macro-opened namespace only shortens the chain,
// which leaves a proof unproven (hedged), never invents one.
inline void primeChains( const IngestResult& ing, std::vector<std::pair<std::uint32_t, std::uint32_t>> want, BindCache& cache )
{
    std::erase_if( want, [ & ]( const auto& fa ) { return cache.chains.find( hashutil::packPair( fa.first, fa.second ) ) != cache.chains.end(); } );
    std::ranges::sort( want );
    want.erase( std::unique( want.begin(), want.end() ), want.end() );
    std::string scratch;
    for( std::size_t from = 0; from < want.size(); )
    {
        std::size_t to = from;
        while( to < want.size() && want[ to ].first == want[ from ].first )
        {
            ++to;
        }
        std::vector<std::size_t> offsets;
        for( std::size_t k = from; k < to; ++k )
        {
            offsets.push_back( want[ k ].second );
        }
        std::vector<std::optional<std::vector<std::string>>> got( offsets.size() );
        if( const std::string* text = lexicalScanText( ing, want[ from ].first, scratch ); text != nullptr )
        {
            std::string blanked = *text;
            editCheckBlankComments( blanked );
            got = EditCheckBraceLexer( blanked ).chainsAt( offsets, /*allowScopeMacro=*/true );
        }
        for( std::size_t k = from; k < to; ++k )
        {
            const std::uint64_t key = hashutil::packPair( want[ k ].first, want[ k ].second );
            if( !got[ k - from ] )
            {
                cache.unknown.try_emplace( key, '\1' );
            }
            cache.chains.try_emplace( key, got[ k - from ].value_or( std::vector<std::string>{} ) );
        }
        from = to;
    }
}

// The LEXICAL path that encloses `s` (S1: a C++ class's scope is its own name, so its namespace is read off the file's braces,
// never guessed from another symbol's scope): the namespaces and classes around its declaration, outermost first, then the owner
// its scope names (`IColumn` for an out-of-line `void IColumn::insert`; a type's own name, the last segment of its scope, is not
// an owner), the segments the two spell alike merged once (a function's scope `B` inside `namespace B`).
// Returns false when the file's chain is unknown (unreadable, or braces a macro may open): `out` is then the scope's word alone.
inline bool enclosingPath( const IngestResult& ing, const Symbol& s, BindCache& cache, std::vector<std::string>& out )
{
    auto at = cache.chains.find( hashutil::packPair( s.fileId, s.sigStartByte ) );
    if( at == cache.chains.end() )
    {
        primeChains( ing, { { s.fileId, s.sigStartByte } }, cache );
        at = cache.chains.find( hashutil::packPair( s.fileId, s.sigStartByte ) );
    }
    out = at->second;
    std::vector<std::string_view> owner;
    namesplit::appendFields( s.scope, "::", owner );   // `a::b::c` -> a, b, c ("" adds nothing)
    const bool callable = s.kind == SymKind::Method || s.kind == SymKind::Function;
    if( !callable && !owner.empty() && owner.back() == s.name )
    {
        owner.pop_back();
    }
    std::size_t overlap = std::min( out.size(), owner.size() );
    for( ; overlap > 0; --overlap )
    {
        if( std::equal( owner.begin(), owner.begin() + std::ptrdiff_t( overlap ), out.end() - std::ptrdiff_t( overlap ) ) )
        {
            break;
        }
    }
    out.insert( out.end(), owner.begin() + std::ptrdiff_t( overlap ), owner.end() );
    return cache.unknown.find( hashutil::packPair( s.fileId, s.sigStartByte ) ) == cache.unknown.end();
}

template <class A, class B>
inline bool pathEndsWith( const std::vector<A>& path, const std::vector<B>& tail )
{
    return tail.size() <= path.size() && std::equal( tail.rbegin(), tail.rend(), path.rbegin(), []( const auto& x, const auto& y ) { return std::string_view( x ) == std::string_view( y ); } );
}
template <class A, class B>
inline bool pathStartsWith( const std::vector<A>& path, const std::vector<B>& head )
{
    return head.size() <= path.size() && std::equal( head.begin(), head.end(), path.begin(), []( const auto& x, const auto& y ) { return std::string_view( x ) == std::string_view( y ); } );
}

// What a written spelling binds. `ids`: the leaf's code definitions the spelling can name, bodied before bodyless (a forward
// declaration `class X;` only when nothing else binds), the alias's own file first, then id order. `hedged`: the qualifier could
// not be PROVEN on any of them (bound="name": a namesake may be meant, never a plain leaf that says "binds nothing", S1).
struct BoundSpelling
{
    std::vector<NodeId> ids;
    bool                hedged = false;
};

// A QUALIFIED spelling (`N2::Widget`, `COW::Ptr`) binds the definitions whose enclosing path ends with the qualifier, segment by
// segment; when none does and the qualifier's last segment is a namespace somewhere (a namespace the index has no body for, a
// macro-opened one), the leaf's definitions bind HEDGED. An UNQUALIFIED spelling binds what C++ lookup finds from the alias's own
// place: the definitions whose enclosing path is a prefix of the alias's, the innermost first (`N1::WP = Widget` is N1::Widget);
// none such (a using-directive, a base class's member) binds them all, hedged. `types`: only type definitions (a template
// argument). `std::` / an empty or numeric head: none.
inline BoundSpelling bindSpelling( const IngestResult& ing, std::string_view spelling, const Symbol& from, bool types, BindCache& cache )
{
    BoundSpelling out;
    if( spelling.empty() || spelling.starts_with( "std::" ) || spelling == "std" || ( spelling[ 0 ] >= '0' && spelling[ 0 ] <= '9' ) )
    {
        return out;
    }
    const std::size_t      cut  = spelling.rfind( "::" );
    const std::string_view leaf = cut == std::string_view::npos ? spelling : spelling.substr( cut + 2 );
    const std::string_view q    = cut == std::string_view::npos ? std::string_view{} : spelling.substr( 0, cut );
    std::vector<NodeId>    cands;
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
        cands.push_back( n );
    }
    if( cands.empty() )
    {
        return out;
    }
    {   // the candidates' chains (and the alias's own) in one pass per file
        std::vector<std::pair<std::uint32_t, std::uint32_t>> at{ { from.fileId, from.sigStartByte } };
        for( const NodeId n : cands )
        {
            at.emplace_back( ing.symbols[ n ].fileId, ing.symbols[ n ].sigStartByte );
        }
        primeChains( ing, std::move( at ), cache );
    }
    std::vector<std::string> path;
    if( !q.empty() )
    {
        std::vector<std::string_view> written;
        namesplit::appendFields( q, "::", written );
        for( const NodeId n : cands )
        {
            enclosingPath( ing, ing.symbols[ n ], cache, path );
            if( pathEndsWith( path, written ) )
            {
                out.ids.push_back( n );
            }
        }
        if( out.ids.empty() )
        {
            // not proven on any definition: a qualifier that is a namespace somewhere binds the leaf's definitions HEDGED; one
            // that names nothing (a template parameter's member `typename T::Ptr`) leaves a leaf
            const std::string_view qLast = written.back();
            const auto [ at, fresh ]     = cache.isNamespace.try_emplace( std::string( qLast ), '\0' );
            if( fresh )
            {
                // a type qualifier (`IColumn::Ptr`, Ptr inherited from a base) is no namespace: it stays a leaf
                const bool isType = std::ranges::any_of( resolveAllByNameQualified( ing, qLast ), [ & ]( NodeId n )
                                                         {
                                                             const Symbol& t = ing.symbols[ n ];
                                                             return t.name == qLast && ( t.kind == SymKind::Class || t.kind == SymKind::Interface || isStructOrNamedType( t.kind ) );
                                                         } );
                at->second = !isType && std::ranges::any_of( ing.symbols, [ & ]( const Symbol& t ) { return namesplit::hasField( t.scope, "::", qLast, /*visitTrailingEmpty=*/true ); } ) ? '\1' : '\0';
            }
            if( at->second != '\0' )
            {
                out.ids    = cands;
                out.hedged = true;
            }
        }
    }
    else
    {
        std::vector<std::string> here;
        enclosingPath( ing, from, cache, here );
        if( !( from.kind == SymKind::Method || from.kind == SymKind::Function ) && !aliasTargetRow( ing, from ) )
        {
            here.push_back( from.name );   // a type's members see its own scope
        }
        std::size_t best    = 0;
        bool        any     = false;
        bool        unknown = false;   // a kept definition's chain is unknown: its empty path proves no lookup
        for( const NodeId n : cands )
        {
            const bool known = enclosingPath( ing, ing.symbols[ n ], cache, path );
            if( pathStartsWith( here, path ) )
            {
                if( !any || path.size() > best )
                {
                    out.ids.clear();
                    best    = path.size();
                    unknown = false;
                }
                any = true;
                if( path.size() == best )
                {
                    out.ids.push_back( n );
                    unknown = unknown || !known;
                }
            }
        }
        if( !any )
        {
            out.ids = cands;
        }
        out.hedged = !any || unknown;
    }
    // a definition inside another translation unit's source file cannot be what this alias names (`class IColumn` in an example
    // .cpp beside the real one in a header): dropped while another definition remains
    const auto visible = [ & ]( NodeId n ) { const Symbol& s = ing.symbols[ n ]; return s.fileId == from.fileId || !cxxSourceFile( ing.files[ s.fileId ] ); };
    if( std::ranges::any_of( out.ids, visible ) )
    {
        std::erase_if( out.ids, [ & ]( NodeId n ) { return !visible( n ); } );
    }
    const auto bodied = [ & ]( NodeId n ) { const Symbol& s = ing.symbols[ n ]; return s.endByte > s.sigEndByte || aliasTargetRow( ing, s ); };
    if( std::ranges::any_of( out.ids, bodied ) )
    {
        std::erase_if( out.ids, [ & ]( NodeId n ) { return !bodied( n ); } );
    }
    std::ranges::stable_sort( out.ids, [ & ]( NodeId a, NodeId b )
                              {
                                  const bool fa = ing.symbols[ a ].fileId == from.fileId, fb = ing.symbols[ b ].fileId == from.fileId;
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
            aliashop_detail::BoundSpelling b     = bindSpelling( ing, sp.head, ing.symbols[ from ], /*types=*/false, cache );
            std::vector<NodeId>&           bound = b.ids;
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
                c.steps.push_back( { n, std::uint8_t( depth ), false, cands, b.hedged } );
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
        aliashop_detail::BoundSpelling b     = bindSpelling( ing, a, ing.symbols[ alias ], /*types=*/true, cache );
        std::vector<NodeId>&           bound = b.ids;
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
                c.steps.push_back( { n, 1, true, cands, b.hedged } );
            }
        }
    }
    return c;
}

// The reverse walk: which alias rows reach the definitions `targets` (as head or template argument), transitively. Built once
// per answer; the verb reads `rows`. HOISTING (S6): nothing is read when no target's language records alias targets; a row's
// target text is folded and kept only when one of its identifiers is a name the walk can ever want (an asked definition's or any
// alias row's name, known before a byte is read), so the rounds re-test a short list in memory and never re-read a file.
struct AliasReach
{
    struct Row
    {
        NodeId alias  = kNoNode;
        NodeId target = kNoNode;   // the asked definition it reaches
        bool   hedged = false;     // a hop on the way bound by name only (BoundSpelling::hedged): its sites are hedged too
    };
    std::vector<Row> rows;         // alias id order (one row per alias; the first asked target its chain reaches)
    bool             capped = false;   // the rounds stopped at kAliasHopDepth with a row still growing (alias_depth_capped=)
    std::size_t      unread = 0;   // alias rows whose file could not be read (their reach is unknown)
    aliashop_detail::BindCache cache;   // the namespace paths the binds read, kept for the verb's visibility test

    AliasReach( const IngestResult& ing, const std::vector<NodeId>& targets )
    {
        if( targets.empty() || ing.aliasTargets.empty()
            || std::ranges::none_of( targets, [ & ]( NodeId t ) { return t < ing.symbols.size() && langFacts( ing.symbols[ t ].lang ).aliasTargetDefs; } ) )
        {
            return;
        }
        // what an alias row may name: the asked definitions, then each alias found (an alias of an alias); keyed by name, so a row's
        // identifier tokens are tested by hash, never by a substring search per name
        HashMap<std::string_view, std::vector<NodeId>> want;
        HashMap<std::string_view, char>                 everWanted;   // the asked names and every alias row's name: the pre-filter
        std::vector<NodeId> standsFor( ing.symbols.size(), kNoNode );   // an asked definition (itself) or an alias reached: what it stands for
        std::vector<char>   hedgedFor( ing.symbols.size(), 0 );
        for( const NodeId t : targets )
        {
            want[ ing.symbols[ t ].name ].push_back( t );
            everWanted.try_emplace( ing.symbols[ t ].name, '\1' );
            standsFor[ t ] = t;
        }
        for( const AliasTarget& a : ing.aliasTargets )
        {
            if( a.id < ing.symbols.size() )
            {
                everWanted.try_emplace( ing.symbols[ a.id ].name, '\1' );
            }
        }
        const auto namesWanted = []( std::string_view raw, const auto& set )
        {
            for( std::size_t i = 0; i < raw.size(); )
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
                if( set.find( raw.substr( i, e - i ) ) != set.end() )
                {
                    return true;
                }
                i = e;
            }
            return false;
        };
        // the candidate rows' written targets, folded ONCE (one read per file; the rounds below re-test them in memory)
        std::vector<std::pair<std::size_t, std::string>> folded;   // (aliasTargets index, folded target)
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
                if( text == nullptr || s.endByte > text->size() || a.start > s.endByte )
                {
                    ++unread;   // could not read is never "reaches none": counted, the verb discloses it
                    continue;
                }
                const std::string_view raw = std::string_view( *text ).substr( a.start, s.endByte - a.start );
                if( namesWanted( raw, everWanted ) )
                {
                    folded.emplace_back( k, foldAliasTarget( raw ) );
                }
            }
        }
        for( std::size_t round = 0; round < kAliasHopDepth; ++round )
        {
            bool grew = false;
            for( const auto& [ k, raw ] : folded )
            {
                const AliasTarget& a = ing.aliasTargets[ k ];
                if( standsFor[ a.id ] != kNoNode || !namesWanted( raw, want ) )
                {
                    continue;   // the cheap test first: no identifier of the target names a wanted definition: no parse, no resolve
                }
                const Symbol&                         s       = ing.symbols[ a.id ];
                const aliashop_detail::TargetSpelling sp      = aliashop_detail::parseTarget( raw );
                NodeId                                reached = kNoNode;
                bool                                  hedged  = false;
                const auto probe = [ & ]( std::string_view spelling, bool types )
                {
                    const aliashop_detail::BoundSpelling b = aliashop_detail::bindSpelling( ing, spelling, s, types, cache );
                    for( const NodeId n : b.ids )
                    {
                        const auto w = want.find( ing.symbols[ n ].name );
                        if( w != want.end() && std::ranges::find( w->second, n ) != w->second.end() )
                        {
                            reached = n;
                            hedged  = b.hedged;
                            return;
                        }
                    }
                };
                probe( sp.head, false );
                for( std::size_t j = 0; reached == kNoNode && j < sp.args.size(); ++j )
                {
                    probe( sp.args[ j ], true );
                }
                if( reached == kNoNode )
                {
                    continue;
                }
                standsFor[ a.id ] = standsFor[ reached ];   // an alias of an alias stands for the asked definition its target stands for
                hedgedFor[ a.id ] = char( hedged || hedgedFor[ reached ] != 0 );
                rows.push_back( { a.id, standsFor[ a.id ], hedgedFor[ a.id ] != 0 } );
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

// The uses verb's disclosure of the sites written through an alias (present-only: each clause only when its attribute is printed).
struct AliasUsesFacts
{
    std::size_t viaAlias  = 0;       // proven alias sites (counted in count=)
    std::size_t hedged    = 0;       // alias-name sites whose reached alias is not the one in scope there (hedge="name", not counted)
    std::size_t namesakes = 0;
    std::size_t unread    = 0;
    bool        capped    = false;   // the reverse walk stopped at its depth with an alias still to follow
};
inline std::string aliasUsesLegend( const AliasUsesFacts& f )
{
    std::string out;
    if( f.viaAlias > 0 || f.hedged > 0 )
    {
        out += "via=\"alias\" alias=A: the site is written as the alias A, whose written target reaches SYM (as the head or a template "
               "argument, up to 4 alias hops), never a call edge; these rows follow the direct ones. A row counts in count= and "
               "via_alias= only when the A that reaches SYM is the one in scope at the site (its file, a namespace or class that "
               "encloses the site, the innermost such A); ";
    }
    if( f.hedged > 0 )
    {
        out += "hedge=\"name\": the site's A is matched by name only (no reaching A encloses it, or a namesake A does: alias_hedged=N "
               "such rows, listed last, never in count=); ";
    }
    if( f.namesakes > 0 && ( f.viaAlias > 0 || f.hedged > 0 ) )
    {
        out += "alias_namesakes=K: K definitions share a listed alias's name and reach none of SYM; ";
    }
    if( f.viaAlias > 0 || f.hedged > 0 )
    {
        out += "alias_sites_held=N: the columnar form keeps those N sites out of its rows; ";
    }
    if( f.unread > 0 )
    {
        out += "alias_unread=N: N alias declarations could not be read, so their reach is unknown (a floor); ";
    }
    if( f.capped )
    {
        out += "alias_depth_capped=\"1\": the alias walk stopped at 4 hops with an alias still to follow (via_alias= a floor); ";
    }
    if( !out.empty() )
    {
        out += "These rows are the aliased spellings the role=\"type\" sentence above leaves out. ";
    }
    return out;
}
inline std::string aliasUsesAttrXml( const AliasUsesFacts& f, bool columnar )
{
    std::string out;
    const auto num = [ & ]( std::string_view k, std::size_t v ) { out.append( " " ).append( k ).append( "=\"" ).append( std::to_string( v ) ).append( "\"" ); };
    if( f.viaAlias > 0 )
    {
        num( columnar ? "alias_sites_held" : "via_alias", f.viaAlias );
    }
    if( f.hedged > 0 )
    {
        num( "alias_hedged", f.hedged );
    }
    if( ( f.viaAlias > 0 || f.hedged > 0 ) && f.namesakes > 0 )
    {
        num( "alias_namesakes", f.namesakes );
    }
    if( f.unread > 0 )
    {
        num( "alias_unread", f.unread );
    }
    if( f.capped )
    {
        out.append( " alias_depth_capped=\"1\"" );
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
