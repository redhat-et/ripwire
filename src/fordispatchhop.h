#pragma once
// fordispatchhop.h — THE DISPATCH HOP of a name-exact --for answer (lane mf1-nx, wave 4): when the question names a call the
// served function makes through an interface-, trait- or abstract-typed receiver, the implementations that can run there.
//
// WHY. "When `Parser::Load` calls `file_reader_->ReadFile(...)`, which ReadFile runs?" routes name-exact and serves Parser::Load:
// its signature, its callers, its body. The call itself is absent from the body's <calls>: the resolver DECLINED it (the receiver
// is a `FileReader*`, an interface with four implementors; ifacedispatch.h, gate="iface") and stored exactly that candidate list,
// which only `--callees … --legend=full` printed, as file:line. Measured offline before this code (reports/mf1-nx.md Stage 0):
// the two MF1-DEV which-definition-runs rows (mdbook-02 `renderer.render`, ninja-02 `file_reader_->ReadFile`) gained 1 and 3
// required items from the candidate rows plus the sites that construct the candidates' types.
//
// WHAT. <dispatch call= in= p=file:line cands= shown= [test=] capped= next=> after the caller hop and before the bodies:
//   * one <s t= n= p=file:line> row per NON-TEST candidate method (the resolver's own declined list, in its order; a test double
//     is counted in test=, never shown — a test-path definition, or one whose type only test code names), at most kForDispatchHopRows;
//   * <s … ctor="Owner::new"> rows: the callers of each shown candidate owner's constructor (a member of the candidate's scope
//     named as the language spells a constructor — forctorhop.h ctor_detail::isCtorName, plus Rust `new`), non-test, at most kForDispatchCtorRows in all —
//     where a candidate's type is made, which is where the choice is decided;
//   * the candidate's body when exactly ONE non-test candidate exists (the implementation production code can run there).
// Hedged by construction: the rows are the declined list, never an edge (which one runs is unproven) — nothing enters a reaches=
// set, and a call the resolver bound or declined for another reason (ladder, builtin, std) carries no element.
//
// WHEN. The name-exact route's auto <bodies> bundle, the DEFAULT regime and the XML dialect (the caller hop's posture, verbs_for.h);
// a body candidate that is a function or method made the declined call; and the TASK names that call: a task token spelling a
// member access (`recv.m`, `recv->m`, `Q::m`) whose last segment is the called name, and that name is not the calling function's
// own (a `render` wrapper calling `inner.render` stays as it was). The shape comes from the task text, never from a row id.
// RIPWIRE_NO_DISPATCH_HOP (any value) turns it off — the A/B handle.

#include "callhierarchy.h"   // oneHopCallerRows — the callers verb's rows
#include "declinedsites.h"   // declinedSitesMadeBy, orderDeclinedSites
#include "filter.h"          // isTestSymbol
#include "forcallerhop.h"    // appendCallerHopRow / CallerHopRowCtx — the caller hop's <s> row
#include "forctorhop.h"     // ctor_detail::isCtorName — the language-gated constructor spelling
#include "forfold.h"         // fold_detail::renderOneBody
#include "langfacts.h"       // langFacts( lang ).structuralTyping
#include "graph.h"
#include "memberowner.h"
#include "model.h"
#include "nextverb.h"
#include "receiverevidence.h"   // ReceiverEvidence::callableKind
#include "sarif.h"           // rootRelativeUri
#include "serialize.h"       // escapeXml

#include <algorithm>
#include <cctype>
#include <optional>
#include <cstddef>
#include <cstdlib>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// Runaway guards, not size targets: every row left out is counted (cands=, test=, capped="1") and next= lists them all.
inline constexpr std::size_t kForDispatchHopRows  = 8;   // candidate rows per call
inline constexpr std::size_t kForDispatchCtorRows = 4;   // constructor-caller rows per call
inline constexpr std::size_t kForDispatchSites    = 2;   // calls per answer (a task naming more is a different question)

inline bool forDispatchHopOn()
{
    return std::getenv( "RIPWIRE_NO_DISPATCH_HOP" ) == nullptr;
}

inline constexpr std::string_view kForDispatchHopLegend =
    "; dispatch call=: the task names a call the served function in= makes at p=file:line through an interface, trait or abstract "
    "receiver, which the resolver declined: s t= n= p=file:line rows are the implementations that can run there (cands= the in-tree "
    "candidates, shown= of them, test= test doubles not shown (test code, or a type only test code names), floor=1 the language types structurally so an unlisted "
    "implementation can run too, which one runs is unproven, never an edge), s ctor= rows call that candidate "
    "type's constructor (where it is made), one shown candidate carries its body b (never when floor=1), capped=1 if cut, next= lists every definition";
