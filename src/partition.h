#pragma once

// partition.h — `--pack-task="TASK" --partition=N`, the FAN-OUT form of the task bundle.
// Evidence: four parallel audit agents each re-derived the SAME orientation context for one shared task.
// Four agents × one `--pack-task` each = four near-identical bundles: the same top symbols, the same bodies,
// the same tests — four times the tokens for one map. What the orchestrator actually wanted was ONE map cut
// into four slices plus the bit they all need.
//
// This file is deliberately a COMPOSITION, not a new bundle format: every emitted bundle is produced by the
// SAME packTaskBundleText() (packtask.h) that plain `--pack-task` and the MCP explore verb call, given a
// RANK VECTOR MASKED to that bundle's assigned symbols. Nothing about a bundle's internal shape is decided
// here — sections, budget shares, truncation reporting, the d0/d1/d2 detail ladder all stay in the one
// assembler, so the partitioned and single forms can never drift. Each `<ctx>…</ctx>` inside the output is
// byte-for-byte what a standalone call with that mask would emit, so an orchestrator can slice one out and
// hand it to an agent verbatim.
//
// ── the four decisions this file owns (and why) ───────────────────────────────────────────────────────────
//
// 1. THE SURFACE. The task-relevant surface is the top-ranked positive-score head, sized
//    `kPackTaskBodyCandidates + kPackTaskRankTopN × N` — big enough that every partition can fill its own
//    ranking window and the core still has its anchors, and no bigger (a surface past that is rank noise the
//    single-bundle form would never have shown either).
//
// 2. THE COMMON CORE = the top `kPackTaskBodyCandidates` of that surface — EXACTLY the anchors a plain
//    `--pack-task` would have given full bodies to. That is the principled cut: those symbols are what the
//    task statement is literally about, and an agent that does not know their shape cannot read its own
//    slice. Below that head is where a task's surface genuinely spreads across modules, and that is what
//    gets carved. Core ids are REMOVED from the partitions (repeating them would spend every agent's budget
//    on the same bytes twice) — but their 1-hop neighborhoods can legitimately reappear inside a partition,
//    and that is measured, not hidden (see `core_overlap`).
//
// 3. COMMUNITY → PARTITION. First, a symbol the call graph is SILENT about (no in- or out-edge — Louvain's
//    `isolated=` population, and the bulk of any data-type-heavy surface) is grouped by its FILE instead of
//    by its own singleton community; see groupKeyFor below for why that is not a cheat. Then, when the group
//    count K and the partition count N disagree, in both directions:
//      K ≥ N  → pack WHOLE communities into N bins, largest-first onto the lightest bin (LPT). A partition
//               is then a UNION OF WHOLE MODULES — coherent to read — and LPT keeps the bundles comparable
//               in size so no agent gets a slice it cannot finish.
//      K < N  → fewer modules than agents; something must be cut. Cut the widest group at its rank median,
//               repeatedly, until there are N groups. Rank-median is the least arbitrary cut available: both
//               halves stay contiguous in relevance, so each still reads as "the next most relevant slice of
//               this module" instead of an interleaved scatter. `split=` reports how many cuts it took.
//      All groups singletons and still K < N → emit K partitions, report `partitions` < `requested`. A verb
//               that silently invents empty bundles to hit the number would be worse than one that says so.
//
// 4. THE BUDGET is PER AGENT, not global. `--token-budget` in partition mode means "what ONE agent's context
//    can hold", and it is split core/partition `kCoreBudgetShare` : (1 − kCoreBudgetShare), so core + any one
//    partition lands under it. Dividing a single global budget by N instead would make every bundle 1/N-sized
//    and useless at N=8 — the opposite of the point. The TOTAL emitted is therefore ~budget × (share + N×rest)
//    and the header states it, so nobody is surprised by the byte count on stdout.
//
// DETERMINISM. The assignment is a pure function of (repo, task, N). Louvain here is the same deterministic
// `communities( g )` --communities uses (id-order local moving, ties → lower community id). Everything this
// file layers on top is INTEGER-keyed on purpose: groups are discovered in best-rank order (no sort at all),
// bin packing orders by member COUNT with a stable sort (ties → lower group index) and breaks load ties to
// the lowest bin index, and the split picks the widest group with ties → lowest index. No float comparison
// decides any assignment, so the plan cannot drift with a reordered floating-point sum.

