#pragma once
// defattrib.h — THE one home of "which of the selector's definitions does this row belong to" (lane attrib-multidef).
//
// THE DEFECT CLASS (round 4, O1 false claims ninja-07 / nfpm-06 / ninja-26): a selector that names several same-named
// definitions (`--callers=empty` with StringPiece::empty and EvalString::empty) answers with the UNION of their callers,
// callees or dependants, and every row read as belonging to one definition. defs="2" said there were two; nothing said
// which row was whose. fix27 hedged the --impact file rollup only. Every verb that folds per-selector rows reads this file:
// --callers/--callees and their MCP twins (callhierarchy.h computes the rows once for both), --safe-delete's caller rows,
// --impact (CLI + MCP) and its <rf> rollup, and the --path endpoints.
//
// THE DEFINITION GROUP. A bodied definition plus the bodyless declarations that DECLARE it is one group; any other match is
// a group of its own. Who declares whom is never a new rule here:
//   * C, C++, ObjC: the --edit-check identity rule (editcheckdecl.h editCheckTieDeclaration — same full scope chain, member
//     qualifiers, parameter-type list, include proof, linkage), through the same fold (editcheck.h editCheckDeclFoldTargets).
//     A declaration of `a::detail::f` never pairs with a definition of `b::detail::f` (Symbol::scope is only the innermost
//     label — review M1 on that file), and a prototype never pairs with a `static` definition in another file.
//   * TypeScript: an overload signature (a bodyless function, or a bodyless method that is not an interface/abstract/ambient
//     contract — tsContractSignatures below) joins the implementation that follows it: the language requires the
//     implementation to come next in the same declaration list, so the nearest following bodied same-name, same-kind,
//     same-scope match in its file is it.
//   * Every other language: each match is its own group. Their bodyless matches are contracts (a Java interface method, a
//     Rust trait or Swift protocol requirement, a Go interface method), which are other definitions, not declarations of one.
//     Python `@overload` stubs carry a `...` body, so each is its own group: a disclosed floor (the rows still attribute to
//     whichever stub the resolver bound).
//
// THE ROW ATTRIBUTION. Labels come from the resolver's edges only (Graph::outNameOnly / outProv), never from text:
//   K    a proven edge ties the row to group K (the resolver's binding, not a type check)
//   K~s  only edges that are one arm of a call the resolver split between same-named definitions (outProv 3)
//   K~n  only edges bound by name alone (outNameOnly)
//   K~t  a proven edge into a PRIMARY template's member while a specialisation of it is another listed group (Q2: the parser
//        labels them sc="Box" and sc="Box<int>"; which one the call reaches is unproven). A hedge read off the two scope
//        labels — a string relation, so it may only ever WEAKEN a token, never make one.
// callers: row → a member of K; callees: a member of K → row; impact: a chain of calls from the row to a member of K (any
// by-name hop makes the chain ~n, else any split hop ~s); the <rf> rollup row: the union of its file's symbols, strongest per K.
// A one-group answer (one definition, or one with its own declarations) carries no table and no of_def; its rows whose every
// non-by-name edge to the selector is a split arm carry prov="split" (the orchestrator's Q1 ruling: whatever defs= is).
//
// WHAT IT DOES NOT MEAN (checklist 3): K is the resolver's binding, not a compiler's — a proven edge can still be wrong (the
// Box<int> case is why ~t exists); K~n / K~s / K~t do not say the edge is false; of_def says nothing about calls the resolver
// declined (declined_calls= stays that floor).

#include "editcheck.h"   // editCheckGroupKeys' fold (editCheckDeclFoldTargets) — the C-family declaration identity
#include "graph.h"
#include "langfacts.h"   // langFacts(l).overloadSignatures — the TypeScript overload-signature rule, as a column
#include "memberowner.h"   // QUALNAME-1: MemberOwners / qualifiedMemberName — the one member-owner rule for every row
#include "model.h"
#include "pageview.h"
#include "sarif.h"       // rootRelativeUri: the table's p= in the rows' own path dialect
#include "serialize.h"   // escapeXml / jsonStr / symTag
#include "infra/sortutil.h"   // svLess: tsContractSignatures' explicit byte order

#include <algorithm>
#include <cstdint>
#include <format>
#include <iterator>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// The table lists every group up to this many; above it, only the groups a row on the page names (defs_listed= says how
// many it listed). textual's `render` has 61 definitions and `compose` 1047: a full table there would outweigh the page.
// Above it a row also enumerates no by-name tie (defTokensTo): its K, K~s, K~t and one bare ~n (final review R2).
inline constexpr std::size_t kDefTableCap = 16;

// One row's tie to one group, weakest first, so the strongest of several edges is a max().
enum class DefMark : std::uint8_t
{
    None   = 0,
    Name   = 1,   // K~n
    Split  = 2,   // K~s
    Proven = 3,   // K (or K~t when the group is a primary template with a listed specialisation)
};

struct DefGroups
{
    std::vector<std::uint32_t> ofMatch;         // parallel to the matches: the group each one belongs to
    std::vector<NodeId>        rep;             // per group: the bodied member (the table's t=/sc=/p=), else its first match
    std::vector<char>          bodyless;        // per group: no member has a body (a declaration that declares no listed definition)
    std::vector<char>          primaryOfSpec;   // per group: its sc= is the template base of another group's sc= (the ~t mark)
    std::vector<char>          untied;          // per group: C-family declarations only, which MAY declare a listed definition (the
                                                // identity rule's Unproven: a template-qualified or macro-built declarator, no shared
                                                // #include) — dropped only when no row ties to it and one group is left
                                                // (defGroupsDropSilent); on a printed table it is listed bodyless="1"

    std::size_t size() const noexcept { return rep.size(); }
    bool        multi() const noexcept { return rep.size() >= 2; }
};

