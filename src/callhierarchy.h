#pragma once
// callhierarchy.h — the ONE 1-hop call-hierarchy computation, shared by the CLI's --callers/--callees and
// by the MCP twins find_referencing_symbols / find_symbol.
//
// WHY THIS FILE EXISTS (capture-audit 2026-09-04, H14 + M13). The two surfaces answered the same question
// from two different pieces of code. The CLI resolved EVERY definition of the name
// (resolveAllByNameQualified), unioned their neighbours, sorted them tier-then-path, partitioned them into
// tested/untested and paged the result — so its root carried `defs= count= hop_tested= hop_untested=` and
// its rows carried `tested="1"`. The MCP twin walked the CSR from ONE resolved def (resolveFocus) in raw
// node order and emitted `{name,kind,file,line,handle}` and nothing else: no defs (so a caller could not
// tell that the name it asked about has three definitions and it got the union of one), no test-reach lens
// (the exact lens --test-gate is built on), and no page 2 at all.
//
// That is the clone-seam class this repo has closed a dozen times: two emitters of one computation drift on
// what they disclose, and each passes its own tests in isolation. The computation moves here; both surfaces
// call it and differ only in how they RENDER. The gate is test/mcpattrparitycheck.sh (attribute-name-set
// diff, CLI root ⊆ MCP keys and per-row likewise) plus test/mcpclidiffcheck.sh's existing lenses.
//
// Deliberately NOT here: the rendering, the refusal wording, and the display cap policy. Those are
// surface-specific by contract (the CLI has a legend, the MCP arm speaks JSON-RPC errors), and folding them
// in would trade one drift for another.

#include "filter.h"    // pathTierIndexOver / compareTierThenPath — the tier-then-path row order both surfaces serve
#include "graph.h"     // resolveAllByNameQualified, the CSR, testSymbolForwardReach / countTestedIn / isTestedByReach
#include "model.h"
#include "infra/sortutil.h"   // svLess: the explicit byte order every string_view sort here takes (portablebuildcheck #6)
#include "valuerefs.h" // the reference-as-value rows both surfaces serve beside the call rows

#include <algorithm>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// A6: the 1-hop tested/untested partition, bundled into one call so a caller pays ONE statement instead of
// separately naming testReach / tested / untested / attr. The counting loop itself lives in
// graph.h::countTestedIn, shared with --impact. (Hoisted here from verbs_navigate.h, unchanged, so the MCP
// twins can serve the same partition instead of omitting the lens.)
struct HopTestedPartition
{
    std::vector<char> testReach;
    std::size_t       tested;
    std::size_t       untested;
    std::string       xmlAttr;   // " hop_tested=\"N\" hop_untested=\"M\""
};

inline HopTestedPartition computeHopTestedPartition( const IngestResult& ing, const Graph& g, const std::vector<NodeId>& rows )
{
    std::vector<char> testReach = testSymbolForwardReach( ing, g );
    const std::size_t tested    = countTestedIn( ing, testReach, rows );
    const std::size_t untested  = rows.size() - tested;
    std::string       attr      = " hop_tested=\"" + std::to_string( tested ) + "\" hop_untested=\"" + std::to_string( untested ) + "\"";
    return { std::move( testReach ), tested, untested, std::move( attr ) };
}

// The rows one 1-hop question yields, with the two counts that qualify them.
//   matches — every DEFINITION the selector resolved to. Its size is the `defs=` disclosure: the rows below
//             are the UNION of all of their neighbours, and a reader who thought they were one symbol's
//             would be wrong by however many definitions the name has.
//   rows    — the deduped neighbour set, in the served order: tier, then — CALLERS ONLY (cut-fix C, fix round 1) —
//             most-called first, then path, line and name as the tie-break. Callees stay in path order: fan-in
//             ranking a callee list scored WORSE than path order on this repo's own co-blame instrument
//             (rv-cutfix-navlists B1: default-cap recall 0.592 -> 0.466, n=18) because a callee's OWN caller
//             count says nothing about how central it is to the body that calls it — it put the leaf helpers
//             (empty, size, c_str) first and the two most specific callees last, off the default cap.
// `bodylessDefs` is meaningful for the callee direction only (a declaration with no body has no callees),
// and is counted here rather than at each emitter so the two cannot disagree about what "bodyless" means.
// `declinedCalls` is the tier-3 declines the rows cannot show (graph.h): for callers, declined calls that named a
// match among their candidates; for callees, declined calls a match made. Counted here with bodylessDefs, so the
// CLI and MCP twins cannot disagree about the number printed beside count=.
// `unprovenDefs` (H1) is the decl→def widening's RESIDUE: same-named definitions a `file:name` selector found
// and could not tie to the file it named, so they are in neither `matches` nor `rows`. It belongs here, beside
// the two counts that qualify the same answer, for the same reason they do — and it is meaningful in BOTH
// directions, where bodylessDefs is callees-only.
struct CallHierarchyRows
{
    std::vector<NodeId> matches;
    std::vector<NodeId> rows;
    std::size_t         bodylessDefs  = 0;
    std::size_t         unprovenDefs  = 0;
    std::size_t         declinedCalls = 0;
    std::string         crossKind;            // cross_kind= value ("fn:1,method:10"), "" unless defs span 2+ kinds
    std::size_t         declinedIface = 0;   // callers only: declinedIfaceCallsNaming below, the root's declined_iface=
    ValueRefRows        valueRefs;     // reference-as-value round: <vr> rows, never in `rows` or any count above
    StdMemberCallsMade  stdCalls;      // callees only: of declinedCalls, the C++ standard-member ones (graph.h stdMemberCallsMadeBy)
};

