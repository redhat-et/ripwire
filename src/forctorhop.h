#pragma once
// forctorhop.h — the OWNER'S CONSTRUCTOR on the top method row of a compact-route --for answer (lane peer-s, card OWNER-CTOR-HOP).
//
// WHY. A question about a method often turns on state its class's constructor set up: koa's per-request ctx is built by
// Application.createContext (r=1) from `this.ctxStorage`, which the constructor fills with getAsyncLocalStorage(options). The
// constructor rode as a bare signature row (r=13), so the call that answers the question was one hop away and never printed.
// Mechanism learned from code-review-graph's traverse_graph_func (MIT: a breadth-first walk from the top seed over every edge
// kind, containment included, names only) — no code taken; this takes exactly one containment hop and one call hop.
//
// WHAT. When the answer's r=1 row is a METHOD (or a function whose span lies inside a class of its file) and its innermost
// enclosing class/struct (same file, span containment) defines a constructor by its language's spelling (JS/TS `constructor`,
// Python `__init__`, Ruby `initialize`, PHP `__construct`, Java/C#/C++/Kotlin/Dart/Swift a member named as the class or `init`),
// the r=1 row gains
//   ctor_l="N"         the constructor's line,
//   ctor_calls="a,b"   the distinct callee names the index resolved from the constructor (up to kForCtorHopCap, edge order),
//   ctor_calls_more=   callee names not listed (absent when none was cut).
// Names only: a callee is a resolved call edge, never a claim that it answers the question. NOT the constructor's field writes
// (`this.f =`): a Write-reference reading matched none on the JS and Python gate fixtures, so a field list is unproven here —
// a later card.
//
// NOT ON: an r=1 row that is not a callable member; a class with no constructor; a constructor that IS the r=1 row; a constructor
// whose text the answer already carries (the fold or the body slot serves it or an enclosing body); a constructor with no
// resolved callee. Same posture as mem= (formembers.h). RIPWIRE_NO_CTOR_HOP (any value) turns it off.

#include "forfold.h"            // fold_detail::overlapsServed / spanInside — the fold's own containment reading
#include "formembers.h"         // MemberNamesServed
#include "graph.h"
#include "model.h"
#include "receiverevidence.h"   // ReceiverEvidence::classLike / callableKind
#include "infra/sortutil.h"      // svLess

#include <algorithm>
#include <cstddef>
#include <cstdlib>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::ptrdiff_t kForCtorHopCap = 16;   // callee names listed on ctor_calls=; the rest counted in ctor_calls_more=
static_assert( kForCtorHopCap == 16, "kForCtorHopLegend states the cap: move the sentence with the constant" );

inline bool forCtorHopOn()
{
    return std::getenv( "RIPWIRE_NO_CTOR_HOP" ) == nullptr;
}

inline constexpr std::string_view kForCompactCtorHopLegend =
    "; d ctor_l= ctor_calls= the r=1 method's owner constructor: its line, its resolved callee names (names only), ctor_calls_more= cut";
inline constexpr std::string_view kForCtorHopLegend =
    "; ctor_l= on the r=1 method row: the line of its enclosing class's constructor, ctor_calls= up to 16 callee names the index "
    "resolved from that constructor (ctor_calls_more= the names not listed), names only, not a claim they answer";
static_assert( kForCompactCtorHopLegend.find( ';', 1 ) == std::string_view::npos && kForCtorHopLegend.find( ';', 1 ) == std::string_view::npos,
               "one clause each: a ';' inside would split it (the legend's clause separator)" );

namespace ctor_detail
{
// The constructor spelling of `lang` for a class named `owner` (W: keyword spellings are per language).
inline bool isCtorName( Lang lang, std::string_view name, std::string_view owner ) noexcept
{
    switch( lang )
    {
        case Lang::JavaScript: case Lang::TypeScript: return name == "constructor";
        case Lang::Python:                            return name == "__init__";
        case Lang::Ruby:                              return name == "initialize";
        case Lang::Php:                               return name == "__construct";
        case Lang::Swift:                             return name == "init";
        case Lang::Java: case Lang::CSharp: case Lang::Cpp: case Lang::Kotlin: case Lang::Dart:
            return !owner.empty() && name == owner;
        default:                                      return false;
    }
}
// The innermost class/struct of `id`'s file whose span holds it; kNoNode when none does.
inline NodeId innermostOwner( const IngestResult& ing, NodeId id, const std::vector<NodeId>& fileClasses )
{
    NodeId best = kNoNode;
    for( const NodeId c : fileClasses )
    {
        if( c != id && fold_detail::spanInside( ing, id, c ) && ( best == kNoNode || fold_detail::spanInside( ing, c, best ) ) )
        {
            best = c;
        }
    }
    return best;
}
}   // namespace ctor_detail