// The TypeScript methods with no body that are a CONTRACT — an interface member (method_signature), an abstract or an
// ambient (.d.ts) member — as their own symbol ids, minus overload signatures: those sit in the same OWNER (the innermost
// class or interface whose span holds them, in the same file) as a bodied method of the same name, which implements
// them, so their receiver is that class and not an interface. The owner is part of the key because TS methods carry no
// `scope`: keyed by file alone, an `interface Router { match(): void }` beside an unrelated `class Matcher { match() {} }`
// lost its signature (test/declinecheck.sh (I), the same-file arm).
inline std::vector<NodeId> tsContractSignatures( const IngestResult& ing )
{
    struct Span
    {
        std::uint32_t fileId;
        std::uint32_t start;
        std::uint32_t end;
        NodeId        id;
    };
    std::vector<Span>   owners;   // every TS class/interface/struct span, by file then start
    std::vector<NodeId> methods;
    for( NodeId id = 0; id < ing.symbols.size(); ++id )
    {
        const Symbol& s = ing.symbols[id];
        if( !langFacts( s.lang ).overloadSignatures )
        {
            continue;
        }
        if( s.kind == SymKind::Method )
        {
            methods.push_back( id );
        }
        else if( s.kind == SymKind::Class || s.kind == SymKind::Interface || isStructOrNamedType( s.kind ) )
        {
            owners.push_back( Span{ s.fileId, s.sigStartByte, s.endByte, id } );
        }
    }
    std::sort( owners.begin(), owners.end(), []( const Span& a, const Span& b ) noexcept
               { return a.fileId != b.fileId ? a.fileId < b.fileId : a.start < b.start; } );
    // The innermost owner span holding `s` in its own file; kNoNode for a method no owner span holds.
    const auto ownerOf = [ & ]( const Symbol& s ) noexcept
    {
        const auto first = std::lower_bound( owners.begin(), owners.end(), s.fileId,
                                             []( const Span& o, std::uint32_t f ) noexcept { return o.fileId < f; } );
        NodeId        best    = kNoNode;
        std::uint32_t bestLen = 0xFFFFFFFFu;
        for( auto it = first; it != owners.end() && it->fileId == s.fileId && it->start <= s.sigStartByte; ++it )
        {
            if( s.sigStartByte < it->end && it->end - it->start < bestLen )
            {
                best    = it->id;
                bestLen = it->end - it->start;
            }
        }
        return best;
    };
    struct Owned
    {
        NodeId           owner;
        std::uint32_t    fileId;
        std::string_view name;
    };
    const auto byOwnerThenName = []( const Owned& a, const Owned& b ) noexcept
    {
        if( a.fileId != b.fileId )
        {
            return a.fileId < b.fileId;
        }
        return a.owner != b.owner ? a.owner < b.owner : sortutil::svLess( a.name, b.name );
    };
    std::vector<Owned>  bodied;   // (file, owner, name) of every bodied TS method
    std::vector<NodeId> bodyless;
    for( const NodeId id : methods )
    {
        const Symbol& s = ing.symbols[id];
        if( s.sigEndByte == s.endByte )
        {
            bodyless.push_back( id );
        }
        else
        {
            bodied.push_back( Owned{ ownerOf( s ), s.fileId, s.name } );
        }
    }
    std::sort( bodied.begin(), bodied.end(), byOwnerThenName );
    std::erase_if( bodyless, [ & ]( NodeId id )
    {
        const Symbol& s = ing.symbols[id];
        return std::binary_search( bodied.begin(), bodied.end(), Owned{ ownerOf( s ), s.fileId, s.name }, byOwnerThenName );
    } );
    return bodyless;
}

// TypeScript's overload-signature rule (see the header): the implementation a bodyless TS match `i` declares, or i itself.
inline std::size_t defGroupTsImplementation( const IngestResult& ing, std::span<const NodeId> matches, std::size_t i,
                                             std::span<const NodeId> contracts )
{
    const Symbol& d = ing.symbols[ matches[i] ];
    if( std::binary_search( contracts.begin(), contracts.end(), matches[i] ) )
    {
        return i;   // an interface / abstract / ambient member: a contract, not a declaration of a body
    }
    std::size_t best = i;
    for( std::size_t j = 0; j < matches.size(); ++j )
    {
        const Symbol& f = ing.symbols[ matches[j] ];
        if( j == i || !langFacts( f.lang ).overloadSignatures || f.fileId != d.fileId || f.kind != d.kind || f.name != d.name || f.scope != d.scope
            || !isDefinitionNotDeclaration( f ) || f.sigStartByte < d.endByte )
        {
            continue;
        }
        if( best == i || f.sigStartByte < ing.symbols[ matches[best] ].sigStartByte )
        {
            best = j;
        }
    }
    return best;
}

// The fold target of every match (its own index when it declares no other listed match), by the two rules above.
inline std::vector<std::size_t> defGroupTargets( const IngestResult& ing, std::span<const NodeId> matches )
{
    std::vector<std::size_t> target( matches.size() );
    bool                     anyCDecl = false;
    bool                     anyTsDecl = false;
    for( std::size_t i = 0; i < matches.size(); ++i )
    {
        target[i]        = i;
        const Symbol& s  = ing.symbols[ matches[i] ];
        const bool    bodyless = !isDefinitionNotDeclaration( s );
        anyCDecl  = anyCDecl || ( bodyless && langCompatible( s.lang, Lang::C ) );
        anyTsDecl = anyTsDecl || ( bodyless && langFacts( s.lang ).overloadSignatures && ( s.kind == SymKind::Function || s.kind == SymKind::Method ) );
    }
    if( anyCDecl )
    {
        // One editcheck group per match, so the fold's "definitions in two groups" rule reads "declares two definitions":
        // such a declaration (one header, a posix.cpp and a win.cpp) stays its own group.
        EditCheckGroupKeys gk;
        for( std::size_t i = 0; i < matches.size(); ++i )
        {
            gk.keys.emplace_back( ing.symbols[ matches[i] ].fileId, std::to_string( i ) );
            gk.members.push_back( { matches[i] } );
        }
        target = editCheckDeclFoldTargets( ing, gk );
    }
    if( anyTsDecl )
    {
        std::vector<NodeId> contracts = tsContractSignatures( ing );
        std::sort( contracts.begin(), contracts.end() );
        for( std::size_t i = 0; i < matches.size(); ++i )
        {
            const Symbol& s = ing.symbols[ matches[i] ];
            if( langFacts( s.lang ).overloadSignatures && !isDefinitionNotDeclaration( s ) && ( s.kind == SymKind::Function || s.kind == SymKind::Method ) )
            {
                target[i] = defGroupTsImplementation( ing, matches, i, contracts );
            }
        }
    }
    ENSURES( target.size() == matches.size() );
    return target;
}

// Per group: 1 when every member is a C-family declaration and the identity rule answers Unproven (may declare, could not prove)
// for one of the listed definitions. A Different-from-all declaration (another scope chain, a static definition elsewhere) is a
// separate function and stays a group of its own; an Unproven one may be the same function, so it is listed only when a row
// actually ties to it — otherwise every template class's out-of-line member (`template <class T> void Box<T>::grow()`, an
// unknown chain) and every local forward declaration would grow a table about a tie nobody can prove either way.
inline std::vector<char> defGroupUntied( const IngestResult& ing, std::span<const NodeId> matches, const DefGroups& groups );