// The callees answer's <stdm> line (graph.h StdMemberGate, stdMemberCallsMadeBy), one spelling per dialect — the JSON keys
// mirror the XML attributes, n= the same comma-joined value — absent when the definitions made no such call, so every
// answer on a tree the gate never touched keeps its bytes.
inline std::string stdMemberCallsXml( const StdMemberCallsMade& m )
{
    return m.calls == 0 ? std::string() : "<stdm n=\"" + m.names + "\" calls=\"" + std::to_string( m.calls ) + "\"/>";
}
inline std::string stdMemberCallsKeyJson( const StdMemberCallsMade& m )
{
    return m.calls == 0 ? std::string() : ",\"stdm\":{\"n\":\"" + m.names + "\",\"calls\":" + std::to_string( m.calls ) + "}";
}

// cross_kind= (comparison table hono-07, 2026-09-30): a bare `getPath` resolved to ONE free function
// (src/utils/url.ts) and TEN `protected getPath` methods of unrelated classes, and the rows unioned their callers
// with nothing but defs="11" to say so — `createRequest` (which calls this.getPath) read as a caller of the utils
// function. The union is the documented reading of defs=; what was missing is that the definitions are not even the
// same KIND of thing. The value lists each kind with its def count, in SymKind order, and is empty (the attribute
// absent) whenever every definition shares one kind, so a same-kind overload set keeps its bytes.
inline std::string crossKindValue( const IngestResult& ing, const std::vector<NodeId>& matches )
{
    constexpr std::size_t kKinds = kSymKindCount;   // model.h's compile-time-proven count (was ModuleScope+1: an appended kind tripped the EXPECTS)
    std::size_t           perKind[kKinds] = {};
    std::size_t           distinct        = 0;
    for( const NodeId m : matches )
    {
        if( m >= ing.symbols.size() )
        {
            continue;
        }
        const std::size_t k = std::size_t( ing.symbols[m].kind );
        EXPECTS( k < kKinds, "a symbol's kind is a SymKind enumerator (kSymKindCount bounds them)" );
        distinct += perKind[k] == 0 ? 1 : 0;
        ++perKind[k];
    }
    if( distinct < 2 )
    {
        return {};
    }
    std::string value;
    for( std::size_t k = 0; k < kKinds; ++k )
    {
        if( perKind[k] > 0 )
        {
            value += ( value.empty() ? "" : "," ) + std::string( symTag( SymKind( k ) ) ) + ":" + std::to_string( perKind[k] );
        }
    }
    return value;
}

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
        if( s.lang != Lang::TypeScript )
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

// One declined list's verdict for declinedIfaceCallsNaming: TypeScript, its called name among `sigNames`, and either a
// candidate in `isTarget` or the name among `targetSigNames`. A declined list is one called name's same-language
// definitions, so its first candidate names the call.
inline bool declinedListIsIfaceNaming( const IngestResult& ing, std::span<const NodeId> cand, std::span<const std::string_view> sigNames,
                                       std::span<const std::string_view> targetSigNames, const std::vector<char>& isTarget )
{
    if( cand.empty() || cand.front() >= ing.symbols.size() )
    {
        return false;
    }
    const Symbol& head = ing.symbols[ cand.front() ];
    if( head.lang != Lang::TypeScript || !std::binary_search( sigNames.begin(), sigNames.end(), head.name, sortutil::svLess ) )
    {
        return false;
    }
    return std::binary_search( targetSigNames.begin(), targetSigNames.end(), head.name, sortutil::svLess )
        || std::any_of( cand.begin(), cand.end(), [ & ]( NodeId c ) { return c < isTarget.size() && isTarget[c]; } );
}

