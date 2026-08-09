#pragma once

// lanes.h — `--plan-lanes=N --task="…"` / `--plan-lanes --brief=FILE`, the
// ORCHESTRATOR surface: *if I split this task across N isolated worktrees, which lanes would collide, and in
// what order should they land?*
//
// The field has 100+ worktree-orchestrator UIs and none of them computes lane conflicts from a code graph;
// spec-driven decomposers split a task in PROSE and cannot predict which halves collide. This verb emits the
// machine-readable plan those tools consume. ripwire is the planning brain and never the agent runner: the
// plan is advisory, ripwire does not police it, and nothing here writes a file (the artifact is stdout —
// `ripwire . --plan-lanes=3 --task="…" > .ripwire_lanes.json`, so the tool stays read-only and a reviewer
// verifies a committed plan by re-running the command and diffing).
//
// ── COMPOSITION ONLY, like landingplan.h ──────────────────────────────────────────────────────────────────
// Nothing below re-derives ranking, community structure, conflict semantics, landing order, blast radius or
// test selection. The lane carve is packpartition::planPartition; the pairwise conflict/risk classification
// and the landing order are mergescout::computeOnePairOverlap / computeOverlaps / landingOrder, fed SYNTHETIC
// Arms; the blast radius is graph.h's transitiveCallers (the traversal --impact uses); the test obligations
// are situ.h's computeTestGate machinery. Two things this file must NOT do, both tempting:
//   1. never call mergescout::computeMergeScout — it resolves refs, git-archives trees and re-ingests them.
//      There are no refs here: the whole point is that the prediction is PRE-HOC, before a line is written,
//      which is also why this verb has NO git in its hot path beyond the at= stamp and the churn lens.
//   2. never build claims through mergescout::buildTreeIndex — see §KEY below.
//
// ── §KEY — what a lane claim is keyed on, and why not `id=` ───────────────────────────────────────────────
// A claim keys on (p, scope, n) — root-relative path, captured enclosing scope, name — hashed as
// fnv1a64(p \0 scope \0 n). PATH-QUALIFIED ALWAYS, including when scope is empty. This is byte-for-byte the
// same key space mergescout::buildTreeIndex builds (quality::bodyHashesBySym's pathQualified mode, pinned by
// test/scoutkeycheck.sh) — deliberately the SAME shape rather than a third keying scheme.
//
// `id=` is NOT the join key and must never become one. resolve.h:927 returns the BARE NAME when no scope was
// captured, so free functions, shell functions and top-level Python defs all degrade to an identity with no
// path in it at all: measured on this repo, 343 id values name more than one symbol, covering 1689 of 5763
// symbol rows (29.3%), of which 263 rows (4.6%) are true same-file overloads and 1426 are bare names
// colliding ACROSS FILES. That is not a corner case, it is a quarter of the corpus, and joining lanes on it
// would report two lanes editing two different files as conflicting. `id` is carried per row for
// ADDRESSABILITY (paste it into --expand/--callers/--impact) and is null when it would be a bare name;
// `id_addressable` is false when it is null OR resolves to more than one symbol in this tree. `l`/`ord` are
// display only and are never joined on — a line number is invalidated by any edit above it, which is exactly
// what a lane agent does.
//
// Fixing canonicalId itself is the right long-term change and is deliberately NOT in v1: it is the emitted
// identity of the whole tool (the golden map's id=, the --for/--pack-task chaining contract, .ripwire_notes
// targets, .ripwire_quality_acks keying, the quality-delta origin oracle, the qsnap blobs), so it is a round
// with two committed-file migrations, not a lane. v1 gets soundness from its own key and states the residual.
//
// ── §FOLD — the residual, and why over-reporting is the SAFE direction ────────────────────────────────────
// After path-qualification the residual collision class is genuine same-file overloads (80 ids / 263 rows
// here). Two lanes claiming two different overloads of one name in one file are reported as a conflict. That
// is a false positive and it is deliberate: the fold direction is provably one-way. quality::bodyHashesBySym
// folds overloads by sorting their individual body hashes and hashing the concatenation, so a change to ANY
// member changes the folded hash — a coarser key OVER-merges the claim sets and can only OVER-report overlap,
// never hide one. For a conflict predictor that is the correct error direction: a missed collision costs a
// wasted lane-day and a hand-resolved merge; a spurious one costs a serialization nobody needed. (The one
// constructible false negative is pathological: two overloads swapping bodies exactly.) The fold is never
// silent — `overloads=K` sits on the row, `id_addressable` goes false, and the `folded-claims` warning
// carries the count and names the DIRECTION of the error.
//
// ── §PAIRS — three classes, deliberately separate ─────────────────────────────────────────────────────────
// The conflict test runs on CLAIMS, never on blast radii. Two lanes reading the same downstream caller is the
// normal case, not a collision, and intersecting blast radii is the single easiest way to build a conflict
// tool that reports everything and is believed by nobody. So:
//   conflicts[]      — the same claim key on both lanes. Git will fight; a human resolves.
//   same_file_risk[] — different keys, same file. AGGREGATED PER FILE: computeOnePairOverlap is a nested loop
//                      that emits one RiskPair per same-file/different-key COMBINATION, so two lanes with 40
//                      and 35 claims in one file produce 1400 rows for one fact. The compute is unchanged
//                      (composition); only the RENDERING aggregates, and `pairs` carries the raw count so
//                      nothing is hidden.
//   contract_touch[] — a claim of lane `from` lies inside lane `to`'s blast radius. NOT a merge conflict:
//                      `from` may have to adapt to a signature change `to` makes. Its own class precisely so
//                      the real signal in that intersection is not lost under a name that would be mistaken
//                      for a conflict, and it is never counted into conflict_count.
//
// ── DETERMINISM ──────────────────────────────────────────────────────────────────────────────────────────
// Byte-identical run to run: the carve is planPartition's own integer-keyed plan, claims are emitted in key
// order, files/tests/blast paths in path order, pairs in (a,b) lane-ordinal order, and the landing order is
// mergescout's fewest-conflicts-first greedy with a ref-name tie-break. No hash-map iteration and no clock
// reaches the output. The one float pair (overlap_mean/overlap_max) is printed at fixed precision from
// measureOverlap, which is itself a pure function of integer id sets.

#include "model.h"
#include "graph.h"
#include "partition.h"    // planPartition / measureOverlap / groupKeyFor / kMinPartitions..kMaxPartitions
#include "mergescout.h"   // Arm / ChangedSym / computeOverlaps / landingOrder — the conflict + order machinery
#include "situ.h"         // computeTestGateForSymbols / testSeedForwardReach
#include "notes.h"        // NoteIndex — the field-notes surfacing lookup
#include "gitstamp.h"     // stampAt — the at="<sha>[+dirty]" root anchor
#include "resolve.h"      // canonicalId
#include "arch.h"         // relForHash / fnv1a64
#include "serialize.h"    // jsonStr
#include "Diagnostics.h"  // DEGRADED_PATH_ALERT

#include "btree.hpp"      // gtl::btree_map — sorted iteration (house rule: never std::map)

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

