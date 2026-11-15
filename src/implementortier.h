#pragma once
// implementortier.h — IMPL-TIER: the implementors of a member, which is what a signature change breaks.
//
// A call graph answers "who calls this". A signature change on an interface, trait, abstract or virtual
// member breaks something else: every type that IMPLEMENTS it. Those are not callers, so no caller walk
// reaches them, and --impact's radius had no row for them at all. Measured on the 2026-11-15 file-grain
// gold set (docs/EVALS.md, the implementor tier's card): --impact recovered 24.2 % of the required files
// on dispatch-through-indirection targets against 94.0 % on concrete ones, and the missing files were the
// implementors themselves — `implementor: (*Deb).ConventionalFileName`, `override: def render_line`,
// `vtable slot :63; impl fn :27`, cell after cell, language after language.
//
// This is a PRIMITIVE, not a verb. The owner's instruction of 2026-11-15 was to propagate what the
// --impact work learns, and the same relation answers more than one question:
//   * --impact   (the registered band): what breaks if I change this signature.
//   * --edit-check: its whole job is "the contract changed — who is now incompatible?", and for a
//     bodyless member the incompatible parties ARE the implementors, not the callers.
//   * --callers on a pure virtual answers count="0" today (ninja's FileReader::ReadFile, measured), which
//     is true and useless: the implementors and their callers are what the asker wanted.
//   * --safe-delete: deleting a declaration orphans every override of it.
// Each of those is its own claim with its own band; this header is the one measurement they share, so no
// two of them can disagree about who implements what.
//
// TWO SCOPES, and the fixture test/ifacedispatchfix/cpp was chosen because it breaks a join that misses
// either one:
//   * OWNER-scoped — the implementors come from Graph::implementors (the extends/implements edges), walked
//     by graph.h legoImplementorClosure, the same closure --lego prints. `Hollow::hollowRun` is pure
//     virtual with NO implementor of Hollow while `Unrelated` and `Unrelated2` define their own
//     hollowRun(): a join that reads the NAME names them, and this one names neither.
//   * METHOD-scoped — only an implementor's member of the SEED's own name joins. `--lego=Widget` on
//     textual reports 137 implementors and exactly one of them defines `render_line`; a type-scoped join
//     would add 137 rows of noise for one row of signal, which is why the registered band names that cell
//     as the counter-example that detects it.
//
// What it does NOT claim: an implementor row is not a call edge and never enters a reach set or a caller
// count. It is a different relation and every consumer labels it as one.

#include "graph.h"   // Graph::implementors / implementorBound, legoImplementorClosure, ImplementorRow
#include "model.h"   // Symbol, scopeLastSegment, IngestResult

#include <algorithm>   // std::find — the row set is tiny and ordered, so a flat scan beats a set
#include <cstddef>
#include <span>
#include <string_view>
#include <vector>