// Q2: `base` is the template base of `spec` — spec spells base<…> (the parser's scope labels: sc="Box" vs sc="Box<int>").
inline bool defScopeIsTemplateBaseOf( std::string_view base, std::string_view spec ) noexcept
{
    return !base.empty() && spec.size() > base.size() + 2 && spec.starts_with( base ) && spec[ base.size() ] == '<' && spec.back() == '>';
}

inline DefGroups defGroupsOf( const IngestResult& ing, std::span<const NodeId> matches )
{
    DefGroups out;
    if( matches.size() < 2 )
    {
        out.ofMatch.assign( matches.size(), 0 );
        if( !matches.empty() )
        {
            out.rep.push_back( matches.front() );
            out.bodyless.push_back( isDefinitionNotDeclaration( ing.symbols[ matches.front() ] ) ? 0 : 1 );
            out.primaryOfSpec.push_back( 0 );
            out.untied.push_back( 0 );
        }
        return out;
    }
    const std::vector<std::size_t> target = defGroupTargets( ing, matches );
    std::vector<std::uint32_t>     groupOfKept( matches.size(), UINT32_MAX );
    for( std::size_t i = 0; i < matches.size(); ++i )   // the resolver's match order: group ix follows the first member
    {
        const std::size_t t = target[i];
        ASSUME( t < matches.size() && target[t] == t, "a fold target is kept (it holds the body the declaration declares)" );
        if( groupOfKept[t] == UINT32_MAX )
        {
            groupOfKept[t] = std::uint32_t( out.rep.size() );
            out.rep.push_back( matches[t] );
            out.bodyless.push_back( isDefinitionNotDeclaration( ing.symbols[ matches[t] ] ) ? 0 : 1 );
        }
    }
    out.ofMatch.resize( matches.size() );
    for( std::size_t i = 0; i < matches.size(); ++i )
    {
        out.ofMatch[i] = groupOfKept[ target[i] ];
    }
    out.primaryOfSpec.assign( out.rep.size(), 0 );
    for( std::size_t a = 0; a < out.rep.size(); ++a )
    {
        const Symbol& p = ing.symbols[ out.rep[a] ];
        for( std::size_t b = 0; b < out.rep.size() && !out.primaryOfSpec[a]; ++b )
        {
            const Symbol& q = ing.symbols[ out.rep[b] ];
            out.primaryOfSpec[a] = ( b != a && p.name == q.name && langCompatible( p.lang, q.lang ) && defScopeIsTemplateBaseOf( p.scope, q.scope ) ) ? 1 : 0;
        }
    }
    out.untied = defGroupUntied( ing, matches, out );
    ENSURES( out.ofMatch.size() == matches.size() && out.rep.size() <= matches.size() && out.untied.size() == out.rep.size() );
    return out;
}

inline std::vector<char> defGroupUntied( const IngestResult& ing, std::span<const NodeId> matches, const DefGroups& groups )
{
    std::vector<char> untied( groups.size(), 0 );
    std::vector<char> declOnly( groups.size(), 1 );
    for( std::size_t i = 0; i < matches.size(); ++i )
    {
        const Symbol& s = ing.symbols[ matches[i] ];
        declOnly[ groups.ofMatch[i] ] &= char( langCompatible( s.lang, Lang::C ) && !isDefinitionNotDeclaration( s ) );
    }
    if( std::none_of( declOnly.begin(), declOnly.end(), []( char c ) { return c != 0; } ) )
    {
        return untied;
    }
    EditCheckSources                                  sources( ing, EditCheckSpliced{} );
    std::vector<std::optional<EditCheckSignature>> defSigs( matches.size() );   // by match position: each one's signature, read once
    for( std::size_t i = 0; i < matches.size(); ++i )
    {
        const std::uint32_t grp = groups.ofMatch[i];
        if( !declOnly[grp] || untied[grp] )
        {
            continue;
        }
        for( std::size_t j = 0; j < matches.size() && !untied[grp]; ++j )
        {
            const Symbol& f = ing.symbols[ matches[j] ];
            if( !editCheckTieCandidate( ing.symbols[ matches[i] ], f ) )
            {
                continue;   // Different on parser fields alone: no source read
            }
            if( !defSigs[j] )
            {
                defSigs[j] = editCheckSignatureOf( sources, f );
            }
            untied[grp] = editCheckTieDeclaration( ing, sources, matches[i], matches[j], *defSigs[j] ).tie == EditCheckTie::Unproven ? 1 : 0;
        }
    }
    return untied;
}

// ── the per-row tokens ──────────────────────────────────────────────────────────────────────────────────────────────
// A CSR over the rows (in the served order): row r's ties are tok[off[r] .. off[r+1]), each (group << 2) | DefMark, groups
// ascending. Built once per answer; every dialect and both transports read it.
struct RowDefTokens
{
    std::vector<std::uint32_t> off;
    std::vector<std::uint32_t> tok;

    bool empty() const noexcept { return off.empty(); }
    std::span<const std::uint32_t> of( std::size_t row ) const noexcept
    {
        return row + 1 < off.size() ? std::span<const std::uint32_t>( tok.data() + off[row], off[row + 1] - off[row] )
                                    : std::span<const std::uint32_t>();
    }
    // the strongest tie the row has to any group (None when the row has none recorded)
    DefMark strongest( std::size_t row ) const noexcept
    {
        std::uint32_t best = 0;
        for( const std::uint32_t t : of( row ) )
        {
            best = std::max( best, t & 3u );
        }
        return DefMark( best );
    }
};

// One out-edge's tie, off its two parallel per-edge bytes (either may be unallocated: a graph with no such edge).
inline DefMark defMarkOfEdge( const Graph& g, std::size_t e ) noexcept
{
    if( e < g.outNameOnly.size() && edgeKindByte( g.outNameOnly[e] ) == kEdgeName )
    {
        return DefMark::Name;
    }
    return ( e < g.outProv.size() && g.outProv[e] == 3u ) ? DefMark::Split : DefMark::Proven;
}

// FE-B's two path predicates' sibling: the hop from → to is one arm of a resolver split (and not by name alone).
inline bool edgeSplitArm( const Graph& g, NodeId from, NodeId to ) noexcept
{
    const std::size_t e = edgeIndex( g, from, to );
    return e != SIZE_MAX && defMarkOfEdge( g, e ) == DefMark::Split;
}

