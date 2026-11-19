#pragma once
// contractseed.h — BODILESS-SEED: a selector that names a CONTRACT method (an interface or abstract member with no body of
// its own) seeds the graph verbs from what a call through that contract runs: its implementors' same-named bodied methods.
//
// THE DEFECT. A call through an interface-typed receiver (`this.router.match( m, p )`, Go `p.Package( info, f )`) never
// draws an edge to the interface's bodiless signature: the resolver binds a call to a BODY (ifacedispatch.h), or declines it
// with the implementors' bodies as its candidates. So the contract method itself had no caller, no reach and no use, and
// hono `--impact=Router.match` answered reaches="0" beside 23 importers, `--safe-delete=Router.match` said risk="none-found",
// and Go `--impact=Packager.Package` answered reaches="0" while the bare `--impact=Package` reached 100 symbols. A confident
// zero on the one spelling an agent copies from the source.
//
// THE RULE. A match is a contract seed when it is a callable with no body (its signature end is its end) DECLARED inside an
// owner type T (the innermost class-like type whose span holds it; a C prototype outside any type is never one, even when its
// scope names a type) and T owns no bodied method of that name (a body's owner is its container, else the type its scope
// names: same file, same package directory for a package-scoped language, or the only type of that name). Its implementors are T's
// --lego closure (graph.h legoImplementorClosure over the extends/implements map); for a structurally typed language whose
// map lists none (Go), the types whose bodied methods cover every name T declares (by NAME: arity and signatures unread, so
// a floor of the set and a hedge on each member). The widened seed list is the matches, then those implementors' bodied
// methods of the seed's name, ascending, each once. The root discloses it as impls=K (graphlegend.h implsAttrXml): K bodied
// methods joined defs= as seeds; impls="0" says the contract has no implementor in the tree, so the zero beside it is none
// found (an implementor outside the tree, a macro-made one or an object literal may exist).
//
// ONE HELPER for --impact, --callers, --safe-delete and --path (and the MCP twins of impact, callers and path), so the four
// verbs cannot disagree on what a contract seed reaches. A selector with no bodiless callable among its matches returns them
// untouched (contracts == 0), so every other answer keeps its bytes; so does one whose matches already held every implementor
// body and some bodied def (a bare name): contracts and impls read 0 there, since the seeds are unchanged.

#include "graph.h"             // Graph::implementors / implementorBound, legoImplementorClosure
#include "graphlegend.h"       // implsFieldOrEmpty / implsLegend — the path root's from_impls=/to_impls= and its legend clause
#include "langfacts.h"         // structuralTyping — the method-set rule's language column
#include "infra/sortutil.h"     // svLess — the byte order every string_view sort here uses (portablebuildcheck #6)
#include "model.h"
#include "receiverevidence.h"  // memberOwnerRuleOf — a scoped member's owner by package directory (Go)

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

struct ContractSeeds
{
    std::vector<NodeId> seeds;           // the matches as resolved, then the added implementor bodies (ascending ids, none a match)
    std::size_t         contracts = 0;   // matches that are a contract seed; 0 = nothing widened, the matches are returned as they are
    std::size_t         impls     = 0;   // implementor bodies in `seeds` (added, or already among the matches): the root's impls=
};

