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

#include "closures.h"        // ClosureIndex — the callees form's <in> blocks: functions written inside of='s body
#include "declinedsites.h"   // the <dc> rows: the declined call sites, ordered here once for every surface
#include "editcheck.h" // rowCallSites / callSitesAttrXml — the C2 byte band estimates the rows it serves
#include "pageview.h"  // kCallersBandMaxBytes / kCallerRowMinBytes / kCallHierarchyBandMax
#include "defattrib.h" // the per-row definition attribution every surface of these rows serves (and tsContractSignatures)
#include "filter.h"    // pathTierIndexOver / compareTierThenPath — the tier-then-path row order both surfaces serve
#include "graph.h"     // resolveAllByNameQualified, the CSR, testSymbolForwardReach / countTestedIn / isTestedByReach
#include "memberowner.h"   // QUALNAME-1: MemberOwners / qualifiedMemberName — n="Owner.name" on every member row
#include "model.h"
#include "nextverb.h"  // nextFlag / nextAttrXml / nextFieldJson — a cut <in> block's next=
#include "sarif.h"     // rootRelativeUri — the <in> blocks' p=, as every other row
#include "infra/sortutil.h"   // svLess: the explicit byte order every string_view sort here takes (portablebuildcheck #6)
#include "valuerefs.h" // the reference-as-value rows both surfaces serve beside the call rows

#include <algorithm>
#include <format>     // std::format — the <stdm> line's two spellings (stdMemberCallsSpelling)
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <tuple>      // std::tie — declined_calls= and its <dc> records from one call
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
    StdMemberCallsMade  stdCalls;      // callees only: of declinedCalls, the standard-member ones (graph.h stdMemberCallsMadeBy)
    OneHopAttribution   attr;          // attrib-multidef (defattrib.h): the definition groups + each row's ties, parallel to `rows`
    // lane declined-sites (declinedsites.h): the records behind declinedCalls, in served order (callers file-first, callees
    // file and line) — the <dc> rows, never in `rows` or any count above; uncut, declinedSites.size() == declinedCalls.
    std::vector<std::uint32_t> declinedSites;
};

// ── CLOSURE BLOCKS (lane ix2-slice, IX-2 P2): what the functions written INSIDE of='s body call ───────────────────────────
// `--callees=getTemplate` listed what getTemplate's own body calls, but nunjucks' `const createTemplate = ( err, info ) => {
// … new Template( … ) … }` is a definition of its own, so Template was in no row. The callees form now carries one <in> block
// per closure (src/closures.h: a named function whose innermost enclosing definition is a function of=, at any depth) listing
// that closure's own callees. A block is CONTAINMENT, not a call: its rows are in no count=, and of= reaches them only by
// running the closure or handing it on (via="closure" on every block says so). kClosureBlocks blocks, kClosureRows rows each.
inline constexpr std::size_t kClosureBlocks = 4;   // <in> blocks per answer; closures= counts them all, closures_capped="1" says so
inline constexpr std::size_t kClosureRows   = 8;   // rows per block; count= is the closure's distinct callees, capped="1" past it

// One closure's callees: its resolved out-edges, deduped, in the callees form's tier-then-path order (then line, name).
inline std::vector<NodeId> closureCalleeRows( const IngestResult& ing, const Graph& g, NodeId inner )
{
    std::vector<NodeId> rows;
    for( std::uint32_t k = g.outOff[inner]; k < g.outOff[inner + 1]; ++k )
    {
        if( const NodeId c = g.outTargets[k]; c < ing.symbols.size() && c != inner )
        {
            rows.push_back( c );
        }
    }
    std::ranges::sort( rows );
    rows.erase( std::ranges::unique( rows ).begin(), rows.end() );
    const std::vector<std::uint8_t> tierOfFile = pathTierIndexOver( ing, rows, [ & ]( NodeId r ) { return ing.symbols[r].fileId; } );
    std::sort( rows.begin(), rows.end(), [ & ]( NodeId a, NodeId b )
    {
        const Symbol& sa = ing.symbols[a];
        const Symbol& sb = ing.symbols[b];
        if( const int c = compareTierThenPath( ing, tierOfFile, sa.fileId, sb.fileId ); c != 0 )
        {
            return c < 0;
        }
        return sa.line != sb.line ? sa.line < sb.line : sa.name < sb.name;
    } );
    return rows;
}