namespace rw
{
namespace lanes
{

// N bounds — the same 2..16 --partition and the multi-root workspace use: 1 lane is not a fan-out, and past
// 16 an orchestrator is doing something other than parallel worktrees.
inline constexpr std::uint32_t kMinLanes = packpartition::kMinPartitions;
inline constexpr std::uint32_t kMaxLanes = packpartition::kMaxPartitions;

inline constexpr int         kSchemaVersion   = 1;    // `v` — bumped only on a BREAKING change; additive fields do not
inline constexpr std::size_t kBriefClaimsPerLane = std::size_t( kPackTaskRankTopN );   // brief mode: top-K per lane line
inline constexpr std::size_t kMaxBlastFiles   = 40;   // blast-radius file rows per lane; total + capped always reported
inline constexpr std::size_t kMaxTestRows     = 40;   // tests_to_run rows per lane; same "never drop without a number"

// ── claim identity, tree-wide ─────────────────────────────────────────────────────────────────────────────
// One pass over every symbol, so a per-lane claim can answer "how many definitions does my key fold?" and
// "how many other symbols would answer to my id?" without a second scan. Vectors are parallel to ing.symbols
// (SoA, index = NodeId) rather than a map keyed on a string.
struct ClaimIdentity
{
    std::vector<std::uint64_t> key;              // fnv1a64(relPath \0 scope \0 name) — THE join key
    std::vector<std::uint32_t> ord;              // ordinal among same-key defs, ordered by sigStartByte
    std::vector<std::uint32_t> defsForKey;       // how many definitions share this key (>1 ⇒ the §FOLD case)
    std::vector<std::uint32_t> idCollidesWith;   // how many OTHER symbols share this symbol's canonicalId
};

inline std::uint64_t claimKeyOf( const IngestResult& ing, std::string_view root, const Symbol& s )
{
    std::string keyText;
    keyText.append( relForHash( ing.files[ s.fileId ], root ) ).push_back( '\0' );
    keyText.append( s.scope ).push_back( '\0' );
    keyText.append( s.name );
    return fnv1a64( keyText );
}

inline ClaimIdentity buildClaimIdentity( const IngestResult& ing, const Graph& g, const std::string& root )
{
    const std::size_t symbolCount = ing.symbols.size();
    ClaimIdentity     out;
    out.key.assign( symbolCount, 0u );
    out.ord.assign( symbolCount, 0u );
    out.defsForKey.assign( symbolCount, 1u );
    out.idCollidesWith.assign( symbolCount, 0u );

    // keys, then the same-key groups (sorted by sigStartByte so `ord` is a stable, source-order ordinal)
    gtl::btree_map<std::uint64_t, std::vector<NodeId>> byKey;
    for( NodeId i = 0; i < NodeId( symbolCount ); ++i )
    {
        if( ing.symbols[i].fileId >= ing.files.size() )
        {
            continue; // degrade: an unfilable symbol keeps key 0
        }
        out.key[i] = claimKeyOf( ing, root, ing.symbols[i] );
        byKey[ out.key[i] ].push_back( i );
    }
    for( auto& [ k, members ] : byKey )
    {
        (void)k;
        std::sort( members.begin(), members.end(), [ & ]( NodeId a, NodeId b )
                   { return ing.symbols[a].sigStartByte != ing.symbols[b].sigStartByte
                          ? ing.symbols[a].sigStartByte < ing.symbols[b].sigStartByte : a < b; } );
        for( std::size_t rank = 0; rank < members.size(); ++rank )
        {
            out.ord       [ members[rank] ] = std::uint32_t( rank );
            out.defsForKey[ members[rank] ] = std::uint32_t( members.size() );
        }
    }

    // canonicalId multiplicity — the per-row measurement behind `id_addressable`. Read from g.canonId when the
    // graph carries it (byte-identical to what the map emits as id=); otherwise derived the same way.
    const bool haveGraphIds = g.canonId.size() == symbolCount;
    gtl::btree_map<std::string, std::uint32_t> idCount;
    std::vector<std::string>                   idOf( symbolCount );
    for( NodeId i = 0; i < NodeId( symbolCount ); ++i )
    {
        idOf[i] = haveGraphIds ? g.canonId[i]
                               : canonicalId( relForHash( ing.files[ ing.symbols[i].fileId ], root ), ing.symbols[i].scope, ing.symbols[i].name );
        ++idCount[ idOf[i] ];
    }
    for( NodeId i = 0; i < NodeId( symbolCount ); ++i )
    {
        out.idCollidesWith[i] = idCount[ idOf[i] ] - 1u;
    }
    return out;
}

// ── one claim row ─────────────────────────────────────────────────────────────────────────────────────────
struct Claim
{
    NodeId        node          = kNoNode;   // the representative definition (lowest ord among the folded set)
    std::uint64_t key           = 0;
    std::uint32_t line          = 0;
    std::uint32_t ord           = 0;
    std::uint32_t overloads     = 1;
    std::uint32_t idCollidesWith = 0;
    bool          idAddressable = false;
    std::string   path;                      // `p` — the map's own spelling, pasteable into --affected/--test-gate
    std::string   name;
    std::string   scope;
    std::string   id;                        // canonicalId, or "" ⇒ emitted as null (it would be a bare name)
    std::uint32_t amb = 0, cx = 0, ccx = 0, churn = 0;
    std::uint8_t  tested = 0;
};

struct LaneFileRow
{
    std::string   path;
    std::uint32_t symbolCount = 0;
    std::uint32_t churn       = 0;
    std::uint32_t ccxSum      = 0;
    std::uint32_t hotspotRank = 0;     // 1-based among files with a non-zero hotspot score; 0 ⇒ emitted as null
};

struct Lane
{
    std::string              id;            // "lane-0"… — stable, ordinal, and the landing-order tie-break key
    std::string              task;          // the brief line, or the whole --task text in auto-carve mode
    std::vector<Claim>       claims;        // key-sorted
    std::vector<NodeId>      claimNodes;    // every folded definition, sorted — the seed set for reach + tests
    std::vector<LaneFileRow> files;         // path-sorted
    std::vector<std::string> blastFiles;    // path-sorted, capped at kMaxBlastFiles
    std::size_t              blastReaches   = 0;    // symbols outside the claims that transitively reach them
    std::size_t              blastFileTotal = 0;
    bool                     blastCapped    = false;
    std::vector<char>        blastMask;     // per-node: in this lane's blast radius (the contract_touch join)
    std::vector<std::string> tests;         // path-sorted, capped at kMaxTestRows
    std::size_t              testTotal      = 0;
    bool                     testsCapped    = false;
    std::size_t              untested       = 0;
    std::vector<std::string> notes;
    std::uint32_t            moduleSpan     = 0;    // distinct call-graph modules (or files, for the edgeless)
};

struct RiskFileRow  { std::string path; std::uint32_t aSymbols = 0, bSymbols = 0; std::size_t pairCount = 0; };
struct TouchRow     { std::string path, name, from, to; std::uint64_t key = 0; };

struct PairRow
{
    std::string                 a, b;
    std::vector<Claim>          conflicts;       // the SAME claim key on both lanes
    std::vector<RiskFileRow>    sameFileRisk;    // different keys, same file — one row per shared file
    std::vector<TouchRow>       contractTouch;
    std::size_t                 riskPairCount = 0;   // the raw same-file combination count the rows aggregate
};

struct Warning
{
    const char*   code = "";
    const char*   sev  = "info";   // info | warn
    bool          hasCount = false;
    std::uint64_t count = 0;
    std::string   text;
};

struct CorpusStats  { std::size_t files = 0, symbols = 0, edges = 0, ambiguous = 0, unresolved = 0; };

struct CarveStats
{
    std::uint32_t surface = 0, modules = 0, split = 0;
    double        overlapMean = 0.0, overlapMax = 0.0, coreOverlap = 0.0;
    std::uint32_t sharedSymbols = 0, unionSymbols = 0;
};

struct CoreSymbol { std::string path, name, scope, id; std::uint32_t line = 0; };

struct PlanLanesResult
{
    std::string              at, root, task, source;
    std::uint32_t            requested = 0;
    CorpusStats              corpus;
    bool                     haveCarve = false;
    CarveStats               carve;
    std::vector<std::string> coreFiles;
    std::vector<CoreSymbol>  coreSymbols;
    std::vector<Lane>        lanes;
    std::vector<PairRow>     pairs;
    std::vector<std::string> landingOrder;
    std::vector<Warning>     warnings;
};

// ── inputs ────────────────────────────────────────────────────────────────────────────────────────────────
// The caller (main.cpp) owns every ranking — computeLensRanking is THE ranking implementation and this file
// does not get to have a second one. Auto-carve gets one rank vector for the whole task; brief mode gets one
// per lane line. Both are views: the caller owns the storage.
struct LanesInputs
{
    const IngestResult*                    ing   = nullptr;
    const Graph*                           g     = nullptr;
    const std::string*                     root  = nullptr;
    std::string                            task;              // "" in brief mode
    std::vector<std::string>               laneTasks;         // brief mode: one line per lane
    bool                                   autoCarve = false;
    std::uint32_t                          requested = 0;
    const std::vector<float>*              carveRank = nullptr;                 // auto-carve
    const std::vector<std::vector<float>>* laneRanks = nullptr;                 // brief mode
    const std::vector<std::uint32_t>*      churn     = nullptr;                 // per file, --hotspots' own axis
    const std::vector<std::uint8_t>*       tested    = nullptr;                 // per symbol
    const notes::NoteIndex*                notes     = nullptr;
    CorpusStats                            corpus;
};

// ── claim construction ────────────────────────────────────────────────────────────────────────────────────
// The per-lane hot values a claim row carries, grouped so buildClaims stays one parameter shy of the bar.
struct ClaimLens
{
    const ClaimIdentity*              ident  = nullptr;
    const std::vector<std::uint32_t>* churn  = nullptr;
    const std::vector<std::uint8_t>*  tested = nullptr;
};

inline Claim makeClaim( const IngestResult& ing, const Graph& g, const ClaimLens& lens, NodeId node )
{
    const Symbol& s = ing.symbols[ node ];
    Claim         c;
    c.node           = node;
    c.key            = lens.ident->key[ node ];
    c.line           = s.line;
    c.ord            = lens.ident->ord[ node ];
    c.overloads      = lens.ident->defsForKey[ node ];
    c.idCollidesWith = lens.ident->idCollidesWith[ node ];
    c.path           = ing.files[ s.fileId ];
    c.name           = s.name;
    c.scope          = s.scope;
    c.cx             = s.cx;
    c.ccx            = s.ccx;

    // `id` is emitted ONLY when canonicalId adds something over the bare name; addressability additionally
    // requires that it resolves to exactly one symbol here (never emit an id and let the consumer discover
    // it is ambiguous). The spelling is g.canonId's, i.e. byte-identical to the map's own id=.
    if( !s.scope.empty() )
    {
        c.id = ( g.canonId.size() == ing.symbols.size() ) ? g.canonId[ node ] : canonicalId( c.path, s.scope, s.name );
    }
    c.idAddressable = !c.id.empty() && c.idCollidesWith == 0 && c.overloads == 1;

    if( node < g.ambOut.size() )
    {
        c.amb = g.ambOut[node];
    }
    if( lens.churn && s.fileId < lens.churn->size() )
    {
        c.churn = ( *lens.churn )[s.fileId];
    }
    if( lens.tested && node < NodeId( lens.tested->size() ) )
    {
        c.tested = ( *lens.tested )[node];
    }
    return c;
}

// Ranked node ids → key-folded claims. Two nodes that share a key are ONE claim (§FOLD): the representative
// is the lowest-ord member, and `claimNodes` keeps every folded definition so the blast radius and the test
// obligations cover all of them. Emitted in key order — a total order, so the output cannot drift.
inline void buildClaims( const IngestResult& ing, const Graph& g, const ClaimLens& lens,
                         const std::vector<NodeId>& assigned, Lane& lane )
{
    gtl::btree_map<std::uint64_t, Claim> byKey;
    for( NodeId node : assigned )
    {
        if( node >= NodeId( ing.symbols.size() ) )
        {
            continue;
        }
        lane.claimNodes.push_back( node );
        const Claim c  = makeClaim( ing, g, lens, node );
        const auto  it = byKey.find( c.key );
        if( it == byKey.end() )
        {
            byKey.emplace( c.key, c );
        }
        else if( c.ord < it->second.ord )
        {
            it->second = c; // the lowest-ord member represents the fold
        }
    }
    for( const auto& [ k, c ] : byKey ) { (void)k; lane.claims.push_back( c ); }

    // Every OTHER definition sharing a claimed key is claimed too — the key is what the conflict test compares,
    // so a lane that owns one overload owns them all, and its blast radius/tests must say so.
    std::sort( lane.claimNodes.begin(), lane.claimNodes.end() );
    lane.claimNodes.erase( std::unique( lane.claimNodes.begin(), lane.claimNodes.end() ), lane.claimNodes.end() );
}

// ── the file rows on a lane ───────────────────────────────────────────────────────────────────────────────
inline void buildLaneFiles( const IngestResult& ing, const std::vector<std::uint32_t>* churn,
                            const std::vector<std::uint32_t>& hotspotRank, Lane& lane )
{
    gtl::btree_map<std::string, LaneFileRow> byPath;
    for( const Claim& c : lane.claims )
    {
        LaneFileRow& row = byPath[ c.path ];
        row.path         = c.path;
        ++row.symbolCount;
    }
    for( NodeId node : lane.claimNodes )
    {
        const std::uint32_t f  = ing.symbols[ node ].fileId;
        const auto          it = byPath.find( ing.files[f] );
        if( it == byPath.end() )
        {
            continue;
        }
        it->second.ccxSum += ing.symbols[ node ].ccx;
        it->second.churn   = ( churn && f < churn->size() ) ? (*churn)[f] : 0u;
        it->second.hotspotRank = f < hotspotRank.size() ? hotspotRank[f] : 0u;
    }
    for( const auto& [ p, row ] : byPath ) { (void)p; lane.files.push_back( row ); }
}

// hotspot rank per file: complexity × churn, the SAME two inputs --hotspots ranks on. 1-based over the files
// with a non-zero score (score desc, path asc); 0 for the rest, emitted as null rather than a fake rank.
inline std::vector<std::uint32_t> buildHotspotRanks( const IngestResult& ing, const std::vector<std::uint32_t>* churn )
{
    const std::size_t          fileCount = ing.files.size();
    std::vector<std::uint64_t> score( fileCount, 0u );
    std::vector<std::uint64_t> ccxSum( fileCount, 0u );
    for( const Symbol& s : ing.symbols )
    {
        if( s.fileId < fileCount )
        {
            ccxSum[s.fileId] += s.ccx;
        }
    }
    for( std::size_t f = 0; f < fileCount; ++f )
    {
        score[f] = ccxSum[f] * std::uint64_t( churn && f < churn->size() ? (*churn)[f] : 0u );
    }

    std::vector<std::uint32_t> ranked;
    for( std::uint32_t f = 0; f < std::uint32_t( fileCount ); ++f )
    {
        if( score[f] > 0 )
        {
            ranked.push_back( f );
        }
    }
    std::sort( ranked.begin(), ranked.end(), [ & ]( std::uint32_t a, std::uint32_t b )
               { return score[a] != score[b] ? score[a] > score[b] : ing.files[a] < ing.files[b]; } );

    std::vector<std::uint32_t> rankOf( fileCount, 0u );
    for( std::size_t i = 0; i < ranked.size(); ++i )
    {
        rankOf[ranked[i]] = std::uint32_t( i + 1 );
    }
    return rankOf;
}

// ── the blast radius (READ territory, never claimed) + the test obligations ───────────────────────────────
inline void buildLaneReach( const IngestResult& ing, const Graph& g, const std::vector<char>& testReach, Lane& lane )
{
    const std::size_t symbolCount = ing.symbols.size();
    std::vector<char> isClaim( symbolCount, 0 );
    for( NodeId n : lane.claimNodes )
    {
        if( n < NodeId( symbolCount ) )
        {
            isClaim[n] = 1;
        }
    }

    lane.blastMask.assign( symbolCount, 0 );
    gtl::btree_map<std::string, char> blastPaths;
    for( NodeId n : transitiveCallers( g, lane.claimNodes ) )
    {
        if( n >= NodeId( symbolCount ) || isClaim[n] )
        {
            continue; // the claims are the change, not its radius
        }
        lane.blastMask[n] = 1;
        ++lane.blastReaches;
        blastPaths[ ing.files[ ing.symbols[n].fileId ] ] = 1;
    }
    lane.blastFileTotal = blastPaths.size();
    for( const auto& [ p, seen ] : blastPaths )
    {
        (void)seen;
        if( lane.blastFiles.size() >= kMaxBlastFiles ) { lane.blastCapped = true; break; }
        lane.blastFiles.push_back( p );
    }

    const TestGateResult gate = computeTestGateForSymbols( ing, g, lane.claimNodes, &testReach );
    lane.testTotal            = gate.tests.size();
    lane.untested             = gate.untested.size();
    for( std::uint32_t f : gate.tests )
    {
        if( lane.tests.size() >= kMaxTestRows ) { lane.testsCapped = true; break; }
        lane.tests.push_back( ing.files[f] );
    }
}

// ── field notes on the claimed symbols and files (free: the index is already built) ───────────────────────
inline void buildLaneNotes( const notes::NoteIndex* ni, Lane& lane )
{
    if( !ni )
    {
        return;
    }
    gtl::btree_map<std::string, char> seen;
    const auto collect = [ & ]( const std::string& target )
    {
        const std::vector<std::uint32_t>* hits = ni->find( target );
        if( !hits )
        {
            return;
        }
        for( std::uint32_t idx : *hits )
        {
            if( idx < ni->notes.size() )
            {
                seen[ni->notes[idx].target + ": " + ni->notes[idx].text] = 1;
            }
        }
    };
    for( const Claim& c : lane.claims )
    {
        const std::string rel = std::string( relForHash( c.path, ni->root ) );
        collect( canonicalId( rel, c.scope, c.name ) );
        collect( rel );
    }
    for( const auto& [ line, mark ] : seen ) { (void)mark; lane.notes.push_back( line ); }
}

// module span — how many call-graph modules a lane's claims cover. Reuses packpartition::groupKeyFor verbatim
// (community for a symbol WITH call edges, its FILE for the call-graph-edgeless), so "module" means exactly
// what it means to the carve that produced the lane.
inline std::uint32_t moduleSpanOf( const IngestResult& ing, const Graph& g, const Communities& cm, const Lane& lane )
{
    gtl::btree_map<std::uint64_t, char> keys;
    for( const Claim& c : lane.claims )
    {
        keys[packpartition::groupKeyFor( ing, g, cm, c.node )] = 1;
    }
    return std::uint32_t( keys.size() );
}

// ── the synthetic arms: claims → mergescout's OWN conflict machinery ─────────────────────────────────────
// computeOverlaps/landingOrder take std::vector<Arm> and touch only Arm::ref, Arm::changed, and within
// ChangedSym only `key` and `file`. So a lane becomes an Arm with its claims as ChangedSyms and the pure
// functions run unchanged — ZERO conflict logic is written here, and the §KEY substitution is legal precisely
// because those functions never look at how a key was derived. `headConflicts` is empty by construction:
// there is no fork point yet, so there is nothing for the live line to have changed.
inline std::vector<mergescout::Arm> synthesizeArms( const std::vector<Lane>& lanes )
{
    std::vector<mergescout::Arm> arms;
    arms.reserve( lanes.size() );
    for( const Lane& lane : lanes )
    {
        mergescout::Arm arm;
        arm.ref = lane.id;
        arm.ok  = true;
        for( const Claim& c : lane.claims )
        {
            arm.changed.push_back( mergescout::ChangedSym{ c.key, c.path, c.id.empty() ? c.name : c.id } );
        }
        std::sort( arm.changed.begin(), arm.changed.end(),
                   [ ]( const mergescout::ChangedSym& x, const mergescout::ChangedSym& y ) { return x.key < y.key; } );
        arms.push_back( std::move( arm ) );
    }
    return arms;
}

inline const Claim* findClaimByKey( const Lane& lane, std::uint64_t key )
{
    for( const Claim& c : lane.claims )
    {
        if( c.key == key )
        {
            return &c;
        }
    }
    return nullptr;
}

// One lane's claims that sit inside the OTHER lane's blast radius. Directional by construction, so a pair
// emits both directions and the row names which way the adaptation runs.
inline void collectContractTouch( const Lane& from, const Lane& to, std::vector<TouchRow>& out )
{
    if( to.blastMask.empty() )
    {
        return;
    }
    for( const Claim& c : from.claims )
    {
        if( c.node >= NodeId( to.blastMask.size() ) || !to.blastMask[c.node] )
        {
            continue;
        }
        out.push_back( TouchRow{ c.path, c.name, from.id, to.id, c.key } );
    }
}

// PairOverlap (mergescout's own classification) → the emitted pair row. The conflicts come through verbatim;
// the risks are AGGREGATED PER FILE here and only here (§PAIRS) — the raw combination count is kept so the
// aggregation hides nothing.
inline PairRow renderPair( const std::vector<Lane>& lanes, const mergescout::PairOverlap& p )
{
    const Lane& laneA = lanes[ p.a ];
    const Lane& laneB = lanes[ p.b ];
    PairRow     row;
    row.a = laneA.id;
    row.b = laneB.id;

    for( const mergescout::ChangedSym& s : p.conflicts )
    {
        if( const Claim* c = findClaimByKey( laneA, s.key ) )
        {
            row.conflicts.push_back( *c );
        }
    }

    gtl::btree_map<std::string, RiskFileRow>                     byFile;
    gtl::btree_map<std::string, gtl::btree_map<std::uint64_t, char>> aKeys, bKeys;
    for( const mergescout::RiskPair& r : p.risks )
    {
        RiskFileRow& fileRow = byFile[ r.a.file ];
        fileRow.path         = r.a.file;
        ++fileRow.pairCount;
        aKeys[ r.a.file ][ r.a.key ] = 1;
        bKeys[ r.a.file ][ r.b.key ] = 1;
    }
    for( auto& [ path, fileRow ] : byFile )
    {
        fileRow.aSymbols = std::uint32_t( aKeys[ path ].size() );
        fileRow.bSymbols = std::uint32_t( bKeys[ path ].size() );
        row.sameFileRisk.push_back( fileRow );
    }
    row.riskPairCount = p.risks.size();

    collectContractTouch( laneA, laneB, row.contractTouch );
    collectContractTouch( laneB, laneA, row.contractTouch );
    return row;
}


// ── in-band honesty (§2.5): every limit is a machine-readable row with a stable code ──────────────────────
struct WarnTally
{
    std::uint64_t bareNameClaims = 0, foldedClaims = 0, idCollisions = 0, nonSourceClaims = 0, claimTotal = 0;
};

inline WarnTally tallyClaims( const std::vector<Lane>& lanes )
{
    WarnTally t;
    for( const Lane& lane : lanes )
    {
        for( const Claim& c : lane.claims )
        {
            ++t.claimTotal;
            if( c.id.empty() )
            {
                ++t.bareNameClaims;
            }
            if( c.overloads > 1 )
            {
                ++t.foldedClaims;
            }
            if( c.idCollidesWith > 0 )
            {
                ++t.idCollisions;
            }
            if( isTestPath( c.path ) )
            {
                ++t.nonSourceClaims;
            }
        }
    }
    return t;
}

inline void addWarning( std::vector<Warning>& out, const char* code, const char* sev, std::string text )
{
    out.push_back( Warning{ code, sev, false, 0, std::move( text ) } );
}

inline void addCountedWarning( std::vector<Warning>& out, const char* code, const char* sev, std::uint64_t count, std::string text )
{
    out.push_back( Warning{ code, sev, true, count, std::move( text ) } );
}

// Two lanes whose CLAIM SETS largely coincide are not two lanes. Every conflict between them is then an
// artifact of the carve — the same symbol handed to both — rather than a property of the work, and a conflict
// tool that reports those without saying so is the false-positive failure this verb exists to avoid. Measured
// on a 6-symbol corpus where top-K exceeds the whole surface: both lanes claimed all four symbols and the pair
// reported 4 conflicts. Jaccard over claim KEYS, so it is the same identity the conflicts are computed on.
inline void warnCoincidingClaims( PlanLanesResult& result )
{
    char buf[ 640 ];
    for( std::size_t a = 0; a < result.lanes.size(); ++a )
    {
        for( std::size_t b = a + 1; b < result.lanes.size(); ++b )
        {
            const std::vector<Claim>& ca = result.lanes[a].claims;
            const std::vector<Claim>& cb = result.lanes[b].claims;
            if( ca.empty() || cb.empty() )
            {
                continue;
            }

            ankerl::unordered_dense::set<std::uint64_t> keysA, keysB;
            for( const Claim& c : ca )
            {
                keysA.insert( c.key );
            }
            std::size_t shared = 0;
            for( const Claim& c : cb )
            {
                if( keysB.insert( c.key ).second && keysA.count( c.key ) )
                {
                    ++shared;
                }
            }

            const std::size_t unionCount = keysA.size() + keysB.size() - shared;
            if( unionCount == 0 )
            {
                continue;
            }
            const double jaccard = double( shared ) / double( unionCount );
            if( jaccard < 0.5 )
            {
                continue; // only flag a genuinely degenerate carve
            }

            std::snprintf( buf, sizeof( buf ),
                           "%s and %s claim %zu of %zu symbols IN COMMON (Jaccard %.2f). Their conflicts are an artifact of the "
                           "carve handing the same symbols to both lanes, not a property of the work — do not serialize on them. "
                           "This happens when the ranked surface is smaller than the requested lane count; give each lane its own "
                           "line via brief, or ask for fewer lanes.",
                           result.lanes[a].id.c_str(), result.lanes[b].id.c_str(), shared, unionCount, jaccard );
            addWarning( result.warnings, "lane-claims-coincide", "warn", buf );
        }
    }
}

inline void buildWarnings( const LanesInputs& in, PlanLanesResult& result )
{
    const WarnTally t = tallyClaims( result.lanes );
    char            buf[ 640 ];

    // §7.1 — always, on every run: the graph these numbers are derived from is name-based and incomplete.
    std::snprintf( buf, sizeof( buf ),
                   "%zu of %zu call edges are name-ambiguous and %zu reference names resolve to no in-corpus definition. "
                   "blast_radius and contract_touch inherit that; dynamic dispatch is not an edge at all (a fn-pointer/"
                   "callback call is an edge only when ONE function is bound to that variable in scope, and a "
                   "macro-generated call only when its function-like #define is indexed), "
                   "so a lane whose real coupling runs through a dispatch "
                   "table looks independent. conflicts and same_file_risk do NOT inherit it (they are computed from "
                   "claims, not from edges).",
                   result.corpus.ambiguous, result.corpus.edges, result.corpus.unresolved );
    addWarning( result.warnings, "name-based-callgraph", "info", buf );

    // §KEY — addressability, stated as a count of the rows it affects rather than as prose.
    std::snprintf( buf, sizeof( buf ),
                   "%llu of %llu claimed symbols have no scope captured, so id is null and cannot be pasted into "
                   "expand/callers/impact. Claims are keyed on path+scope+name and are unaffected; only addressability is.",
                   ( unsigned long long )t.bareNameClaims, ( unsigned long long )t.claimTotal );
    addCountedWarning( result.warnings, "bare-name-claims", t.bareNameClaims ? "warn" : "info", t.bareNameClaims, buf );

    std::snprintf( buf, sizeof( buf ),
                   "%llu claims fold two or more same-file overloads under one key. A folded claim OVER-reports overlap; "
                   "it never hides one — the error runs toward a serialization you did not need, never toward a missed "
                   "collision. Folded rows carry overloads>1 and id_addressable=false.",
                   ( unsigned long long )t.foldedClaims );
    addCountedWarning( result.warnings, "folded-claims", t.foldedClaims ? "warn" : "info", t.foldedClaims, buf );

    std::snprintf( buf, sizeof( buf ),
                   "%llu claimed symbols share their canonicalId with at least one other symbol in this tree, so their id "
                   "is reported but id_addressable is false. This is the reason the claim key is path+scope+name and not id.",
                   ( unsigned long long )t.idCollisions );
    addCountedWarning( result.warnings, "id-collisions", t.idCollisions ? "warn" : "info", t.idCollisions, buf );

    // §7.4 — both halves, always.
    addWarning( result.warnings, "tests-are-symbol-granular", "warn",
                "tests_to_run and untested are computed from each lane's claimed SYMBOLS (not its whole claimed files), but a "
                "test is still selected at FILE granularity: the row names a test FILE, never a test case, so running it runs "
                "more than the lane needs. untested is an UPPER BOUND on the lane's real gap." );
    addWarning( result.warnings, "test-surface-is-partial", "warn",
                "Tests are found by walking the call graph forward from symbols in test-path files, so a suite of shell scripts "
                "reaches nothing in the source tree this way and does not appear; and isTestPath treats every path under test/ "
                "as a test, so a fixture can be named as a test to run. Neither an empty nor a populated list is a substitute "
                "for running the suite." );

    // §7.6 — the plan is advisory and it is stamped.
    addWarning( result.warnings, "claims-are-advisory", "info",
                "Nothing stops a lane editing outside its claims and ripwire does not police it — that is the orchestrator's job. "
                "The plan is stamped with the sha it was computed against (at=); read at another sha it describes a tree that has "
                "moved, and the l= locators rot first. Regenerating is cheap; treat a committed plan as re-derivable, never as "
                "authoritative because it was committed." );

    if( in.autoCarve )
    {
        addWarning( result.warnings, "overlap-is-ceiling", "info",
                    "carve.overlap_* are measured over each lane's claims PLUS its blast radius — the surface a lane may read, "
                    "which is a superset of what it will read. They are an upper bound on the overlap actually paid for." );
        std::snprintf( buf, sizeof( buf ),
                       "Lanes were carved from the ranked surface (%u symbols over %u call-graph modules, split=%u). The carve "
                       "balances the RANKING; it does not read the task's clauses, so a task with enumerable parts can have a part "
                       "land in no lane at all. If your task has enumerable parts, use brief with one line per part.",
                       result.carve.surface, result.carve.modules, result.carve.split );
        addWarning( result.warnings, "carve-is-not-decomposition", "warn", buf );
    }
    else
    {
        addWarning( result.warnings, "brief-mode-has-no-core", "info",
                    "In brief mode no shared core is carved: each lane is ranked independently from its own brief line, so two "
                    "lines that rank the same symbol to the top produce a real conflict row rather than a symbol quietly lifted "
                    "into a core nobody claims." );
    }

    if( result.lanes.size() < in.requested )
    {
        std::snprintf( buf, sizeof( buf ), "%zu lanes were requested but only %zu could be carved — there are fewer separable "
                                           "modules than lanes on this task's ranked surface. Emitting the lanes that exist "
                                           "rather than inventing empty ones.",
                       std::size_t( in.requested ), result.lanes.size() );
        addCountedWarning( result.warnings, "lane-count-reduced", "warn", result.lanes.size(), buf );
    }

    for( const Lane& lane : result.lanes )
    {
        if( lane.moduleSpan < 2 && !lane.claims.empty() )
        {
            std::snprintf( buf, sizeof( buf ), "%s spans %u call-graph module(s): its surface sits in one place, so what it got "
                                               "is a rank cut, not a semantic split.", lane.id.c_str(), lane.moduleSpan );
            addWarning( result.warnings, "single-module-lane", "warn", buf );
        }
    }

    warnCoincidingClaims( result );

    if( t.nonSourceClaims > 0 )
    {
        std::snprintf( buf, sizeof( buf ),
                       "%llu claims are on test/fixture paths. Fixture, bench and presentation files are ranked like source, so "
                       "they inflate claims.files and same_file_risk on lanes no agent will actually edit. Pass ignore-tests to "
                       "cut the test half of it.",
                       ( unsigned long long )t.nonSourceClaims );
        addCountedWarning( result.warnings, "ranking-pollution", "warn", t.nonSourceClaims, buf );
    }

    // the single most likely place a plan goes wrong: two lanes on one high-churn file
    gtl::btree_map<std::string, std::uint32_t> lanesPerFile;
    gtl::btree_map<std::string, std::uint32_t> rankOfFile;
    for( const Lane& lane : result.lanes )
    {
        for( const LaneFileRow& f : lane.files ) { ++lanesPerFile[ f.path ]; rankOfFile[ f.path ] = f.hotspotRank; }
    }
    for( const auto& [ path, laneCount ] : lanesPerFile )
    {
        if( laneCount < 2 || rankOfFile[path] == 0 || rankOfFile[path] > 10 )
        {
            continue;
        }
        std::snprintf( buf, sizeof( buf ), "%s is claimed by %u lanes and is hotspot rank %u (complexity x churn). Same-file risk "
                                           "on one of the repo's highest-churn files is the most likely place this plan goes wrong.",
                       path.c_str(), laneCount, rankOfFile[ path ] );
        addCountedWarning( result.warnings, "shared-hotspot", "warn", laneCount, buf );
    }

    if( result.lanes.empty() )
    {
        addWarning( result.warnings, "no-lane-surface", "warn",
                    "The task's ranked surface produced no assignable lane: either nothing scored above zero, or the whole surface "
                    "fits in the shared core. This is a plan with no lanes, not a failure — rephrase the task, or use brief." );
    }
}

// ── the computation ───────────────────────────────────────────────────────────────────────────────────────

// auto-carve: planPartition owns the carve (surface sizing, community grouping, the isolate→FILE fallback,
// the K<N split and the K>=N bin packing). This wrapper only turns its id groups into lanes and copies its
// reported plan facts across.
inline void carveLanes( const LanesInputs& in, const ClaimLens& lens, PlanLanesResult& result )
{
    const IngestResult& ing  = *in.ing;
    const Graph&        g    = *in.g;
    const packpartition::PartitionPlan plan = packpartition::planPartition( ing, g, *in.carveRank, in.requested );

    result.haveCarve    = true;
    result.carve.surface = plan.surfaceCount;
    result.carve.modules = plan.moduleCount;
    result.carve.split   = plan.splitCount;

    for( NodeId node : plan.coreIds )
    {
        if( node >= NodeId( ing.symbols.size() ) )
        {
            continue;
        }
        const Symbol& s = ing.symbols[ node ];
        CoreSymbol    cs;
        cs.path  = ing.files[ s.fileId ];
        cs.name  = s.name;
        cs.scope = s.scope;
        cs.line  = s.line;
        if( !s.scope.empty() )
        {
            cs.id = ( g.canonId.size() == ing.symbols.size() ) ? g.canonId[ node ] : canonicalId( cs.path, s.scope, s.name );
        }
        result.coreSymbols.push_back( cs );
    }
    std::sort( result.coreSymbols.begin(), result.coreSymbols.end(), [ ]( const CoreSymbol& a, const CoreSymbol& b )
               { return a.path != b.path ? a.path < b.path : ( a.name != b.name ? a.name < b.name : a.line < b.line ); } );
    {
        gtl::btree_map<std::string, char> coreFileSet;
        for( const CoreSymbol& cs : result.coreSymbols )
        {
            coreFileSet[cs.path] = 1;
        }
        for( const auto& [ p, mark ] : coreFileSet ) { (void)mark; result.coreFiles.push_back( p ); }
    }

    for( std::size_t i = 0; i < plan.groups.size(); ++i )
    {
        Lane lane;
        lane.id   = "lane-" + std::to_string( i );
        lane.task = in.task;
        buildClaims( ing, g, lens, plan.groups[i], lane );
        result.lanes.push_back( std::move( lane ) );
    }
}

// brief mode: N independent rankings, one per non-blank brief line, each cut at its own top-K positive head.
// No Louvain, no bin packing, no split reporting — and it is the only mode whose PRECISION this verb can
// defend, because the lane boundaries are the ones the operator wrote rather than the ones the ranker implied.
inline void briefLanes( const LanesInputs& in, const ClaimLens& lens, PlanLanesResult& result )
{
    const IngestResult& ing = *in.ing;
    const Graph&        g   = *in.g;
    for( std::size_t i = 0; i < in.laneTasks.size(); ++i )
    {
        const std::vector<float>& rank = (*in.laneRanks)[i];
        std::vector<NodeId>       order( ing.symbols.size() );
        for( NodeId n = 0; n < NodeId( order.size() ); ++n )
        {
            order[n] = n;
        }
        sortutil::radixSortByScoreDescId( order, rank );

        std::vector<NodeId> head;
        for( NodeId n : order )
        {
            if( head.size() >= kBriefClaimsPerLane || rank[n] <= 0.0f )
            {
                break;
            }
            head.push_back( n );
        }

        Lane lane;
        lane.id   = "lane-" + std::to_string( i );
        lane.task = in.laneTasks[i];
        buildClaims( ing, g, lens, head, lane );
        result.lanes.push_back( std::move( lane ) );
    }
}

// carve.overlap_* — measureOverlap verbatim, over each lane's CLAIM+BLAST surface (what a lane may read) and
// the core's own symbol set. Pure integer sets in, so the two floats it returns cannot drift with a reordered
// sum; NaN is impossible (measureOverlap returns 0.0 when there is no pair).
inline void measureLaneOverlap( const IngestResult& ing, const std::vector<Lane>& lanes,
                                const std::vector<CoreSymbol>& coreSymbols, CarveStats& carve )
{
    std::vector<std::vector<NodeId>> surfaces;
    surfaces.reserve( lanes.size() );
    for( const Lane& lane : lanes )
    {
        std::vector<NodeId> surface = lane.claimNodes;
        for( NodeId n = 0; n < NodeId( lane.blastMask.size() ); ++n )
        {
            if( lane.blastMask[n] )
            {
                surface.push_back( n );
            }
        }
        std::sort( surface.begin(), surface.end() );
        surface.erase( std::unique( surface.begin(), surface.end() ), surface.end() );
        surfaces.push_back( std::move( surface ) );
    }

    // the core surface, as node ids: matched by (path, name) — the core rows are display rows, not claims.
    std::vector<NodeId> coreSurface;
    for( NodeId n = 0; n < NodeId( ing.symbols.size() ); ++n )
    {
        for( const CoreSymbol& cs : coreSymbols )
        {
            if( ing.symbols[n].name == cs.name && ing.files[ ing.symbols[n].fileId ] == cs.path ) { coreSurface.push_back( n ); break; }
        }
    }
    std::sort( coreSurface.begin(), coreSurface.end() );

    const packpartition::OverlapStats ov = packpartition::measureOverlap( surfaces, coreSurface );
    carve.overlapMean   = ov.mean;
    carve.overlapMax    = ov.worst;
    carve.coreOverlap   = ov.coreLeak;
    carve.sharedSymbols = ov.sharedCount;
    carve.unionSymbols  = ov.unionCount;
}

// THE computation. Pure with respect to the tree (the only I/O is the at= stamp's two git probes, which the
// caller's own root already implies) — no ref resolution, no archive, no second ingest.
inline PlanLanesResult computePlanLanes( const LanesInputs& in )
{
    VERIFY( in.ing != nullptr && in.g != nullptr && in.root != nullptr );
    const IngestResult& ing = *in.ing;
    const Graph&        g   = *in.g;

    PlanLanesResult result;
    result.at        = gitstamp::stampAt( *in.root );
    result.root      = *in.root;
    result.task      = in.task;
    result.source    = in.autoCarve ? "partition" : "brief";
    result.requested = in.requested;
    result.corpus    = in.corpus;

    const ClaimIdentity ident = buildClaimIdentity( ing, g, *in.root );
    const ClaimLens     lens{ &ident, in.churn, in.tested };

    if( in.autoCarve )
    {
        carveLanes( in, lens, result );
    }
    else
    {
        briefLanes( in, lens, result );
    }

    // the per-lane lenses: files + hotspot rank, blast radius, test obligations, notes, module span
    const std::vector<std::uint32_t> hotspotRank = buildHotspotRanks( ing, in.churn );
    const std::vector<char>          testReach   = testSeedForwardReach( ing, g );   // §3 perf hoist: ONE forward walk for N lanes
    const Communities                cm          = communities( g );
    for( Lane& lane : result.lanes )
    {
        buildLaneFiles( ing, in.churn, hotspotRank, lane );
        buildLaneReach( ing, g, testReach, lane );
        buildLaneNotes( in.notes, lane );
        lane.moduleSpan = moduleSpanOf( ing, g, cm, lane );
    }

    if( result.haveCarve )
    {
        measureLaneOverlap( ing, result.lanes, result.coreSymbols, result.carve );
    }

    // the pairwise classification + the landing order — mergescout's own pure functions, fed synthetic arms
    const std::vector<mergescout::Arm>         arms  = synthesizeArms( result.lanes );
    const std::vector<mergescout::PairOverlap> pairs = mergescout::computeOverlaps( arms );
    for( const mergescout::PairOverlap& p : pairs )
    {
        result.pairs.push_back( renderPair( result.lanes, p ) );
    }
    for( std::size_t idx : mergescout::landingOrder( arms, pairs ) )
    {
        result.landingOrder.push_back( arms[idx].ref );
    }

    buildWarnings( in, result );
    if( result.lanes.empty() )
    {
        DEGRADED_PATH_ALERT( "plan-lanes: the task's ranked surface produced no assignable lane — emitting a plan with zero lanes" );
    }
    return result;
}

// ── JSON emission ─────────────────────────────────────────────────────────────────────────────────────────
// JSON on stdout, always, and deliberately not the house XML default: the artifact's consumer is a program (a
// worktree manager), so making stdout BE the file means `ripwire . --plan-lanes=3 --task=… > .ripwire_lanes.json`
// is the entire write path — no sidecar writer to drift from the printer, ripwire stays read-only, and a
// reviewer verifies a committed plan by re-running and diffing.

inline void writeJsonStringOrNull( std::FILE* out, const std::string& value )
{
    if( value.empty() )
    {
        std::fprintf( out, "null" );
    }
    else
    {
        std::fprintf( out, "\"%s\"", jsonStr( value ).c_str() );
    }
}

inline void writePathArray( std::FILE* out, const std::vector<std::string>& paths )
{
    std::fprintf( out, "[" );
    for( std::size_t i = 0; i < paths.size(); ++i )
    {
        std::fprintf( out, "%s\"%s\"", i == 0 ? "" : ",", jsonStr( paths[i] ).c_str() );
    }
    std::fprintf( out, "]" );
}

inline void writeClaimRow( std::FILE* out, const Claim& c )
{
    std::fprintf( out, "{\"p\":\"%s\",\"n\":\"%s\",\"scope\":\"%s\",\"key\":\"%016llx\",\"id\":",
                  jsonStr( c.path ).c_str(), jsonStr( c.name ).c_str(), jsonStr( c.scope ).c_str(),
                  ( unsigned long long )c.key );
    writeJsonStringOrNull( out, c.id );
    std::fprintf( out, ",\"id_addressable\":%s,\"id_collides_with\":%u,\"l\":%u,\"ord\":%u,\"overloads\":%u,"
                       "\"amb\":%u,\"cx\":%u,\"ccx\":%u,\"churn\":%u,\"tested\":%u}",
                  c.idAddressable ? "true" : "false", c.idCollidesWith, c.line, c.ord, c.overloads,
                  c.amb, c.cx, c.ccx, c.churn, unsigned( c.tested ) );
}

inline void writeLaneFileRow( std::FILE* out, const LaneFileRow& f )
{
    std::fprintf( out, "{\"p\":\"%s\",\"symbols\":%u,\"churn\":%u,\"ccx\":%u,\"hotspot_rank\":",
                  jsonStr( f.path ).c_str(), f.symbolCount, f.churn, f.ccxSum );
    if( f.hotspotRank == 0 )
    {
        std::fprintf( out, "null}" );
    }
    else
    {
        std::fprintf( out, "%u}", f.hotspotRank );
    }
}

inline void writeLane( std::FILE* out, const Lane& lane )
{
    std::fprintf( out, "{\"id\":\"%s\",\"task\":\"%s\",\"claims\":{\"symbols\":[",
                  jsonStr( lane.id ).c_str(), jsonStr( lane.task ).c_str() );
    for( std::size_t i = 0; i < lane.claims.size(); ++i )
    {
        if( i )
        {
            std::fprintf( out, "," );
        }
        writeClaimRow( out, lane.claims[i] );
    }
    std::fprintf( out, "],\"files\":[" );
    for( std::size_t i = 0; i < lane.files.size(); ++i )
    {
        if( i )
        {
            std::fprintf( out, "," );
        }
        writeLaneFileRow( out, lane.files[i] );
    }
    std::fprintf( out, "]},\"blast_radius\":{\"reaches\":%zu,\"files_total\":%zu,\"capped\":%s,\"files\":",
                  lane.blastReaches, lane.blastFileTotal, lane.blastCapped ? "true" : "false" );
    writePathArray( out, lane.blastFiles );
    std::fprintf( out, "},\"tests_to_run\":" );
    writePathArray( out, lane.tests );
    std::fprintf( out, ",\"tests_total\":%zu,\"tests_capped\":%s,\"tests_granularity\":\"claimed-symbols\","
                       "\"untested\":%zu,\"module_span\":%u,\"notes\":",
                  lane.testTotal, lane.testsCapped ? "true" : "false", lane.untested, lane.moduleSpan );
    writePathArray( out, lane.notes );
    std::fprintf( out, "}" );
}

inline void writePair( std::FILE* out, const PairRow& row )
{
    std::fprintf( out, "{\"a\":\"%s\",\"b\":\"%s\",\"conflicts\":[", jsonStr( row.a ).c_str(), jsonStr( row.b ).c_str() );
    for( std::size_t i = 0; i < row.conflicts.size(); ++i )
    {
        const Claim& c = row.conflicts[i];
        std::fprintf( out, "%s{\"key\":\"%016llx\",\"p\":\"%s\",\"n\":\"%s\",\"overloads\":%u,\"id\":",
                      i == 0 ? "" : ",", ( unsigned long long )c.key, jsonStr( c.path ).c_str(), jsonStr( c.name ).c_str(), c.overloads );
        writeJsonStringOrNull( out, c.id );
        std::fprintf( out, "}" );
    }
    std::fprintf( out, "],\"conflict_count\":%zu,\"same_file_risk\":[", row.conflicts.size() );
    for( std::size_t i = 0; i < row.sameFileRisk.size(); ++i )
    {
        const RiskFileRow& f = row.sameFileRisk[i];
        std::fprintf( out, "%s{\"p\":\"%s\",\"a_symbols\":%u,\"b_symbols\":%u,\"pairs\":%zu}",
                      i == 0 ? "" : ",", jsonStr( f.path ).c_str(), f.aSymbols, f.bSymbols, f.pairCount );
    }
    std::fprintf( out, "],\"risk_count\":%zu,\"contract_touch\":[", row.riskPairCount );
    for( std::size_t i = 0; i < row.contractTouch.size(); ++i )
    {
        const TouchRow& t = row.contractTouch[i];
        std::fprintf( out, "%s{\"p\":\"%s\",\"n\":\"%s\",\"key\":\"%016llx\",\"from\":\"%s\",\"to\":\"%s\"}",
                      i == 0 ? "" : ",", jsonStr( t.path ).c_str(), jsonStr( t.name ).c_str(),
                      ( unsigned long long )t.key, jsonStr( t.from ).c_str(), jsonStr( t.to ).c_str() );
    }
    std::fprintf( out, "],\"touch_count\":%zu}", row.contractTouch.size() );
}

inline void writeCarve( std::FILE* out, const PlanLanesResult& r )
{
    if( !r.haveCarve ) { std::fprintf( out, "null" ); return; }
    std::fprintf( out, "{\"surface\":%u,\"modules\":%u,\"split\":%u,\"overlap_mean\":%.3f,\"overlap_max\":%.3f,"
                       "\"shared_symbols\":%u,\"union_symbols\":%u,\"core_overlap\":%.3f,"
                       "\"overlap_surface\":\"claims-plus-blast-radius\",\"overlap_is_ceiling\":true}",
                  r.carve.surface, r.carve.modules, r.carve.split, r.carve.overlapMean, r.carve.overlapMax,
                  r.carve.sharedSymbols, r.carve.unionSymbols, r.carve.coreOverlap );
}

inline void writeCore( std::FILE* out, const PlanLanesResult& r )
{
    std::fprintf( out, "{\"files\":" );
    writePathArray( out, r.coreFiles );
    std::fprintf( out, ",\"symbols\":[" );
    for( std::size_t i = 0; i < r.coreSymbols.size(); ++i )
    {
        const CoreSymbol& cs = r.coreSymbols[i];
        std::fprintf( out, "%s{\"p\":\"%s\",\"n\":\"%s\",\"scope\":\"%s\",\"l\":%u,\"id\":",
                      i == 0 ? "" : ",", jsonStr( cs.path ).c_str(), jsonStr( cs.name ).c_str(),
                      jsonStr( cs.scope ).c_str(), cs.line );
        writeJsonStringOrNull( out, cs.id );
        std::fprintf( out, "}" );
    }
    std::fprintf( out, "]}" );
}

inline void writePlanLanes( std::FILE* out, const PlanLanesResult& r )
{
    std::fprintf( out, "{\"v\":%d,\"verb\":\"plan-lanes\",\"at\":", kSchemaVersion );
    writeJsonStringOrNull( out, r.at );                       // never a fake sha: null on a non-git root
    std::fprintf( out, ",\"root\":\"%s\",\"task\":", jsonStr( r.root ).c_str() );
    writeJsonStringOrNull( out, r.task );                     // null in brief mode
    std::fprintf( out, ",\"source\":\"%s\",\"requested\":%u,\"lane_count\":%zu,"
                       "\"claim_key\":\"path+scope+name\",\"on_conflict\":\"producing-lane-rebases\","
                       "\"corpus\":{\"files\":%zu,\"symbols\":%zu,\"edges\":%zu,\"ambiguous\":%zu,\"unresolved\":%zu},\"carve\":",
                  jsonStr( r.source ).c_str(), r.requested, r.lanes.size(),
                  r.corpus.files, r.corpus.symbols, r.corpus.edges, r.corpus.ambiguous, r.corpus.unresolved );
    writeCarve( out, r );
    std::fprintf( out, ",\"core\":" );
    writeCore( out, r );

    std::fprintf( out, ",\"lanes\":[" );
    for( std::size_t i = 0; i < r.lanes.size(); ++i )
    {
        if( i )
        {
            std::fprintf( out, "," );
        }
        writeLane( out, r.lanes[i] );
    }
    std::fprintf( out, "],\"pairs\":[" );
    for( std::size_t i = 0; i < r.pairs.size(); ++i )
    {
        if( i )
        {
            std::fprintf( out, "," );
        }
        writePair( out, r.pairs[i] );
    }
    std::fprintf( out, "],\"landing_order\":" );
    writePathArray( out, r.landingOrder );
    std::fprintf( out, ",\"landing_rule\":\"fewest-conflicts-first greedy; ties by lane id ascending (lexicographic on the lane id string)\","
                       "\"contract_touch_rule\":\"a claim of lane `from` lies in the transitive-caller blast radius of lane `to`'s claims, so "
                       "`from` may have to adapt to a contract change `to` makes; it is NOT a merge conflict and is never counted into "
                       "conflict_count\",\"warnings\":[" );
    for( std::size_t i = 0; i < r.warnings.size(); ++i )
    {
        const Warning& w = r.warnings[i];
        std::fprintf( out, "%s{\"code\":\"%s\",\"sev\":\"%s\",", i == 0 ? "" : ",", w.code, w.sev );
        if( w.hasCount )
        {
            std::fprintf( out, "\"count\":%llu,", (unsigned long long)w.count );
        }
        std::fprintf( out, "\"text\":\"%s\"}", jsonStr( w.text ).c_str() );
    }
    std::fprintf( out, "]}\n" );
}

}   // namespace lanes
}   // namespace rw