// (row node, group, mark) facts → the CSR over `rows`, strongest mark per (row, group).
struct DefTie
{
    NodeId        node;
    std::uint32_t group;
    std::uint8_t  mark;
};
inline RowDefTokens rowDefTokensFrom( std::vector<DefTie>& ties, std::span<const NodeId> rows )
{
    std::sort( ties.begin(), ties.end(), []( const DefTie& a, const DefTie& b ) noexcept
               { return a.node != b.node ? a.node < b.node : ( a.group != b.group ? a.group < b.group : a.mark > b.mark ); } );
    RowDefTokens out;
    out.off.reserve( rows.size() + 1 );
    out.off.push_back( 0 );
    for( const NodeId r : rows )
    {
        auto it = std::lower_bound( ties.begin(), ties.end(), r, []( const DefTie& t, NodeId n ) noexcept { return t.node < n; } );
        for( ; it != ties.end() && it->node == r; ++it )
        {
            if( out.tok.size() > out.off.back() && ( out.tok.back() >> 2 ) == it->group )
            {
                continue;   // a weaker tie to the same group (sorted strongest first)
            }
            out.tok.push_back( ( it->group << 2 ) | it->mark );
        }
        out.off.push_back( std::uint32_t( out.tok.size() ) );
    }
    ENSURES( out.off.size() == rows.size() + 1 );
    return out;
}

// --callers / --callees / --safe-delete: one pass over each match's edges (the walk that built the rows). `towardMatches`:
// the rows are callers (row → match); else callees (match → row).
inline RowDefTokens attributeOneHop( const Graph& g, const DefGroups& groups, std::span<const NodeId> matches,
                                     std::span<const NodeId> rows, bool towardMatches )
{
    EXPECTS( groups.ofMatch.size() == matches.size(), "the groups are defGroupsOf( matches )" );
    std::vector<DefTie> ties;
    const auto*         ro = g.inEdges.rowOffsets();
    const auto*         ci = g.inEdges.colIndices();
    for( std::size_t mi = 0; mi < matches.size(); ++mi )
    {
        const NodeId        m   = matches[mi];
        const std::uint32_t grp = groups.ofMatch[mi];
        if( std::size_t( m ) + 1 >= g.outOff.size() )
        {
            continue;
        }
        if( towardMatches )
        {
            for( std::uint32_t k = ro[m]; k < ro[m + 1]; ++k )
            {
                const std::size_t e = edgeIndex( g, ci[k], m );
                if( e != SIZE_MAX )
                {
                    ties.push_back( DefTie{ ci[k], grp, std::uint8_t( defMarkOfEdge( g, e ) ) } );
                }
            }
        }
        else
        {
            for( std::uint32_t k = g.outOff[m]; k < g.outOff[ std::size_t( m ) + 1 ]; ++k )
            {
                ties.push_back( DefTie{ g.outTargets[k], grp, std::uint8_t( defMarkOfEdge( g, k ) ) } );
            }
        }
    }
    return rowDefTokensFrom( ties, rows );
}

// --impact: the three reaches of every reached node, as bitsets over the groups — P (an all-proven chain), S (no by-name hop),
// A (any chain) — propagated from the seeds over the in-edges until nothing grows (monotone, so it ends; a cycle only re-adds
// bits it already holds). The bitsets live on a dense index of the reach set plus the seeds, never on every node (review S5:
// 1047 groups over all nodes would be megabytes per walk). Token: K from P, K~s from S\P, K~n from A\S.
struct ReachBits
{
    std::vector<NodeId>        dense;   // ascending: the reach set plus the seeds
    std::size_t                words = 0;
    std::vector<std::uint64_t> p, s, a;  // dense.size() * words each

    std::size_t denseOf( NodeId n ) const noexcept
    {
        const auto [ first, last ] = std::equal_range( dense.begin(), dense.end(), n );
        return first == last ? SIZE_MAX : std::size_t( first - dense.begin() );
    }
    // fold u's reaches into its caller c across one edge of tie `mark`; true when c gained a bit
    bool foldInto( std::size_t c, std::size_t u, DefMark mark ) noexcept
    {
        bool changed = false;
        for( std::size_t w = 0; w < words; ++w )
        {
            const std::size_t cw = c * words + w;
            const std::size_t uw = u * words + w;
            const std::uint64_t na = a[cw] | a[uw];
            const std::uint64_t ns = mark >= DefMark::Split ? ( s[cw] | s[uw] ) : s[cw];
            const std::uint64_t np = mark == DefMark::Proven ? ( p[cw] | p[uw] ) : p[cw];
            changed = changed || na != a[cw] || ns != s[cw] || np != p[cw];
            a[cw] = na;
            s[cw] = ns;
            p[cw] = np;
        }
        return changed;
    }
    DefMark markOf( std::size_t d, std::size_t grp ) const noexcept
    {
        const std::uint64_t bit = std::uint64_t( 1 ) << ( grp % 64 );
        const std::size_t   w   = d * words + grp / 64;
        return ( p[w] & bit ) ? DefMark::Proven : ( s[w] & bit ) ? DefMark::Split : ( a[w] & bit ) ? DefMark::Name : DefMark::None;
    }
};

inline ReachBits reachBitsets( const Graph& g, const DefGroups& groups, std::span<const NodeId> seeds, std::span<const NodeId> reach )
{
    EXPECTS( groups.ofMatch.size() == seeds.size(), "the groups are defGroupsOf( seeds )" );
    ReachBits bits;
    bits.dense.assign( reach.begin(), reach.end() );
    bits.dense.insert( bits.dense.end(), seeds.begin(), seeds.end() );
    std::sort( bits.dense.begin(), bits.dense.end() );
    bits.dense.erase( std::unique( bits.dense.begin(), bits.dense.end() ), bits.dense.end() );
    bits.words = ( groups.size() + 63 ) / 64;
    bits.p.assign( bits.dense.size() * bits.words, 0 );
    bits.s = bits.p;
    bits.a = bits.p;
    std::vector<char>        queued( bits.dense.size(), 0 );
    std::vector<std::size_t> work;
    for( std::size_t si = 0; si < seeds.size(); ++si )
    {
        const std::size_t d = bits.denseOf( seeds[si] );
        ASSUME( d != SIZE_MAX, "every seed is in the dense index (it was inserted)" );
        const std::size_t   w   = d * bits.words + groups.ofMatch[si] / 64;
        const std::uint64_t bit = std::uint64_t( 1 ) << ( groups.ofMatch[si] % 64 );
        bits.p[w] |= bit;
        bits.s[w] |= bit;
        bits.a[w] |= bit;
        work.push_back( d );
        queued[d] = 1;
    }
    const auto* ro = g.inEdges.rowOffsets();
    const auto* ci = g.inEdges.colIndices();
    while( !work.empty() )
    {
        const std::size_t u = work.back();
        work.pop_back();
        queued[u] = 0;
        for( std::uint32_t k = ro[ bits.dense[u] ]; k < ro[ bits.dense[u] + 1 ]; ++k )
        {
            const std::size_t c = bits.denseOf( ci[k] );
            const std::size_t e = edgeIndex( g, ci[k], bits.dense[u] );
            // outside the reach set (cannot happen for a full closure) or no out-edge twin: nothing to fold
            if( c != SIZE_MAX && e != SIZE_MAX && bits.foldInto( c, u, defMarkOfEdge( g, e ) ) && !queued[c] )
            {
                queued[c] = 1;
                work.push_back( c );
            }
        }
    }
    return bits;
}