#include "packtask.h"           // packTaskBundleText / LensRanking / PackTaskInputs / kPackTask* constants
#include "graph.h"              // communities() — the SAME deterministic Louvain --communities uses
#include "clones.h"             // findClones — hoisted here so N+1 bundles share ONE clone pass
#include "serialize.h"          // kMinBytesPerToken / jsonStr
#include "infra/Diagnostics.h"  // DEGRADED_PATH_ALERT

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

namespace rw
{
namespace packpartition
{

// N bounds. 2 because a 1-way "split" is just --pack-task (refused at the CLI seam, VERIFYed here); 16 to
// match the multi-root cap — the same "an orchestrator fanning out past this is doing something else" line.
inline constexpr std::uint32_t kMinPartitions = 2;
inline constexpr std::uint32_t kMaxPartitions = 16;

// the share of ONE AGENT's token budget the shared core takes; the partition gets the rest (see decision 4).
inline constexpr double kCoreBudgetShare = 0.34;

// how much ranked surface each partition is sized for — the assembler's own ranking window, so a partition
// that fills its window looks exactly like a standalone --pack-task run.
inline constexpr std::size_t kSurfacePerPartition = std::size_t( kPackTaskRankTopN );

// ── the plan ──────────────────────────────────────────────────────────────────────────────────────────────

struct PartitionPlan
{
    std::vector<NodeId>              coreIds;            // the shared common core, rank order
    std::vector<std::vector<NodeId>> groups;             // groups[p] = partition p's assigned ids, rank order
    std::vector<std::uint32_t>       groupModuleCount;   // whole groups (community or file) that landed in groups[p]
    std::uint32_t                    surfaceCount   = 0; // |core| + |assignable|
    std::uint32_t                    moduleCount    = 0; // distinct groups on the assignable surface (community, or FILE
                                                         // for the call-graph-edgeless — see groupKeyFor)
    std::uint32_t                    splitCount     = 0; // community cuts forced by K < N (0 = none)
};

// the assignable surface grouped by community, each group in rank order, the GROUPS themselves in best-rank
// order (a community's group appears where its highest-ranked member appears). Discovery order IS the order —
// no sort runs here, so the grouping cannot depend on a map's iteration order.
struct CommunityGroups
{
    std::vector<std::vector<NodeId>> members;
    std::vector<std::uint64_t>       groupKey;   // the tagged key each group was discovered under (see groupKeyFor)
};

// ── the ISOLATE fallback (dogfooding found this, and it matters) ──────────────────────────────────────────
// Louvain leaves a call-graph-EDGELESS symbol alone in its own singleton community — the same `isolated=`
// population --communities reports. Data types are the common case: on an "audit the uniform structs" task
// nearly the whole ranked surface is edgeless, every group is a singleton, and packing them by community
// degenerates into a load-balanced round-robin that scatters one header's five structs across four agents.
// The call graph has no opinion about those symbols — so fall back to the grouping the repo DOES assert, the
// FILE: five structs in one header are one unit of reading whether or not anything calls them. Symbols WITH
// edges keep their community, unchanged; only the ones the graph is silent about move. The two key spaces
// are tagged so a community id and a file id can never collide.
inline std::uint64_t groupKeyFor( const IngestResult& ing, const Graph& g, const Communities& cm, NodeId id )
{
    const auto* inRowOffset  = g.inEdges.rowOffsets();
    const bool  hasCallEdges = id + 1 < g.outOff.size()
                            && ( g.outOff[id] != g.outOff[id + 1] || inRowOffset[id] != inRowOffset[id + 1] );
    if( hasCallEdges )
    {
        return std::uint64_t( id < cm.comm.size() ? cm.comm[id] : 0u );
    }
    return ( std::uint64_t( 1 ) << 32 ) | ( id < ing.symbols.size() ? ing.symbols[id].fileId : 0u );
}

inline CommunityGroups groupSurfaceByCommunity( const IngestResult& ing, const Graph& g,
                                                const std::vector<NodeId>& assignable, const Communities& cm )
{
    CommunityGroups out;
    HashMap<std::uint64_t, std::uint32_t> slotOfKey;
    slotOfKey.reserve( assignable.size() );
    for( NodeId id : assignable )
    {
        const std::uint64_t key = groupKeyFor( ing, g, cm, id );
        const auto          it  = slotOfKey.find( key );
        std::uint32_t       slot;
        if( it == slotOfKey.end() )
        {
            slot = std::uint32_t( out.members.size() );
            slotOfKey.emplace( key, slot );
            out.members.emplace_back();
            out.groupKey.push_back( key );
        }
        else
        {
            slot = it->second;
        }
        out.members[ slot ].push_back( id );
    }
    return out;
}

inline constexpr std::size_t kNoGroup = SIZE_MAX;   // "no splittable group" — distinct from any valid group INDEX

// the widest group with at least 2 members, ties → lowest index. kNoGroup when every group is a singleton.
// Member COUNT decides, never a score, so the choice is integer-deterministic.
inline std::size_t widestSplittableGroup( const CommunityGroups& grp )
{
    std::size_t widestIndex = kNoGroup;
    for( std::size_t i = 0; i < grp.members.size(); ++i )
    {
        if( grp.members[i].size() >= 2 && ( widestIndex == kNoGroup || grp.members[i].size() > grp.members[ widestIndex ].size() ) )
        {
            widestIndex = i;
        }
    }
    return widestIndex;
}

// K < N (decision 3, second direction): cut the WIDEST group at its rank median — top half stays, bottom half
// becomes a new group appended at the end — until there are `targetCount` groups or every group is a
// singleton. Returns the number of cuts made (0 = the community structure already had enough modules).
inline std::uint32_t splitGroupsUpTo( CommunityGroups& grp, std::uint32_t targetCount )
{
    std::uint32_t cuts = 0;
    while( grp.members.size() < std::size_t( targetCount ) )
    {
        const std::size_t widest = widestSplittableGroup( grp );
        if( widest == kNoGroup )
        {
            break; // every group is a singleton — N is unreachable, caller reports it
        }

        std::vector<NodeId>& src  = grp.members[ widest ];
        const std::size_t    half = ( src.size() + 1 ) / 2;
        std::vector<NodeId>  tail( src.begin() + std::ptrdiff_t( half ), src.end() );
        src.resize( half );
        grp.members.push_back( std::move( tail ) );
        grp.groupKey.push_back( grp.groupKey[ widest ] );
        ++cuts;
    }
    return cuts;
}

// K >= N (decision 3, first direction): largest-first bin packing of WHOLE groups into `binCount` bins.
// Returns bins[b] = the group indices assigned to bin b.
inline std::vector<std::vector<std::uint32_t>> packGroupsIntoBins( const CommunityGroups& grp, std::uint32_t binCount )
{
    VERIFY( binCount > 0 );
    std::vector<std::uint32_t> byWeight( grp.members.size() );
    for( std::uint32_t i = 0; i < byWeight.size(); ++i )
    {
        byWeight[i] = i;
    }
    std::stable_sort( byWeight.begin(), byWeight.end(),                                   // stable ⇒ ties keep index order
                      [ & ]( std::uint32_t a, std::uint32_t b ) { return grp.members[a].size() > grp.members[b].size(); } );

    std::vector<std::vector<std::uint32_t>> bins( binCount );
    std::vector<std::size_t>                binLoad( binCount, 0 );
    for( std::uint32_t gi : byWeight )
    {
        std::size_t lightest = 0;
        for( std::size_t b = 1; b < binCount; ++b )
        {
            if( binLoad[b] < binLoad[lightest] )
            {
                lightest = b; // ties → lowest index
            }
        }
        bins[ lightest ].push_back( gi );
        binLoad[ lightest ] += grp.members[ gi ].size();
    }
    return bins;
}

// THE plan: (repo, task-ranking, N) → core + N disjoint id groups. Pure; no I/O, no wall clock.
inline PartitionPlan planPartition( const IngestResult& ing, const Graph& g, const std::vector<float>& rank, std::uint32_t partitionCount )
{
    VERIFY( partitionCount >= kMinPartitions && partitionCount <= kMaxPartitions );
    PartitionPlan plan;

    // ── decision 1 — the task-relevant surface (top ranked, positive score only) ──────────────────────────
    std::vector<NodeId> order( ing.symbols.size() );
    for( NodeId i = 0; i < order.size(); ++i )
    {
        order[i] = i;
    }
    sortutil::radixSortByScoreDescId( order, rank );

    const std::size_t   surfaceCap = kPackTaskBodyCandidates + kSurfacePerPartition * std::size_t( partitionCount );
    std::vector<NodeId> surface;
    surface.reserve( surfaceCap );
    for( std::size_t k = 0; k < order.size() && surface.size() < surfaceCap; ++k )
    {
        if( rank[order[k]] <= 0.0f )
        {
            break; // a zero-score symbol is not on the task's surface at all
        }
        surface.push_back( order[k] );
    }
    plan.surfaceCount = std::uint32_t( surface.size() );

    // ── decision 2 — the shared common core = the anchors a plain --pack-task would have bodied ───────────
    const std::size_t coreCount = std::min( kPackTaskBodyCandidates, surface.size() );
    plan.coreIds.assign( surface.begin(), surface.begin() + std::ptrdiff_t( coreCount ) );
    const std::vector<NodeId> assignable( surface.begin() + std::ptrdiff_t( coreCount ), surface.end() );
    if( assignable.empty() )                       // nothing beyond the core to carve — 0 partitions, honestly reported
    {
        DEGRADED_PATH_ALERT( "pack-task partition: the task's ranked surface fits entirely in the shared core — no partitions to carve" );
        return plan;
    }

    // ── decision 3 — communities → partitions ─────────────────────────────────────────────────────────────
    const Communities cm  = communities( g );
    CommunityGroups   grp = groupSurfaceByCommunity( ing, g, assignable, cm );
    plan.moduleCount      = std::uint32_t( grp.members.size() );
    plan.splitCount       = splitGroupsUpTo( grp, partitionCount );          // no-op when K >= N

    const std::uint32_t binCount = std::min<std::uint32_t>( partitionCount, std::uint32_t( grp.members.size() ) );
    if( binCount < partitionCount )
    {
        DEGRADED_PATH_ALERT( "pack-task partition: fewer separable modules than partitions requested — emitting the modules that exist" );
    }

    const std::vector<std::vector<std::uint32_t>> bins = packGroupsIntoBins( grp, binCount );
    plan.groups.resize( binCount );
    plan.groupModuleCount.assign( binCount, 0u );
    for( std::uint32_t b = 0; b < binCount; ++b )
    {
        for( std::uint32_t gi : bins[b] )
        {
            plan.groups[b].insert( plan.groups[b].end(), grp.members[gi].begin(), grp.members[gi].end() );
            ++plan.groupModuleCount[b];
        }
        // back to the GLOBAL rank order inside the bundle (score desc, id asc) — the same total order the
        // assembler and every other ranked verb present in.
        std::sort( plan.groups[b].begin(), plan.groups[b].end(),
                   [ & ]( NodeId lhs, NodeId rhs ) { return rank[lhs] != rank[rhs] ? rank[lhs] > rank[rhs] : lhs < rhs; } );
    }
    return plan;
}

// ── overlap measurement ───────────────────────────────────────────────────────────────────────────────────
// Measured over each bundle's SURFACE — the ids the bundle actually names: its ranking window (incl. the
// name-only <far> tier) ∪ its full-body anchors ∪ their 1-hop callers and callees (which is also where the
// inline <c> callee signatures inside each body come from). Reported by the assembler itself via its
// surfaceOut tail, so this is what the emitted XML talks about, not a re-derivation that could disagree with
// it. HONEST LIMIT: it is the pre-budget-trim surface — a bundle whose tail was trimmed names slightly fewer
// symbols than this counts, so the figures are a ceiling on the overlap actually paid for.

struct OverlapStats
{
    double        mean = 0.0;          // mean pairwise Jaccard over the partition bundles
    double        worst = 0.0;         // worst (max) pairwise Jaccard
    double        coreLeak = 0.0;      // fraction of the CORE bundle's surface that also appears in some partition
    std::uint32_t sharedCount = 0;     // ids named by two or more partition bundles
    std::uint32_t unionCount = 0;      // distinct ids named by any partition bundle
};

inline std::size_t sortedIntersectionSize( const std::vector<NodeId>& a, const std::vector<NodeId>& b )
{
    std::size_t n = 0, i = 0, j = 0;
    while( i < a.size() && j < b.size() )
    {
        if( a[i] == b[j] )      { ++n;  ++i;  ++j; }
        else if( a[i] < b[j] )
        {
            ++i;
        }
        else
        {
            ++j;
        }
    }
    return n;
}

inline OverlapStats measureOverlap( const std::vector<std::vector<NodeId>>& surfaces, const std::vector<NodeId>& coreSurface )
{
    OverlapStats out;

    // pairwise Jaccard
    std::size_t pairCount = 0;
    double      sum = 0.0;
    for( std::size_t i = 0; i < surfaces.size(); ++i )
    {
        for( std::size_t j = i + 1; j < surfaces.size(); ++j )
        {
            const std::size_t inter = sortedIntersectionSize( surfaces[i], surfaces[j] );
            const std::size_t uni   = surfaces[i].size() + surfaces[j].size() - inter;
            const double      jac   = uni == 0 ? 0.0 : double( inter ) / double( uni );
            sum += jac;  ++pairCount;
            if( jac > out.worst )
            {
                out.worst = jac;
            }
        }
    }
    out.mean = pairCount == 0 ? 0.0 : sum / double( pairCount );

    // shared / union across all partition surfaces
    std::vector<NodeId> all;
    for( const std::vector<NodeId>& s : surfaces )
    {
        all.insert( all.end(), s.begin(), s.end() );
    }
    std::sort( all.begin(), all.end() );
    for( std::size_t i = 0; i < all.size(); )
    {
        std::size_t j = i;
        while( j < all.size() && all[j] == all[i] )
        {
            ++j;
        }
        ++out.unionCount;
        if( j - i >= 2 )
        {
            ++out.sharedCount;
        }
        i = j;
    }

    // how much of the CORE bundle's surface a partition re-derives anyway (0 = the core is pure shared cost)
    std::vector<NodeId> unionIds = all;
    unionIds.erase( std::unique( unionIds.begin(), unionIds.end() ), unionIds.end() );
    if( !coreSurface.empty() )
    {
        out.coreLeak = double( sortedIntersectionSize( coreSurface, unionIds ) ) / double( coreSurface.size() );
    }
    return out;
}

// ── the driver ────────────────────────────────────────────────────────────────────────────────────────────

// one emitted bundle: the assembler's verbatim <ctx>…</ctx> plus the plan facts the wrapper element carries.
struct BundleOut
{
    std::string         xml;
    std::string         json;
    std::vector<NodeId> surface;
    std::uint32_t       assigned = 0;
    std::uint32_t       modules  = 0;
};

// the fixed context every bundle render shares — grouped (not individual params) so renderMaskedBundle stays
// under the params-regression bar, the same shape packtask.h's own D1WalkCtx/RankingSectionInputs use.
struct BundleRenderCtx
{
    const IngestResult*   ing;
    const Graph*          g;
    const std::string*    task;
    const LensRanking*    lr;
    const PackTaskInputs* in;
    bool                  wantJson = false;
};

// render ONE bundle through the shared assembler with the ranking MASKED to `keep`. The mask is
// packtask.h's own buildMaskedRank — the same "pin everything else below any real score" primitive the
// assembler already uses internally for its d0∪d1 eligibility cut, not a second spelling of it.
inline BundleOut renderMaskedBundle( const BundleRenderCtx& ctx, const std::vector<NodeId>& keep, std::size_t budgetTokens )
{
    BundleOut out;
    out.assigned = std::uint32_t( keep.size() );

    LensRanking masked = *ctx.lr;                                        // keeps route/mention/boost notes on every bundle
    masked.rank        = buildMaskedRank( *ctx.ing, ctx.lr->rank, keep );

    PackTaskInputs in = *ctx.in;
    in.budgetTokens   = budgetTokens;
    in.rankTopN       = std::min( std::size_t( kPackTaskRankTopN ), keep.size() );   // never widen the window past the slice

    out.xml = packTaskBundleText( *ctx.ing, *ctx.g, *ctx.task, masked, in, ctx.wantJson ? &out.json : nullptr, &out.surface );
    std::sort( out.surface.begin(), out.surface.end() );
    out.surface.erase( std::unique( out.surface.begin(), out.surface.end() ), out.surface.end() );
    return out;
}

// the wrapper element's summary attributes — one snprintf, so the XML and JSON forms below read the same
// numbers from the same place.
struct PartitionSummary
{
    std::uint32_t emitted = 0, requested = 0;
    std::size_t   agentTokens = 0, coreTokens = 0, partitionTokens = 0, totalBytes = 0;
};

inline std::string partitionSummaryAttrs( const PartitionPlan& plan, const PartitionSummary& sum, const OverlapStats& ov )
{
    char b[ 640 ];
    std::snprintf( b, sizeof( b ),
                   " partitions=\"%u\" requested=\"%u\" core_symbols=\"%zu\" surface=\"%u\" modules=\"%u\" split=\"%u\""
                   " budget_per_agent_tokens=\"%zu\" core_budget_tokens=\"%zu\" partition_budget_tokens=\"%zu\" total_bytes=\"%zu\""
                   " overlap_mean=\"%.3f\" overlap_max=\"%.3f\" shared_symbols=\"%u\" union_symbols=\"%u\" core_overlap=\"%.3f\"",
                   sum.emitted, sum.requested, plan.coreIds.size(), plan.surfaceCount, plan.moduleCount, plan.splitCount,
                   sum.agentTokens, sum.coreTokens, sum.partitionTokens, sum.totalBytes,
                   ov.mean, ov.worst, ov.sharedCount, ov.unionCount, ov.coreLeak );
    return b;
}

// The partitioned-bundle legend, hoisted to a file-scope constant on the same reasoning situ.h gives for
// kTestGateLegend: it is a paragraph, not control flow. Inlined, ~27 lines of prose sat inside
// packTaskPartitionText and made the driver read long when none of its LOGIC had grown.
inline constexpr const char* kPartitionLegend =
    "<!-- ripwire partitioned task bundle: ONE shared common core plus N minimally overlapping per agent slices, "
    "carved along the call graph's own community structure. Each bundle wraps one ctx document, exactly what a standalone "
    "pack task call with that slice would emit, so an orchestrator hands one bundle to one agent verbatim. budget_per_agent_tokens is "
    "the budget for core PLUS one partition, not the whole document; total_bytes is the bundles' combined size. "
    "overlap_mean/overlap_max are pairwise Jaccard over the ids each partition names (ranking window, bodies, and their "
    "1 hop neighbors), measured BEFORE budget trimming, so they are a ceiling. shared_symbols counts the ids TWO OR "
    "MORE partitions name — NOT the ids every partition names; an id two of sixteen slices both carry is already "
    "duplicated work — and union_symbols the ids ANY partition names: one GLOBAL at-least-two over at-least-one "
    "pair, not an average. That ratio and overlap_mean (an average of PAIRWISE Jaccard) therefore answer different "
    "questions. They COINCIDE at partitions=2, where there is one pair and at-least-two IS its intersection while "
    "at-least-one IS its union, so the ratio equals that pair's Jaccard by identity; from 3 partitions on the two "
    "genuinely diverge, and neither is wrong. The remaining root counters, one clause each. requested= is the "
    "partition count N asked for and partitions= the bundles actually carved; partitions is lower only where the plan "
    "could not reach N, which is either a ranked surface that fit entirely in the shared core (partitions=0, nothing "
    "left to carve) or a surface holding fewer separable modules than N even after splitting. modules= is the distinct "
    "groups found on the assignable surface BEFORE any cut (a call-graph community, or the FILE where that surface "
    "carries no call edges), and split= the community cuts forced because those modules numbered fewer than N, so "
    "modules + split is the group count the bundles were packed from and split=0 means no cut was needed. "
    "core_symbols= is the shared core's size — the body anchors a plain pack task would have expanded, held out of "
    "every partition — and surface= is core_symbols plus the assignable remainder, i.e. the whole positive-rank "
    "window this plan carved up. core_budget_tokens= and partition_budget_tokens= are budget_per_agent_tokens split "
    "between the two halves one agent receives, and they sum to it. core_overlap is the share of the core "
    "bundle's own surface a partition reaches anyway. On each bundle, est_tokens and tokens are the SAME number: "
    "tokens is the original name kept for compatibility, est_tokens is the spelling the rest of the tool uses and "
    "the one to read. Both are that bundle's own bytes= divided by 2.36 B/tok — the DENSEST calibrated language "
    "rate — which is a different (deliberately conservative) currency from the default map's est_tokens, where "
    "the divisor is that corpus's own language-weighted rate: measured over real emitted bytes either way, but a "
    "bundle's number reads slightly HIGH, which is the safe direction for a per-agent budget. On this root "
    "element the unit is carried in the NAME instead (budget_per_agent_tokens, total_bytes) rather than by a "
    "separate unit attribute, which is a deliberate exception to the est_tokens convention and not a second "
    "estimator. -->";

// THE verb: `--pack-task="TASK" --partition=N`. Returns the whole <ctx-partitions>…</ctx-partitions> document
// (never touches stdout — the caller owns the sink, exactly like packTaskBundleText). `jsonOut`, when given,
// receives the same plan + the same per-bundle decisions in JSON, from the SAME assembler calls.
inline std::string packTaskPartitionText( const IngestResult& ing, const Graph& g, const std::string& task,
                                          const LensRanking& lr, const PackTaskInputs& inBase,
                                          std::uint32_t partitionCount, std::string* jsonOut = nullptr )
{
    VERIFY( partitionCount >= kMinPartitions && partitionCount <= kMaxPartitions );
    const PartitionPlan plan = planPartition( ing, g, lr.rank, partitionCount );

    // ── decision 4 — the per-AGENT budget split ───────────────────────────────────────────────────────────
    PartitionSummary sum;
    sum.emitted         = std::uint32_t( plan.groups.size() );
    sum.requested       = partitionCount;
    sum.agentTokens     = inBase.budgetTokens > 0 ? inBase.budgetTokens : std::size_t( kPackTaskDefaultTokens );
    sum.coreTokens      = std::max<std::size_t>( 1, std::size_t( double( sum.agentTokens ) * kCoreBudgetShare ) );
    sum.partitionTokens = sum.agentTokens > sum.coreTokens ? sum.agentTokens - sum.coreTokens : 1;

    // the Q3 clone lens is a pure function of `ing` and costs a full clone pass — hoist it out of the N+1
    // assembler calls so a 16-way fan-out pays for it ONCE (the assembler computes its own when unset).
    std::vector<std::uint8_t> cloneMember( ing.symbols.size(), 0u );
    for( const CloneGroup& cg : findClones( ing, 40 ) )
    {
        for( NodeId m : cg.members )
        {
            if( m < cloneMember.size() )
            {
                cloneMember[m] = 1u;
            }
        }
    }

    PackTaskInputs in = inBase;
    in.cloneMember    = &cloneMember;

    // ── the bundles: core first, then one per partition — every one through the SAME assembler ────────────
    const BundleRenderCtx renderCtx{ &ing, &g, &task, &lr, &in, jsonOut != nullptr };   // NOT named `ctx` — that is the namespace kMinBytesPerToken below is qualified with
    const BundleOut       core = renderMaskedBundle( renderCtx, plan.coreIds, sum.coreTokens );

    std::vector<BundleOut> parts;
    parts.reserve( plan.groups.size() );
    for( std::size_t p = 0; p < plan.groups.size(); ++p )
    {
        BundleOut b = renderMaskedBundle( renderCtx, plan.groups[p], sum.partitionTokens );
        b.modules   = plan.groupModuleCount[p];
        parts.push_back( std::move( b ) );
    }

    std::vector<std::vector<NodeId>> partSurfaces;
    partSurfaces.reserve( parts.size() );
    for( const BundleOut& b : parts )
    {
        partSurfaces.push_back( b.surface );
    }
    const OverlapStats ov = measureOverlap( partSurfaces, core.surface );

    sum.totalBytes = core.xml.size();
    for( const BundleOut& b : parts )
    {
        sum.totalBytes += b.xml.size();
    }

    // ── the document ──────────────────────────────────────────────────────────────────────────────────────
    // The wrapper comment is deliberately STATIC (it never echoes the task) — a task string containing "--"
    // would otherwise make the comment malformed, and every inner <ctx> already echoes the task itself (G4).
    const auto bundleOpen = []( const char* role, int index, const BundleOut& b ) -> std::string
    {
        // §P8 vocabulary: this number is the tool's est_tokens under a THIRD spelling — `tokens=`. Renaming
        // it outright would break every caller already reading `tokens=`, so est_tokens= is emitted ALONGSIDE
        // it with the identical value (one expression, evaluated once, written to both — never two counters),
        // and the wrapper comment below declares them aliases. `tokens=` is the compatibility name; new
        // consumers should read est_tokens=, which is what the other ~10 verbs that report a size call it.
        //
        // §H7/§B13.4: this estimate was already the honest KIND — measured over the bundle's real emitted
        // bytes, never a model of a symbol set — but at the CONSERVATIVE densest-language rate rather than the
        // map family's language-weighted one, i.e. a third CURRENCY, and it said so nowhere. It keeps that rate
        // (a fan-out plan hands each agent a budget, and a per-agent size that reads slightly HIGH is the safe
        // direction) and now goes through the same tokensForEmittedBytes seam every other charged emitter uses,
        // with the rate named in kPartitionLegend so a reader can reconcile it against a map's est_tokens.
        const std::size_t estTokens = rw::tokensForEmittedBytes( b.xml.size(), rw::kMinBytesPerToken );
        char h[ 288 ];
        if( index < 0 )
        {
            std::snprintf( h, sizeof( h ), "<bundle role=\"%s\" symbols=\"%u\" bytes=\"%zu\" tokens=\"%zu\" est_tokens=\"%zu\">",
                           role, b.assigned, b.xml.size(), estTokens, estTokens );
        }
        else
        {
            std::snprintf( h, sizeof( h ), "<bundle role=\"%s\" i=\"%d\" symbols=\"%u\" modules=\"%u\" bytes=\"%zu\" tokens=\"%zu\" est_tokens=\"%zu\">",
                           role, index, b.assigned, b.modules, b.xml.size(), estTokens, estTokens );
        }
        return h;
    };

    std::string whole = "<ctx-partitions";
    whole += partitionSummaryAttrs( plan, sum, ov );
    whole += ">";
    whole += kPartitionLegend;
    whole += bundleOpen( "core", -1, core );
    whole += core.xml;
    whole += "</bundle>";
    for( std::size_t p = 0; p < parts.size(); ++p )
    {
        whole += bundleOpen( "partition", int( p ), parts[p] );
        whole += parts[p].xml;
        whole += "</bundle>";
    }
    whole += "</ctx-partitions>";

    if( jsonOut )
    {
        std::string& j = *jsonOut;
        char         nb[ 640 ];
        std::snprintf( nb, sizeof( nb ),
                       "{\"partitions\":%u,\"requested\":%u,\"core_symbols\":%zu,\"surface\":%u,\"modules\":%u,\"split\":%u,"
                       "\"budget_per_agent_tokens\":%zu,\"core_budget_tokens\":%zu,\"partition_budget_tokens\":%zu,\"total_bytes\":%zu,"
                       "\"overlap_mean\":%.3f,\"overlap_max\":%.3f,\"shared_symbols\":%u,\"union_symbols\":%u,\"core_overlap\":%.3f",
                       sum.emitted, sum.requested, plan.coreIds.size(), plan.surfaceCount, plan.moduleCount, plan.splitCount,
                       sum.agentTokens, sum.coreTokens, sum.partitionTokens, sum.totalBytes,
                       ov.mean, ov.worst, ov.sharedCount, ov.unionCount, ov.coreLeak );
        j  = nb;
        j += ",\"task\":\"" + jsonStr( task ) + "\",\"core\":" + ( core.json.empty() ? "{}" : core.json ) + ",\"bundles\":[";
        for( std::size_t p = 0; p < parts.size(); ++p )
        {
            char pb[ 96 ];
            std::snprintf( pb, sizeof( pb ), "%s{\"index\":%zu,\"symbols\":%u,\"modules\":%u,\"bundle\":",
                           p == 0 ? "" : ",", p, parts[p].assigned, parts[p].modules );
            j += pb;
            j += parts[p].json.empty() ? "{}" : parts[p].json;
            j += "}";
        }
        j += "]}";
    }
    return whole;
}

}   // namespace packpartition
}   // namespace rw