// declined_iface= on the callers and impact answers (graphlegend.h kDeclinedIfaceLegend). graph.h Rule 2 does not narrow a
// TS call to an interface member on an annotation (`x: Router`, `router!: Router`), so a call through an interface-typed
// receiver whose method name has several definitions is declined, and the interface's own answer could miss it: the
// decl/def collapse can keep the bodyless signature out of the candidate list, so declined_calls= on
// `--callers=router.ts:match` was absent. This counts, once per CALL, the TS declines whose called name is also the name
// of a TS contract signature in the tree (tsContractSignatures), and that either named one of `targets` among their
// candidates or share the name of a signature in `targets` (the interface's own selector). The second arm is why it is
// NOT a subset of declined_calls= and can exceed it. The match is by NAME: no receiver type is read, so a counted call
// MAY go through the interface or may be another same-named method (String.prototype.match). A disclosure, never a
// bind: the real fix narrows on annotations and is out of this count's scope.
// Zero, at no cost past one scan of `targets`, when no target is TypeScript, so every other language keeps its bytes.
inline std::size_t declinedIfaceCallsNaming( const IngestResult& ing, const Graph& g, std::span<const NodeId> targets )
{
    const auto isTs = [ & ]( NodeId t ) { return t < ing.symbols.size() && ing.symbols[t].lang == Lang::TypeScript; };
    if( g.declinedListCallCount.empty() || !std::any_of( targets.begin(), targets.end(), isTs ) )
    {
        return 0;
    }
    EXPECTS( g.declinedListOff.size() == g.declinedListCallCount.size() + 1, "one offset past every declined list" );
    std::vector<std::string_view> sigNames;
    std::vector<std::string_view> targetSigNames;   // the interface's own selector: its signatures' names
    std::vector<char>             isTarget( ing.symbols.size(), 0 );
    for( const NodeId t : targets )
    {
        if( t < isTarget.size() )
        {
            isTarget[t] = 1;
        }
    }
    for( const NodeId id : tsContractSignatures( ing ) )
    {
        sigNames.push_back( ing.symbols[id].name );
        if( isTarget[id] )
        {
            targetSigNames.push_back( ing.symbols[id].name );
        }
    }
    std::sort( sigNames.begin(), sigNames.end(), sortutil::svLess );
    sigNames.erase( std::unique( sigNames.begin(), sigNames.end() ), sigNames.end() );
    std::sort( targetSigNames.begin(), targetSigNames.end(), sortutil::svLess );
    std::size_t callCount = 0;
    for( std::size_t listIndex = 0; listIndex < g.declinedListCallCount.size(); ++listIndex )
    {
        const std::span<const NodeId> cand( g.declinedListCand.data() + g.declinedListOff[ listIndex ],
                                            g.declinedListOff[ listIndex + 1 ] - g.declinedListOff[ listIndex ] );
        if( declinedListIsIfaceNaming( ing, cand, sigNames, targetSigNames, isTarget ) )
        {
            callCount += g.declinedListCallCount[ listIndex ];
        }
    }
    return callCount;
}

// The ONE selector derivation for both callers emitters and their legend condition.
// A declined call names no single definition: widen only a narrowed callers selector to
// its resolved definitions' shared name. Bare selectors and all non-declined answers keep their bytes.
inline std::pair<std::string_view, bool> callHierarchyNextSelector( const IngestResult& ing, const CallHierarchyRows& hierarchy,
                                                                  std::string_view selector, bool wantCallers )
{
    if( !wantCallers || hierarchy.declinedCalls == 0 || hierarchy.matches.empty() )
    {
        return { selector, false };
    }
    const std::string_view name = ing.symbols[ hierarchy.matches.front() ].name;
    if( name == selector )
    {
        return { selector, false };
    }
    // resolveAllByNameQualified's tiers share one leaf name; guard that before widening.
    for( const NodeId id : hierarchy.matches )
    {
        if( ing.symbols[id].name != name )
        {
            return { selector, false };
        }
    }
    return { name, true };
}