inline constexpr std::string_view kForCompactDispatchHopLegend =
    "; dispatch call= in= p=: a task-named call declined at an interface/trait receiver, s rows the implementations that can run "
    "(unproven which), cands= in-tree shown= test= doubles floor=1 unlisted ones can run, s ctor= rows make that type, one candidate: its body b, capped=1 if cut, next= every definition";
static_assert( kForDispatchHopLegend.find( ';', 1 ) == std::string_view::npos && kForCompactDispatchHopLegend.find( ';', 1 ) == std::string_view::npos
                   && kForDispatchHopLegend.find( "--" ) == std::string_view::npos && kForCompactDispatchHopLegend.find( "--" ) == std::string_view::npos,
               "one clause each, and no \"--\": it rides inside an XML comment" );

namespace dispatch_detail
{
// The last segment of a task token that spells a member access or a qualified name (`recv.m`, `recv->m`, `Q::m`, `m(…)` after
// one of those); "" for a bare word — a bare word is prose ("the name"), not a named call.
inline std::string_view callSegment( std::string_view tok )
{
    if( const std::size_t paren = tok.find( '(' ); paren != std::string_view::npos )
    {
        tok = tok.substr( 0, paren );
    }
    while( !tok.empty() && !( std::isalnum( static_cast<unsigned char>( tok.back() ) ) || tok.back() == '_' ) )
    {
        tok.remove_suffix( 1 );
    }
    std::size_t cut = std::string_view::npos;
    for( const std::string_view sep : { std::string_view( "->" ), std::string_view( "::" ), std::string_view( "." ) } )
    {
        if( const std::size_t at = tok.rfind( sep ); at != std::string_view::npos && ( cut == std::string_view::npos || at + sep.size() > cut ) )
        {
            cut = at + sep.size();
        }
    }
    if( cut == std::string_view::npos || cut == 0 || cut >= tok.size() )
    {
        return {};
    }
    return tok.substr( cut );
}
// A named call in the task: the called name and, when the token spells `recv.m` / `recv->m` with an identifier before the
// separator, that receiver ("" for `Q::m`, `f()->m` and the like: no receiver written).
struct TaskCall
{
    std::string_view name;
    std::string_view recv;
};
inline std::string_view lastIdent( std::string_view t )
{
    std::size_t e = t.size();
    while( e > 0 && ( std::isalnum( static_cast<unsigned char>( t[e - 1] ) ) || t[e - 1] == '_' ) )
    {
        --e;
    }
    return t.substr( e );
}
inline TaskCall callOfToken( std::string_view tok )
{
    const std::string_view seg = callSegment( tok );
    if( seg.empty() )
    {
        return {};
    }
    // the prefix before the final segment: `src_->` / `a.b.` / `Q::`; only a `.` or `->` separator carries a receiver
    std::string_view pre = tok.substr( 0, static_cast<std::size_t>( seg.data() - tok.data() ) );
    if( pre.ends_with( "->" ) )
    {
        pre.remove_suffix( 2 );
    }
    else if( pre.ends_with( '.' ) )
    {
        pre.remove_suffix( 1 );
    }
    else
    {
        return { seg, {} };
    }
    return { seg, lastIdent( pre ) };
}
inline std::vector<TaskCall> taskCallNames( std::string_view task )
{
    std::vector<TaskCall> out;
    std::size_t           i = 0;
    while( i < task.size() )
    {
        while( i < task.size() && ( std::isspace( static_cast<unsigned char>( task[i] ) ) || task[i] == '`' ) )
        {
            ++i;
        }
        std::size_t j = i;
        while( j < task.size() && !std::isspace( static_cast<unsigned char>( task[j] ) ) && task[j] != '`' )
        {
            ++j;
        }
        if( const TaskCall c = callOfToken( task.substr( i, j - i ) );
            !c.name.empty() && std::ranges::none_of( out, [ & ]( const TaskCall& o ) { return o.name == c.name && o.recv == c.recv; } ) )
        {
            out.push_back( c );
        }
        i = j;
    }
    return out;
}
inline std::span<const NodeId> siteCandidates( const Graph& g, std::uint32_t site )
{
    const std::uint32_t list = g.declinedSiteList[ site ];
    if( list == kNoDeclinedList || list + 1 >= g.declinedListOff.size() )
    {
        return {};
    }
    return std::span<const NodeId>( g.declinedListCand.data() + g.declinedListOff[ list ], g.declinedListOff[ list + 1 ] - g.declinedListOff[ list ] );
}
}   // namespace dispatch_detail