inline RowDefTokens attributeReach( const Graph& g, const DefGroups& groups, std::span<const NodeId> seeds, std::span<const NodeId> reach,
                                    std::span<const NodeId> rows )
{
    const ReachBits     bits = reachBitsets( g, groups, seeds, reach );
    std::vector<DefTie> ties;
    for( const NodeId r : rows )
    {
        const std::size_t d = bits.denseOf( r );
        for( std::size_t grp = 0; grp < groups.size() && d != SIZE_MAX; ++grp )
        {
            if( const DefMark m = bits.markOf( d, grp ); m != DefMark::None )
            {
                ties.push_back( DefTie{ r, std::uint32_t( grp ), std::uint8_t( m ) } );
            }
        }
    }
    return rowDefTokensFrom( ties, rows );
}

// The --impact <rf> rollup: per FILE, the union of its reached symbols' ties, the strongest per group. `files` are the
// rollup rows' file ids in their order; `reach` with `reachTok` (attributeReach over `reach` itself) supplies the symbols.
inline RowDefTokens attributeFiles( const IngestResult& ing, std::span<const std::uint32_t> files, std::span<const NodeId> reach,
                                    const RowDefTokens& reachTok )
{
    std::vector<DefTie> ties;
    for( std::size_t i = 0; i < reach.size(); ++i )
    {
        for( const std::uint32_t t : reachTok.of( i ) )
        {
            ties.push_back( DefTie{ NodeId( ing.symbols[ reach[i] ].fileId ), t >> 2, std::uint8_t( t & 3u ) } );
        }
    }
    std::vector<NodeId> fileRows( files.begin(), files.end() );
    return rowDefTokensFrom( ties, fileRows );
}

// ── the table and the rendering ──────────────────────────────────────────────────────────────────────────────────────
// Which groups the table lists: all of them up to kDefTableCap, else the ones a shown row names (`named`, by group).
struct DefTableListing
{
    std::vector<std::uint32_t> listed;   // ascending group indices
    bool                       cut = false;
};
// Above the cap the table is cut, and a row's by-name ties are not enumerated (they print as one bare ~n).
inline bool defTableCapped( const DefGroups& groups ) noexcept { return groups.size() > kDefTableCap; }
// A token the row PRINTS: every one up to the cap; above it, no K~n (the groups a cut table lists are the printed ones).
inline bool defTokenPrinted( const DefGroups& groups, std::uint32_t tok ) noexcept
{
    return !defTableCapped( groups ) || DefMark( tok & 3u ) != DefMark::Name;
}
inline void defTableMarkNamed( std::vector<char>& named, const DefGroups& groups, const RowDefTokens& tokens, std::size_t begin, std::size_t end )
{
    named.resize( groups.size(), 0 );
    for( std::size_t r = begin; r < end; ++r )
    {
        for( const std::uint32_t t : tokens.of( r ) )
        {
            named[ t >> 2 ] = char( named[ t >> 2 ] | ( defTokenPrinted( groups, t ) ? 1 : 0 ) );
        }
    }
}
inline DefTableListing defTableListing( const DefGroups& groups, const std::vector<char>& named )
{
    DefTableListing out;
    const bool      all = !defTableCapped( groups );
    for( std::size_t k = 0; k < groups.size(); ++k )
    {
        if( all || ( k < named.size() && named[k] ) )
        {
            out.listed.push_back( std::uint32_t( k ) );
        }
    }
    out.cut = !all;   // above the cap even a listing that names every group says defs_listed= (its rows print no K~n)
    return out;
}

// One token: K (1-based, the table's ix=) and its mark.
inline void defTokenTo( std::string& out, const DefGroups& groups, std::uint32_t tok )
{
    const std::uint32_t grp  = tok >> 2;
    const DefMark       mark = DefMark( tok & 3u );
    std::format_to( std::back_inserter( out ), "{}", grp + 1 );   // into the row's own buffer (review N1)
    if( mark == DefMark::Name )
    {
        out += "~n";
    }
    else if( mark == DefMark::Split )
    {
        out += "~s";
    }
    else if( grp < groups.primaryOfSpec.size() && groups.primaryOfSpec[grp] )
    {
        out += "~t";
    }
}
// A row's printed tokens appended to `out`, each wrapped in `quote` and joined by `sep` (XML/columnar: " " and "", the sites_at=
// convention; JSON: "," and "\""). Above the cap (R2) the K~n ties are not enumerated: the K/K~s/K~t tokens, then ONE bare
// `~n` when the row also has a by-name tie.
inline void defTokensTo( std::string& out, const DefGroups& groups, std::span<const std::uint32_t> toks, std::string_view sep, std::string_view quote )
{
    std::size_t printed = 0;
    bool        byName  = false;
    for( const std::uint32_t tok : toks )
    {
        if( !defTokenPrinted( groups, tok ) )
        {
            byName = true;
            continue;
        }
        out.append( printed++ ? sep : std::string_view() ).append( quote );
        defTokenTo( out, groups, tok );
        out.append( quote );
    }
    if( byName )
    {
        out.append( printed ? sep : std::string_view() ).append( quote ).append( "~n" ).append( quote );
    }
}
// Above the cap a row tied by name alone (or not at all) carries no of_def: its via="name" is the hedge (R2).
inline bool defRowUnprinted( const DefGroups& groups, const RowDefTokens& tokens, std::size_t row ) noexcept
{
    return defTableCapped( groups ) && tokens.strongest( row ) <= DefMark::Name;
}
// A row's of_def in one dialect: `open`, the printed tokens (`sep`, `quote`), `close`. A row with no printed token on a cut
// table carries no of_def at all (its via="name" is the hedge); below the cap every row keeps the attribute, as before.
inline std::string ofDefIn( const DefGroups& groups, const RowDefTokens& tokens, std::size_t row, std::string_view open, std::string_view sep,
                            std::string_view quote, char close )
{
    if( !groups.multi() || tokens.empty() || defRowUnprinted( groups, tokens, row ) )
    {
        return {};
    }
    std::string out( open );
    defTokensTo( out, groups, tokens.of( row ), sep, quote );
    out += close;
    return out;
}
inline std::string ofDefAttrXml( const DefGroups& groups, const RowDefTokens& tokens, std::size_t row )
{
    return ofDefIn( groups, tokens, row, " of_def=\"", " ", "", '"' );
}
inline std::string ofDefKeyJson( const DefGroups& groups, const RowDefTokens& tokens, std::size_t row )
{
    return ofDefIn( groups, tokens, row, ",\"of_def\":[", ",", "\"", ']' );
}
// The columnar of_def column's value for one row: the printed tokens space-separated (the sites_at column's convention).
inline std::string ofDefColumnValue( const DefGroups& groups, const RowDefTokens& tokens, std::size_t row )
{
    std::string text;
    if( !defRowUnprinted( groups, tokens, row ) )
    {
        defTokensTo( text, groups, tokens.of( row ), " ", "" );
    }
    return text;
}