namespace contractseed_detail
{
// A type a method can belong to is graph.h namespaceCompatible's Type rule (a class, an interface, a struct or a named type: Go
// `type N int` owns methods too); a callable is ReceiverEvidence::callableKind's (a method or a function).

// a declaration with no body, by the house test (model.h isDefinitionNotDeclaration): Ruby has no declarations, so its empty
// `def hook; end` is a definition and never a contract
inline bool bodiless( const Symbol& s ) noexcept
{
    return !isDefinitionNotDeclaration( s );
}

// Owners by containment and by scope, for one widening: the owner types of the files the members live in, and the owner types
// named like a member's scope. Built over two passes of the symbol table, only for the members a contract widening reads.
class OwnerIndex
{
public:
    OwnerIndex( const IngestResult& ing, std::span<const NodeId> members ) : ing_( ing )
    {
        std::vector<char>             memberFile( ing.files.size(), 0 );   // indexed by file id
        std::vector<std::string_view> scopes;
        for( const NodeId m : members )
        {
            memberFile[ ing.symbols[ m ].fileId ] = 1;
            if( const std::string_view sc = scopeLastSegment( ing.symbols[ m ].scope ); !sc.empty() )
            {
                scopes.push_back( sc );
            }
        }
        std::ranges::sort( scopes, sortutil::svLess );
        const auto [ dupFirst, dupLast ] = std::ranges::unique( scopes );
        scopes.erase( dupFirst, dupLast );
        for( const Symbol& t : ing.symbols )
        {
            if( !namespaceCompatible( RefRole::Type, t.kind ) )
            {
                continue;
            }
            if( memberFile[ t.fileId ] != 0 )
            {
                inFiles_.push_back( t.id );
            }
            if( std::binary_search( scopes.begin(), scopes.end(), std::string_view( t.name ), sortutil::svLess ) )
            {
                named_.push_back( t.id );
            }
        }
    }

    // `m`'s owner type: the innermost owner type whose span holds it (same file), else the one its scope names — in its file, else
    // (a package-scoped language) in its package directory, else the only one of that name in its language; kNoNode otherwise
    NodeId ownerOf( NodeId m ) const
    {
        if( const NodeId held = containerOf( m ); held != kNoNode )
        {
            return held;
        }
        return namedByScope( m );
    }

    // the innermost owner type whose span holds `m` (same file); kNoNode when none does. A contract is DECLARED inside its type
    // (an interface member, a pure virtual, a Go interface method spec), so this is the contract's owner; the scope route is only
    // for a body declared outside its type (a Go receiver method, a C++ out-of-line definition)
    NodeId containerOf( NodeId m ) const
    {
        // graph.h typeEnclosesMember, and strictly: the type starts BEFORE the member and ends after its whole signature (a
        // bodiless member ends at it), so a type spelled inside the member's own declaration (C `static enum E f( int );`
        // indexes `enum E` as a type) never holds it
        const Symbol&       s = ing_.symbols[ m ];
        std::vector<NodeId> holders;
        std::ranges::copy_if( inFiles_, std::back_inserter( holders ), [ & ]( NodeId t ) {
            const Symbol& ty = ing_.symbols[ t ];
            return t != m && typeEnclosesMember( ty, s ) && ty.sigStartByte < s.sigStartByte && s.sigEndByte <= ty.endByte;
        } );
        // the innermost: the latest start (a nested type starts inside its outer one), the higher id on a tie
        return holders.empty() ? kNoNode : std::ranges::max( holders, {}, [ & ]( NodeId t ) { return std::pair( ing_.symbols[ t ].sigStartByte, t ); } );
    }

    // the owner type `m`'s scope names: in its file, else (a package-scoped language) in its package directory, else the only
    // one of that name in its language; kNoNode otherwise
    NodeId namedByScope( NodeId m ) const
    {
        const Symbol&          s  = ing_.symbols[ m ];
        const std::string_view sc = scopeLastSegment( s.scope );
        if( sc.empty() )
        {
            return kNoNode;
        }
        NodeId sameDir = kNoNode, only = kNoNode;
        std::size_t sameDirCount = 0, count = 0;
        for( const NodeId t : named_ )
        {
            const Symbol& ty = ing_.symbols[ t ];
            if( ty.name != sc || ty.lang != s.lang )
            {
                continue;
            }
            if( ty.fileId == s.fileId )
            {
                return t;
            }
            ++count;
            only = t;
            if( includerDir( ing_.files[ ty.fileId ] ) == includerDir( ing_.files[ s.fileId ] ) )
            {
                ++sameDirCount;
                sameDir = t;
            }
        }
        if( memberOwnerRuleOf( s.lang ) == MemberOwnerRule::PackageDir )
        {
            return sameDirCount == 1 ? sameDir : kNoNode;
        }
        return count == 1 ? only : kNoNode;
    }