// An entry point the runtime itself runs, with no caller in the code: `main`, a Go `init`, and the C/C++ entries the OS runs under
// another name (`wmain`, `_tmain`, `WinMain`, `wWinMain`, `DllMain`). A switch, not a `== Lang::` predicate: the language-identity
// ratchet (test/langidentity/ratchet.tsv) counts predicates in shared files and may never rise.
inline bool runtimeRoot( Lang lang, std::string_view name ) noexcept
{
    switch( lang )
    {
        case Lang::Go:  return name == "main" || name == "init";
        case Lang::C:
        case Lang::Cpp: return name == "main" || name == "wmain" || name == "_tmain" || name == "WinMain" || name == "wWinMain" || name == "DllMain";
        default:        return name == "main";
    }
}

// Does any production code name the candidate's type? A reference (call, type use, member type, base clause, qualifier) spelling
// the owner's name from a non-test symbol in a non-test file is production evidence when it comes
//   * from a file holding none of the owner's members (a registry, a main, a composition root), or
//   * from INSIDE the owner's own files, by a non-member that production runs: a factory (`Store* MakePg() { return new Pg(); }`)
//     with a non-test caller, a file-level registrar, `main`, a Go `init`, a C/C++ OS entry (`WinMain`, `DllMain`, …) — a type made where it is defined is still made. An
//     uncalled helper (dead code, a debug dump) is not evidence: it is not known to run.
// By name only, so a collision keeps a candidate shown (never the other way): a candidate whose type test code names and nothing
// else does (ninja's VirtualFileSystem, defined in src/test.cc and used by *_test.cc only) is a test double, counted in test=; a
// type nothing outside its own members names (a Rust unit struct built in place) keeps its row: no evidence, no demotion.
inline bool ownerNamedByProduction( const IngestResult& ing, const Graph& g, NodeId cand )
{
    const Symbol& c = ing.symbols[ cand ];
    if( c.scope.empty() )
    {
        return true;   // a free function: no type to ask about
    }
    const std::size_t      sep   = c.scope.find_last_of( ".:" );
    const std::string_view owner = sep == std::string::npos ? std::string_view( c.scope ) : std::string_view( c.scope ).substr( sep + 1 );
    std::vector<std::uint32_t> ownFiles;
    for( const Symbol& s : ing.symbols )
    {
        if( ( s.scope == c.scope || ( s.name == owner && s.lang == c.lang && ReceiverEvidence::classLike( s.kind ) ) ) && std::ranges::find( ownFiles, s.fileId ) == ownFiles.end() )
        {
            ownFiles.push_back( s.fileId );
        }
    }
    bool testNames = false;
    for( const Reference& r : ing.references )
    {
        if( ( r.calleeName != owner && r.qualifier != owner ) || r.isDocLink )
        {
            continue;
        }
        const bool inOwnFiles = std::ranges::find( ownFiles, r.fileId ) != ownFiles.end();
        if( isTestPath( rootRelPath( ing, r.fileId ) ) || ( r.fromSymbol != kNoNode && isTestSymbol( ing, r.fromSymbol ) ) )
        {
            testNames = testNames || !inOwnFiles;
            continue;
        }
        if( !inOwnFiles || r.fromSymbol == kNoNode )
        {
            return true;
        }
        // inside the owner's own files: only a non-member that production runs counts (the type's own members name it constantly)
        const Symbol& from = ing.symbols[ r.fromSymbol ];
        if( from.scope == c.scope || from.name == owner )
        {
            continue;
        }
        const std::vector<NodeId> fromTarget{ r.fromSymbol };
        const std::vector<NodeId> who = oneHopCallerRows( ing, g, fromTarget );
        // a root the runtime runs (main, a Go init, a C/C++ OS entry; a file-level registrar is the kNoNode case above) has no callers; a factory has a
        // non-test caller. Any OTHER caller-less function is dead code or a debug helper: not evidence production runs the type
        if( runtimeRoot( from.lang, from.name ) || std::ranges::any_of( who, [ & ]( NodeId w ) { return !isTestSymbol( ing, w ); } ) )
        {
            return true;
        }
    }
    return !testNames;   // named by nothing production runs: no evidence either way, so it stays a candidate
}