// Q1: a row of a ONE-group answer whose every non-by-name edge to the selector is a split arm says so, in the map's per-edge
// vocabulary. Never on a multi-group answer (its tokens carry ~s), never on a by-name row (via="name" already hedges it).
inline bool rowSplitArm( const DefGroups& groups, const RowDefTokens& tokens, std::size_t row ) noexcept
{
    if( groups.multi() )
    {
        return false;   // its tokens carry ~s instead
    }
    return tokens.strongest( row ) == DefMark::Split;   // None when no tie was recorded
}
inline const char* splitArmAttrXml( bool on ) noexcept { return on ? " prov=\"split\"" : ""; }
inline const char* splitArmKeyJson( bool on ) noexcept { return on ? ",\"prov\":\"split\"" : ""; }

// The <def> rows (XML; the columnar form prints the same rows before its <cols>).
inline std::string defTableXml( const IngestResult& ing, const DefGroups& groups, const DefTableListing& listing, std::string_view rootPrefix )
{
    if( !groups.multi() )
    {
        return {};
    }
    // An empty listing is reachable (above the cap, a page past the last row names no group): it prints no rows, and the root's
    // defs_listed="0" says the table was cut to nothing.
    std::vector<char> esc;
    std::string       out;
    for( const std::uint32_t k : listing.listed )
    {
        const Symbol&          s   = ing.symbols[ groups.rep[k] ];
        const std::string_view raw = ing.files[ s.fileId ];
        const std::string_view rel = rootPrefix.empty() ? raw : sarif::rootRelativeUri( raw, rootPrefix );
        out += "<def ix=\"" + std::to_string( k + 1 ) + "\" t=\"" + symTag( s.kind ) + "\"";
        if( !s.scope.empty() )
        {
            out += " sc=\"" + std::string( escapeXml( s.scope, esc ) ) + "\"";
        }
        out += " p=\"" + std::string( escapeXml( rel, esc ) ) + ":" + std::to_string( s.line ) + "\"";
        out += groups.bodyless[k] ? " bodyless=\"1\"/>" : "/>";
    }
    return out;
}
// The CLI JSON dialect: "def_table":[{"ix","t","sc","p"[,"bodyless"]}] (the XML attribute names); `mcp` spells the MCP row
// vocabulary instead ({"ix","kind","scope","file","line"[,"bodyless"]}), the keys find_symbol's own rows use.
inline std::string defTableJson( const IngestResult& ing, const DefGroups& groups, const DefTableListing& listing, std::string_view rootPrefix, bool mcp )
{
    if( !groups.multi() )
    {
        return {};
    }
    std::string out = ",\"def_table\":[";
    for( std::size_t i = 0; i < listing.listed.size(); ++i )
    {
        const std::uint32_t    k   = listing.listed[i];
        const Symbol&          s   = ing.symbols[ groups.rep[k] ];
        const std::string_view raw = ing.files[ s.fileId ];
        const std::string_view rel = rootPrefix.empty() ? raw : sarif::rootRelativeUri( raw, rootPrefix );
        out += ( i ? ",{\"ix\":" : "{\"ix\":" ) + std::to_string( k + 1 );
        out += mcp ? ",\"kind\":\"" : ",\"t\":\"";
        out += symTag( s.kind );
        out += '"';
        if( !s.scope.empty() )
        {
            out += ( mcp ? ",\"scope\":\"" : ",\"sc\":\"" ) + jsonStr( s.scope ) + "\"";
        }
        out += mcp ? ",\"file\":\"" + jsonStr( rel ) + "\",\"line\":" + std::to_string( s.line )
                   : ",\"p\":\"" + jsonStr( rel ) + ":" + std::to_string( s.line ) + "\"";
        out += groups.bodyless[k] ? ",\"bodyless\":1}" : "}";
    }
    out += "]";
    if( listing.cut )
    {
        out += ",\"defs_listed\":" + std::to_string( listing.listed.size() );
    }
    return out;
}
inline std::string defsListedAttrXml( const DefGroups& groups, const DefTableListing& listing )
{
    return ( groups.multi() && listing.cut ) ? " defs_listed=\"" + std::to_string( listing.listed.size() ) + "\"" : std::string();
}

// An answer's groups once its ties are known: the untied groups (defGroupUntied) no row names are dropped ONLY when that leaves
// one group — the tmux/ninja prototype + definition answer stays one group with no table. When two or more groups would remain
// the table is printed anyway, and it claims to list every group defs= forms, so nothing is dropped: each untied declaration
// is listed (bodyless="1": "another function, or the tie is unproven"), as --edit-check counts it as a contract of its own
// (final review R1). Dropping: the rest renumbered in order, the tokens rewritten to the new numbers.
inline void defGroupsDropSilent( DefGroups& groups, RowDefTokens& tokens )
{
    if( !groups.multi() || std::none_of( groups.untied.begin(), groups.untied.end(), []( char c ) { return c != 0; } ) )
    {
        return;
    }
    std::vector<char> named( groups.size(), 0 );
    for( const std::uint32_t t : tokens.tok )
    {
        named[ t >> 2 ] = 1;
    }
    std::size_t left = 0;
    for( std::size_t k = 0; k < groups.size(); ++k )
    {
        left += ( groups.untied[k] && !named[k] ) ? 0 : 1;
    }
    if( left >= 2 )
    {
        return;   // a table is printed: every group is listed
    }
    std::vector<std::uint32_t> renum( groups.size(), UINT32_MAX );
    DefGroups                  kept;
    for( std::size_t k = 0; k < groups.size(); ++k )
    {
        if( groups.untied[k] && !named[k] )
        {
            continue;
        }
        renum[k] = std::uint32_t( kept.rep.size() );
        kept.rep.push_back( groups.rep[k] );
        kept.bodyless.push_back( groups.bodyless[k] );
        kept.primaryOfSpec.push_back( groups.primaryOfSpec[k] );
        kept.untied.push_back( groups.untied[k] );
    }
    kept.ofMatch.reserve( groups.ofMatch.size() );
    for( const std::uint32_t g : groups.ofMatch )
    {
        kept.ofMatch.push_back( renum[g] );   // UINT32_MAX: a silent group's member (no row ties to it)
    }
    for( std::uint32_t& t : tokens.tok )
    {
        ASSUME( renum[ t >> 2 ] != UINT32_MAX, "a group a row names is kept" );
        t = ( renum[ t >> 2 ] << 2 ) | ( t & 3u );
    }
    groups = std::move( kept );
}