    // another DEFINED owner type (not a forward declaration) of `type`'s name and language, among the types named like a member's
    // scope: an out-of-line body scoped by that name may be the namesake's
    bool definedNamesakeOf( NodeId type ) const
    {
        const Symbol& ty = ing_.symbols[ type ];
        return std::ranges::any_of( named_, [ & ]( NodeId t ) {
            const Symbol& o = ing_.symbols[ t ];
            return t != type && o.name == ty.name && o.lang == ty.lang && !bodiless( o );
        } );
    }

private:
    const IngestResult& ing_;
    std::vector<NodeId> inFiles_;   // owner types of the members' files
    std::vector<NodeId> named_;     // owner types named like a member's scope
};

// Can body `b` be declaration `decl`'s own definition? Not when both carry a fixed, call-comparable arity and the two differ
// (`virtual void send( int ) = 0` beside a concrete `void send()`: another overload, CodeRabbit #665); by name otherwise.
inline bool sameOverload( const Symbol& decl, const Symbol& b ) noexcept
{
    return !( decl.arityExact != 0 && b.arityExact != 0 && decl.params != b.params );
}

// The structural rule (a language whose types implement an interface by having its methods, and whose extends/implements map
// lists no implementor of T): the owner types whose BODIED methods cover every method name T declares. By name only.
inline std::vector<NodeId> methodSetImplementors( const IngestResult& ing, NodeId type )
{
    const Symbol&                 t = ing.symbols[ type ];
    std::vector<NodeId>           members;   // T's own bodiless methods (scope-named or contained)
    std::vector<std::string_view> names;
    std::vector<NodeId>           bodied;    // the bodied callables of the same language carrying one of those names
    for( const Symbol& s : ing.symbols )
    {
        if( ReceiverEvidence::callableKind( s.kind ) && bodiless( s ) && s.lang == t.lang && s.fileId == t.fileId
            && ( scopeLastSegment( s.scope ) == t.name || ( t.sigStartByte <= s.sigStartByte && s.endByte <= t.endByte ) ) )
        {
            members.push_back( s.id );
            names.push_back( s.name );
        }
    }
    sortutil::sortUnique( names, sortutil::svLess );
    if( names.empty() )
    {
        return {};
    }
    for( const Symbol& s : ing.symbols )
    {
        if( ReceiverEvidence::callableKind( s.kind ) && !bodiless( s ) && s.lang == t.lang && std::binary_search( names.begin(), names.end(), std::string_view( s.name ), sortutil::svLess ) )
        {
            bodied.push_back( s.id );
        }
    }
    const OwnerIndex                                   owners( ing, bodied );
    std::vector<std::pair<NodeId, std::string_view>>   covered;   // ( owner, name ) once each
    for( const NodeId b : bodied )
    {
        if( const NodeId o = owners.ownerOf( b ); o != kNoNode && o != type )
        {
            covered.emplace_back( o, ing.symbols[ b ].name );
        }
    }
    sortutil::sortUnique( covered, []( const auto& a, const auto& b ) {
        return a.first != b.first ? a.first < b.first : sortutil::svLess( a.second, b.second );
    } );
    std::vector<NodeId> out;
    for( std::size_t i = 0; i < covered.size(); )
    {
        std::size_t j = i;
        while( j < covered.size() && covered[ j ].first == covered[ i ].first )
        {
            ++j;
        }
        if( j - i == names.size() )
        {
            out.push_back( covered[ i ].first );
        }
        i = j;
    }
    return out;
}

// T's implementor types: its --lego closure, else (structural typing, none listed) the method-set rule; ascending ids
inline std::vector<NodeId> implementorTypes( const IngestResult& ing, const Graph& g, NodeId type )
{
    std::vector<NodeId> out;
    for( const ImplementorRow& row : legoImplementorClosure( g.implementors, g.implementorBound, type ).rows )
    {
        out.push_back( row.id );
    }
    if( out.empty() && langFacts( ing.symbols[ type ].lang ).structuralTyping )
    {
        out = methodSetImplementors( ing, type );
    }
    std::sort( out.begin(), out.end() );
    return out;
}
}   // namespace contractseed_detail