// One declined site's candidates split: the production ones (shown) and the count of test doubles (a test-path/test-scope
// definition, or a type only test code names). Used at decision time (a site with no production candidate carries nothing) and
// by the renderer, so the answer's header and its element cannot disagree.
struct DispatchCands
{
    std::vector<NodeId> prod;
    std::size_t         tests = 0;
};
//
// On an index the memory guard CUT (the MCP surface answers over one; the CLI refuses it before --for runs) the second test reads
// an ABSENCE — "no kept file builds this type" — and the cut may have dropped exactly the file that does (the crawl keeps files in
// name order, so a late `main.cc` goes first). An absence on a partial index proves nothing, so only POSITIVE evidence demotes
// there (the candidate's own definition sits on a test path); a type named only by tests stays a shown candidate. The answer's
// `_memory_stop` already says the index is a floor.
inline DispatchCands splitDispatchCands( const IngestResult& ing, const Graph& g, std::uint32_t site )
{
    DispatchCands out;
    const bool    partialIndex = ing.memoryStop.isSet();
    for( const NodeId c : dispatch_detail::siteCandidates( g, site ) )
    {
        if( isTestSymbol( ing, c ) || ( !partialIndex && !ownerNamedByProduction( ing, g, c ) ) )
        {
            ++out.tests;
        }
        else
        {
            out.prod.push_back( c );
        }
    }
    return out;
}

// The calls the element is about: declined gate="iface" sites with a stored list holding at least one production candidate, made
// by a callable body candidate, whose called name the task names as a call and which is not the caller's own name. Per called
// name: a task token that writes a receiver (`cache_->Fetch`) picks the site(s) with that receiver, and when none has it the
// site is answered only if every same-name site carries the SAME candidate list (never another receiver's list), and a site that
// names a different receiver of its own is never the asked call's answer; a token with no
// receiver keeps every same-name site, one per distinct list. At most kForDispatchSites, in the declined rows' served order.
inline std::vector<std::uint32_t> forDispatchSites( const IngestResult& ing, const Graph& g, std::span<const NodeId> bodyCandidates, std::string_view task )
{
    std::vector<std::uint32_t> out;
    const std::vector<dispatch_detail::TaskCall> names = dispatch_detail::taskCallNames( task );
    if( names.empty() || bodyCandidates.empty() )
    {
        return out;
    }
    std::vector<NodeId> callers;
    for( const NodeId id : bodyCandidates )
    {
        if( id < ing.symbols.size() && ReceiverEvidence::callableKind( ing.symbols[id].kind ) )
        {
            callers.push_back( id );
        }
    }
    std::vector<std::uint32_t> sites = declinedSitesMadeBy( g, callers );
    orderDeclinedSites( ing, g, sites, /*fileFirst=*/false );
    // pass 1: the sites that name a task call and could answer it
    std::vector<std::uint32_t> eligible;
    for( const std::uint32_t site : sites )
    {
        const Reference& r = ing.references[ g.declinedSiteRef[ site ] ];
        if( g.declinedSiteKind[ site ] == DeclinedSiteKind::Iface && !dispatch_detail::siteCandidates( g, site ).empty() && ing.symbols[ g.declinedSiteCaller[ site ] ].name != r.calleeName
            && std::ranges::any_of( names, [ & ]( const dispatch_detail::TaskCall& t ) { return t.name == r.calleeName; } ) )
        {
            eligible.push_back( site );
        }
    }
    const auto sameList = [ & ]( std::uint32_t a, std::uint32_t b ) {
        return std::ranges::equal( dispatch_detail::siteCandidates( g, a ), dispatch_detail::siteCandidates( g, b ) );
    };
    // pass 2: per called name, the receiver the task wrote picks the site; one per distinct list
    const auto wroteRecv = [ & ]( std::string_view name ) {
        return std::ranges::any_of( names, [ & ]( const dispatch_detail::TaskCall& t ) { return t.name == name && !t.recv.empty(); } );
    };
    const auto exactRecv = [ & ]( std::uint32_t site ) {
        const Reference& r = ing.references[ g.declinedSiteRef[ site ] ];
        return std::ranges::any_of( names, [ & ]( const dispatch_detail::TaskCall& t ) {
            return t.name == r.calleeName && !t.recv.empty() && t.recv == dispatch_detail::lastIdent( r.recvVar );
        } );
    };
    const auto sameName = [ & ]( std::uint32_t a, std::uint32_t b ) {
        return ing.references[ g.declinedSiteRef[ a ] ].calleeName == ing.references[ g.declinedSiteRef[ b ] ].calleeName;
    };
    std::vector<std::uint32_t> kept;
    for( const std::uint32_t site : eligible )
    {
        const Reference& r = ing.references[ g.declinedSiteRef[ site ] ];
        if( wroteRecv( r.calleeName ) && !exactRecv( site )
            && ( !dispatch_detail::lastIdent( r.recvVar ).empty()
                 || std::ranges::any_of( eligible, [ & ]( std::uint32_t o ) { return sameName( o, site ) && ( exactRecv( o ) || !sameList( o, site ) ); } ) ) )
        {
            // the asked receiver is not this site's: a site that names its own (different) receiver is another call, even when no other
            // site is left (the asked `x_->F` was bound by name, never declined); a site with no receiver recorded (TS parameter, Rust)
            // cannot be told apart from one with another list
            continue;
        }
        if( std::ranges::any_of( kept, [ & ]( std::uint32_t k ) { return sameName( k, site ) && sameList( k, site ); } ) )
        {
            continue;
        }
        if( splitDispatchCands( ing, g, site ).prod.empty() )
        {
            continue;   // only test doubles: nothing production code runs to name, so no element and no clause
        }
        kept.push_back( site );
        out.push_back( site );
        if( out.size() == kForDispatchSites )
        {
            break;
        }
    }
    return out;
}
// The MCP `for` twin's body candidates (it has no auto <bodies> bundle): the r=1 row and every ranked-head row sharing its name and
// scope — the decl/def pair the CLI's anchor-restricted head holds on the same name-exact route.
inline std::vector<NodeId> dispatchHeadCandidates( const IngestResult& ing, std::span<const NodeId> head )
{
    std::vector<NodeId> out;
    if( head.empty() || head.front() >= ing.symbols.size() )
    {
        return out;
    }
    const Symbol& top = ing.symbols[ head.front() ];
    for( const NodeId id : head )
    {
        if( id < ing.symbols.size() && ing.symbols[id].name == top.name && ing.symbols[id].scope == top.scope )
        {
            out.push_back( id );
        }
    }
    return out;
}