// Does a SHOWN closure block row carry via="name" (the answer then needs that reading)? Exactly the rows closureBlocks prints.
inline bool closureBlocksAnyVia( const IngestResult& ing, const Graph& g, std::span<const NodeId> closures )
{
    for( std::size_t b = 0; b < std::min( closures.size(), kClosureBlocks ); ++b )
    {
        const std::vector<NodeId> rows = closureCalleeRows( ing, g, closures[b] );
        for( std::size_t i = 0; i < std::min( rows.size(), kClosureRows ); ++i )
        {
            if( edgeNameOnly( g, closures[b], rows[i] ) )
            {
                return true;
            }
        }
    }
    return false;
}

// The callees root's closures="K" [closures_capped="1"] (head) and the <in> blocks (rows), or their JSON spellings: the
// ,"closures":K[,"closures_capped":1] keys and the ,"in":[…] array (keys = the XML attribute names, rows = {t,n,p[,via]}).
// Both empty with no closure, so an answer without one keeps its bytes.
struct ClosureBlocksOut
{
    std::string head;
    std::string rows;
};
inline ClosureBlocksOut closureBlocks( const IngestResult& ing, const Graph& g, std::span<const NodeId> closures, bool singleRoot,
                                       std::string_view rootPrefix, bool json )
{
    if( closures.empty() )
    {
        return {};
    }
    const bool        overCap = closures.size() > kClosureBlocks;
    const std::string k       = std::to_string( closures.size() );
    ClosureBlocksOut  res{ json ? ",\"closures\":" + k + ( overCap ? ",\"closures_capped\":1" : "" )
                                : " closures=\"" + k + "\"" + ( overCap ? " closures_capped=\"1\"" : "" ), {} };
    std::vector<char> esc;
    const auto ex  = [ & ]( std::string_view v ) -> std::string { return std::string( escapeXml( v, esc ) ); };
    const auto rel = [ & ]( const Symbol& s ) -> std::string
    {
        return std::string( singleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix ) : std::string_view( ing.files[ s.fileId ] ) )
             + ":" + std::to_string( s.line );
    };
    const auto sel = [ & ]( const Symbol& s ) -> std::string   // file:name, the selector the block's next= replays
    {
        return std::string( singleRoot ? sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix ) : std::string_view( ing.files[ s.fileId ] ) ) + ":" + s.name;
    };
    std::string out = json ? ",\"in\":[" : "";
    const std::size_t blocks = std::min( closures.size(), kClosureBlocks );
    const std::optional<MemberOwners> owners = json ? std::nullopt : std::optional<MemberOwners>( std::in_place, ing );   // QUALNAME-1: XML rows only (JSON keys stay)
    for( std::size_t b = 0; b < blocks; ++b )
    {
        const NodeId              inner = closures[b];
        const Symbol&             is    = ing.symbols[inner];
        const std::vector<NodeId> rows  = closureCalleeRows( ing, g, inner );
        const std::size_t         shown = std::min( rows.size(), kClosureRows );
        const bool                cut   = shown < rows.size();
        const std::string         next  = cut ? nextFlag( "--callees=", sel( is ) ) : std::string();
        if( json )
        {
            out += std::string( b == 0 ? "" : "," ) + "{\"n\":\"" + jsonStr( is.name ) + "\",\"p\":\"" + jsonStr( rel( is ) ) + "\",\"via\":\"closure\",\"count\":"
                 + std::to_string( rows.size() ) + ( cut ? ",\"shown\":" + std::to_string( shown ) + ",\"capped\":1" : "" ) + nextFieldJson( next ) + ",\"calls\":[";
        }
        else
        {
            out += "<in n=\"" + ex( is.name ) + "\" p=\"" + ex( rel( is ) ) + "\" via=\"closure\" count=\"" + std::to_string( rows.size() ) + "\""
                 + ( cut ? " shown=\"" + std::to_string( shown ) + "\" capped=\"1\"" : "" ) + nextAttrXml( next ) + ">";
        }
        for( std::size_t i = 0; i < shown; ++i )
        {
            const Symbol& s   = ing.symbols[ rows[i] ];
            const bool    via = edgeNameOnly( g, inner, rows[i] );   // FE-B: a name-only edge says so, as on the callees rows
            out += json ? std::string( i == 0 ? "" : "," ) + "{\"t\":\"" + symTag( s.kind ) + "\",\"n\":\"" + jsonStr( s.name ) + "\",\"p\":\"" + jsonStr( rel( s ) ) + "\""
                              + ( via ? ",\"via\":\"name\"" : "" ) + "}"
                        : "<s t=\"" + std::string( symTag( s.kind ) ) + "\" n=\"" + ex( qualifiedMemberName( *owners, s ) ) + "\" p=\"" + ex( rel( s ) ) + "\"" + viaNameAttr( via ) + "/>";
        }
        out += json ? "]}" : "</in>";
    }
    res.rows = json ? out + "]" : out;
    return res;
}

