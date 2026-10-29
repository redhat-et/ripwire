#pragma once

// testonlycallers.h — FOR-TONLY (card A2 carrier): the ONE predicate "every indexed caller of this function is test code",
// read by --dead-code's test-only rows (verbs_quality.h) and by the --for lens's tonly="1" row attribute (CLI XML, --json and
// the MCP `for` twin). One rule, two surfaces: a second copy is what would drift.
//
// The rule is on CALLERS only. A caller is test code by filter.h isTestSymbol (the shared test-path rule plus the in-file
// test scopes); a by-name (hedged) edge from a library symbol is still a library caller, so it keeps the flag off; an edge a
// test reaches by name alone can only add a test caller. A function with NO caller is not test-only (that is "no callers",
// already spelled by an absent in=). A test symbol itself is never flagged.

#include "filter.h"
#include "graph.h"
#include "lintrules.h"        // langOfPath — which skipped files could have held a caller
#include "model.h"
#include "valuerefindex.h"    // ValueRefIndex::narrowFor / isValueReferenced — a name a library holds as a VALUE is a use
#include "infra/sortutil.h"   // svLess

#include <algorithm>
#include <cstdint>
#include <string_view>
#include <vector>

namespace rw
{

// D1 TESTONLY-DEAD: every in-edge of `id` comes from a test symbol. all_of over an empty row is TRUE, so a caller that wants
// "test-only" (not "no callers") must also check the row is non-empty; computeTestOnlyCallers below does.
inline bool everyCallerIsTest( const IngestResult& ing, const Graph& g, NodeId id ) noexcept
{
    const auto* ro = g.inEdges.rowOffsets();
    const auto* ci = g.inEdges.colIndices();
    return std::all_of( ci + ro[ id ], ci + ro[ id + 1 ], [ & ]( NodeId caller ) { return isTestSymbol( ing, caller ); } );
}

// Was the whole tree indexed? A "every caller is a test" claim rests on having seen every caller: a memory-guard stop
// (partial crawl or parse) or a dropped oversize file in a language that carries calls can hide a library caller. Data and
// prose files (json/toml/yaml/markdown) carry no call, so an oversize lockfile does not switch the claim off.
inline bool testOnlyIndexWhole( const IngestResult& ing ) noexcept
{
    if( ing.memoryStop.isSet() )
    {
        return false;
    }
    return std::none_of( ing.skippedOversize.begin(), ing.skippedOversize.end(), []( const SkippedOversize& f )
    {
        const Lang l = langOfPath( f.path );
        return l != Lang::Unknown && l != Lang::Json && l != Lang::Toml && l != Lang::Yaml && l != Lang::Markdown;
    } );
}

// Declined-call evidence (graph.h Graph::declinedSite*): a call the resolver refused to bind (an interface value, an untyped
// receiver, a name gate) gets no edge but names the definitions it could have meant. A declined call made by LIBRARY code that
// names a function is a library caller the edge pass cannot see, so that function is not "called only by tests" — the same
// evidence --callers prints as declined_calls= and <dc> rows. A decline made by a test symbol adds only a test caller.
// `unknown` is set when a library decline kept no candidate list (the uint32 offset degrade): then no function can be vetted.
inline std::vector<char> namedByLibraryDeclinedCall( const IngestResult& ing, const Graph& g, bool& unknown )
{
    std::vector<char> named( ing.symbols.size(), 0 );
    unknown = false;
    if( g.declinedSiteCaller.empty() )
    {
        return named;
    }
    std::vector<char> listFromLibrary( g.declinedListCallCount.size(), 0 );
    for( std::size_t site = 0; site < g.declinedSiteCaller.size(); ++site )
    {
        if( isTestSymbol( ing, g.declinedSiteCaller[ site ] ) )
        {
            continue;
        }
        if( const std::uint32_t list = g.declinedSiteList[ site ]; list == kNoDeclinedList )
        {
            unknown = true;
        }
        else if( list < listFromLibrary.size() )
        {
            listFromLibrary[ list ] = 1;
        }
    }
    for( std::size_t list = 0; list < listFromLibrary.size(); ++list )
    {
        for( std::uint32_t slot = g.declinedListOff[ list ]; listFromLibrary[ list ] && slot < g.declinedListOff[ list + 1 ]; ++slot )
        {
            if( const NodeId cand = g.declinedListCand[ slot ]; cand < named.size() )
            {
                named[ cand ] = 1;
            }
        }
    }
    return named;
}

// The names of methods an INTERFACE (SymKind::Interface: a Go/Java/C#/TypeScript interface) declares. A call through the interface
// value binds to that declaration, never to an implementing method, so an implementation only tests call directly still has
// library callers the graph cannot name (nfpm's RPM.Package, run by the CLI through the Packager interface). Every method
// carrying such a name is dispatch-reachable and keeps the flag off. Sorted by svLess for binary search.
inline std::vector<std::string_view> interfaceMethodNames( const IngestResult& ing )
{
    std::vector<std::string_view> ifaces;
    for( const Symbol& s : ing.symbols )
    {
        if( s.kind == SymKind::Interface )
        {
            ifaces.push_back( s.name );
        }
    }
    std::ranges::sort( ifaces, sortutil::svLess );
    std::vector<std::string_view> methods;
    for( const Symbol& s : ing.symbols )
    {
        if( s.kind == SymKind::Method && !s.scope.empty() && std::ranges::binary_search( ifaces, scopeLastSegment( s.scope ), sortutil::svLess ) )
        {
            methods.push_back( s.name );
        }
    }
    std::ranges::sort( methods, sortutil::svLess );
    methods.erase( std::ranges::unique( methods ).begin(), methods.end() );
    return methods;
}

// FOR-TONLY: per symbol, 1 iff it is a library function or method that has at least one indexed caller, every caller is a
// test symbol, no library code holds it as a value (a dispatch table, a registering decorator: ValueRefIndex), no library call
// the resolver declined names it, it is not a method an interface declares, and the index is whole. Empty vector (no flag
// anywhere) when the index is cut or nothing qualifies. O(in-edges + declined records) for the edge pass; the value-use vetting
// runs over the few names that pass it, on a narrow index.
inline std::vector<std::uint8_t> computeTestOnlyCallers( const IngestResult& ing, const Graph& g )
{
    std::vector<std::uint8_t> flags;
    if( !testOnlyIndexWhole( ing ) || g.inEdges.rowOffsets() == nullptr )
    {
        return flags;
    }
    bool              declinedUnknown = false;
    const std::vector<char> declined  = namedByLibraryDeclinedCall( ing, g, declinedUnknown );
    if( declinedUnknown )
    {
        return flags;
    }
    const std::vector<std::string_view> ifaceMethods = interfaceMethodNames( ing );
    const auto*         ro = g.inEdges.rowOffsets();
    std::vector<NodeId> cands;
    for( const Symbol& s : ing.symbols )
    {
        if( ( s.kind != SymKind::Function && s.kind != SymKind::Method ) || ro[ s.id + 1 ] == ro[ s.id ] || isTestSymbol( ing, s.id )
            || declined[ s.id ] != 0 )
        {
            continue;
        }
        if( s.kind == SymKind::Method && std::ranges::binary_search( ifaceMethods, std::string_view( s.name ), sortutil::svLess ) )
        {
            continue;
        }
        if( everyCallerIsTest( ing, g, s.id ) )
        {
            cands.push_back( s.id );
        }
    }
    if( cands.empty() )
    {
        return flags;
    }
    std::vector<std::string_view> names;
    names.reserve( cands.size() );
    for( const NodeId id : cands )
    {
        names.push_back( ing.symbols[ id ].name );
    }
    std::ranges::sort( names, sortutil::svLess );
    names.erase( std::ranges::unique( names ).begin(), names.end() );
    const ValueRefIndex vri = ValueRefIndex::narrowFor( ing, names );
    flags.assign( ing.symbols.size(), 0u );
    for( const NodeId id : cands )
    {
        flags[ id ] = vri.isValueReferenced( id ) ? 0u : 1u;
    }
    return flags;
}

}   // namespace rw