// THE SPLICE: on the first <d> row (shownIds[0]) append ` ctor_l= ctor_calls= [ctor_calls_more=]`. Returns the
// bytes added (0: `sigs` untouched).
inline std::size_t spliceCtorHop( std::string& sigs, const IngestResult& ing, const Graph& g, const std::vector<NodeId>& shownIds,
                                  const MemberNamesServed& served )
{
    using namespace ctor_detail;
    if( shownIds.empty() || shownIds[0] >= ing.symbols.size() )
    {
        return 0;
    }
    const NodeId  top = shownIds[0];
    const Symbol& ts  = ing.symbols[top];
    if( !ReceiverEvidence::callableKind( ts.kind ) )
    {
        return 0;
    }
    std::vector<NodeId> fileClasses;
    for( NodeId id = 0; id < ing.symbols.size(); ++id )
    {
        if( ing.symbols[id].fileId == ts.fileId && ReceiverEvidence::classLike( ing.symbols[id].kind ) )
        {
            fileClasses.push_back( id );
        }
    }
    const NodeId owner = innermostOwner( ing, top, fileClasses );
    if( owner == kNoNode )
    {
        return 0;
    }
    NodeId ctor = kNoNode;
    for( NodeId id = 0; id < ing.symbols.size(); ++id )
    {
        const Symbol& s = ing.symbols[id];
        if( s.fileId == ts.fileId && ReceiverEvidence::callableKind( s.kind ) && isCtorName( s.lang, s.name, ing.symbols[owner].name )
            && innermostOwner( ing, id, fileClasses ) == owner && s.endByte > s.sigEndByte )
        {
            ctor = id;   // the first defining constructor by id (source order); an overload set names its first
            break;
        }
    }
    if( ctor == kNoNode || ctor == top || fold_detail::overlapsServed( ing, ctor, served.bodies, /*orHolds=*/false ) )
    {
        return 0;
    }
    // The callee names, DISTINCT and in NAME order BEFORE the cap: the 16 kept are a function of the constructor's own callees,
    // not of which file defines each (target ids follow path order), and a name two definitions share is cut or counted once.
    std::vector<std::string_view> names;
    for( std::uint32_t e = g.outOff[ctor]; e < g.outOff[ctor + 1]; ++e )
    {
        const NodeId t = g.outTargets[e];
        if( t < ing.symbols.size() && !ing.symbols[t].name.empty() )
        {
            names.emplace_back( ing.symbols[t].name );
        }
    }
    std::ranges::sort( names, sortutil::svLess );   // the byte order operator< defines; the DEFAULT comparator aborts the Linux sanitizer leg (portablebuildcheck #6b)
    names.erase( std::unique( names.begin(), names.end() ), names.end() );
    std::vector<std::string_view> calls;
    std::size_t                   more = 0;
    for( const std::string_view n : names )
    {
        if( n.find( ',' ) != std::string_view::npos || std::ssize( calls ) >= kForCtorHopCap )
        {
            ++more;   // cut by the count, or a name the list's comma would split: counted, never silent
            continue;
        }
        calls.push_back( n );
    }
    if( calls.empty() )
    {
        return 0;
    }
    constexpr std::string_view kOpen = "<d l=\"";
    const std::size_t head = sigs.find( kOpen );
    const std::size_t next = head == std::string::npos ? std::string::npos : sigs.find( kOpen, head + kOpen.size() );
    const std::size_t close = head == std::string::npos ? std::string::npos : sigs.find( '>', head );
    if( head == std::string::npos || close == std::string::npos || ( next != std::string::npos && close > next ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "no row carries ctor_l=: the answer is the one without the constructor hop",
                  "spliceCtorHop: the first <sigs> row did not parse" );
        return 0;
    }
    std::vector<char> esc;
    const auto join = [ & ]( const std::vector<std::string_view>& v )
    {
        std::string s;
        for( std::size_t k = 0; k < v.size(); ++k )
        {
            s += k == 0 ? "" : ",";
            s += escapeXml( v[k], esc );
        }
        return s;
    };
    std::string run = " ctor_l=\"" + std::to_string( ing.symbols[ctor].line ) + "\"";
    run += " ctor_calls=\"" + join( calls ) + "\"";
    if( more > 0 )
    {
        run += " ctor_calls_more=\"" + std::to_string( more ) + "\"";
    }
    sigs.insert( close, run );
    return run.size();
}

}   // namespace rw