// The callees legend's closure sentence, carried only by an answer with a block (absent otherwise: byte-identical).
inline constexpr std::string_view kClosureBlocksLegend =
    "closures=K: K named functions are written INSIDE of='s body (closures, at any depth); each <in n= p= via=\"closure\" count=> "
    "block lists that closure's OWN callees (count= distinct, at most 8 shown, capped=1 = cut, its next= lists them all), at most 4 "
    "blocks (closures_capped=1 = more). A block is containment, not a call edge: its rows are in no count= above, and of= reaches "
    "them only by running the closure or handing it on. ";
inline std::string_view closureBlocksLegend( bool on ) noexcept
{
    return on ? kClosureBlocksLegend : std::string_view();
}

// The callees answer's <stdm> line (graph.h StdMemberGate, stdMemberCallsMadeBy), one spelling per dialect — the JSON keys
// mirror the XML attributes, n= the same comma-joined value — absent when the definitions made no such call, so every
// answer on a tree the gate never touched keeps its bytes.
inline std::string stdMemberCallsSpelling( const StdMemberCallsMade& m, bool json )
{
    if( m.calls == 0 )
    {
        return {};
    }
    return json ? std::format( ",\"stdm\":{{\"n\":\"{}\",\"calls\":{}}}", m.names, m.calls )
                : std::format( "<stdm n=\"{}\" calls=\"{}\"/>", m.names, m.calls );
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

// tsContractSignatures (the TS contract-vs-overload-signature rule) lives in defattrib.h, beside the definition grouping that
// also reads it.

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

// attrib-multidef (defattrib.h): which definition each row belongs to, over the rows in their FINAL order — computed here,
// once, so every dialect of both surfaces (the CLI verbs and the MCP twins) reads one attribution.
inline CallHierarchyRows withOneHopAttribution( const IngestResult& ing, const Graph& g, CallHierarchyRows rows, bool wantCallers )
{
    rows.attr = attributeOneHopAnswer( ing, g, rows.matches, rows.rows, wantCallers );
    return rows;
}

// LB-G (r10 §5): the served order of a one-hop listing — TIER before path (filter.h states the key once and --uses shares
// it; plain path order put 171 `tests/` rows ahead of anything useful on django's `--callers=bulk_create`), then line, then name.
inline void sortOneHopRows( const IngestResult& ing, std::vector<NodeId>& rows )
{
    const std::vector<std::uint8_t> tierOfFile = pathTierIndexOver( ing, rows, [ & ]( NodeId r ) { return ing.symbols[r].fileId; } );
    std::sort( rows.begin(), rows.end(), [ & ]( NodeId a, NodeId b )
    {
        const Symbol& sa = ing.symbols[a];
        const Symbol& sb = ing.symbols[b];
        if( const int c = compareTierThenPath( ing, tierOfFile, sa.fileId, sb.fileId ); c != 0 )
        {
            return c < 0;
        }
        return sa.line != sb.line ? sa.line < sb.line : sa.name < sb.name;
    } );
}

// The 1-hop CALLER rows of `defs` — the callers verb's rows, and the --for caller hop's (forcallerhop.h): every distinct
// in-edge source of any def, in sortOneHopRows' order, then RANKED BEFORE THE CAP.
// cut-fix C (2026-09-23): within a tier the most-called caller comes first (graph.h navRelevanceWeight; the path order is the
// tie-break), so every window over the callers rows — the CLI's default cap, find_referencing_symbols, and find_symbol's
// calledBy array — keeps the rows most depended on and drops the lightest (filter.h rankBeforeCap states the rule and its
// paging guarantee). CALLERS ONLY. Fix round 1 (2026-09-24, rv-cutfix-navlists B1, blocking): the first cut of that lane
// applied the SAME rank to the callee direction too, unmeasured. It made callees WORSE: this repo's own co-blame instrument
// fell 0.592 -> 0.466 at the default cap (n=18, W/L 1/11), and every multi-row --callees / find_symbol `calls` answer led
// with the row's LEAST specific neighbours (empty, empty, empty, size, c_str) because a callee's rank there is ITS OWN caller
// count, which measures how widely-called that callee is elsewhere, not how central it is to the body that calls it.
inline std::vector<NodeId> oneHopCallerRows( const IngestResult& ing, const Graph& g, std::span<const NodeId> defs )
{
    std::vector<NodeId> rows;
    std::vector<char>   seen( ing.symbols.size(), 0 );
    const auto*         ro = g.inEdges.rowOffsets();
    const auto*         ci = g.inEdges.colIndices();
    for( const NodeId x : defs )
    {
        for( std::uint32_t k = ro[x]; k < ro[x + 1]; ++k )
        {
            if( NodeId c = ci[k]; c < seen.size() && !seen[c] ) { seen[c] = 1;  rows.push_back( c ); }
        }
    }
    sortOneHopRows( ing, rows );
    rankBeforeCap( ing, rows, [ & ]( NodeId r ) { return ing.symbols[r].fileId; },
                   [ & ]( NodeId r ) { return navRelevanceWeight( g, r ); } );
    return rows;
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

    if( wantCallers )
    {
        out.rows = oneHopCallerRows( ing, g, out.matches );   // collected, tier/path ordered and ranked before the cap (below)
    }
    else
    {
        std::vector<char> seen( ing.symbols.size(), 0 );
        for( const NodeId x : out.matches )
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
        sortOneHopRows( ing, out.rows );   // callees keep the tier/path order: no rank (oneHopCallerRows says why)
    }

    std::tie( out.declinedCalls, out.declinedSites ) = declinedCallsAndSites( ing, g, out.matches, wantCallers );   // the count and its <dc> rows
    out.declinedIface = wantCallers ? declinedIfaceCallsNaming( ing, g, out.matches ) : 0;
    out.stdCalls      = wantCallers ? StdMemberCallsMade{} : stdMemberCallsMadeBy( g, out.matches );

    // Reference-as-value round: the <vr> rows beside the call rows — the binding sites of `matches` (callers), or what
    // `matches` stores/passes and may call through (callees). Never merged into `rows`: they are not calls.
    {
        const std::optional<ValueRefIndex> local = valueIndex == nullptr ? std::optional<ValueRefIndex>( std::in_place, ing ) : std::nullopt;
        const ValueRefIndex&               vri   = valueIndex != nullptr ? *valueIndex : *local;
        out.valueRefs = withPatternRows( wantCallers ? valueRefCallerRows( ing, vri, out.matches ) : valueRefCalleeRows( ing, vri, out.matches ), PatternIndex( ing, vri ), out.matches, wantCallers );
    }
    return withOneHopAttribution( ing, g, std::move( out ), wantCallers );
}

// C2 callers byte band (pageview.h kCallersBandMaxBytes): the estimated bytes of EVERY row of a callers answer, so
// callHierarchyRowCap can serve the whole list when it fits, plus the site pass that estimate needed (the emitter reuses it
// instead of walking the reference table twice). The estimate is the XML row each caller prints — `<s t= n= p=file:line/>`
// with its tested=, via=, prov=, of_def= and sites_at=/sites_total= — with n= and p= XML-escaped as the row prints them
// (a `<file-scope>` caller is `&lt;file-scope&gt;`, 6 B more; rv-callers-band2 N1) but without a macro row's role=, so it
// reads at or a little below the bytes printed. ONE number for every surface (CLI XML, columnar, --json, MCP), so the
// dialects agree on whether an answer is cut. rowBytes = 0 means no estimate was made: an explicit --limit, a total the row
// band already covers, or a total too large to fit the band at kCallerRowMinBytes a row. `attr` is the rows' own
// attribution (its row index = the position in `rows`); `testReach` the tested lens's reach (HopTestedPartition::testReach);
// `keptForwards` Graph::keptForwards, so the band's site pass counts the same kept forwards as rowCallSites' other readers
// (model.h forwardCounts; train 31 merge of callers-band2 over fcall-forward).
struct CallersByteBand
{
    std::size_t  rowBytes;
    RowCallSites sites;   // over every row, in row order, exactly when rowBytes > 0
};

// The band is built in a local and returned as one aggregate. (Fix round 1 restructured this for the gcc-14.2 Release/LTO
// rc=139; the SEGV round found the cause in pageview.h callHierarchyRowCap's unstated precondition, not here.)
inline CallersByteBand callersByteBand( const IngestResult& ing, std::span<const NodeId> defs, std::span<const NodeId> rows, const VrRender& rr, int pageLimit,
                                        const std::vector<char>& testReach, const OneHopAttribution& attr, std::span<const std::uint32_t> keptForwards )
{
    if( pageLimit > 0 || rows.size() <= std::size_t( kCallHierarchyBandMax ) || rows.size() > kCallersBandMaxBytes / kCallerRowMinBytes )
    {
        return CallersByteBand{};
    }
    RowCallSites       sites = rowCallSites( ing, defs, rows, rr, keptForwards );
    std::vector<char>  esc;   // the escape buffer the row's n= and p= are measured through
    const MemberOwners owners( ing );   // QUALNAME-1: the row's n= is its owner-qualified name (memberowner.h), so the estimate charges it
    std::size_t       bytes = 0;
    for( std::size_t i = 0; i < rows.size(); ++i )
    {
        const Symbol&     s       = ing.symbols[ rows[i] ];
        const std::size_t nameLen = escapeXml( qualifiedMemberName( owners, s ), esc ).size();
        const std::size_t pathLen = escapeXml( vrPath( ing, s.fileId, rr ), esc ).size();
        bytes += std::string_view( "<s t=\"\" n=\"\" p=\":\"/>" ).size() + std::string_view( symTag( s.kind ) ).size() + nameLen + pathLen
               + std::to_string( s.line ).size()
               + ( isTestedByReach( ing, testReach, rows[i] ) ? std::string_view( " tested=\"1\"" ).size() : 0 )
               + std::string_view( viaNameAttr( attr.nameOnly( i ) ) ).size() + std::string_view( splitArmAttrXml( attr.splitArm( i ) ) ).size()
               + ofDefAttrXml( attr.groups, attr.tokens, i ).size() + callSitesAttrXml( sites.tokens[i], sites.totals[i] ).size();
    }
    ENSURES( sites.tokens.size() == rows.size(), "the site pass covers every row the estimate read" );   // rowCallSites' own ENSURES
    return CallersByteBand{ std::max( bytes, std::size_t( 1 ) ), std::move( sites ) };
}

}   // namespace rw