struct DispatchHopRender
{
    std::string xml;              // <dispatch …>…</dispatch> per site; empty when nothing rides
    std::size_t bodyBytes = 0;    // the body elements' bytes inside xml (the body rate); the rest is markup
};

// A constructor spelling for the element: forctorhop.h's per-language rule, plus Rust `new` (an associated function, not a
// keyword). A switch, not a language-equality predicate: the language-identity ratchet counts those in shared files.
inline bool dispatchCtorName( Lang lang, std::string_view name, std::string_view owner ) noexcept
{
    switch( lang )
    {
        case Lang::Rust: return name == "new";
        default:         return ctor_detail::isCtorName( lang, name, owner );
    }
}

// The constructors of `cand`'s owner: callables of the same scope whose name the language spells a constructor (forctorhop.h
// isCtorName: a C++ `init()` is an ordinary method), and a Rust `new` (an associated function, not a keyword).
inline std::vector<NodeId> dispatchOwnerCtors( const IngestResult& ing, NodeId cand )
{
    std::vector<NodeId> out;
    const Symbol&       c = ing.symbols[ cand ];
    if( c.scope.empty() )
    {
        return out;
    }
    const std::size_t      sep   = c.scope.find_last_of( ".:" );
    const std::string_view owner = sep == std::string::npos ? std::string_view( c.scope ) : std::string_view( c.scope ).substr( sep + 1 );
    for( NodeId id = 0; id < ing.symbols.size(); ++id )
    {
        const Symbol& s = ing.symbols[id];
        if( id != cand && s.lang == c.lang && s.scope == c.scope && ReceiverEvidence::callableKind( s.kind )
            && dispatchCtorName( s.lang, s.name, owner ) )
        {
            out.push_back( id );
        }
    }
    return out;
}