// ── one answer's attribution, computed once ──────────────────────────────────────────────────────────────────────────
// What a 1-hop answer (callers / callees / safe-delete) carries. Computed only when it can say something: a multi-group
// selector, or a graph that holds split arms (Q1) or by-name edges (the rows' via="name" reads strongest() == Name).
struct OneHopAttribution
{
    DefGroups         groups;
    RowDefTokens      tokens;   // parallel to the rows; empty when nothing was computed
    std::vector<char> impl;     // lane L6: parallel to the rows, 1 = every edge joining the row to the matches is via="impl"; empty when none is

    bool nameOnly( std::size_t row ) const noexcept { return tokens.strongest( row ) == DefMark::Name; }   // None when none recorded
    bool splitArm( std::size_t row ) const noexcept { return rowSplitArm( groups, tokens, row ); }
    bool viaImpl( std::size_t row ) const noexcept { return row < impl.size() && impl[ row ] != 0; }
};
// lane L6: per row, whether every edge joining it to the matches (row → match toward the matches, match → row away) is the
// one-implementor edge (graph.h kProvImpl); empty when no row's is, so an answer without one keeps its bytes
inline std::vector<char> rowsViaImpl( const Graph& g, std::span<const NodeId> matches, std::span<const NodeId> rows, bool towardMatches )
{
    std::vector<char> out;
    if( g.outProv.empty() )
    {
        return out;
    }
    bool any = false;
    std::vector<char> impl( rows.size(), 0 );
    for( std::size_t i = 0; i < rows.size(); ++i )
    {
        std::size_t joined = 0, viaImpl = 0;
        for( const NodeId m : matches )
        {
            const std::size_t e = towardMatches ? edgeIndex( g, rows[ i ], m ) : edgeIndex( g, m, rows[ i ] );
            if( e != SIZE_MAX )
            {
                ++joined;
                viaImpl += g.outProv[ e ] == kProvImpl ? 1u : 0u;
            }
        }
        impl[ i ] = joined > 0 && viaImpl == joined ? 1 : 0;
        any       = any || impl[ i ] != 0;
    }
    if( any )
    {
        out.swap( impl );
    }
    return out;
}
inline OneHopAttribution attributeOneHopAnswer( const IngestResult& ing, const Graph& g, std::span<const NodeId> matches,
                                                std::span<const NodeId> rows, bool towardMatches )
{
    OneHopAttribution out;
    out.groups = defGroupsOf( ing, matches );
    if( out.groups.multi() || !g.outProv.empty() || !g.outNameOnly.empty() )
    {
        out.tokens = attributeOneHop( g, out.groups, matches, rows, towardMatches );
        defGroupsDropSilent( out.groups, out.tokens );
    }
    out.impl = rowsViaImpl( g, matches, rows, towardMatches );
    return out;
}

// What an --impact answer carries (CLI and MCP): the groups, and each reached node's ties through the chains of calls.
// Computed only on a multi-group selector — a one-group answer keeps its bytes (its rows' via="name" is provenCallerReach's).
struct ReachAttribution
{
    DefGroups               groups;
    std::span<const NodeId> reach;    // ascending (transitiveCallersDepth sorts it); the caller keeps the vector alive
    RowDefTokens            tokens;   // parallel to `reach`; empty unless groups.multi()

    std::size_t indexOf( NodeId n ) const noexcept
    {
        const auto [ first, last ] = std::equal_range( reach.begin(), reach.end(), n );
        return first == last ? SIZE_MAX : std::size_t( first - reach.begin() );
    }
    std::string ofDefXml( NodeId n ) const
    {
        const std::size_t i = indexOf( n );
        return i == SIZE_MAX ? std::string() : ofDefAttrXml( groups, tokens, i );
    }
    std::string ofDefJson( NodeId n ) const
    {
        const std::size_t i = indexOf( n );
        return i == SIZE_MAX ? std::string() : ofDefKeyJson( groups, tokens, i );
    }
    void markNamed( std::vector<char>& named, NodeId n ) const
    {
        if( const std::size_t i = indexOf( n ); i != SIZE_MAX )
        {
            defTableMarkNamed( named, groups, tokens, i, i + 1 );
        }
    }
};
inline ReachAttribution attributeReachAnswer( const IngestResult& ing, const Graph& g, std::span<const NodeId> seeds, std::span<const NodeId> reach )
{
    ReachAttribution out;
    out.groups = defGroupsOf( ing, seeds );
    out.reach  = reach;
    if( out.groups.multi() )
    {
        out.tokens = attributeReach( g, out.groups, seeds, reach, reach );
        defGroupsDropSilent( out.groups, out.tokens );
        if( !out.groups.multi() )
        {
            out.tokens = RowDefTokens{};   // one group left: the answer keeps its bytes (impact carries no one-group mark)
        }
    }
    return out;
}
// The <rf> rollup rows' of_def (the union of each listed file's reached symbols, strongest per group), rendered once for both
// dialects onto the rows the page shows, and the groups they name marked for the table.
template<class RollupT>
inline void attachRollupOfDef( RollupT& rollup, const IngestResult& ing, const ReachAttribution& a, std::vector<char>& named )
{
    if( !a.groups.multi() || rollup.rows.empty() )
    {
        return;
    }
    std::vector<std::uint32_t> files;
    for( std::size_t i = 0; i < rollup.shown; ++i )
    {
        files.push_back( rollup.rows[i].fileId );
    }
    const RowDefTokens fileTok = attributeFiles( ing, files, a.reach, a.tokens );
    defTableMarkNamed( named, a.groups, fileTok, 0, files.size() );
    for( std::size_t i = 0; i < rollup.shown; ++i )
    {
        rollup.rows[i].ofDefXml  = ofDefAttrXml( a.groups, fileTok, i );
        rollup.rows[i].ofDefJson = ofDefKeyJson( a.groups, fileTok, i );
    }
}