inline CallHierarchyRows callHierarchyRows( const IngestResult& ing, const Graph& g, std::string_view selector, bool wantCallers,
                                            const ValueRefIndex* valueIndex = nullptr )   // the MCP server passes its cached one
{
    CallHierarchyRows out;
    // X9(b): "file:name" disambiguates here (the same rule --around/--lego/--edit-check use through
    // resolveFocus) — a same-named symbol living in more than one file must be pickable on either surface.
    // H1: the resolver's residue travels WITH the matches it is the complement of — always written (0 on
    // every tier that never reaches the widening), so no emitter can read a stale value.
    out.matches = resolveAllByNameQualified( ing, selector, &out.unprovenDefs );
    if( out.matches.empty() )
    {
        return out;   // the caller owns the refusal: a CLI stderr line, or a JSON-RPC -32602
    }
    out.crossKind = crossKindValue( ing, out.matches );

    std::vector<char> seen( ing.symbols.size(), 0 );
    for( const NodeId x : out.matches )
    {
        if( wantCallers )
        {
            const auto* ro = g.inEdges.rowOffsets();
            const auto* ci = g.inEdges.colIndices();
            for( std::uint32_t k = ro[x]; k < ro[x + 1]; ++k )
            {
                if( NodeId c = ci[k]; c < seen.size() && !seen[c] ) { seen[c] = 1;  out.rows.push_back( c ); }
            }
        }
        else
        {
            for( std::uint32_t k = g.outOff[x]; k < g.outOff[x + 1]; ++k )
            {
                if( NodeId c = g.outTargets[k]; c < seen.size() && !seen[c] ) { seen[c] = 1;  out.rows.push_back( c ); }
            }
            // Bodyless definitions (a declaration whose signature end IS its end): they have no callees, so
            // an empty row set is explained rather than mysterious.
            if( const Symbol& sym = ing.symbols[x]; sym.sigEndByte == sym.endByte )
            {
                ++out.bodylessDefs;
            }
        }
    }

    out.declinedCalls = wantCallers ? declinedCallsNaming( g, out.matches ) : declinedCallsMadeBy( g, out.matches );
    out.declinedIface = wantCallers ? declinedIfaceCallsNaming( ing, g, out.matches ) : 0;
    out.stdCalls      = wantCallers ? StdMemberCallsMade{} : stdMemberCallsMadeBy( g, out.matches );

    // LB-G (r10 §5): TIER before path — filter.h states the key once and --uses shares it. Plain path order
    // put 171 `tests/` rows ahead of anything useful on django's `--callers=bulk_create`.
    const std::vector<std::uint8_t> tierOfFile = pathTierIndexOver( ing, out.rows, [ & ]( NodeId r ) { return ing.symbols[r].fileId; } );
    std::sort( out.rows.begin(), out.rows.end(), [ & ]( NodeId a, NodeId b )
    {
        const Symbol& sa = ing.symbols[a];
        const Symbol& sb = ing.symbols[b];
        if( const int c = compareTierThenPath( ing, tierOfFile, sa.fileId, sb.fileId ); c != 0 )
        {
            return c < 0;
        }
        return sa.line != sb.line ? sa.line < sb.line : sa.name < sb.name;
    } );
    // cut-fix C (2026-09-23): RANK BEFORE THE CAP — CALLERS ONLY. Within a tier the most-called caller comes
    // first (graph.h navRelevanceWeight; the path order above is the tie-break), so every window over the
    // callers rows — the CLI's default cap, find_referencing_symbols, and find_symbol's calledBy array — keeps
    // the rows most depended on and drops the lightest (filter.h rankBeforeCap states the rule and its paging
    // guarantee).
    //
    // Fix round 1 (2026-09-24, rv-cutfix-navlists B1, blocking): the first cut of this lane applied the SAME
    // rank to the callee direction too, unmeasured. It made callees WORSE: this repo's own co-blame instrument
    // (the same one the table above reports) fell 0.592 -> 0.466 at the default cap (n=18, W/L 1/11), and every
    // multi-row --callees / find_symbol `calls` answer led with the row's LEAST specific neighbours (empty,
    // empty, empty, size, c_str) because a callee's rank there is ITS OWN caller count, which measures how
    // widely-called that callee is elsewhere, not how central it is to the body that calls it. Guarded on
    // wantCallers so callees (and find_symbol's `calls`) keep the tier/path order above, byte-identical to
    // origin/main.
    // Reference-as-value round: the <vr> rows beside the call rows — the binding sites of `matches` (callers), or what
    // `matches` stores/passes and may call through (callees). Never merged into `rows`: they are not calls.
    {
        const std::optional<ValueRefIndex> local = valueIndex == nullptr ? std::optional<ValueRefIndex>( std::in_place, ing ) : std::nullopt;
        const ValueRefIndex&               vri   = valueIndex != nullptr ? *valueIndex : *local;
        out.valueRefs = wantCallers ? valueRefCallerRows( ing, vri, out.matches ) : valueRefCalleeRows( ing, vri, out.matches );
    }
    if( wantCallers )
    {
        rankBeforeCap( ing, out.rows, [ & ]( NodeId r ) { return ing.symbols[r].fileId; },
                       [ & ]( NodeId r ) { return navRelevanceWeight( g, r ); } );
    }
    return out;
}

}   // namespace rw