// The seeds a graph verb walks for `matches` (contractseed.h's header states the rule). O(matches) when no match is a bodiless
// callable; otherwise a few passes of the symbol table per distinct contract name.
inline ContractSeeds widenContractSeeds( const IngestResult& ing, const Graph& g, std::vector<NodeId> matches )
{
    using namespace contractseed_detail;
    ContractSeeds out;
    std::vector<NodeId> contracts;
    for( const NodeId m : matches )
    {
        if( m < ing.symbols.size() && ReceiverEvidence::callableKind( ing.symbols[ m ].kind ) && bodiless( ing.symbols[ m ] ) )
        {
            contracts.push_back( m );
        }
    }
    out.seeds = std::move( matches );
    std::vector<NodeId> implBodies;
    for( const NodeId c : contracts )
    {
        std::vector<NodeId> named = resolveAllByName( ing, ing.symbols[ c ].name );   // the callables of its name, bodied or not
        std::erase_if( named, [ & ]( NodeId n ) { return !ReceiverEvidence::callableKind( ing.symbols[ n ].kind ); } );
        const OwnerIndex          owners( ing, named );
        const NodeId              type = owners.containerOf( c );
        if( type == kNoNode )
        {
            continue;   // declared outside any type (a C prototype, even one whose scope names a type): no contract
        }
        // its own body: a bodied method the type holds, or one whose scope NAMES the type (a C++ out-of-line definition in
        // another file, read by name because a forward `class T;` makes the type's name ambiguous to ownerOf) while no other
        // DEFINED type carries that name: the index keeps a C++ scope's last segment only (`other::Port::send` is sc="Port"),
        // so beside a defined namesake the name is no evidence the body is this type's (CodeRabbit #665)
        const Symbol& ty      = ing.symbols[ type ];
        const bool    ownBody = std::ranges::any_of( named, [ & ]( NodeId n ) {
            const Symbol& b = ing.symbols[ n ];
            return !bodiless( b ) && sameOverload( ing.symbols[ c ], b )
                   && ( owners.ownerOf( n ) == type || ( b.lang == ty.lang && scopeLastSegment( b.scope ) == ty.name && !owners.definedNamesakeOf( type ) ) );
        } );
        if( ownBody )
        {
            continue;   // a declaration beside its own definition (C++ out-of-line, a TS overload signature): not a contract
        }
        ++out.contracts;
        const std::vector<NodeId> impls = implementorTypes( ing, g, type );
        for( const NodeId n : named )
        {
            const Symbol& s = ing.symbols[ n ];
            if( !bodiless( s ) && s.lang == ing.symbols[ c ].lang && std::binary_search( impls.begin(), impls.end(), owners.ownerOf( n ) ) )
            {
                implBodies.push_back( n );
            }
        }
    }
    sortutil::sortUnique( implBodies );
    out.impls = implBodies.size();
    const std::size_t   matchCount = out.seeds.size();
    std::vector<NodeId> sortedSeeds( out.seeds );
    std::sort( sortedSeeds.begin(), sortedSeeds.end() );
    for( const NodeId b : implBodies )
    {
        if( !std::binary_search( sortedSeeds.begin(), sortedSeeds.end(), b ) )
        {
            out.seeds.push_back( b );
        }
    }
    // Disclose only an answer the widening changed or one that stands on contracts alone. A selector that already matched
    // every implementor body (a bare `match` beside its interface member) walks the same seeds as before: no impls=, so
    // its bytes stay main's.
    if( out.seeds.size() == matchCount && out.contracts < matchCount )
    {
        out.contracts = 0;
        out.impls     = 0;
    }
    ENSURES( out.contracts > 0 || out.impls == 0, "only a contract seed adds implementor bodies" );
    return out;
}

}   // namespace rw