namespace rw
{

struct ImplementorMembers
{
    std::vector<NodeId> rows;            // the implementors' own members of the seed's name, closure order
    std::size_t         owners   = 0;    // distinct owner types whose implementors were walked
    bool                armed    = false;   // a seed is a member of a type that HAS implementors
    bool                unproven = false;   // at least one row came through a name-only base edge (a hedge)
};

// The owner a MEMBER is contained in, for the languages that store no scope on one (TS/JS methods).
// Exactly memberowner.h's rule, which is graph.h's: the types of the member's own file in ascending
// signature-start order, and an owner only when precisely ONE class encloses it.
inline std::string_view containedOwnerNameOf( const IngestResult& ing, const Symbol& s )
{
    std::vector<NodeId> types;
    for( std::size_t id = 0; id < ing.symbols.size(); ++id )
    {
        const Symbol& t = ing.symbols[ id ];
        if( t.fileId == s.fileId && ( t.kind == SymKind::Class || t.kind == SymKind::Interface || isStructOrNamedType( t.kind ) ) )
        {
            types.push_back( NodeId( id ) );
        }
    }
    std::sort( types.begin(), types.end(),
               [ & ]( NodeId a, NodeId b ) { return ing.symbols[ a ].sigStartByte < ing.symbols[ b ].sigStartByte; } );
    const ContainedOwners owners = containedOwnersOf( ing, types, s );
    return ( owners.chain.size() == 1 && !owners.nested ) ? owners.chain.front() : std::string_view();
}

// ONE rule for "which type owns this member", used on both sides of the join: the stored scope where the
// language keeps one, else containment. Applying it to the owner but not to the candidates is a bug this
// lane had for one build: every TypeScript interface member found its owner and then matched no
// implementor, because the implementors' own methods store no scope either.
inline std::string_view memberOwnerNameOf( const IngestResult& ing, const Symbol& s )
{
    const std::string_view stored = scopeLastSegment( s.scope );
    return stored.empty() ? containedOwnerNameOf( ing, s ) : stored;
}

// The owner type of a member symbol, as a NodeId of the implementors map — kNoNode when the symbol has no
// stored scope (Java, C#, Swift store none: memberowner.h says so, and a floor is not a claim), when its
// owner's last segment names no indexed type, or when that type has no implementors. The map's KEYS are
// type nodes, so this walks only types that already have an implementor list rather than every symbol.
inline NodeId implementorOwnerOf( const IngestResult& ing, const Graph& g, NodeId member )
{
    if( std::size_t( member ) >= ing.symbols.size() )
    {
        return kNoNode;
    }
    std::string_view owner = memberOwnerNameOf( ing, ing.symbols[ member ] );
    if( owner.empty() )
    {
        return kNoNode;   // no stored scope and no single enclosing class: a floor, not an owner
    }
    for( std::size_t base = 0; base < g.implementors.size(); ++base )
    {
        if( g.implementors[ base ].empty() || base >= ing.symbols.size() )
        {
            continue;
        }
        if( ing.symbols[ base ].name == owner )
        {
            return NodeId( base );
        }
    }
    return kNoNode;
}

// The members named `name` that the implementors of `ownerBase` own, in closure order. The closure is
// graph.h's — proven extends edges walked, a name-only edge's row hedged and not walked — so this tier
// inherits --lego's provenance rather than inventing a second notion of "implements".
inline void appendImplementorMembers( const IngestResult& ing, const Graph& g, NodeId ownerBase,
                                      std::string_view name, NodeId excludeSeed, ImplementorMembers& out )
{
    const bool          seedArityExact = std::size_t( excludeSeed ) < ing.symbols.size() && ing.symbols[ excludeSeed ].arityExact != 0;
    const std::uint16_t seedParams     = std::size_t( excludeSeed ) < ing.symbols.size() ? ing.symbols[ excludeSeed ].params : 0;
    const LegoClosure closure = legoImplementorClosure( g.implementors, g.implementorBound, ownerBase );
    for( const ImplementorRow& row : closure.rows )
    {
        if( std::size_t( row.id ) >= ing.symbols.size() )
        {
            continue;
        }
        const std::string_view implName = ing.symbols[ row.id ].name;
        for( std::size_t sym = 0; sym < ing.symbols.size(); ++sym )
        {
            const Symbol& s = ing.symbols[ sym ];
            if( s.name != name || NodeId( sym ) == excludeSeed )
            {
                continue;   // the cheap test first: most symbols fail on the name
            }
            if( memberOwnerNameOf( ing, s ) != implName )
            {
                continue;   // METHOD-scoped: an implementor's member of ANOTHER name is not this contract
            }
            // ARITY: an OVERLOAD is not an override. The fixture's DryRunCommandRunner declares both
            // StartCommand( Edge* ) and StartCommand( Edge*, int ); changing the first one's signature does
            // not break the second, so claiming it would be a false relation of exactly the kind the gold
            // sets call a "wrong item". Only skip when BOTH arities are call-comparable (arityExact), which
            // is the one case where a difference is a fact rather than an unknown.
            if( seedArityExact && s.arityExact != 0 && s.params != seedParams )
            {
                continue;
            }
            if( std::find( out.rows.begin(), out.rows.end(), NodeId( sym ) ) == out.rows.end() )
            {
                out.rows.push_back( NodeId( sym ) );
                out.unproven = out.unproven || row.byName;
            }
        }
    }
}

// The whole tier for one answer's matched definitions. `seeds` are the verb's own resolved defs.
// DECL-OVER-DEF: an implementor may carry BOTH a declaration and an out-of-line definition of the same
// member (the fixture's RealCommandRunner::StartCommand is declared at runners.cc:5 and defined at :9).
// They are one method, so one row: the bodied one, by the house test (model.h isDefinitionNotDeclaration,
// the same rule graph.h's decl/def collapse and lexical.h's tiebreak use). Counting both would inflate
// implementors= and read as two things to change.
inline void collapseDeclOverDef( const IngestResult& ing, std::vector<NodeId>& rows )
{
    std::vector<NodeId> kept;
    kept.reserve( rows.size() );
    for( const NodeId id : rows )
    {
        const Symbol& s     = ing.symbols[ id ];
        bool          drop  = false;
        for( NodeId& other : kept )
        {
            const Symbol& k = ing.symbols[ other ];
            if( k.name != s.name || memberOwnerNameOf( ing, k ) != memberOwnerNameOf( ing, s ) || k.fileId != s.fileId )
            {
                continue;
            }
            if( !isDefinitionNotDeclaration( k ) && isDefinitionNotDeclaration( s ) )
            {
                other = id;   // the bodied one wins the pair
            }
            drop = true;
            break;
        }
        if( !drop )
        {
            kept.push_back( id );
        }
    }
    rows.swap( kept );
}

inline ImplementorMembers implementorMembersOf( const IngestResult& ing, const Graph& g, std::span<const NodeId> seeds )
{
    ImplementorMembers out;
    if( g.implementors.empty() )
    {
        return out;
    }
    for( const NodeId seed : seeds )
    {
        const NodeId ownerBase = implementorOwnerOf( ing, g, seed );
        if( ownerBase == kNoNode )
        {
            continue;
        }
        out.armed = true;
        ++out.owners;
        appendImplementorMembers( ing, g, ownerBase, ing.symbols[ seed ].name, seed, out );
    }
    collapseDeclOverDef( ing, out.rows );
    return out;
}

// ── rendering: present-only, so an answer with no implementor tier is byte-identical to one before it ──
// Every helper returns "" when the tier named nothing. That is the registered Band 4 requirement and the
// house idiom (impactRingAttrXml, valueRefsCountAttrXml): absence is not an empty element.

inline std::string implementorsAttrXml( const ImplementorMembers& im )
{
    return im.rows.empty() ? std::string()
                           : " implementors=\"" + std::to_string( im.rows.size() ) + "\""
                                 + ( im.unproven ? " implementors_by_name=\"1\"" : "" );
}

inline std::string implementorsKeyJson( const ImplementorMembers& im )
{
    return im.rows.empty() ? std::string()
                           : ",\"implementors\":" + std::to_string( im.rows.size() )
                                 + ( im.unproven ? ",\"implementors_by_name\":1" : "" );
}

// The rows themselves. `<impl>` and not `<s>`: an implementor is not a caller, it is in no reach set and
// in no count= of callers, and the element name says so before any attribute does.
inline std::string implementorMembersXml( const IngestResult& ing, const ImplementorMembers& im,
                                          bool singleRoot, std::string_view rootPrefix )
{
    std::string       out;
    std::vector<char> esc;
    for( const NodeId id : im.rows )
    {
        const Symbol&          s  = ing.symbols[ id ];
        const std::string_view rp = singleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix )
                                               : std::string_view( ing.files[ s.fileId ] );
        out += "<impl t=\"" + std::string( symTag( s.kind ) ) + "\" n=\"" + std::string( escapeXml( s.name, esc ) ) + "\" p=\""
             + std::string( escapeXml( rp, esc ) ) + ":" + std::to_string( s.line ) + "\" via=\"implementor\"/>";
    }
    return out;
}