// `withBody` false: the MCP `for` twin, which serves no inline body (its bodies ride by fetch_body handle) — rows only.
inline DispatchHopRender renderForDispatchHop( const IngestResult& ing, const Graph& g, std::span<const std::uint32_t> sites, const BodyFoldInputs& bodyIn,
                                               bool withBody = true )
{
    DispatchHopRender     out;
    std::vector<char>     esc;
    const MemberOwners    owners( ing );
    const CallerHopRowCtx rc{ ing, owners, bodyIn.rootArg, esc };
    for( const std::uint32_t site : sites )
    {
        const Reference&              r     = ing.references[ g.declinedSiteRef[ site ] ];
        const std::span<const NodeId> cands = dispatch_detail::siteCandidates( g, site );
        const DispatchCands    split = splitDispatchCands( ing, g, site );
        const auto&            prod  = split.prod;
        const std::size_t      tests = split.tests;
        if( prod.empty() )
        {
            continue;   // only test doubles: forDispatchSites never hands such a site over; defensive
        }
        const std::size_t shown = std::min( prod.size(), kForDispatchHopRows );
        // where each shown candidate's type is made: the callers of its constructors, non-test, deduped, capped over the call
        std::vector<std::pair<NodeId, NodeId>> made;   // (caller, ctor)
        std::size_t                            madeTotal = 0;
        for( std::size_t i = 0; i < shown; ++i )
        {
            for( const NodeId ctor : dispatchOwnerCtors( ing, prod[i] ) )
            {
                const std::vector<NodeId> ctorTargets{ ctor };
                for( const NodeId caller : oneHopCallerRows( ing, g, ctorTargets ) )
                {
                    if( isTestSymbol( ing, caller ) || std::ranges::any_of( made, [ & ]( const auto& m ) { return m.first == caller; } ) )
                    {
                        continue;
                    }
                    ++madeTotal;
                    if( made.size() < kForDispatchCtorRows )
                    {
                        made.emplace_back( caller, ctor );
                    }
                }
            }
        }
        const Symbol&          caller = ing.symbols[ g.declinedSiteCaller[ site ] ];
        // a structurally typed language (TS/JS/Go): the candidate list is a floor, an unlisted object literal / type can run too
        const bool isFloor = langFacts( caller.lang ).structuralTyping;
        const std::string_view rp     = bodyIn.rootArg.empty() ? std::string_view( ing.files[ r.fileId ] ) : sarif::rootRelativeUri( ing.files[ r.fileId ], bodyIn.rootArg );
        std::string            x;
        x += "<dispatch call=\"";
        x += escapeXml( r.recvVar.empty() ? std::string( r.calleeName ) : r.recvVar + ( r.viaArrow ? "->" : "." ) + r.calleeName, esc );
        x += "\" in=\"";
        x += escapeXml( qualifiedMemberName( owners, caller ), esc );
        x += "\" p=\"";
        x += escapeXml( rp, esc );
        x += ':' + std::to_string( r.line ) + "\" cands=\"" + std::to_string( cands.size() ) + "\" shown=\"" + std::to_string( shown ) + '"';
        if( tests > 0 )
        {
            x += " test=\"" + std::to_string( tests ) + '"';
        }
        if( isFloor )
        {
            x += " floor=\"1\"";
        }
        x += " capped=\"";
        x += ( shown < prod.size() || made.size() < madeTotal ) ? "1" : "0";
        x += '"';
        x += nextAttrXml( nextFlag( "--whereis=", r.calleeName ) );
        x += '>';
        for( std::size_t i = 0; i < shown; ++i )
        {
            appendCallerHopRow( x, rc, prod[i], {} );
        }
        for( const auto& [ who, ctor ] : made )
        {
            appendCallerHopRow( x, rc, who, std::string( " ctor=\"" ) + std::string( escapeXml( qualifiedMemberName( owners, ing.symbols[ ctor ] ), esc ) ) + '"' );
        }
        if( withBody && prod.size() == 1 && !isFloor )   // a floor list names no single implementation
        {
            if( const std::optional<std::string> body = fold_detail::renderOneBody( bodyIn, prod.front() ) )
            {
                x += *body;
                out.bodyBytes += body->size();
            }
        }
        x += "</dispatch>";
        out.xml += x;
    }
    return out;
}

// The MCP twin's own comment: the element carries its definition beside it (the MCP for header's clauses are fixed at render time).
inline std::string dispatchHopMcpXml( const DispatchHopRender& r )
{
    return r.xml.empty() ? std::string() : "<!-- ripwire for" + std::string( kForDispatchHopLegend ) + " -->" + r.xml;
}

}   // namespace rw