// ── --path endpoints ─────────────────────────────────────────────────────────────────────────────────────────────────
// from_p= / to_p= name "the definition the endpoint was bound to". With several definitions that claim needs a binding:
// the path's own start (from=) or a PROVEN hop into its end (to=). Unreached, or reached through a split arm or a by-name
// hop, the endpoint was not bound and the attribute is left out (the hop row's prov=/via= says why).
// `srcDefs` / `dstDefs` are endpointDefinitionCount's, not the raw match counts.
struct PathEndpointBinding
{
    bool from     = true;
    bool to       = true;
    bool splitHop = false;   // some hop's edge into it is a split arm (its row carries prov="split"; the legend clause rides)
};
// How many definitions an endpoint really names: its groups (a definition with its declarations is one), less the untied
// declarations (defGroupUntied) — a prototype the identity rule cannot prove is the same function is no second candidate here,
// exactly as it is silent on a 1-hop answer no row ties it to.
inline std::size_t candidateGroupCount( const DefGroups& groups )
{
    const std::size_t untied = std::size_t( std::count( groups.untied.begin(), groups.untied.end(), char( 1 ) ) );
    return std::max<std::size_t>( 1, groups.size() - untied );
}
inline std::size_t endpointDefinitionCount( const IngestResult& ing, std::span<const NodeId> defs )
{
    if( defs.size() < 2 )
    {
        return defs.size();
    }
    return candidateGroupCount( defGroupsOf( ing, defs ) );
}
// a hop row (i > 0) whose edge into it is a split arm (Q1: on every path, whatever the endpoints' defs=)
inline bool pathHopSplitArm( const Graph& g, std::span<const NodeId> path, std::size_t i ) noexcept
{
    return i > 0 && i < path.size() && edgeSplitArm( g, path[ i - 1 ], path[i] );
}
inline PathEndpointBinding pathEndpointBinding( const Graph& g, std::size_t srcDefs, std::size_t dstDefs, std::span<const NodeId> path ) noexcept
{
    PathEndpointBinding b;
    b.from = srcDefs <= 1 || !path.empty();
    for( std::size_t i = 1; i < path.size() && !b.splitHop; ++i )
    {
        b.splitHop = pathHopSplitArm( g, path, i );
    }
    if( dstDefs > 1 )
    {
        if( path.size() < 2 )
        {
            b.to = path.size() == 1;   // from= is to= (a zero-hop path binds it); unreached binds nothing
        }
        else
        {
            const std::size_t e = edgeIndex( g, path[ path.size() - 2 ], path.back() );
            b.to = e != SIZE_MAX && defMarkOfEdge( g, e ) == DefMark::Proven;
        }
    }
    return b;
}

// ── PATH-OWNERS (train 30): a --path / path_between hop row names a member by its owner, n="Owner.name" ────────────────
// A bare hop name made the reader re-resolve it: a path through A::go and B::go read n="go" n="go". QUALNAME-1 moved the rule to
// memberowner.h (MemberOwners) so every member row shares it — the owner is the parser's own scope, printed only when the index
// DEFINES its last segment as a member owner in the hop's language; a type hop, a C++ namespace-scope function, a function-local
// def (a closure) and a language whose defs carry no sc= (Java, C#, Swift, Kotlin `object`) keep bare rows — a floor, not a claim;
// a TS/JS method prints the class whose body holds it (memberowner.h). The separator is the language's own (langfacts.h memberSeparator: `Builder::Build`, `Application#run`, `Pattern.Match`).
// Per hop, the owner its row prints ("" = bare). Built only when some hop could print one (memberOwnerPossible): a free-function
// path costs nothing.
inline std::vector<std::string_view> pathHopOwners( const IngestResult& ing, std::span<const NodeId> path )
{
    std::vector<std::string_view> owner( path.size() );
    const bool anyScope = std::any_of( path.begin(), path.end(), [ & ]( NodeId id ) { return memberOwnerPossible( ing.symbols[ id ] ); } );
    if( !anyScope )
    {
        return owner;
    }
    const MemberOwners owners( ing );
    for( std::size_t i = 0; i < path.size(); ++i )
    {
        owner[i] = owners.ownerOf( ing.symbols[ path[i] ] );
    }
    ENSURES( owner.size() == path.size(), "one owner slot per hop" );
    return owner;
}
// THE hop rows of a --path answer — the CLI (stdout) and MCP path_between (its memstream) both write through this, so the two
// transports cannot drift (they were two copies of one loop). Row i's via="name" (FE-B), via="link" and anchor="missing" (a
// markdown link, #409) and prov="split" (attrib-multidef) read the edge INTO it; the first row is no hop.
inline void emitPathHopRows( std::FILE* out, const IngestResult& ing, const Graph& g, std::span<const NodeId> path,
                             std::span<const std::string_view> owners, bool singleRoot, std::string_view rootPrefix )
{
    EXPECTS( owners.size() == path.size(), "owners come from pathHopOwners( ing, path )" );
    std::vector<char> esc;
    for( std::size_t i = 0; i < path.size(); ++i )
    {
        const Symbol&          s     = ing.symbols[ path[i] ];
        const std::string_view rp    = singleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix ) : std::string_view( ing.files[ s.fileId ] );
        const std::string      name  = std::string( escapeXml( qualifiedMemberName( owners[i], s ), esc ) );   // QUALNAME-1: the language's separator
        const bool             hop   = i > 0;
        const std::string      mark  = std::string( viaEdgeAttr( hop && edgeNameOnly( g, path[ i - 1 ], path[i] ), hop && edgeIsLink( g, path[ i - 1 ], path[i] ) ) )
                                     + anchorMissAttr( hop && edgeAnchorMiss( g, path[ i - 1 ], path[i] ) );
        emitTo( out, "<s t=\"{}\" n=\"{}\" p=\"{}:{}\"{}{}{}/>", symTag( s.kind ), name, escapeXml( rp, esc ), s.line,
                mark, splitArmAttrXml( pathHopSplitArm( g, path, i ) ), viaImplAttr( hop && edgeViaImpl( g, path[ i - 1 ], path[i] ) ) );   // lane L6: via="impl"
    }
}

}   // namespace rw