inline std::string implementorMembersJson( const IngestResult& ing, const ImplementorMembers& im,
                                           bool singleRoot, std::string_view rootPrefix )
{
    if( im.rows.empty() )
    {
        return std::string();
    }
    std::string out = ",\"impl\":[";
    for( std::size_t i = 0; i < im.rows.size(); ++i )
    {
        const Symbol&          s  = ing.symbols[ im.rows[ i ] ];
        const std::string_view rp = singleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix )
                                               : std::string_view( ing.files[ s.fileId ] );
        out += std::string( i == 0 ? "" : "," ) + "{\"t\":\"" + std::string( symTag( s.kind ) ) + "\",\"n\":\"" + jsonStr( s.name )
             + "\",\"p\":\"" + jsonStr( std::string( rp ) + ":" + std::to_string( s.line ) ) + "\",\"via\":\"implementor\"}";
    }
    return out + "]";
}

// The legend sentence, carried only by an answer that has a row (absent otherwise: byte-identical).
inline constexpr std::string_view kImplementorTierLegend =
    "implementors=K (absent when 0) counts <impl t= n= p= via=\"implementor\"> rows: the members of this owner's "
    "IMPLEMENTORS that share the asked member's name — what a signature change breaks. An implementor is NOT a caller: "
    "these rows are in no reach set, in no count= of callers, and no edge claim is made about them. The implements/extends "
    "edges are --lego's own closure, so implementors_by_name=1 says at least one row was reached through a base bound by "
    "NAME only (a hedge, not a proven edge). A member whose owner declares no implementors emits no attribute and no row. ";

inline std::string_view implementorTierLegend( bool on ) noexcept
{
    return on ? kImplementorTierLegend : std::string_view();
}

}   // namespace rw
