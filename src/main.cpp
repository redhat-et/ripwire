// main.cpp — ripwire entry point: parse args → ingest → graph → PageRank → minified XML,
// plus --map-diff (teleport toward git-changed files) and --pack-top-n (append source).
// ingest() comes from ingest.cpp (real, tree-sitter) or stub_ingest.cpp (test).

#include "model.h"
#include "infra/stdinline.h"       // R4: readByteSafeLine — the ONE byte-safe stdin line reader (--from-trace=- / --batch=-)
#include "ingest.h"
#include "workspace.h"             // multi-root workspaces: root hygiene + labels + the id-offset merge
#include "graph.h"
#include "scip.h"                  // SCIP precision overlay (--scip=index.scip)
#include "serialize.h"
#include "pageview.h"              // §P8: the ONE --limit/--offset window + root-element shown=/capped= disclosure
#include "graphlegend.h"           // §H4 §3.4: the ONE counts_floor= marker + the shared graph-count legend wording
#include "columnar.h"              // RESEARCH lever 1: opt-in columnar re-serialization for the flat list verbs (--format=columnar)
#include "redact.h"                // RedactCounts + reportRedactions for the emitted-body secret redaction
#include "filter.h"
#include "eval.h"
#include "skilleval.h"
#include "lexical.h"
#include "recall.h"
#include "situ.h"
#include "handoff.h"               // --handoff: the continuation packet (verified + heuristic sections)
#include "dmm.h"                   // --dmm: the Delta Maintainability Model scalar — the trendable complement to --quality-delta
#include "readability.h"           // --readability: the Posnett (MSR 2011) per-function readability lens
#include "commentcoherence.h"      // --comment-coherence: Steidl c_coeff + Scalabrino CIC, per documented function/method
#include "contextratio.h"          // --context-ratio: the LOCAL-REASONING lens (outside-the-file share of a unit's context)
#include "nonlocalstate.h"         // --nonlocal-state: per function, the non-local MUTABLE state it reaches (reads vs writes)
#include "renamemine.h"            // --naming-calibration: the naming-* rules scored against the repo's own rename history (§9.5)
#include "namingconsistency.h"     // --naming-consistency: §9.2 TIER A convention normalization (corpus-derived case-style vote)
#include "ensemble.h"              // --ensemble: the family join over structural / lexical / confusion / historical evidence
#include "qualitypanel.h"          // --quality-panel: THE SINGLE COMMAND — the ensemble's four families plus colocation and state, under a preset
#include "testmap.h"               // §P11.2/§P11.4: the test<->code map both ways (--affected=SYM seeding)
#include "packtask.h"              // L4: the shared --pack-task / MCP explore/pack_task bundle assembler (packTaskBundleText)
#include "partition.h"             // --pack-task --partition=N — the fan-out form (core + N slices), same assembler.
                                   //   BEFORE mcp.h so mcpverbs.h's explore verb can reach packTaskPartitionText (same rule packtask.h follows).
#include "tracelocus.h"            // L4: the shared --from-trace / MCP from_trace bundle assembler (fromTraceBundleText)
#include "editcheck.h"             // L4: the shared --edit-check / MCP edit_check contract-comparison core (editCheckBundleText)
#include "slice.h"                 // lane/paper-slice: --slice=SYM[:VAR] — the ARISE-motivated def-use slice core (sliceBundleText)
#include "mcp.h"
#include "mcpserver.h"             // the optional remote MCP transport (--listen), picked below
#include "editplan.h"              // CLI-first versioned multi-edit transactions
#include "wrap.h"
#include "infra/profileScope.h"    // PROFILE_SCOPE self-profiling — gated by PROFILE_ENABLED (off unless -DRIPWIRE_PROFILE=ON)
#include "arch.h"
#include "search.h"
#include "query.h"
#include "pattern.h"               // R2: the pattern surface's compiler + disclosures (the matcher runs inside the ingest walk)
#include "verify.h"                // G4 verify-a-claim: the --verify closed claim grammar + verdict/limit vocabularies (runVerify below)
#include "taskroute.h"             // --help-task: deterministic task -> one safe CLI recommendation or abstention
#include "quality.h"
#include "gitstamp.h"              // r26-stamp Task A: gitstamp::atAttr — the at="<sha>[+dirty]" root anchor, shared by
                                   // --hotspots / --quality-delta / --doctor below (each verb's own file pulls it too)
#include "binstale.h"              // --doctor's tracked-binary-staleness check (git-order, not mtime)
#include "codexdoctor.h"           // --doctor --agent=codex: live binary/skills/hooks/MCP surface parity
#include "crossref.h"              // --stray-content / --whereis — the cross-branch content index
#include "darkflags.h"             // --flags — the dark-content (compile/cmake/env gate) dashboard
#include "flipimpact.h"            // --flags --flip=NAME: the blast radius of turning ONE of those gates ON
#include "layout.h"                // --layout=STRUCT — computed field offsets + tripwires + mirror drift
#include "fieldaffinity.h"         // --field-affinity — the cache-locality lens (co-access graph vs declared order)
#include "abicheck.h"              // --stray-content --abi — the cross-branch ABI-BREAK gate (layout x stray-content)
#include "docdrift.h"              // --doc-drift — the markdown doc-anchor verifier
#include "gitoracle.h"             // --with-history: the shared "was this name ever here" git-history oracle
#include "mergescout.h"            // L1: --merge-scout=REF[,REF...] — read-only cross-branch overlap + landing order
#include "landingplan.h"           // --stray-content --plan — composes crossref's sweep with mergescout's overlap oracle
#include "lanes.h"                 // --plan-lanes=N --task / --plan-lanes --brief — the PRE-HOC lane plan (JSON on stdout)
#include "exemplar.h"              // A3-F5: shared --exemplar selection (ccx ceiling + fixture penalty + task→kind confidence)
#include "didyoumean.h"            // §P12.1 / §B6 M8: the ONE near-miss suggester, now shared with the MCP refusal table
#include "selectorrefuse.h"        // §B4.2: the ONE file:name selector not-found refusal — all six SYM-taking verbs
#include "gitmine.h"
#include "ownersview.h"            // §P6.4: countUniformOwnership/ownershipRowsToPrint — shared with mcpverbs.h's `owners` verb
#include "mention.h"               // B8: query-mention anchoring — files/modules/symbols NAMED in the --for text
#include "siblift.h"               // r4 EXPERIMENT: env-gated same-directory sibling lift (inert by default)
#include "filepool.h"              // r5 EXPERIMENT: env-gated file-level evidence pooling (inert by default)
#include "expand.h"                // r6 EXPERIMENT: env-gated structural expansion from top-ranked files (inert by default)
#include "tracein.h"               // L2: --from-trace=FILE — table-driven stack-trace/sanitizer/compiler frame extraction
#include "clones.h"
#include "skillscan.h"
#include "htmlexport.h"
#include "lintrules.h"
#include "lintcatalog.h"           // L7: --lint-catalog + --lint-select=/--lint-ignore= — the built-in rule registry
#include "atoms.h"                 // --lint: the atoms-of-confusion pack (Gopstein FSE 2017), C-family only
#include "cachelint.h"             // --lint: the cache-friendliness pack (access-pattern half; layout half is --field-affinity)
#include "naminglens.h"            // identifier-naming lens v1: the naming-* built-in --lint rules (deterministic, dictionary-free)
#include "verbtable.h"             // V6: known-verb dictionary for the community/zoom label verb-histogram suffix
#include "sarif.h"                 // --sarif: SARIF 2.1.0 re-serialization of --lint's findings (github code-scanning UI)
#include "prcontext.h"
#include "ccjson.h"
#include "cli.h"
#include "embedded_queries.h"      // configure-generated tags.scm table shared with ingest and --doctor
#include "infra/hashutil.h"        // sanitizer-clean modulo-2^64 FNV multiplication
#include "infra/charconvcompat.h"  // rw::parseFloating — FP from_chars is `= delete` on older libc++ (macos-14 CI)

#include <algorithm>
#include <array>
#include <charconv>
#include <cctype>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <functional>
#include <numeric>
#include <optional>
#include <span>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
#include <cstdint>
#include <climits>
#include <sys/stat.h>
#include <unistd.h>           // getpid — unique temp-dir suffix for the HEAD-snapshot path (T0.1)
#include <chrono>             // VT-1 --run-trace: the wall clock behind duration_ms/timeout (steady_clock)
#include <csignal>            // VT-1 --run-trace: SIGKILL for the timeout's process-group kill
#include <fcntl.h>            // VT-1 --run-trace: /dev/null for the child's stdin
#include <poll.h>             // VT-1 --run-trace: the capture loop's deadline wait
#include <sys/wait.h>         // VT-1 --run-trace: waitpid — the command's exit status, honestly decoded
#include <tree_sitter/api.h>  // --doctor's grammar-probe check (ts_query_new against each grammar's tags.scm)
#if defined( __APPLE__ )
#include <mach-o/dyld.h>       // --doctor's self-exe-path check (_NSGetExecutablePath)
#endif

namespace
{

using rw::shSingleQuote;   // defined in gitmine.h, shared with the MCP server

// The per-user cache-dir ladder + the git-baseline helpers now live in quality.h (the baseline home) so BOTH
// the CLI --quality-* paths and the MCP quality_delta/quality_baseline verbs call ONE copy — no duplicated
// git-archive / stale-vs-HEAD logic. Re-exported here so every existing call site below is byte-unchanged.
using rw::quality::cacheDirLadder;
using rw::quality::gitHeadSha;
using rw::quality::gitRepoHasHistory;
using rw::quality::computeHeadSnapshot;
using rw::quality::resolveCacheBlobPath;   // Y4: shard-aware blob path — see quality.h

// 2026-08-29 main.cpp split: the cross-family helpers promoted to their domain headers, re-exported so
// every existing call site below (and in the verb-family sections this file includes) is byte-unchanged.
using rw::gitChangedFiles;                 // situ.h — the working-tree changed-file mask, one mask builder for CLI + MCP
using rw::gitChurnCounts;                  // gitmine.h — per-file commit counts over a window
using rw::mineChurnPerFile;                // gitmine.h — THE shared per-file churn miner (single- and multi-root)
using rw::quality::isHeaderPath;           // quality.h — the --dead-code eligibility trio, shared with --safe-delete
using rw::quality::sourceHasStaticToken;
using rw::quality::deadCodeEligibleKind;

// Warm-by-default cache location: a per-root file keyed by the root's ABSOLUTE path (FNV-1a 64), under
// the hardened cacheDirLadder(), so repeated invocations on the same tree re-parse only changed files.
// Absolute path so two different dirs both invoked as "." don't collide (a collision would only ever
// cost a cold re-parse — the cache is keyed per-file-path internally — but absolute keeps each tree's
// cache distinct and warm). Cache content is content-hashed + parserVer-gated, so a stale/foreign cache
// self-heals to a correct cold parse. STABLE per (user, root): same root + same env → same path, so
// warm-cache reuse still works across runs.
//
// A4-P4: the cache file is SPLIT by verb class (lean vs rich). --for/--metrics/--uses/--exemplar
// ingest "rich" (captureValueUses=true); everything else "lean". Both classes are parserVer-gated to
// DIFFERENT versions (parserVerFor), so a single shared file forced a full re-parse + full rewrite on
// every class switch (measured: plain-map-after --for 0.81 s vs 0.16 s warm). Suffixing the filename
// with the class gives each class its OWN warm cache, so alternating verb classes never thrashes.
// (MCP has its own separate file, mcpCachePath in mcp.h — unaffected.)
//
// Y4: resolved through resolveCacheBlobPath (quality.h) — the shard-aware, backward-compatible
// choke point every ripwire-*.bin blob path now routes through. See its comment for the full rationale.
std::string defaultCachePath( const std::string& root, bool captureValueUses )
{
    char        absbuf[ PATH_MAX ];
    const char* abs = realpath( root.c_str(), absbuf ) ? absbuf : root.c_str();
    std::uint64_t h = 1469598103934665603ull;
    for( const char* c = abs; *c; ++c ) { h ^= static_cast<unsigned char>( *c ); h = rw::hashutil::fnv1aMultiply( h ); }
    char tail[ 48 ];
    std::snprintf( tail, sizeof( tail ), "ripwire-%016llx-%s.bin",
                   static_cast<unsigned long long>( h ), captureValueUses ? "rich" : "lean" );
    return resolveCacheBlobPath( cacheDirLadder(), tail );
}

// computeHeadSnapshot / gitHeadSha / gitRepoHasHistory / cacheDirLadder now live in quality.h (the
// baseline home) and are re-exported via the `using` aliases above — one shared copy for CLI + MCP.
// module = a symbol's immediate parent DIRECTORY (the real subsystem: canyon/, steer/, …). Fills
// symDir[symbolId] = module id and dirName[id] = directory path. Shared by --seams and --mermaid —
// one-level Louvain is too fine to be a "module"; the directory is the meaningful boundary.
// R-E (2026-08-17 harvest): rootPrefix empty ⇒ dirName[] keeps the ing.files[] directory spelling unchanged
// (multi-root, or no single root to strip) — relativizing at the point the directory string is FIRST
// derived, same reasoning as communityPresentation() above, so both --seams and --mermaid inherit the fix.
void computeDirModules( const rw::IngestResult& ing, std::vector<std::uint32_t>& symDir, std::vector<std::string>& dirName,
                        std::string_view rootPrefix = {} )
{
    rw::HashMap<std::string, std::uint32_t> dirId;
    const auto idOf = [ & ]( std::string_view d ) -> std::uint32_t
    {
        const auto it = dirId.find( std::string( d ) );
        if( it != dirId.end() )
        {
            return it->second;
        }
        const std::uint32_t id = std::uint32_t( dirName.size() );
        dirId.emplace( std::string( d ), id );  dirName.emplace_back( d );
        return id;
    };
    symDir.assign( ing.symbols.size(), 0 );
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        std::string_view  rawP = ing.files[ ing.symbols[i].fileId ];
        std::string_view  p    = rootPrefix.empty() ? rawP : rw::sarif::rootRelativeUri( rawP, rootPrefix );
        const std::size_t sl = p.rfind( '/' );
        symDir[i] = idOf( sl == std::string_view::npos ? std::string_view( "." ) : p.substr( 0, sl ) );
    }
}


// gitRepoHasHistory / gitHeadSha moved to quality.h (re-exported via the `using` aliases above) so the CLI
// --quality-* paths and the MCP quality_delta/quality_baseline verbs share ONE copy of the HEAD probes.

// Wave-4 remote ergonomics: `ripwire <git-url>` — if the positional arg is a git URL (https:// or
// git@), shallow-clone it (git clone --depth=1, core.quotepath=false) into a stable per-URL cache dir
// under $TMPDIR (reused if it already exists) and return the local path to map. On success, prints one
// stderr line telling the user where it cloned. On failure, prints a clear error and returns "" (the
// caller degrades: error + exit 1). A non-URL arg is returned unchanged (no clone attempted).
//
// A3-F15: a leading '-' is rejected here even if it otherwise matches a scheme prefix (it can't, since
// none of the four prefixes start with '-', but this also blocks a bare "-..." that some future scheme
// addition might otherwise accept) — the load-bearing option-injection defense lives at the clone
// call site (`--` before the URL + the protocol.ext/protocol.file allow-list below); this check is a
// second, cheap gate on the "is this even a URL" recognizer itself.
bool isGitUrl( std::string_view s ) noexcept
{
    if( s.empty() || s.front() == '-' )
    {
        return false; // never treat a dash-leading arg as a URL (option-injection guard)
    }
    return s.rfind( "https://", 0 ) == 0 || s.rfind( "http://", 0 ) == 0 || s.rfind( "git@", 0 ) == 0 || s.rfind( "ssh://", 0 ) == 0;
}

// T2 pagination window + the §P8 root-element disclosure both live in pageview.h now — three serializers
// need them (main.cpp's verbs, crossref.h's --whereis, docdrift.h's --doc-drift) and the vocabulary must not
// drift between them. `using` rather than a re-declaration so there is exactly one definition.
using rw::PageWindow;
using rw::pageWindow;
using rw::pageDisclosure;
using rw::pagingDisclosure;
using rw::effectiveRowCap;

// §P8 G1: the local pageAttr() that used to live here — a bare ` offset="M" limit="N"` for --callers/
// --callees/--tree — is DELETED, not deprecated. It cut rows correctly but disclosed neither the total nor
// has_more/next_offset, so those three verbs looked paginated while a loop over them could never terminate:
// a second, strictly weaker paging vocabulary sitting next to the real one. Every caller now uses
// pageDisclosure() (or pagingDisclosure() where a noun-prefixed shown_<noun>= already serves), so there is
// exactly ONE spelling of "this response is a page" in the tool. See src/pageview.h.


// §P6.2: a community label anchored to a trivial accessor ("push_back@svector.h", "empty@notes.h" — the
// real-repo instances that motivated this) tells a reader nothing about a multi-member module. These names
// are called from everywhere by construction (every container user calls push_back/empty/size), so they
// tend to WIN the highest-PageRank/highest-fan-in race despite carrying no semantic content. Table mirrored
// by hand in test/communitylabelcheck.sh (the gate has no way to import a constexpr table from the binary).
constexpr std::array<std::string_view, 31> kAccessorNames = {
    "empty", "size", "begin", "end", "cbegin", "cend", "push_back", "pop_back", "emplace_back",
    "data", "get", "set", "front", "back", "clear", "reserve", "resize", "at", "count", "length",
    "c_str", "insert", "erase", "find", "top", "push", "pop", "key", "value", "first", "second",
};

bool isAccessorName( std::string_view name ) noexcept
{
    for( std::string_view accessor : kAccessorNames )
    {
        if( name == accessor )
        {
            return true;
        }
    }
    // getX / setX getter-setter convention (name[3] uppercase, e.g. "getIndex", "setFlag").
    if( name.size() > 3 && ( name.rfind( "get", 0 ) == 0 || name.rfind( "set", 0 ) == 0 ) )
    {
        return name[3] >= 'A' && name[3] <= 'Z';
    }
    return false;
}

// A community-label anchor's sort key: ASCENDING on (isAccessor, invFanIn, invRank, nodeId), so plain
// operator< on this struct directly implements "prefer non-accessor, then highest fan-in, then highest
// PageRank, then lowest nodeId" without a hand-written comparison chain — that shape already exists as
// notes.h's noteLess() total order, and quality-delta's clone detector (correctly) flags a second one.
// invFanIn/invRank carry the DESCENDING fields inverted so the whole key stays a single ascending tuple.
struct AnchorKey
{
    bool          isAccessor;
    std::uint32_t invFanIn;
    float         invRank;
    rw::NodeId   nodeId;

    bool operator<( const AnchorKey& other ) const noexcept
    {
        return std::tie( isAccessor, invFanIn, invRank, nodeId ) < std::tie( other.isAccessor, other.invFanIn, other.invRank, other.nodeId );
    }
};

// A Louvain community id is an implementation detail, and a dominant directory alone is not unique when
// one directory contains multiple cohesive call clusters. Give every community a deterministic semantic
// label anchored to its highest-fan-in NON-ACCESSOR symbol (falling back to the highest-ranked symbol only
// when every member is an accessor) and exact source location. sigStartByte is a source anchor, not an
// opaque community-id suffix; it disambiguates overloads or generated definitions on the same line.
struct CommunityPresentation
{
    std::vector<std::string> directory;
    std::vector<std::string> label;
};

// community id → its member symbol ids. N=2 is FREE (rw::svector<NodeId,1> and <NodeId,2> are both 16 B,
// against a std::vector's 24) and covers 92.9%/95.5% of communities across the two census corpora: a
// Louvain partition of a call graph is mostly singletons — 88.1%/92.7% of communities hold exactly ONE
// symbol — so nearly every list here was a one-element heap block. 5 990 of them on this tree, 31 369 on
// the validation corpus, rebuilt by each of the four verbs below.
using CommunityMembers = std::vector<rw::SmallVec<rw::NodeId, 2>>;

// V6 (graphrag-transfer): the ordering key for --communities/--zoom module rows. The pre-fix ordering was
// raw member count alone, which lets a large PERIPHERAL leaf cluster (many members, each individually
// low-ranked) outrank a small LOAD-BEARING hub cluster (few members, each highly ranked) — confirmed live
// on ripwire's own tree, where the 572-member `min@infra/fastmath.h` cluster (mostly unrelated call-site
// name collisions) sorts first by size alone. Mass sums the already-computed PageRank vector over a
// community's members instead of merely counting them; member count remains the deterministic SECONDARY
// tie-break (mirroring the pre-fix primary), then community id — see every call site below.
float communityRankMass( const rw::SmallVec<rw::NodeId, 2>& communityMembers, const std::vector<float>& rank ) noexcept
{
    return std::accumulate( communityMembers.begin(), communityMembers.end(), 0.0f,
                            [ & ]( float acc, rw::NodeId nodeId ) { return acc + rank[nodeId]; } );
}

// V6: the shared (rank-mass desc, size desc, id asc) tie-break every module-ordering sort below uses —
// --communities' flat `order`/`ord` and --zoom's per-level `topOrder`/`kids` are all the same three-key
// comparator over a different (mass, members) slice, so it is one function rather than four inline copies.
bool massSizeIdLess( std::uint32_t a, std::uint32_t b, const std::vector<float>& mass, const CommunityMembers& members ) noexcept
{
    if( mass[a] != mass[b] )                     { return mass[a] > mass[b]; }
    if( members[a].size() != members[b].size() ) { return members[a].size() > members[b].size(); }
    return a < b;
}

// V6: --zoom's per-LEVEL counterpart to communityRankMass — one mass vector per level of the multi-level
// hierarchy, precomputed once so every sort at every level (top-level order + every level's child order)
// is an O(1) lookup rather than re-summing a group's members on each comparator call.
std::vector<std::vector<float>> perLevelRankMass( const std::vector<CommunityMembers>& members, const std::vector<float>& rank )
{
    std::vector<std::vector<float>> mass( members.size() );
    for( std::size_t l = 0; l < members.size(); ++l )
    {
        mass[l].resize( members[l].size() );
        for( std::size_t gid = 0; gid < members[l].size(); ++gid )
        {
            mass[l][gid] = communityRankMass( members[l][gid], rank );
        }
    }
    return mass;
}

// V6 (grepai-transfer): a deterministic verb-histogram SUFFIX for a community's label. grepai's RPG
// hierarchy (rpg/extractor_local.go's LocalExtractor + rpg/hierarchy.go's EnrichLabels) tags every symbol
// with its first-word verb (a fixed dictionary lookup) and aggregates the per-cluster frequency into the
// label; ripwire's community label was a single lead-symbol anchor only, so two clusters that happen to
// share an anchor NAME (two different `process` clusters, say) were indistinguishable. This reuses two
// primitives that already exist — naminglens::splitIdentifier for the tokenizer, verbtable::kKnownVerbs
// for the dictionary check (via std::binary_search — see that header for why there is no wrapper
// function here) — and is purely additive: the anchor (§P6.2) stays the primary disambiguator.
//
// Determinism: communityMembers arrives in ascending NodeId order (both call sites below build it with a
// single ascending push loop), so "first-seen" IS a stable, reproducible tie-break; stable_sort by count
// alone over an already-deterministic input cannot introduce nondeterminism, and ties never depend on
// container iteration order because the sort operates on `verbOrder`, a plain vector, not the map.
std::string communityVerbSuffix( const rw::IngestResult& ing, const rw::SmallVec<rw::NodeId, 2>& communityMembers )
{
    std::vector<std::string>                verbOrder;   // first-seen order == the eventual tie-break
    rw::HashMap<std::string, std::uint32_t>  verbCount;
    std::vector<std::string>                 splitScratch;

    for( rw::NodeId nodeId : communityMembers )
    {
        rw::naminglens::splitIdentifier( ing.symbols[nodeId].name, splitScratch );
        if( splitScratch.empty() )
        {
            continue;
        }
        const std::string first = rw::naminglens::toLowerAscii( splitScratch.front() );
        if( !std::binary_search( rw::verbtable::kKnownVerbs.begin(), rw::verbtable::kKnownVerbs.end(), std::string_view( first ) ) )
        {
            continue;
        }
        const auto [ it, inserted ] = verbCount.try_emplace( first, 0u );
        if( inserted )
        {
            verbOrder.push_back( first );
        }
        ++it->second;
    }
    std::stable_sort( verbOrder.begin(), verbOrder.end(),
                      [ & ]( const std::string& a, const std::string& b ) { return verbCount[a] > verbCount[b]; } );

    const std::size_t topVerbs = std::min<std::size_t>( 3, verbOrder.size() );
    if( topVerbs == 0 )
    {
        return {};
    }
    std::string suffix = " [";
    for( std::size_t i = 0; i < topVerbs; ++i )
    {
        if( i ) { suffix += ","; }
        suffix += verbOrder[i];
    }
    suffix += "]";
    return suffix;
}

// R-E (2026-08-17 harvest): rootPrefix empty ⇒ dir=/label= keep the ing.files[] directory spelling unchanged
// (multi-root, or no single root to strip) — the SAME convention every other lens's pathRel uses, applied
// here at the point the directory string is first derived so every downstream reader of dir=/label= (both
// emitters below, and the zoom view) inherits the fix instead of needing its own patch.
CommunityPresentation communityPresentation( const rw::IngestResult& ing, const rw::Graph& g,
                                             const CommunityMembers& members,
                                             const std::vector<float>& rank,
                                             std::string_view rootPrefix = {} )
{
    CommunityPresentation out;
    out.directory.resize( members.size() );
    out.label.resize( members.size() );
    const auto* inRowOffset = g.inEdges.rowOffsets();   // in-edge CSR row offsets: fanIn(i) = inRowOffset[i+1]-inRowOffset[i]
    const auto  fanIn       = [ & ]( rw::NodeId nodeId ) { return inRowOffset[ nodeId + 1 ] - inRowOffset[ nodeId ]; };

    for( std::size_t communityIndex = 0; communityIndex < members.size(); ++communityIndex )
    {
        const rw::SmallVec<rw::NodeId, 2>& communityMembers = members[ communityIndex ];
        if( communityMembers.empty() )
        {
            continue;
        }

        rw::HashMap<std::string, std::uint32_t> directoryCount;
        const auto keyOf = [ & ]( rw::NodeId nodeId ) -> AnchorKey
            { return { isAccessorName( ing.symbols[nodeId].name ), ~fanIn( nodeId ), -rank[nodeId], nodeId }; };
        rw::NodeId lead    = communityMembers.front();
        AnchorKey   leadKey = keyOf( lead );
        for( rw::NodeId nodeId : communityMembers )
        {
            std::string_view  rawPath = ing.files[ ing.symbols[nodeId].fileId ];
            std::string_view  path    = rootPrefix.empty() ? rawPath : rw::sarif::rootRelativeUri( rawPath, rootPrefix );
            const std::size_t slash = path.rfind( '/' );
            ++directoryCount[ std::string( slash == std::string_view::npos ? path : path.substr( 0, slash ) ) ];

            const AnchorKey key = keyOf( nodeId );
            if( key < leadKey ) { lead = nodeId; leadKey = key; }
        }

        std::uint32_t dominantCount = 0;
        for( const auto& [ directory, count ] : directoryCount )
        {
            if( count > dominantCount || ( count == dominantCount && directory < out.directory[ communityIndex ] ) )
            {
                dominantCount                   = count;
                out.directory[ communityIndex ] = directory;
        }
        }

        const rw::Symbol& symbol = ing.symbols[ lead ];
        // R-E (2026-08-17 harvest) fix: this MUST read the same relativized spelling out.directory[] above
        // was just built from (rawPath/path further up in this loop), never the raw ing.files[] value — the
        // prefix-strip below matches directoryPrefix (relative) against anchorPath at position 0, and an
        // absolute anchorPath against a relative prefix never matches at 0, so the strip silently no-oped
        // and the full absolute path rode into the label instead of just failing loudly.
        std::string_view   anchorPath = rootPrefix.empty() ? ing.files[ symbol.fileId ] : rw::sarif::rootRelativeUri( ing.files[ symbol.fileId ], rootPrefix );
        const std::string  directoryPrefix = out.directory[ communityIndex ] + "/";
        if( anchorPath.rfind( directoryPrefix, 0 ) == 0 )
        {
            anchorPath.remove_prefix( directoryPrefix.size() );
        }
        out.label[ communityIndex ] = out.directory[ communityIndex ] + "::" + symbol.name + "@"
                                    + std::string( anchorPath ) + ":" + std::to_string( symbol.line ) + ":"
                                    + std::to_string( symbol.sigStartByte )
                                    + communityVerbSuffix( ing, communityMembers );
    }
    return out;
}


struct IsolateStats
{
    std::uint32_t total               = 0;
    std::uint32_t declaration         = 0;
    std::uint32_t header              = 0;
    std::uint32_t source              = 0;
    std::uint32_t document            = 0;
    std::uint32_t connectedSingletons = 0;
};

IsolateStats isolateStats( const rw::IngestResult& ing, const rw::Graph& graph,
                           const CommunityMembers& members ) noexcept
{
    IsolateStats stats;
    const auto*  inRowOffset = graph.inEdges.rowOffsets();

    for( const rw::SmallVec<rw::NodeId, 2>& communityMembers : members )
    {
        if( communityMembers.size() != 1 )
        {
            continue;
        }
        const rw::NodeId nodeId = communityMembers.front();
        const bool isConnected = graph.outOff[nodeId] != graph.outOff[nodeId + 1]
                              || inRowOffset[nodeId] != inRowOffset[nodeId + 1];
        if( isConnected )
        {
            ++stats.connectedSingletons;
        }
    }

    for( const rw::Symbol& symbol : ing.symbols )
    {
        const rw::NodeId nodeId = symbol.id;
        if( graph.outOff[nodeId] != graph.outOff[nodeId + 1] || inRowOffset[nodeId] != inRowOffset[nodeId + 1] )
        {
            continue;
        }
        ++stats.total;

        // Mutually-exclusive provenance, ordered from semantic node kind to definition placement.
        if( symbol.kind == rw::SymKind::Section )
        {
            ++stats.document;
        }
        else if( symbol.sigEndByte >= symbol.endByte )
        {
            ++stats.declaration;
        }
        else if( isHeaderPath( ing.files[symbol.fileId] ) )
        {
            ++stats.header;
        }
        else
        {
            ++stats.source;
        }
    }
    return stats;
}


// octocode partial-fetch + the §P8 seam-1 selector: split one --expand/--outline token into the SELECTOR
// it resolves through and an optional 1-based [start,end] line range. The grammar (documented in --help):
//
//     NAME                 whole body                                        (original)
//     NAME:START-END       body slice                                        (original)
//     FILE:NAME            file-qualified selector                           (§P8 seam 1)
//     FILE:LINE:NAME       a pasted `p="path:line"` locator + the row's n=    (§P8 seam 1)
//     FILE:NAME:START-END  selector AND slice                                (§P8 seam 1)
//
// The text after the LAST ':' decides, by ONE rule: **it is a range attempt iff it starts with a digit**
// — no identifier in any grammar we parse starts with a digit, so the two readings can never collide.
// Everything else leaves the WHOLE token as the selector, which then resolves through the same
// resolveAllByNameQualified() --callers/--callees/--impact use (one resolver, not a second implementation):
// bare name → every def of that name; canonical id → exact; file:name → that file's def. This is what makes
// `--callers=X` → pick a row → fetch its body a real chain — before it, the `:` in the row's own `p=` was
// read as a range, warned "malformed range", and the leftover path was refused as a typo'd symbol name.
//
// A range attempt that does not parse (non-numeric, empty half, START==0) still DEGRADES to whole-body —
// never a hard error, never a crash — with a one-line stderr note naming `verb` (house style: recoverable
// input ⇒ degrade + note, not VERIFY/throw). `verb` exists because --outline routes through here too and
// used to emit a note blaming --expand (§P10 X7). A reversed range (START>END) is NOT rejected here —
// sliceBodyLines() swaps it defensively — so only truly unparseable text degrades.
struct ExpandToken { std::string selector; rw::LineRange range; };
inline ExpandToken parseExpandToken( const std::string& token, const char* verb = "--expand" ) noexcept
{
    ExpandToken out;
    out.selector = token;                                               // the default for every non-range shape

    // Split at the LAST ':' — a canonical id (path::scope::name, exactly what --for/--pack-task emit in id=)
    // is full of ':' and every one of them is scope syntax, never a range seam. Splitting at the FIRST ':'
    // turned "./src/serialize.h::XmlWriter::write" into the name "./src/serialize.h" and then refused it.
    const std::size_t colon = token.rfind( ':' );
    if( colon == std::string::npos )
    {
        return out; // no range → whole-body, unchanged
    }

    const std::string_view rangeStr = std::string_view( token ).substr( colon + 1 );

    // The disambiguator. A tail that does not open with a digit is a NAME, so the whole token is a
    // file-qualified selector — return it untouched and silently (this is a CORRECT input, not a botch).
    if( rangeStr.empty() || rangeStr.front() < '0' || rangeStr.front() > '9' )
    {
        return out;
    }

    out.selector = token.substr( 0, colon );
    const std::size_t dash = rangeStr.find( '-' );

    const auto parseU32 = []( std::string_view s, std::uint32_t& v ) noexcept
    {
        if( s.empty() )
        {
            return false;
        }
        for( char c : s )
        {
            if( c < '0' || c > '9' )
            {
                return false; // digits only — no sign, no whitespace
            }
        }
        char*      end = nullptr;
        const long n   = std::strtol( std::string( s ).c_str(), &end, 10 );
        if( n <= 0 || n > 0x7FFFFFFFL )
        {
            return false; // START/END are 1-based; 0 or overflow is malformed
        }
        v = std::uint32_t( n );
        return true;
    };

    std::uint32_t startLine = 0, endLine = 0;
    const bool    parsed = dash != std::string_view::npos
                         && parseU32( rangeStr.substr( 0, dash ), startLine )
                         && parseU32( rangeStr.substr( dash + 1 ), endLine );
    if( !parsed )
    {
        // A "::" anywhere means the tail is a scope segment, not a botched range: the whole token is the
        // name. Silent by design — "path::scope::name" is a CORRECT input, so warning about it would train
        // the reader to ignore a warning that fires on the happy path.
        if( token.find( "::" ) != std::string::npos ) { out.selector = token;  return out; }

        std::fprintf( stderr, "ripwire: %s=%s: malformed range '%.*s' (want START-END, e.g. 5-10) — emitting the whole body\n",
                      verb, token.c_str(), int( rangeStr.size() ), rangeStr.data() );
        return out;   // degrade: selector only, hasRange stays false
    }
    out.range.startLine = startLine;
    out.range.endLine   = endLine;
    out.range.hasRange  = true;
    return out;
}

// S3: how old is a cached clone, in whole days, from the cache DIR's mtime (no network call — the dir's
// mtime is bumped by the clone itself and untouched by a read-only map, so it approximates "when we last
// fetched"). Clamped to >= 0 so a clock skew (mtime in the future) never prints a negative age.
long cloneAgeDays( const std::string& cacheDir )
{
    struct stat st{};
    if( ::stat( cacheDir.c_str(), &st ) != 0 )
    {
        return 0;
    }
    const long long ageSec = static_cast<long long>( std::time( nullptr ) ) - static_cast<long long>( st.st_mtime );
    return ageSec > 0 ? static_cast<long>( ageSec / 86400 ) : 0;
}

// returns { localPath, ok }. ok=false ⇒ clone failed (caller exits 1). Non-URL ⇒ { url-as-is, true }.
// refetch=true forces a fresh clone even if a cached one already exists (S3: the cache otherwise never
// refetches — a months-old clone would be silently mapped forever).
std::pair<std::string, bool> resolveRemoteRoot( const std::string& urlOrPath, bool refetch = false )
{
    if( !isGitUrl( urlOrPath ) )
    {
        return { urlOrPath, true };
    }

    // cache key = FNV-1a-64 of the URL → <hardened cache dir>/ripwire-remote-<hex>. Reuse if the dir
    // already exists (idempotent: a second run on the same URL is instant, no re-clone) — S4: same
    // $TMPDIR → $XDG_CACHE_HOME/ripwire (0700) → /tmp ladder as defaultCachePath/mcpCachePath.
    std::uint64_t h = 1469598103934665603ull;
    for( const char c : urlOrPath )
    {
        h = rw::hashutil::fnv1aAbsorb( h, c );
    }
    char tail[ 48 ];
    std::snprintf( tail, sizeof( tail ), "/ripwire-remote-%016llx", static_cast<unsigned long long>( h ) );
    const std::string cacheDir = cacheDirLadder() + tail;

    namespace fs = std::filesystem;
    std::error_code ec;
    if( !refetch && fs::exists( fs::path( cacheDir ) / ".git", ec ) && !ec )
    {
        const long ageDays = cloneAgeDays( cacheDir );
        std::fprintf( stderr, "ripwire: reusing cached clone of %s (%ld day%s old); pass --refetch to update\n",
                      urlOrPath.c_str(), ageDays, ageDays == 1 ? "" : "s" );
        return { cacheDir, true };
    }

    // fresh clone (either no cache yet, or --refetch forced one). Remove any existing/partial dir first
    // so a half-clone (or a stale one, under --refetch) can't poison the cache.
    //
    // A3-F15 hardening: `-c protocol.ext.allow=never` blocks the `ext::` transport (arbitrary command
    // execution via a crafted "URL") and `-c protocol.file.allow=user` keeps `file://` limited to the
    // invoking user's own privilege (no cross-user local-clone tricks); `--` before the URL stops a
    // URL string that starts with `-` from ever being parsed as a `git clone` OPTION even if isGitUrl's
    // own leading-dash guard were ever bypassed or loosened — belt-and-suspenders, not the only gate.
    fs::remove_all( fs::path( cacheDir ), ec );
    const std::string cmd = "git -c protocol.ext.allow=never -c protocol.file.allow=user -c core.quotepath=false "
                             "clone --depth=1 -q -- " + rw::shSingleQuote( urlOrPath )
                          + " " + rw::shSingleQuote( cacheDir ) + " 2>&1";
    std::fprintf( stderr, "ripwire: cloning %s → %s\n", urlOrPath.c_str(), cacheDir.c_str() );
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        std::fprintf( stderr, "ripwire: could not launch git clone (is git on PATH?)\n" );
        return { std::string(), false };
    }
    char line[ 4096 ];
    while( std::fgets( line, sizeof( line ), pipe ) )
    {
        std::fprintf( stderr, "  %s", line ); // surface git's own diagnostics
    }
    const int rc = pclose( pipe );
    if( rc != 0 || !( fs::exists( fs::path( cacheDir ) / ".git", ec ) && !ec ) )
    {
        std::fprintf( stderr, "ripwire: git clone failed for %s\n", urlOrPath.c_str() );
        fs::remove_all( fs::path( cacheDir ), ec );
        return { std::string(), false };
    }
    return { cacheDir, true };
}

// §P12.1 / A3-F16a: the bounded-edit-distance near-miss suggester moved to src/didyoumean.h (§B6 M8) so
// the MCP arms can reach the SAME one — their not-found refusals used to carry no suggestion at all
// because this code was unreachable from a header. Pulled back in under its original three names, so
// every call site below (17 of them) is unchanged.
using rw::boundedEditDistance;
using rw::didYouMean;
using rw::withDidYouMean;
using rw::selectorNotFoundMessage;   // §B4.2: the shared file:name selector refusal (selectorrefuse.h)

// ── verb-dispatch context (Phase B7.2) ───────────────────────────────────────────────────────────────
// The shared, post-graph state every verb handler reads. Bundling it into one views-at-the-seam struct
// keeps each handler to a single parameter; each handler rebinds only the fields it uses, so the moved
// bodies below are byte-identical to the pre-B7.2 inline dispatch blocks in main().
struct MainDispatch
{
    const rw::Config&                     cfg;
    const rw::IngestResult&               ing;
    const rw::Graph&                      g;
    const std::string&                     root;
    bool                                   multiRoot;
    const std::vector<rw::WorkspaceRoot>& ws;
    const std::vector<std::uint32_t>&      fanIn;
    const std::vector<std::uint32_t>*      fanInPtr;
    const rw::QMetrics&                   qmetrics;
    const std::vector<std::uint32_t>*      ampPtr;
    const std::vector<std::uint32_t>*      cboPtr;
    const std::vector<std::uint8_t>*       testedPtr;
    const std::vector<std::uint32_t>*      lcom4Ptr;
    const std::vector<char>*               impurePtr;
    std::vector<std::uint32_t>&            forChurn;
    rw::RedactCounts&                     redactCounts;
    rw::RedactCounts*                     redactPtr;
    const rw::notes::NoteIndex*           notesPtr;   // L3: field-notes surfacing index (nullptr ⇒ inert: no/empty file, or multi-root)
};

}   // namespace — part 1: the shared preamble helpers + the verb-dispatch context

// ── the verb-family sections (2026-08-29 split) ──────────────────────────────────────────────────────
// Each verbs_*.h below is a SECTION of this translation unit, not a library header: it reopens the
// unnamed namespace above (one TU, one unnamed namespace), sees every #include and preamble helper
// defined so far, and is included exactly once, right here. RIPWIRE_MAIN_TU is the enforcement: any
// other includer is a compile error. Order matters — a later section may call an earlier one (the
// change family calls the for family's computeLensRanking; everything may call the promoted domain
// helpers re-exported at the top of this file).
#define RIPWIRE_MAIN_TU 1
#include "verbs_doctor.h"
#include "verbs_lint.h"
#include "verbs_for.h"
#include "verbs_navigate.h"
#include "verbs_quality.h"

namespace
{

std::optional<int> runArchViews( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool             avSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view avRootArg    = avSingleRoot ? cfg.roots[0] : std::string_view();

    // --deps: the file→file physical dependency view (#include / import counts + targets), heaviest
    // first — the "why pull in 100 headers for something simple" detector.
    if( cfg.deps )
    {
        const auto      adj    = resolveIncludeAdj( ing );   // the file→file dependency graph (forward = includes)
        const auto      cycles = sccCycles( adj );           // Lakos cardinal sin: cyclic physical deps
        const DepHealth h      = dependencyHealth( adj );    // per-file transitive cone (unrestricted BFS)
        // §P9.4: <health>'s ccd/acd/nccd are the RESTRICTED (dependency-capable-only) numbers — recomputed
        // from h.transitive (a post-pass, not a second BFS; see graph.h::restrictDependencyHealth).
        const RestrictedDepHealth rh = restrictDependencyHealth( ing, h.transitive );
        std::vector<std::uint32_t> afferent( ing.files.size(), 0 );   // Ca: # files that include each file (blast radius)
        for( const auto& outs : adj )
        {
            for( std::uint32_t g : outs )
            {
                if( g < afferent.size() )
                {
                    ++afferent[g];
                }
            }
        }
        packDeps( stdout, ing, cfg.packTopN > 0 ? cfg.packTopN : 40, cycles, h.transitive, afferent, adj, rh.ccd, rh.acd, rh.nccd, cfg.pageLimit, cfg.pageOffset, avRootArg );
        return 0;
    }

    // --arch=FILE: architectural fitness function. Enforce the user's declared layering rules against the
    // #include graph; print every crossing edge; exit 2 if any (a CI gate). The rules are the user's — ripwire
    // imposes no architecture, only the one declared.
    //
    // S5-B --baseline support: a `.ripwire_arch_baseline` sidecar (one FNV-1a-64 hex hash per line) identifies
    // accepted violations (the current debt). Hash key = src_file + NUL + dst_file + NUL + FROM->TO label.
    // --baseline (first run): write the sidecar with all current violations, exit 0.
    // No flag + sidecar present: suppress baselined violations; exit 2 ONLY for new (un-baselined) ones.
    // --baseline-update: merge current violations into the sidecar (accept new debt deliberately), exit 0.
    if( !cfg.archRules.empty() )
    {
        const ArchRules ar = parseArchRules( std::string( cfg.archRules ) );
        if( !ar.loaded )
        {
            // D9: a malformed non-comment line already got a specific `path:lineNo: reason` message from
            // parseArchRules itself (mirrors --lint-rules) — printing the generic "cannot read" on top would
            // misdescribe a syntax error (file exists, parses to nothing) as a missing/unreadable file.
            if( !ar.parseError )
            {
                std::fprintf( stderr, "ripwire: --arch cannot read rules file: %.*s\n", int( cfg.archRules.size() ), cfg.archRules.data() );
            }
            return 1;
        }
        const auto adj = resolveIncludeAdj( ing );

        // ── EVERY rule is matched against the ROOT-RELATIVE path, never the emitted one ────────────────────
        // ing.files spells each file `<ingest-root>/<relative>` verbatim, so matching a user regex or a layer
        // substring against it makes the rule mean different things in different checkouts. Measured on the
        // shipped fixture: `deny path src/(\w+)/.* -> src/(?!\1/).*` gives 4 violations from a checkout with
        // no `src` in its path and 7 from one named `wt-cf2src`, because the leftmost `src/` regex_search
        // finds is the one inside the CHECKOUT NAME — so \1 captures the wrong segment and the
        // sibling-isolation lookahead spares nothing. The layer half fails the same way and worse: the same
        // `deny test -> render` fixture reports violations="1" run from inside the fixture dir and
        // violations="0" run from the repo root, because `/test/` then appears in the absolute path of the
        // RENDER file too and first-match-wins puts both files in one layer. A CI gate that reports zero
        // because of where the tree was cloned is the failure this closes; test/archcheck.sh's header used to
        // document cd-ing into the fixture as the workaround.
        //
        // relForHash is the SAME normalization the baseline hash has used since it was made portable across
        // root spellings — which is what left the verb half-normalized: a violation's IDENTITY was already
        // root-spelling-independent while the RULE that produced it was not. Anchoring instead (`^src/`) was
        // rejected: it makes the rule author responsible for the depth of a directory they cannot know, and
        // every rule in the docs and fixtures is already written repo-relative, so relative matching is what
        // the grammar has always meant. Documenting it was rejected for the same reason a CI gate exists.
        // Purely lexical (no realpath), so a symlinked or `..`-bearing root stays deterministic; a path that
        // is not under the root degrades to itself, leading-`./`-normalized — the same degrade the baseline
        // hash takes, and the only shape a multi-root invocation could reach here.
        std::vector<std::string_view> relFiles( ing.files.size() );
        for( std::size_t f = 0; f < ing.files.size(); ++f )
        {
            relFiles[f] = relForHash( ing.files[f], cfg.rootPath );
        }

        std::vector<int> lof( ing.files.size() );
        for( std::size_t f = 0; f < ing.files.size(); ++f )
        {
            lof[f] = archLayerOf( ar, relFiles[f] );
        }

        // Collect all violations (sorted for determinism). Each violation carries its own from/to layer
        // labels so layer-name rules and ABS-4 regex PATH-rules share one emit/baseline path. A path-rule
        // violation reports fromLayer="path" toLayer="<from-regex>-><to-regex>" (the matched rule).
        struct Viol
        {
            std::uint32_t from, to;
            std::uint64_t hash;          // stable FNV-1a hash of src+dst+label
            std::string   fromLayer;     // layer name of `from` (or "path" for a regex path-rule)
            std::string   toLayer;       // layer name of `to`   (or the path-rule label)
        };
        std::vector<Viol> viols;
        for( std::size_t f = 0; f < adj.size(); ++f )
        {
            for( std::uint32_t g : adj[f] )
            {
                if( g >= lof.size() )
                {
                    continue;
                }

                // layer-name rules (unchanged): both files layered, distinct layers, edge violates.
                const int la = lof[f], lb = lof[g];
                if( la >= 0 && lb >= 0 && lb != la && archViolates( ar, la, lb ) )
                {
                    const std::string label = ar.layerNames[ la ] + "->" + ar.layerNames[ lb ];
                    // S2: hash root-RELATIVE file paths so a committed baseline is portable across root
                    // spellings (`ripwire .` vs `ripwire /abs/repo`). Display still shows ing.files[…] verbatim.
                    // The same relFiles[] the rule was MATCHED against — one normalization, one meaning.
                    const std::uint64_t h   = archViolHash( relFiles[f], relFiles[g], label );
                    viols.push_back( { std::uint32_t( f ), g, h, ar.layerNames[ la ], ar.layerNames[ lb ] } );
                }

                // ABS-4 regex path-rules: sibling-isolation etc. Independent of layers (an edge can be a
                // path-rule violation even when both files are unlayered). A self-edge can't happen (g!=f
                // by resolveIncludeAdj), so no same-module guard needed beyond the rule's own regex.
                std::size_t ruleIdx = 0;
                if( !ar.pathRules.empty() && pathRuleForbids( ar, relFiles[f], relFiles[g], ruleIdx ) )
                {
                    const PathRule&     pr    = ar.pathRules[ ruleIdx ];
                    const std::string   label = std::string( "path:" ) + pr.from + "->" + pr.to;
                    const std::uint64_t h     = archViolHash( relFiles[f], relFiles[g], label );
                    viols.push_back( { std::uint32_t( f ), g, h, std::string( "path" ), pr.from + "->" + pr.to } );
                }
            }
        }
        std::sort( viols.begin(), viols.end(), [ & ]( const Viol& a, const Viol& b ) { // (src path, dst path, fromLayer) — fromLayer breaks a layer-vs-path tie on the same edge
            if( ing.files[a.from] != ing.files[b.from] )
            {
                return ing.files[a.from] < ing.files[b.from];
            }
            if( ing.files[a.to] != ing.files[b.to] )
            {
                return ing.files[a.to] < ing.files[b.to];
            }
            return a.fromLayer < b.fromLayer;
        } );

        const std::string sidecarPath = archBaselinePath( std::string( cfg.archRules ) );

        // ABS-4: per-MODULE Martin metrics (Ca/Ce/I/A/D + zone) + reachability/orphan, computed ONCE from
        // the same file→file graph. Directory-level approximation from name-based edges (see arch.h) — an
        // additive, descriptive block appended inside <arch>; it never changes the exit code (the regex/
        // layer violations above own that). Emitted in every --arch path (baseline / update / normal).
        const std::vector<ModuleMetric> mods = computeModuleMetrics( ing, adj );

        // Q5b: DSM propagation cost — density of the transitive closure of the file→file dep graph
        // (MacCormack). A single SYSTEM-level number on <metrics> (fixed 3dp → byte-identical). Reported,
        // never a gate. Computed + documented in arch.h::dsmPropagationCostCapable. §P9.4: N is restricted
        // to the SAME dependency-capable mask --deps <health> uses, so the two verbs' denominator agrees.
        const auto   depCapable = dependencyCapableMask( ing );
        const double propCost   = rw::dsmPropagationCostCapable( ing, adj, depCapable );

        // ── shared emitters (one definition → the three return paths can't drift) ──────────────────────
        std::vector<char> ae;   // escapeXml scratch (cleared per call); captured by the lambdas below
        const auto emitViol = [ & ]( const Viol& v, bool showBaselined )
        {
            // escapeXml reuses a single buffer (clears on each call), so capture to strings.
            const std::string ef  = std::string( rw::escapeXml( ing.files[ v.from ], ae ) );
            const std::string efl = std::string( rw::escapeXml( v.fromLayer, ae ) );
            const std::string et  = std::string( rw::escapeXml( ing.files[ v.to ], ae ) );
            const std::string etl = std::string( rw::escapeXml( v.toLayer, ae ) );
            std::printf( "<v from=\"%s\" fromLayer=\"%s\" to=\"%s\" toLayer=\"%s\"%s/>",
                         ef.c_str(), efl.c_str(), et.c_str(), etl.c_str(), showBaselined ? " baselined=\"1\"" : "" );
        };
        const auto emitMetrics = [ & ]()
        {
            // zone summary: pure counts over `mods` (already deterministic: sorted by path, computed once
            // above) — a one-line at-a-glance rollup next to the per-module detail. Zone itself is FOLKLORE
            // (Martin main-sequence heuristic, no independent outcome-based validation — see the EVIDENCE
            // NOTE above computeModuleMetrics in arch.h); the summary
            // carries the same "heuristic, not proof" caveat as the rest of the note= text below.
            // §P6.5: zone="n/a" (arch.h: totalTypes==0, cannot carry an abstractness score) is counted
            // separately, never folded into zone_pain/zone_useless — typed_modules is the honest
            // denominator for those two counts (modules= stays the raw total, facts unchanged on <m> rows).
            // §A10.8: zone_ok was computed (arch.h's default zone, "ok" — outside both the pain and
            // useless corners) but never emitted, so the header's own bucket sum fell 13 short of modules=
            // on the real repo with no attribute admitting the gap. zone_pain + zone_useless + zone_ok +
            // zone_na now partitions modules= exactly — every module lands in exactly one bucket.
            std::uint32_t zonePain = 0, zoneUseless = 0, zoneNa = 0, zoneOk = 0;
            for( const ModuleMetric& mm : mods )
            {
                if( mm.zone == std::string_view( "pain" ) )
                {
                    ++zonePain;
                }
                else if( mm.zone == std::string_view( "useless" ) )
                {
                    ++zoneUseless;
                }
                else if( mm.zone == std::string_view( "n/a" ) )
                {
                    ++zoneNa;
                }
                else if( mm.zone == std::string_view( "ok" ) )
                {
                    ++zoneOk;
                }
            }
            std::printf( "<metrics modules=\"%zu\" typed_modules=\"%zu\" zone_pain=\"%u\" zone_useless=\"%u\" zone_ok=\"%u\" zone_na=\"%u\" propagation_cost=\"%.3f\" note=\"Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from name-based deps; zone_na = types=0 modules excluded from zone_pain/zone_useless (no meaningful abstractness score); zone_ok = typed modules in neither corner (the main-sequence middle); zone_pain+zone_useless+zone_ok+zone_na = modules, the full partition; propagation_cost = density of the file-dep transitive closure (MacCormack, validated coupling form) — fraction of files reachable from an average file\">",
                         mods.size(), mods.size() - zoneNa, zonePain, zoneUseless, zoneOk, zoneNa, propCost );
            for( const ModuleMetric& mm : mods )
            {
                const std::string ep = std::string( rw::escapeXml( mm.path, ae ) );
                std::printf( "<m path=\"%s\" ca=\"%u\" ce=\"%u\" types=\"%u\" abstract=\"%u\" I=\"%.2f\" A=\"%.2f\" D=\"%.2f\" zone=\"%s\" reachable=\"%d\"%s%s/>",
                             ep.c_str(), mm.ca, mm.ce, mm.totalTypes, mm.abstractTypes,
                             mm.instability, mm.abstractness, mm.distance, mm.zone, mm.reachable ? 1 : 0,
                             mm.isolated ? " isolated=\"1\"" : "", mm.isLeaf ? " leaf=\"1\"" : "" );
            }
            std::printf( "</metrics>" );
        };

        // The match domain, said ONCE and appended to all three emit paths (normal / baseline /
        // baseline-update). It is a property of the VERB, not of the mode it ran in, and three hand-written
        // copies of one sentence is how two of them end up saying different things.
        static constexpr const char* kArchMatchDomain =
            " Rules — layer substrings and regex path-rules alike — are matched against each file's"
            " ROOT-RELATIVE path (src/core/x.cpp), never the absolute or ./-prefixed spelling shown in from=/to=,"
            " so a rule means the same thing whatever directory the tree was checked out into.";

        // --baseline: write the sidecar with ALL current violations (accept as baseline); exit 0.
        if( cfg.baseline )
        {
            std::unordered_set<std::uint64_t> hashes;
            for( const Viol& v : viols )
            {
                hashes.insert( v.hash );
            }
            if( !archWriteBaseline( sidecarPath, hashes ) )
            {
                std::fprintf( stderr, "ripwire: --baseline cannot write sidecar: %s\n", sidecarPath.c_str() );
                return 1;
            }
            std::fprintf( stderr, "ripwire arch: baseline written (%zu violation(s) accepted) → %s\n",
                          viols.size(), sidecarPath.c_str() );
            // Still emit the arch XML for reference (shows what was baselined), then exit 0.
            std::printf( "<!-- ripwire arch: baseline mode — all %zu violation(s) accepted as baseline. exit=0.%s -->", viols.size(), kArchMatchDomain );
            std::printf( "<arch layers=\"%zu\" rules=\"%zu\" pathRules=\"%zu\" violations=\"%zu\" baselined=\"%zu\" new_violations=\"0\">",
                         ar.layerNames.size(), ar.rules.size(), ar.pathRules.size(), viols.size(), viols.size() );
            for( const Viol& v : viols )
            {
                emitViol( v, true );
            }
            emitMetrics();
            std::printf( "</arch>" );
            return 0;
        }

        // --baseline-update: merge current violations into an existing (or new) sidecar; exit 0.
        if( cfg.baselineUpdate )
        {
            std::unordered_set<std::uint64_t> hashes = archReadBaseline( sidecarPath );
            for( const Viol& v : viols )
            {
                hashes.insert( v.hash );
            }
            if( !archWriteBaseline( sidecarPath, hashes ) )
            {
                std::fprintf( stderr, "ripwire: --baseline-update cannot write sidecar: %s\n", sidecarPath.c_str() );
                return 1;
            }
            std::fprintf( stderr, "ripwire arch: baseline updated (%zu hash(es) total) → %s\n",
                          hashes.size(), sidecarPath.c_str() );
            std::printf( "<!-- ripwire arch: baseline-update mode — %zu violation(s) merged into baseline. exit=0.%s -->", viols.size(), kArchMatchDomain );
            std::printf( "<arch layers=\"%zu\" rules=\"%zu\" pathRules=\"%zu\" violations=\"%zu\" baselined=\"%zu\" new_violations=\"0\">",
                         ar.layerNames.size(), ar.rules.size(), ar.pathRules.size(), viols.size(), hashes.size() );
            for( const Viol& v : viols )
            {
                emitViol( v, true );
            }
            emitMetrics();
            std::printf( "</arch>" );
            return 0;
        }

        // Normal run: load baseline (if present) and split violations into baselined vs new.
        const std::unordered_set<std::uint64_t> baseline    = archReadBaseline( sidecarPath );
        const bool                              hasBaseline  = !baseline.empty() || [ &sidecarPath ]()
        {
            // detect sidecar presence even if it contains only comments (0 hashes)
            std::ifstream probe( sidecarPath );
            return probe.good();
        }();

        std::vector<const Viol*> newViols, basedViols;
        for( const Viol& v : viols )
        {
            if( hasBaseline && baseline.count( v.hash ) )
            {
                basedViols.push_back( &v );
            }
            else
            {
                newViols.push_back( &v );
            }
        }

        // Informational stderr line when baseline is active.
        if( hasBaseline )
        {
            std::fprintf( stderr, "ripwire arch: %zu violation(s) total — %zu suppressed (baseline) — %zu new\n",
                          viols.size(), basedViols.size(), newViols.size() );
        }

        std::printf( "<!-- ripwire arch: layering fitness function — edges that violate your declared rules (layer rules and regex path-rules). exit=2 if any NEW (un-baselined) violation. <metrics> = descriptive Martin Ca/Ce/I/A/D + reachability, never gates.%s -->", kArchMatchDomain );
        std::printf( "<arch layers=\"%zu\" rules=\"%zu\" pathRules=\"%zu\" violations=\"%zu\" baselined=\"%zu\" new_violations=\"%zu\">",
                     ar.layerNames.size(), ar.rules.size(), ar.pathRules.size(), viols.size(), basedViols.size(), newViols.size() );
        for( const Viol& v : viols )
        {
            emitViol( v, hasBaseline && baseline.count( v.hash ) );
        }
        emitMetrics();
        std::printf( "</arch>" );
        return newViols.empty() ? 0 : 2;
    }
    return std::nullopt;
}

// --clones: function/method bodies with identical NORMALIZED token streams (identifiers + literals
// normalized → catches renamed copies). "Reuse, don't reimplement"; "fix one → fix its twins".
// Each group carries type="1|2" (exact/renamed — identical normalized stream) or type="3" (gapped
// near-miss — highly similar stream, an inserted/changed statement; carries similarity=). Type-1/2
// groups are emitted first (biggest-first, unchanged shape); Type-3 pairs follow (findClonesType3).
//
// Its own function (the named-verb-handler shape) rather than a
// fourth arm inside runMaintenanceViews: §P8 gave the row stream a real windowing step, and folding that
// into an already-340-line dispatch body is how a dispatch chain turns back into a god function.

// §A8.1: the root's total= (groups+type3-group-count, the true row total) on the UN-paged path only —
// when paging is active, pageDisclosure's own paging half already carries total=, and a second attribute
// of that name would break XML well-formedness.
std::string cloneUnpagedTotalAttr( bool clonePaging, std::size_t cloneTotal )
{
    if( clonePaging )
    {
        return {};
    }
    char buf[ 32 ];
    std::snprintf( buf, sizeof( buf ), " total=\"%zu\"", cloneTotal );
    return buf;
}

int emitClonesReport( const rw::Config& cfg, const rw::IngestResult& ing )
{
    using namespace rw;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         clnSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  clnRootPrefix = clnSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  clnRootEsc;
    const std::string  clnRootAttr   = clnSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], clnRootEsc ) ) + "\"" ) : std::string();

    const std::vector<CloneGroup> cg  = findClones( ing, 40 );
    const std::vector<CloneGroup> cg3 = findClonesType3( ing, 40 );   // gapped near-misses (excludes exact = Type-1/2)
    const int                     cap = cfg.packTopN > 0 ? cfg.packTopN : 40;

    // §P8: the root said groups="36" type3="108" while 76 <group> rows followed — NEITHER attribute was the
    // row count, because each list is capped independently. The emission order (all Type-1/2 rows, then all
    // Type-3 rows) is one flat, deterministic row stream, so address it with ONE flat index — [0,cg.size())
    // selects a Type-1/2 group, [cg.size(),…) a Type-3 one — and let both the historic per-list cap and
    // --limit/--offset window the same list:
    //   default (no --limit) — the two per-list caps, i.e. the pre-§P8 rows, byte for byte;
    //   --limit/--offset     — a window over the WHOLE stream, so page N+1 continues page N across the
    //                          Type-1/2 → Type-3 seam instead of restarting inside the second list.
    const bool                 clonePaging = cfg.pageLimit > 0 || cfg.pageOffset > 0;
    const std::size_t          keep12      = clonePaging ? cg.size()  : std::min<std::size_t>( std::size_t( cap > 0 ? cap : 0 ), cg.size()  );
    const std::size_t          keep3       = clonePaging ? cg3.size() : std::min<std::size_t>( std::size_t( cap > 0 ? cap : 0 ), cg3.size() );
    std::vector<std::size_t>   rows;
    rows.reserve( keep12 + keep3 );
    for( std::size_t i = 0; i < keep12; ++i )
    {
        rows.push_back( i );
    }
    for( std::size_t i = 0; i < keep3; ++i )
    {
        rows.push_back( cg.size() + i );
    }

    // The denominator is honest either way: every group that EXISTS, not just the kept ones.
    const std::size_t cloneTotal = cg.size() + cg3.size();
    const PageWindow  clonePage  = clonePaging ? pageWindow( rows.size(), cfg.pageLimit, cfg.pageOffset )
                                               : PageWindow{ 0, rows.size() };
    char              cpab[ kPageDisclosureCap ];

    // §P10.5: --clones and --quality-delta share the detector (kMinCloneTokens) but not the POLICY —
    // quality.h exempts fixture paths and shell test-runners from its duplication kind (documented
    // false-positive classes: sibling gate scripts repeat setup boilerplate BY CONVENTION). --clones is a
    // fact verb, so those groups stay VISIBLE — but each one now says the sibling verb would ignore it,
    // via the SAME predicates (quality::isFixturePath / isTestScriptPath — one policy, two verbs, no copy).
    const auto groupExemptKind = [ & ]( const CloneGroup& gp ) -> const char*
    {
        bool allExempt = true, allScript = true;
        for( NodeId id : gp.members )
        {
            const std::string& p        = ing.files[ ing.symbols[id].fileId ];
            const bool         isScript = quality::isTestScriptPath( p );
            if( !isScript && !quality::isFixturePath( p ) )
            {
                allExempt = false;
            }
            if( !isScript )
            {
                allScript = false;
            }
        }
        return allExempt ? ( allScript ? "shell-runner" : "fixture" ) : nullptr;
    };
    std::size_t exemptGroupCount = 0;
    for( const CloneGroup& gp : cg )
    {
        if( groupExemptKind( gp ) )
        {
            ++exemptGroupCount;
        }
    }
    for( const CloneGroup& gp : cg3 )
    {
        if( groupExemptKind( gp ) )
        {
            ++exemptGroupCount;
        }
    }

    // §A8.1: total= (new) is ALWAYS the true row total (groups+type3-group-count), unpaged included — see
    // cloneUnpagedTotalAttr() above for why it is skipped when paging is active (pageDisclosure already
    // owns total= there; two attributes of the same name would break XML well-formedness).
    // P0-6: the pair graph, resolved into components, and the corpus priced in LOC. Computed over the FULL
    // detector output (cg + cg3), never the displayed window — a summary that shrank with --limit would be
    // a paging artefact, not a measurement.
    const CloneGrouping grouping = groupClones( ing, cg, cg3 );

    std::printf( "<!-- ripwire clones: function bodies with similar normalized token streams (identifiers/literals normalized, so renamed copies match). type=2 exact/renamed (Type-1/2); type=3 gapped near-miss (an inserted/changed statement, similarity in [0.80,1.0)). Reuse don't reimplement; a fix to one likely belongs in all. groups= and type3= are the two GROUP-TYPE totals (each capped independently, so neither is the row count); total= is the true row total (groups + type3-group-count) and is ALWAYS present, paged or not; shown= is the number of group rows that follow this run. capped=\"1\" means rows were dropped. exempt= on a group ⇒ every member is on a path the quality-delta verb's duplication kind deliberately ignores (fixture dirs / shell test-runners repeat boilerplate by convention) — a fact here, never a gate there; exempt_groups= counts them over ALL groups. gid= on a row is its CLONE COMPONENT: the Type-3 pass reports PAIRS, so three functions that are all near-copies of each other arrive as three rows of two; rows sharing a gid are one cluster, and clone_groups= counts the clusters (union-find over the pair graph, over ALL detected rows, not just the shown ones). dup_pct=duplicated-LOC/total-LOC as a percentage, where duplicated-LOC sums, per cluster, every member's loc EXCEPT the largest member's (one instance is the code you keep, the rest is the redundancy — so a 3-clone cluster counts its lines TWICE) and total-LOC is every function/method body the detector considered; dup_loc= and total_loc= are those two operands. counts_floor=\"1\": the Type-3 pair list is capped upstream, so a dropped pair is a cluster left unmerged — clone_groups/dup_loc/dup_pct are floors, never totals. raise the default cap with limit=N (offset=M pages). -->%s", rw::rootRelPathsLegend( clnSingleRoot ) );
    std::printf( "<clones groups=\"%zu\" type3=\"%zu\"%s exempt_groups=\"%zu\" clone_groups=\"%u\" dup_loc=\"%llu\" total_loc=\"%llu\" dup_pct=\"%.1f\" counts_floor=\"1\"%s%s>",
                 cg.size(), cg3.size(),
                 cloneUnpagedTotalAttr( clonePaging, cloneTotal ).c_str(), exemptGroupCount,
                 grouping.componentCount,
                 static_cast<unsigned long long>( grouping.duplicatedLoc ), static_cast<unsigned long long>( grouping.totalLoc ),
                 cloneDuplicationPercent( grouping ),
                 pageDisclosure( cpab, sizeof( cpab ), clonePage.end - clonePage.begin, cloneTotal, clonePage.end,
                                 cfg.pageLimit, cfg.pageOffset, true ),
                 clnRootAttr.c_str() );
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    for( std::size_t rowIndex = clonePage.begin; rowIndex < clonePage.end; ++rowIndex )
    {
        const std::size_t flat    = rows[ rowIndex ];
        const bool        isType3 = flat >= cg.size();
        const CloneGroup& gp      = isType3 ? cg3[ flat - cg.size() ] : cg[ flat ];
        const char* exemptKind = groupExemptKind( gp );
        char        exemptAttr[ 40 ] = "";
        if( exemptKind )
        {
            std::snprintf( exemptAttr, sizeof( exemptAttr ), " exempt=\"%s\"", exemptKind );
        }
        const unsigned gid = flat < grouping.gidOfGroup.size() ? grouping.gidOfGroup[ flat ] : 0u;
        if( isType3 )
        {
            std::printf( "<group type=\"3\" gid=\"%u\" tokens=\"%u\" n=\"%zu\" similarity=\"%.2f\"%s>", gid, gp.tokens, gp.members.size(), gp.similarity, exemptAttr );
        }
        else
        {
            std::printf( "<group type=\"%u\" gid=\"%u\" tokens=\"%u\" n=\"%zu\"%s>", gp.type, gid, gp.tokens, gp.members.size(), exemptAttr );
        }
        for( NodeId id : gp.members )
        {
            const Symbol&           s  = ing.symbols[id];
            const std::string_view  rp = clnSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], clnRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            std::printf( "<f n=\"%s\" p=\"%s:%u\"/>", ex( s.name ).c_str(), ex( rp ).c_str(), s.line );
        }
        std::printf( "</group>" );
    }
    std::printf( "</clones>" );
    return 0;
}


// §P11.3: the worst-function lookup for one --hotspots row, isolated so the row-emission loop inside the
// already-oversized runMaintenanceViews dispatcher gains a function CALL, not another decision point.
struct HotspotWorstFn { const char* name; std::uint32_t line; };
inline HotspotWorstFn hotspotWorstFnOf( const rw::IngestResult& ing, rw::NodeId worstSym )
{
    if( worstSym == rw::kNoNode )
    {
        return { "", 0 };
    }
    const rw::Symbol& s = ing.symbols[ worstSym ];
    return { s.name.c_str(), s.line };
}

// §A9.3 — the two --cochange legends, hoisted out of runMaintenanceViews. They state the SAME predicate
// (dependency-capable = both sides could carry a static dependency at all: source languages yes; sh, md,
// json, ruby and binary/unknown files no — §P9.4's, shared with <health dep_files=>), so they belong beside
// each other where a reader can see they agree, not 60 lines apart inside a 180-branch dispatcher.
// §B7.6 (CA4): both forms emit together= and deg= on every row and NEITHER legend defined together=; the
// only deg= gloss lived in the per-file legend and its denominator is WRONG for the pair form — per-file
// deg is n/commits(the probed file), pair deg is n/min(commits(a), commits(b)), so the same attribute name
// carries two different fractions and the repo-wide reader was handed the other form's definition or none.
// Each legend now defines the pair it actually prints, in the words of its own denominator. §B11.5: window=
// is new on this verb — its two churn siblings have always stamped the window they mined and this one, whose
// numbers are ENTIRELY mined from that window, published nothing, so the 18-month default was readable only
// by reading the source.
inline constexpr const char* kCochangeRepoLegend =
    "<!-- ripwire cochange: file pairs that change together in git but share no transitive static dependency (surprising=1) = hidden coupling. "
    "together= is the number of commits in window= that touched BOTH files (3 or more, or the pair is not reported); "
    "deg= is that count over the commit count of the LESS-CHANGED of the two files, so 1.00 means the quieter file never changed without the other. "
    "conf_ab= is that same fraction over a='s OWN commit count and conf_ba= over b='s, which is the asymmetric form: "
    "conf_ab=1.00 means a never changed without b. deg= is by construction the larger of the two, and driver= names which side it came from "
    "(\"a\" or \"b\") — the file whose changes most reliably imply the other's, and therefore the one to look at first. "
    "driver= is OMITTED when the two directions are equal, because a tie is not a finding. "
    "recur= is how many of sub_windows= the pair actually co-changed in: the mined window is cut into that many equal-COMMIT-COUNT slices "
    "(not equal time — a calendar slice can hold 400 commits or 4), so recur=1 at any together= is one burst of activity and not a persistent "
    "coupling, which is the distinction a single window cannot make. sub_windows= is the denominator and is never omitted; it is smaller than "
    "the nominal 3 only when the window holds fewer commits than that. min_recur= appears when cochange-recur=K (the flag) filtered the rows, so a short "
    "list is explained rather than silent. "
    "window= is the mining window: the default 18 months, or the since=REV|DATE value when one resolved. "
    "surprising= is only defined where BOTH sides could carry a static dependency at all (the same "
    "dependency-capable predicate deps <health dep_files=> uses: source languages yes; sh, md, json, "
    "ruby and binary/unknown files no). A pair with a dep-incapable side keeps its row and carries "
    "dep_capable=0 instead, because for it \"shares no static dependency\" is vacuously true. raise the default cap with limit=N (offset=M pages) -->";

inline constexpr const char* kCochangeFileLegend =
    "<!-- ripwire cochange: when you edit this file, git history says you also edit these (surprising=1 => no transitive #include either way). "
    "together= is the number of commits in window= that touched BOTH this file and the partner (3 or more, or the partner is not reported); "
    "deg= is that count over commits=, THIS file's own commit count — a different denominator from the repo-wide pair form, which divides by the less-changed side. "
    "deg= is therefore already DIRECTIONAL here (this file => partner: of your commits, the fraction that also touched the partner); conf_rev= is the other direction, "
    "that same count over the PARTNER's own commit count. deg=1.00 means you never touch this file alone; conf_rev=1.00 means the partner never moves without you. "
    "recur= is how many of sub_windows= equal-COMMIT-COUNT slices of window= the pair actually co-changed in, so recur=1 is one burst rather than a standing coupling; "
    "sub_windows= is that denominator and min_recur= appears when cochange-recur=K (the flag) filtered the list. "
    "window= is the mining window: the default 18 months, or the since=REV|DATE value when one resolved. "
    "surprising= is only defined where BOTH sides could carry a static dependency at all (the dependency-capable "
    "predicate deps <health dep_files=> uses); a pair with a dep-incapable side carries dep_capable=0 instead. raise the default cap with limit=N (offset=M pages) -->";

// §CLIO — --cochange-groups' own legend. Mo/Cai/Kazman's Modularity Violation Group is the minimal set of
// GROUPS covering all violating pairs (f_core, f_j), not a pair list: "X co-changes with {A,B,C}, none of
// which it depends on" is one row that names the file to fix, where three pair rows leave the actionable
// part implicit. The minimal cover is set cover and set cover is NP-hard, so what ships is the greedy
// approximation — and the legend says so rather than letting groups= read as a proven minimum. Honesty
// rule #3: a number that cannot be a minimum must not be spelled like one.
inline constexpr const char* kCochangeGroupLegend =
    "<!-- ripwire cochange groups: the surprising=1 violating pairs, collapsed around the file each group names. "
    "core= is the file to look at; each <f p=> under it is a partner it co-changes with and has no transitive static dependency on, "
    "so one group replaces its partners= pair rows. together=/recur=/conf_core= are that pair's own numbers: together= is the shared commit count, "
    "recur= how many of sub_windows= equal-commit-count slices of window= it recurs in, and conf_core= is conf(core => partner) — of the CORE's commits, "
    "the fraction that also touched this partner. groups= is a GREEDY cover, not a proven minimal one (minimum set cover is NP-hard): it is an upper "
    "bound on the smallest number of groups, and repeatedly picking the file covering the most still-uncovered pairs is what produced it. "
    "pairs_covered= is the total membership count and equals the number of surprising=1 pairs, because every violating pair lands in exactly one group. "
    "min_recur= appears when cochange-recur=K (the flag) filtered the pairs BEFORE they were grouped. "
    "Pairs that are not surprising=1, and pairs with a dep-incapable side (dep_capable=0), are not violations and are absent here — "
    "drop the cochange-groups flag for the full pair list. raise the default cap with limit=N (offset=M pages) -->";

// §CLIO — min_recur= is emitted by all three --cochange exits and was built three times. One builder, so a
// later edit cannot teach one exit a spelling the others do not use (§P9.1's lesson, one attribute over).
// Returns `buf` so it drops straight into a printf argument list; empty string when the filter is off.
inline const char* coMinRecurAttr( char* buf, std::size_t cap, int minRecur )
{
    buf[ 0 ] = '\0';
    if( minRecur > 0 )
    {
        std::snprintf( buf, cap, " min_recur=\"%d\"", minRecur );
    }
    return buf;
}

// §CLIO — one repo-wide co-change pair, and the document that renders them. `PR` used to be a struct local
// to the --cochange branch; it moved out with the loop for the same reason the legends and the group form did.
struct CoPairRow { std::uint32_t a, b, n; double deg, confAb, confBa; std::uint32_t recur; bool surprising; bool depCapable; };

inline void emitCochangePairs( const rw::IngestResult& ing, const rw::Config& cfg, const std::vector<CoPairRow>& prs,
                               const std::string& windowLabel, std::uint32_t subWindows, const char* minRecAttr,
                               int cap, const std::string& root )
{
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( rw::escapeXml( s, esc ) ); };
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         coSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  coRootPrefix = coSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    const std::string  coRootAttr   = coSingleRoot ? ( " root=\"" + ex( cfg.roots[0] ) + "\"" ) : std::string();

    // §P8: this is the verb the audit caught red-handed — pairs="363" with 30 rows, and --limit=3 still
    // emitted all 30, so a paging loop re-read page 0 forever. The window is honest now, and shown= /
    // capped= reconcile pairs= against the rows that follow even with no --limit at all.
    const rw::PageWindow prpw = rw::pageWindow( prs.size(), rw::effectiveRowCap( cfg.pageLimit, cap ), cfg.pageOffset );
    char                 prab[ 192 ];
    std::printf( "%s%s%s", kCochangeRepoLegend, rw::kAtStampLegend, rw::rootRelPathsLegend( coSingleRoot ) );   // sweep: ditto
    std::printf( "<cochange pairs=\"%zu\" window=\"%s\" sub_windows=\"%u\"%s%s%s%s>", prs.size(), windowLabel.c_str(), subWindows, minRecAttr,
                 rw::pageDisclosure( prab, sizeof( prab ), prpw.end - prpw.begin, prs.size(), prpw.end,
                                     cfg.pageLimit, cfg.pageOffset, true ),
                 // R-E fix (2026-08-19): root= sits BEFORE at=, never after. at= stays the LAST attribute on
                 // every git-mined report root — the r26-stamp placement rule --owners' own emitter comment
                 // states and ownerscheck.sh's "at= is still the last attribute" arm is the record of. root=
                 // is a path-interpretation attribute and belongs with the identifying ones, which is also the
                 // slot --grep already puts it in. The first R-E landing appended it and displaced the stamp.
                 coRootAttr.c_str(),
                 rw::gitstamp::atAttr( root ).c_str() );   // §P8: same anchor as the per-file path above
    for( std::size_t pairIndex = prpw.begin; pairIndex < prpw.end; ++pairIndex )
    {
        const CoPairRow& pr = prs[ pairIndex ];
        // §CLIO driver=: the antecedent of the stronger rule. A TIE emits nothing — breaking it by fiat
        // would hand the reader a claim the history does not make.
        const char* driverAttr = ( pr.confAb > pr.confBa ) ? " driver=\"a\""
                               : ( pr.confBa > pr.confAb ) ? " driver=\"b\""
                                                           : "";
        const std::string_view ra = coSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ pr.a ], coRootPrefix ) : std::string_view( ing.files[ pr.a ] );
        const std::string_view rb = coSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ pr.b ], coRootPrefix ) : std::string_view( ing.files[ pr.b ] );
        std::printf( "<pair a=\"%s\" b=\"%s\" together=\"%u\" deg=\"%.2f\" conf_ab=\"%.2f\" conf_ba=\"%.2f\"%s recur=\"%u\"%s/>",
                     ex( ra ).c_str(), ex( rb ).c_str(),
                     pr.n, pr.deg, pr.confAb, pr.confBa, driverAttr, pr.recur,
                     rw::coPairAttr( pr.depCapable, pr.surprising ) );
    }
    std::printf( "</cochange>" );
}

// §CLIO — the --cochange-groups document, hoisted out of runMaintenanceViews for the reason the legends
// above were: a 180-branch dispatcher is not where a rendering loop belongs, and the group form's own
// disclosure rules (cover="greedy", pairs_covered= reconciling with the membership rows, conf_core= fixed
// to the core's direction) are easier to check when they sit together. Pure output: the cover is already
// computed by gitmine.h's cochangeViolationGroups, and `viol` is the vector its members index into.
inline void emitCochangeGroups( const rw::IngestResult& ing, const rw::Config& cfg,
                                const std::vector<rw::CoViolation>& viol, const std::vector<rw::CoGroup>& groups,
                                const std::string& windowLabel, std::uint32_t subWindows, const char* minRecAttr,
                                int cap, const std::string& root )
{
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( rw::escapeXml( s, esc ) ); };
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         cgSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  cgRootPrefix = cgSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    const std::string  cgRootAttr   = cgSingleRoot ? ( " root=\"" + ex( cfg.roots[0] ) + "\"" ) : std::string();

    const rw::PageWindow gpw = rw::pageWindow( groups.size(), rw::effectiveRowCap( cfg.pageLimit, cap ), cfg.pageOffset );
    char                 gab[ 192 ];
    std::size_t          coveredTotal = 0;
    for( const rw::CoGroup& g : groups )
    {
        coveredTotal += g.members.size();
    }
    std::printf( "%s%s%s", kCochangeGroupLegend, rw::kAtStampLegend, rw::rootRelPathsLegend( cgSingleRoot ) );
    std::printf( "<cochange groups=\"%zu\" pairs_covered=\"%zu\" cover=\"greedy\" window=\"%s\" sub_windows=\"%u\"%s%s%s%s>",
                 groups.size(), coveredTotal, windowLabel.c_str(), subWindows, minRecAttr,
                 rw::pageDisclosure( gab, sizeof( gab ), gpw.end - gpw.begin, groups.size(), gpw.end,
                                     cfg.pageLimit, cfg.pageOffset, true ),
                 cgRootAttr.c_str(),                        // R-E fix: root= before at= — at= stays LAST (r26)
                 rw::gitstamp::atAttr( root ).c_str() );
    for( std::size_t gi = gpw.begin; gi < gpw.end; ++gi )
    {
        const rw::CoGroup&     g  = groups[ gi ];
        const std::string_view rc = cgSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ g.core ], cgRootPrefix ) : std::string_view( ing.files[ g.core ] );
        std::printf( "<group core=\"%s\" partners=\"%zu\">", ex( rc ).c_str(), g.members.size() );
        for( std::size_t vi : g.members )
        {
            const rw::CoViolation& v       = viol[ vi ];
            const std::uint32_t    partner = ( v.a == g.core ) ? v.b : v.a;
            // conf_core= is always conf(core => partner): the group's subject IS the core, so the direction is
            // fixed by the row rather than left for the reader to infer from an a/b ordering this form never prints.
            const double            confCore = ( v.a == g.core ) ? v.confA : v.confB;
            const std::string_view  rp       = cgSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ partner ], cgRootPrefix ) : std::string_view( ing.files[ partner ] );
            std::printf( "<f p=\"%s\" together=\"%u\" recur=\"%u\" conf_core=\"%.2f\"/>",
                         ex( rp ).c_str(), v.together, v.recur, confCore );
        }
        std::printf( "</group>" );
    }
    std::printf( "</cochange>" );
}

std::optional<int> runMaintenanceViews( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const std::string&                root         = d.root;
    const bool                        multiRoot    = d.multiRoot;
    const std::vector<WorkspaceRoot>& ws           = d.ws;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — shared
    // across every lens dispatched from this one function (hotspots/cochange/context-ratio/comment-coherence/
    // nonlocal-state/naming-consistency/dead-code all read cfg/ing without their own copy).
    const bool         mvSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  mvRootPrefix = mvSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  mvRootEsc;
    const std::string  mvRootAttr   = mvSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], mvRootEsc ) ) + "\"" ) : std::string();

    // --ensemble: the FAMILY JOIN (src/ensemble.h owns the join AND its emission, the way --readability owns
    // its lens). It calls four existing measurements and reports which of the four EVIDENCE FAMILIES fire on
    // each function, ranked by the count of distinct families — never by a weighted composite, which is the
    // Maintainability-Index failure mode this verb exists to avoid.
    //
    // GIT IS OPTIONAL HERE, and that is the honesty contract: --hotspots exits 1 without git because its whole
    // output IS the churn product, but three of the ensemble's four families need no history at all. So a
    // failed mining pass hands the join a nullptr and the historical family is reported UNAVAILABLE on the
    // root and on every row — never as "did not fire", which would let a missing measurement read as a clean
    // bill of health. --since is deliberately not plumbed in: the window is part of the disclosed threshold
    // set, and one fixed 12-month window (the same one --hotspots defaults to) keeps hrank= comparable.
    if( cfg.ensemble )
    {
        std::vector<std::uint32_t> churn( ing.files.size(), 0 );
        const rw::SinceScope       noScope;
        const bool                 churnOk = mineChurnPerFile( ing, root, multiRoot, ws, std::string_view(), noScope, rw::ensemble::kEnsembleChurnSince, churn );
        return rw::ensemble::writeEnsembleReport( ing, churnOk ? &churn : nullptr, root, cfg.pageLimit, cfg.pageOffset );
    }

    // --context-ratio: the LOCAL-REASONING lens (src/contextratio.h owns the measurement AND its emission, the
    // way --readability and --ensemble own theirs). It reads the symbol table and the REFERENCE table — the
    // same substrate --uses reports — and needs neither the resolved call graph nor git, so it sits with the
    // other pure lenses: exit 0 always, no verdict, no threshold. The reference table only carries value
    // read/write sites when ingest ran RICH, which is why cfg.contextRatio joins needsValueUses below.
    if( cfg.contextRatio )
    {
        return rw::contextratio::writeContextRatioReport( ing, cfg.pageLimit, cfg.pageOffset, mvRootPrefix, mvRootAttr );
    }

    // --hotspots: the maintenance-pain map = per-file (Σ cognitive complexity) × (recent git churn).
    // Complexity alone is a weak prioritizer (most complex code is never touched); churn is the
    // orthogonal axis that says "and it keeps changing" — together they locate where bugs/pain live.
    if( cfg.hotspots )
    {
        // --since=REV|DATE: scope the churn window to "what got risky AFTER this point" (the regression
        // lens) instead of the fixed 12-month default. resolveSinceScope degrades an unresolvable value
        // to inactive (nullptr-equivalent), so gitChurnCounts falls back to its unscoped "12 months ago".
        const rw::SinceScope sinceScope = rw::resolveSinceScope( root, cfg.since );

        // §P0.5c: an unresolvable --since used to degrade to ALL history while stdout still printed
        // window="12mo" — a false NON-zero. The churn numbers are real; the window they are labelled with is
        // not, and the only honest signal was a DEGRADED_PATH_ALERT on stderr, invisible to every MCP client.
        // --hotspots is a measurement verb and its window is part of the measurement, so refuse instead.
        if( !cfg.since.empty() && !sinceScope.active )
        {
            std::fprintf( stderr, "ripwire: --hotspots --since='%.*s' is neither a git revision nor a recognizable date — refusing rather than "
                                  "reporting an all-history scan under a window label you did not ask for "
                                  "(e.g. ripwire <dir> --hotspots --since=\"2 weeks ago\", or --since=HEAD~20)\n",
                          int( cfg.since.size() ), cfg.since.data() );
            return 1;
        }

        std::vector<std::uint32_t> churn( ing.files.size(), 0 );
        const bool churnOk = mineChurnPerFile( ing, root, multiRoot, ws, cfg.since, sinceScope, "12 months ago", churn );
        if( !churnOk )
        {
            // Empty churn has TWO causes: (1) genuine git-unavailable / not-a-repo / no-history-at-all →
            // the error + exit 1 below; (2) git fine and history exists but an ACTIVE --since window
            // matched zero commits → a legitimate empty result, not an error. A windowless HEAD probe
            // tells them apart: history present + active scope ⇒ clean empty (ranked="0", commits="0",
            // exit 0), NOT the "git unavailable" error.
            if( sinceScope.active && gitRepoHasHistory( root ) )
            {
                std::vector<char>  sinceEsc;
                const std::string  windowLabel = std::string( escapeXml( std::string_view( cfg.since ), sinceEsc ) );
                std::printf( "<!-- ripwire hotspots: the since-window matched no commits — empty result, not an error (git history exists) -->" );
                // the same partition the main path emits, so a reader parsing one shape parses both:
                // an empty window means every file is unranked for want of churn.
                std::printf( "<hotspots window=\"%s\" files=\"%zu\" ranked=\"0\" unranked_no_churn=\"%zu\" unranked_no_complexity=\"0\" commits=\"0\" shown=\"0\" capped=\"0\"%s></hotspots>",
                             windowLabel.c_str(), ing.files.size(), ing.files.size(), gitstamp::atAttr( root ).c_str() );
                return 0;
            }
            std::fprintf( stderr, "ripwire --hotspots: git unavailable / no history (need a git repo)\n" );
            return 1;
        }

        // per-file Σ cognitive complexity + the single worst function (for "go look HERE")
        std::vector<std::uint64_t> ccxSum( ing.files.size(), 0 );
        std::vector<std::uint32_t> worstCcx( ing.files.size(), 0 );
        std::vector<NodeId>        worstSym( ing.files.size(), kNoNode );
        for( const Symbol& s : ing.symbols )
        {
            if( s.kind != SymKind::Function && s.kind != SymKind::Method )
            {
                continue;
            }
            ccxSum[ s.fileId ] += s.ccx;
            if( s.ccx > worstCcx[ s.fileId ] ) { worstCcx[ s.fileId ] = s.ccx;  worstSym[ s.fileId ] = s.id; }
        }

        // ── ranked= NEEDS A DENOMINATOR, and the two ways a file misses the ranking are not the same ──────
        // A hotspot needs both factors nonzero, so a file with no churn and a file with no functions are
        // dropped by the same `if` and were then indistinguishable inside one unexplained total: ranked="209"
        // over a corpus of 832 files, with 623 absences the reader could neither see nor account for. Worse,
        // one of those absences is not a fact about the file at all — churn is joined to the index by PATH, so
        // a file the join could not bind scores zero exactly like a genuinely quiet one, and there is no
        // signal anywhere that tells the two apart. Counted here, so the total at least reconciles:
        //   ranked + unranked_no_churn + unranked_no_complexity = files, exactly, on every run.
        // unranked_no_churn is deliberately the WIDER bucket (churn==0 whatever the complexity) because that
        // is the honest cut: it is "no commit in the window was attributed to this path", which covers the
        // quiet file AND the unbound one. Separating those two needs the join to report its own misses, which
        // it does not; the legend says so rather than implying the count is purely about quietness.
        std::vector<std::uint32_t> order;
        std::size_t                unrankedNoChurn = 0, unrankedNoComplexity = 0;
        for( std::uint32_t f = 0; f < ing.files.size(); ++f )
        {
            if( !churn[f] )      { ++unrankedNoChurn;      continue; }
            if( !ccxSum[f] )     { ++unrankedNoComplexity; continue; }
            order.push_back( f );
        }
        VERIFY( order.size() + unrankedNoChurn + unrankedNoComplexity == ing.files.size() );
        const auto score = [ & ]( std::uint32_t f ) { return std::uint64_t( churn[f] ) * ccxSum[f]; };
        std::sort( order.begin(), order.end(), [ & ]( std::uint32_t a, std::uint32_t b )
                   { return score( a ) != score( b ) ? score( a ) > score( b ) : ing.files[a] < ing.files[b]; } );

        const int topN = cfg.packTopN > 0 ? cfg.packTopN : 40;
        // window= reports the effective window: "12mo" (default) unless --since resolved to an active scope,
        // in which case it names the scoping value so the agent can trust what it's looking at. §P9 N7: the
        // header COMMENT used to hardcode "(window=12mo)" even for a valid --since, so the two halves of the
        // same screen disagreed. One label, computed once, used in both.
        std::vector<char> sinceEsc;
        const std::string windowLabel = ( !cfg.since.empty() && sinceScope.active )
                                       ? std::string( escapeXml( std::string_view( cfg.since ), sinceEsc ) )
                                       : "12mo";
        std::string windowLabelInComment = windowLabel;   // "--" is illegal inside an XML comment (G4)
        for( std::size_t i = 1; i < windowLabelInComment.size(); ++i )
        {
            if( windowLabelInComment[i - 1] == '-' && windowLabelInComment[i] == '-' )
            {
                windowLabelInComment[i] = ' ';
            }
        }
        std::printf( "<!-- ripwire hotspots: maintenance-pain = complexity × recent churn (window=%s). "
                     "churn=commits touching the file; ccx=Σ cognitive complexity; score=churn×ccx; top=worst function. "
                     "files= is the DENOMINATOR ranked= is drawn from, and a hotspot needs both factors nonzero, so "
                     "ranked= + unranked_no_churn= + unranked_no_complexity= = files= exactly. "
                     "unranked_no_complexity= is a file with commits but no function or method to score (a pure "
                     "declaration header, markdown, config). unranked_no_churn= is a file no in-window commit was "
                     "attributed to — and it CONFLATES two cases this verb cannot tell apart: a genuinely quiet file, "
                     "and one whose path the git-to-index join never bound (a rename, an exclusion, or a spelling the "
                     "join could not match), which scores zero for a reason that is not about the file. Treat it as an "
                     "upper bound on quietness, not a measure of it. "
                     "raise the default cap with limit=N (offset=M pages) -->%s%s",
                     windowLabelInComment.c_str(), rw::kAtStampLegend, rw::rootRelPathsLegend( mvSingleRoot ) );   // sweep: at= was undefined on this screen
        if( multiRoot )
        { // §5 comparability caveat: churn scales (commit-count conventions) differ per repo
            std::printf( "<!-- multi-root workspace: churn is mined PER root — hotspot scores are comparable within a root, not across roots -->" );
        }
        // T2: --limit/--offset paginate the sorted `order`. When no --limit, the historic topN cap (40 or
        // --pack-top-n) still bounds the response; --limit overrides it. ranked= is the TRUE total either way.
        // §P8: ranked="185" over 40 emitted rows was a SILENT cap — shown=/capped= now reconcile the two on
        // every run, paginated or not (the one deliberate break in this verb's pre-§P8 byte shape).
        const int         effLimit = effectiveRowCap( cfg.pageLimit, topN );
        const PageWindow  pw       = pageWindow( order.size(), effLimit, cfg.pageOffset );
        char              pab[ 192 ];
        // r26-stamp Task A: anchor churn×complexity scores to the commit (+dirty state) they were mined
        // against — multi-root anchors to the PRIMARY root (d.root); the merged ranking has no per-root
        // sub-scoping to hang a second stamp on, unlike --pr-context's per-root sections.
        std::printf( "<hotspots window=\"%s\" files=\"%zu\" ranked=\"%zu\" unranked_no_churn=\"%zu\" unranked_no_complexity=\"%zu\"%s%s%s>",
                     windowLabel.c_str(), ing.files.size(), order.size(), unrankedNoChurn, unrankedNoComplexity,
                     pageDisclosure( pab, sizeof( pab ), pw.end - pw.begin, order.size(), pw.end,
                                     cfg.pageLimit, cfg.pageOffset, true ),
                     mvRootAttr.c_str(),                    // R-E fix: root= before at= — at= stays LAST (r26)
                     gitstamp::atAttr( root ).c_str() );
        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        for( std::size_t i = pw.begin; i < pw.end; ++i )
        {
            const std::uint32_t   f  = order[i];
            // §P11.3: top="main:322" used to read as a file:line pair (every other name:N in the tool means
            // line) but the trailing number was actually the worst function's cognitive complexity — an
            // agent trying to --expand it landed on a bogus line. Split into top= (bare name), top_ccx=
            // (the complexity score, same digits that used to trail the colon) and top_l= (the function's
            // real 1-based source line) so the --expand hop is buildable straight from this row.
            const HotspotWorstFn    worst = hotspotWorstFnOf( ing, worstSym[f] );
            const std::string_view  rp    = mvSingleRoot ? rw::sarif::rootRelativeUri( ing.files[f], mvRootPrefix ) : std::string_view( ing.files[f] );
            std::printf( "<f p=\"%s\" churn=\"%u\" ccx=\"%llu\" score=\"%llu\" top=\"%s\" top_ccx=\"%u\" top_l=\"%u\"/>",
                         ex( rp ).c_str(), churn[f], (unsigned long long)ccxSum[f],
                         (unsigned long long)score( f ), ex( worst.name ).c_str(), worstCcx[f], worst.line );
        }
        std::printf( "</hotspots>" );
        return 0;
    }

    if( cfg.clones )
    {
        return emitClonesReport( cfg, ing ); // body + §P8 paging: emitClonesReport() above
    }

    // --cochange[=FILE]: files that change together in git history but may share NO static dependency —
    // the hidden coupling a call graph can't see (the lockstep partner you'd forget to update). With a
    // FILE: its partners ("when you edit FILE, you historically also edit these"). Without: top surprising
    // pairs repo-wide (high co-change + no #include either way).
    if( cfg.cochange )
    {
        const int         cap = cfg.packTopN > 0 ? cfg.packTopN : 30;
        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

        // --since=REV|DATE: scope co-change mining to recent coupling instead of the fixed 18-month
        // default. An unresolvable value degrades to inactive → both branches below fall back unchanged.
        const rw::SinceScope sinceScope   = rw::resolveSinceScope( root, cfg.since );
        const rw::SinceScope* sinceScopeP = cfg.since.empty() ? nullptr : &sinceScope;

        // §B11.5: the effective window label, computed ONCE for all three exits below (per-file, empty,
        // repo-wide) — --hotspots' own rule verbatim: name the --since value when it resolved, else the
        // verb's default. Escaped because it is a user-supplied string reaching an attribute value.
        std::vector<char> coSinceEsc;
        const std::string coWindowLabel = ( !cfg.since.empty() && sinceScope.active )
                                         ? std::string( escapeXml( std::string_view( cfg.since ), coSinceEsc ) )
                                         : "18mo";

        if( !cfg.cochangeFile.empty() )                                    // partners of one file → shared core (gitmine.h)
        {
            const std::uint32_t fid = resolveFileSuffix( ing, cfg.cochangeFile );
            if( fid == UINT32_MAX ) { std::fprintf( stderr, "ripwire --cochange: file not found: %.*s\n", int( cfg.cochangeFile.size() ), cfg.cochangeFile.data() ); return 1; }
            // multi-root §5: the probed file belongs to exactly ONE root — mine that repo only (co-change is
            // per-repo by construction; partners in another root are undefined and never synthesized).
            const std::uint32_t fidRoot  = multiRoot ? ing.fileRoot[ fid ] : UINT32_MAX;
            const std::string&  fidRepo  = multiRoot ? ws[ fidRoot ].arg : root;
            const rw::SinceScope fidScope = multiRoot ? rw::resolveSinceScope( fidRepo, cfg.since ) : sinceScope;
            std::uint32_t                commits    = 0;
            std::uint32_t                subWindows = 0;
            std::vector<CoPartner>       ps         = cochangePartners( fidRepo, ing, cfg.cochangeFile, commits,
                                                                        cfg.since.empty() ? nullptr : &fidScope, fidRoot, &subWindows );
            // §CLIO: --cochange-recur=K drops the partners whose co-change does not RECUR across the mined
            // window's sub-windows. Applied BEFORE partners= is counted, so partners= keeps meaning "the rows
            // this run is reporting" and reconciles with shown=/capped= exactly as it always has; the reason
            // the number shrank is published as min_recur= on the element rather than left to be inferred.
            if( cfg.cochangeRecur > 0 )
            {
                const std::uint32_t minRecur = std::uint32_t( cfg.cochangeRecur );
                ps.erase( std::remove_if( ps.begin(), ps.end(), [ & ]( const CoPartner& p ) { return p.recur < minRecur; } ), ps.end() );
            }
            // §P8: partners= is the true total; shown=/capped= say how many of them actually follow, and
            // --limit/--offset window the (already deterministically sorted) partner list.
            const PageWindow  ppw = pageWindow( ps.size(), effectiveRowCap( cfg.pageLimit, cap ), cfg.pageOffset );
            char              pab[ 192 ];
            char              pminrec[ 40 ];
            coMinRecurAttr( pminrec, sizeof( pminrec ), cfg.cochangeRecur );
            std::printf( "%s%s%s", kCochangeFileLegend, rw::kAtStampLegend, rw::rootRelPathsLegend( mvSingleRoot ) );   // sweep: at= was undefined on this screen
            // §P8 vocabulary: at="<sha>[+dirty]" — cochange is a PURE git-history product (every number in
            // it is mined from `git log`), and it was one of the last two verbs of that kind emitting numbers
            // with no anchor to the HEAD that produced them. Same gitstamp::atAttr every other repo-reading
            // verb already calls, placed LAST on the element to match --hotspots' existing attribute order.
            std::printf( "<cochange of=\"%s\" commits=\"%u\" window=\"%s\" sub_windows=\"%u\"%s partners=\"%zu\"%s%s%s>",
                         ex( mvSingleRoot ? rw::sarif::rootRelativeUri( ing.files[fid], mvRootPrefix ) : std::string_view( ing.files[fid] ) ).c_str(),
                         commits, coWindowLabel.c_str(), subWindows, pminrec, ps.size(),
                         pageDisclosure( pab, sizeof( pab ), ppw.end - ppw.begin, ps.size(), ppw.end,
                                         cfg.pageLimit, cfg.pageOffset, true ),
                         mvRootAttr.c_str(),                // R-E fix: root= before at= — at= stays LAST (r26)
                         gitstamp::atAttr( root ).c_str() );
            for( std::size_t partnerIndex = ppw.begin; partnerIndex < ppw.end; ++partnerIndex )
            {
                const std::string_view rp = mvSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ ps[ partnerIndex ].fileId ], mvRootPrefix )
                                                          : std::string_view( ing.files[ ps[ partnerIndex ].fileId ] );
                std::printf( "<f p=\"%s\" together=\"%u\" deg=\"%.2f\" conf_rev=\"%.2f\" recur=\"%u\"%s/>",
                             ex( rp ).c_str(), ps[ partnerIndex ].together,
                             ps[ partnerIndex ].deg, ps[ partnerIndex ].degRev, ps[ partnerIndex ].recur,
                             coPairAttr( ps[ partnerIndex ] ) );
            }
            std::printf( "</cochange>" );
            return 0;
        }

        // repo-wide: ALL co-change pairs (needs the full pair map, unlike the single-file core above).
        // Multi-root §5: mined per root (each against its own files); the merged set list is safe because
        // commits are disjoint across repos — a pair can only ever form WITHIN one root's sets.
        std::vector<std::vector<std::uint32_t>> sets;
        if( multiRoot )
        {
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                const rw::SinceScope rs = rw::resolveSinceScope( ws[r].arg, cfg.since );
                std::vector<std::vector<std::uint32_t>> part = gitCommitFileSets( ws[r].arg, ing, "18 months ago", 30,
                                                                                  cfg.since.empty() ? nullptr : &rs, r );
                for( std::vector<std::uint32_t>& cs : part )
                {
                    sets.push_back( std::move( cs ) );
                }
            }
        }
        else
        {
            sets = gitCommitFileSets( root, ing, "18 months ago", 30, sinceScopeP );
        }
        if( sets.empty() )
        {
            // Same two-cause split as --hotspots: an ACTIVE --since window that matched zero commits is a
            // legitimate empty result (git history exists), not the git-unavailable error. The windowless
            // HEAD probe distinguishes them → clean empty (pairs="0", commits="0", exit 0) vs error+exit 1.
            if( sinceScope.active && gitRepoHasHistory( root ) )
            {
                std::printf( "<!-- ripwire cochange: the since-window matched no commits — empty result, not an error (git history exists) -->" );
                // The at= stamp belongs on the EMPTY result too — "no pairs at this HEAD" is itself a claim
                // about a specific HEAD, and --hotspots' own zero-row path already stamps for that reason.
                // sub_windows="0" is the literal truth on this path: no commit was mined, so no partition was
                // made. Emitting the nominal 3 here would name a denominator that never existed.
                std::printf( "<cochange pairs=\"0\" commits=\"0\" window=\"%s\" sub_windows=\"0\" shown=\"0\" capped=\"0\"%s></cochange>", coWindowLabel.c_str(), gitstamp::atAttr( root ).c_str() );
                return 0;
            }
            std::fprintf( stderr, "ripwire --cochange: git unavailable / no history (need a git repo)\n" );
            return 1;
        }
        // §CLIO: one cell per pair carrying BOTH the support count and the sub-window bitmask, rather than a
        // second parallel map — the inner loop below is O(files-per-commit^2) under the 30-file bulk cap, so
        // one hash probe per pair per commit instead of two is the difference that stays inside the warm
        // latency budget on a big history.
        struct CoCell { std::uint32_t n = 0; std::uint32_t subWindowMask = 0; };
        const std::uint32_t                    subWindows = coEffectiveSubWindows( sets.size() );
        std::vector<std::uint32_t>             freq( ing.files.size(), 0 );
        HashMap<std::uint64_t, CoCell>         pair;                       // (lo<<32|hi) → co-change count + recurrence mask
        for( std::size_t commitIndex = 0; commitIndex < sets.size(); ++commitIndex )
        {
            const std::vector<std::uint32_t>& cs  = sets[ commitIndex ];
            const std::uint32_t               bit = std::uint32_t( 1u ) << coSubWindowOf( commitIndex, sets.size(), subWindows );
            for( std::uint32_t f : cs )
            {
                ++freq[f];
            }
            for( std::size_t i = 0; i < cs.size(); ++i )
            {
                for( std::size_t j = i + 1; j < cs.size(); ++j )
                { // cs is sorted+unique → cs[i] < cs[j]
                    CoCell& cell = pair[ ( std::uint64_t( cs[i] ) << 32 ) | cs[j] ];
                    ++cell.n;
                    cell.subWindowMask |= bit;
                }
            }
        }
        // P9.1: the repo-wide pair scan must use the SAME predicate as the per-file path (gitmine.h's
        // StaticIncludeCoupling) — a bare 1-hop check here previously mis-flagged transitively-coupled
        // pairs (ingest.cpp↔model.h, main.cpp↔notes.h) as "surprising" hidden coupling.
        const StaticIncludeCoupling coupling( ing );
        const auto staticDep = [ & ]( std::uint32_t a, std::uint32_t b ) -> bool { return coupling.isStaticallyCoupled( a, b ); };
        constexpr std::uint32_t kSupport = 3;                              // need ≥3 shared commits (kill coincidence)

        // repo-wide: the surprising couplings (high co-change, no static dep) — hidden architectural debt
        std::vector<CoPairRow>      prs;   // CoPairRow + its emitter are hoisted above — see emitCochangePairs
        const std::uint32_t         minRecur = cfg.cochangeRecur > 0 ? std::uint32_t( cfg.cochangeRecur ) : 0u;
        for( const auto& [k, cell] : pair )
        {
            if( cell.n < kSupport )
            {
                continue;
            }
            const std::uint32_t recur = coRecurrenceOf( cell.subWindowMask );
            if( recur < minRecur )
            {
                continue;   // §CLIO: filtered here so pairs= counts what is reported, and min_recur= on the element says why
            }
            const std::uint32_t a = std::uint32_t( k >> 32 ), b = std::uint32_t( k );
            const std::uint32_t mn = std::min( freq[a], freq[b] );
            // §CLIO directional confidence: conf(a=>b) over a's OWN commit count, conf(b=>a) over b's. deg=
            // divides by the SMALLER count, so it is by construction max(confAb, confBa) — the same magnitude
            // it has always been, now with the direction it came from recoverable.
            const bool isDepCapable = coPairDependencyCapable( ing, a, b );   // §A9.3, the same predicate the per-file path uses
            prs.push_back( { a, b, cell.n, mn ? double( cell.n ) / mn : 0.0,
                             coConfidence( cell.n, freq[a] ), coConfidence( cell.n, freq[b] ), recur,
                             isDepCapable && !staticDep( a, b ), isDepCapable } );
        }
        std::sort( prs.begin(), prs.end(), [ & ]( const CoPairRow& x, const CoPairRow& y ) { // surprising-and-strong first
            if( x.surprising != y.surprising )
            {
                return x.surprising;
            }
            if( x.deg != y.deg )
            {
                return x.deg > y.deg;
            }
            return x.n > y.n;
        } );
        char coMinRec[ 40 ];
        coMinRecurAttr( coMinRec, sizeof( coMinRec ), cfg.cochangeRecur );   // shared with the per-file exit above

        // --cochange-groups: the Modularity Violation GROUP form. The cover itself is gitmine.h's
        // cochangeViolationGroups (domain logic, and the place its determinism argument belongs); this
        // branch selects the violating pairs, hands them over, and renders the result.
        if( cfg.cochangeGroups )
        {
            std::vector<CoViolation> viol;
            for( const CoPairRow& p : prs )
            {
                if( p.surprising )
                {
                    viol.push_back( { p.a, p.b, p.n, p.recur, p.confAb, p.confBa } );
                }
            }
            const std::vector<CoGroup> groups = cochangeViolationGroups( viol, ing.files.size() );
            emitCochangeGroups( ing, cfg, viol, groups, coWindowLabel, subWindows, coMinRec, cap, root );
            return 0;
        }

        emitCochangePairs( ing, cfg, prs, coWindowLabel, subWindows, coMinRec, cap, root );
        return 0;
    }

    // --owners[=SYM]: S5-C bus-factor analysis — recency-weighted author ownership per file.
    // Each commit is weighted by exp(-λ·age) with a 6-month half-life so recent work counts more.
    // Output: per-file top author + weighted share + unique-author count + bus-factor flag (bf=1 when
    // top author holds >80% of weighted commits).  With =SYM: restrict to the file that defines SYM.
    // Deterministic: files sorted by path, authors within a file by (score desc, email asc).
    if( cfg.owners )
    {
        // Resolve an optional symbol name to its file id (--owners=SYM mode)
        std::uint32_t onlyFileId    = UINT32_MAX;
        std::size_t   symDefCount   = 0;              // §B11.3-class: how many definitions the fold below discarded
        if( !cfg.ownersSym.empty() )
        {
            // §B11.1 — this arm resolved with the BARE-NAME resolver and refused in the pre-§B4.2 dialect, so
            // a `file:name` spelling — the grammar its nine SYM-taking siblings accept, and what an agent
            // pastes out of a p="file:line" row — was rejected outright with four words about a symbol that
            // plainly exists. Both halves join the family: resolveAllByNameQualified (bare names resolve
            // byte-identically; splitQualifiedSpec leaves a spec with no ':' alone) and the shared
            // selectorNotFoundMessage, which says whether the PATH half or the NAME half is the fault.
            const std::vector<NodeId> defs = resolveAllByNameQualified( ing, cfg.ownersSym );
            if( defs.empty() )
            {
                std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --owners symbol not found: ",
                                                                       cfg.ownersSym, "--owners=" ).c_str() );
                return 1;
            }
            // §B11.3's SHAPE, found by that item's sweep and closed here: this is a fold that reports a scalar.
            // `defs[0]` is ONE of N definitions of the name — the lowest node id — and the report then covers
            // that definition's file alone under files="1", which reads as "this symbol lives in one file"
            // while --callers/--uses/--impact/--mentions on the same name all disclose defs="3". The pick is a
            // reasonable default (it matches --around/--lego's resolveFocus), but it was invisible.
            onlyFileId  = ing.symbols[ defs[0] ].fileId;
            symDefCount = defs.size();
        }

        // multi-root §5: ownership mined per root against its own files; the concatenation stays fileId-sorted
        // because canonical merge order makes every root-r fileId smaller than every root-(r+1) fileId.
        std::vector<FileOwnership> ownerships;
        if( multiRoot )
        {
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                if( onlyFileId != UINT32_MAX && ing.fileRoot[onlyFileId] != r )
                {
                    continue; // --owners=SYM: its one root
                }
                std::vector<FileOwnership> part = gitFileAuthors( ws[r].arg, ing, onlyFileId, 182.5, r );
                for( FileOwnership& ow : part )
                {
                    ownerships.push_back( std::move( ow ) );
                }
            }
        }
        else
        {
            ownerships = gitFileAuthors( root, ing, onlyFileId );
        }
        if( ownerships.empty() )
        {
            std::fprintf( stderr, "ripwire --owners: git unavailable / no history (need a git repo with commits)\n" );
            return 1;
        }

        // Output: terse XML consistent with the rest of the report verbs. §P6.4: authors=1 files (determin-
        // istically bf=1 share=1.00 — see countUniformOwnership() above) fold into ONE <uniform files="M"/>
        // row instead of M identical <f/> rows; --detail=N restores the full listing (ownershipRowsToPrint()).
        // <owners files="N"><uniform .../><f p="<path>" authors="N" bf="0|1" top="<email>" share="0.NN"/></owners>
        const int                      cap           = cfg.packTopN > 0 ? cfg.packTopN : int( ownerships.size() );
        const bool                     detail        = cfg.detail > 0;
        const std::size_t              uniformCount  = countUniformOwnership( ownerships, cap );
        const std::vector<std::size_t> printRows     = ownershipRowsToPrint( ownerships, cap, detail );

        // XML comments forbid a literal "--" (G4): the flag is spelled "detail=1" below, not "--detail=1".
        std::printf( "<!-- ripwire owners: recency-weighted author ownership (half-life=6mo). "
                     "bf=1 = one person holds >80%% of weighted commits (bus-factor risk); "
                     "authors=1 files fold into <uniform/> below; pass detail=1 for the full per-file listing. "
                     "files= means two different things by DEPTH here and is deliberately not renamed: on the ROOT it is how "
                     "many files were ANALYSED; on the <uniform/> fold it is how many of them collapsed into that one row. "
                     "With a SYM, of= echoes it and defs= is how many DEFINITIONS that name has: this report covers the file "
                     "holding the FIRST of them (lowest node id, the same pick around and lego make), so defs= above 1 means "
                     "the other definitions' files were NOT analysed. Qualify with file:name to choose one -->%s%s",
                     rw::kAtStampLegend, rw::rootRelPathsLegend( mvSingleRoot ) );   // sweep: ditto
        // §P8: --limit/--offset used to be accepted and ignored here (757 rows whatever you asked for). They
        // window `printRows`, which is already deterministic (files sorted by path). files= keeps meaning the
        // number of files ANALYSED — a different quantity from the <f/> row count, which is why the paging
        // half carries its own total= (the row denominator) rather than reusing files=. The <uniform/> fold
        // is a summary of the whole run, not a row, so it is emitted on every page.
        const PageWindow  owpw = pageWindow( printRows.size(), effectiveRowCap( cfg.pageLimit, int( printRows.size() ) ), cfg.pageOffset );
        char              owab[ 192 ];
        // §P8 vocabulary: at="<sha>[+dirty]" — like --cochange above, ownership is mined entirely from git
        // history (recency-weighted commit shares), so every share= here is a claim about ONE HEAD. It was
        // the second and last unanchored pure-git verb.
        // the SYM-mode fold disclosure sits between the paging block and at=, so at= stays last (the r26-stamp
        // placement rule) and no existing `files="N"`-adjacency assertion moves on the all-files form.
        std::vector<char> owSymEsc;
        const std::string owSymAttr = cfg.ownersSym.empty()
                                    ? std::string{}
                                    : " of=\"" + std::string( escapeXml( cfg.ownersSym, owSymEsc ) ) + "\" defs=\"" + std::to_string( symDefCount ) + "\"";
        std::printf( "<owners files=\"%zu\"%s%s%s%s>", ownerships.size(),
                     pageDisclosure( owab, sizeof( owab ), owpw.end - owpw.begin, printRows.size(), owpw.end,
                                     cfg.pageLimit, cfg.pageOffset, false ),
                     owSymAttr.c_str(),
                     mvRootAttr.c_str(),                    // R-E fix: root= before at= — at= stays LAST (r26)
                     gitstamp::atAttr( root ).c_str() );
        if( !detail && uniformCount > 0 )
        {
            std::printf( "<uniform authors=\"1\" bf=\"1\" share=\"1.00\" files=\"%zu\"/>", uniformCount );
        }
        std::vector<char> owEsc;
        for( std::size_t rowIndex = owpw.begin; rowIndex < owpw.end; ++rowIndex )
        {
            const std::size_t    i   = printRows[ rowIndex ];
            const FileOwnership& ow  = ownerships[i];
            const AuthorScore&   top = ow.authors[0];
            // path and email are externally-controlled strings — escape both to keep output valid XML.
            const std::string_view rp = mvSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ ow.fileId ], mvRootPrefix ) : std::string_view( ing.files[ ow.fileId ] );
            const auto ep = rw::escapeXml( rp, owEsc );
            std::printf( "<f p=\"%.*s\" authors=\"%u\" bf=\"%d\"",
                         int( ep.size() ), ep.data(), ow.uniqueAuthors, int( ow.busFactor ) );
            const auto em = rw::escapeXml( top.email, owEsc );
            std::printf( " top=\"%.*s\" share=\"%.2f\"/>", int( em.size() ), em.data(), top.share );
        }
        std::printf( "</owners>" );
        return 0;
    }
    return std::nullopt;
}


std::optional<int> runEvalViews( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::string&                root         = d.root;

    // --eval: deterministic self-eval (co-change recovery vs a BM25 baseline) — does the structural
    // ranking surface the rest of a change's files better than lexical? Needs a git repo with changes.
    if( cfg.eval )
    {
        std::vector<char> changed( ing.files.size(), 0 );
        gitChangedFiles( root, ing, changed );          // current diff = the n=1 fallback; history is primary
        return runEval( root, ing, g, changed );
    }

    // --eval-retrieval: KNOWN-ITEM retrieval eval — validates query-TIME ranker choice (name-exact / routing /
    // anchoring) that the seed-based --eval structurally cannot measure. No git history needed (the gold item
    // is in the corpus by construction), so it runs on any parsed tree. Deterministic.
    if( cfg.evalRetrieval )
    {
        return runEvalRetrieval( ing, g );
    }

    // --eval-mined=FILE: session-trace-mined retrieval eval — consumes a
    // bench/mine_traces.py minedpair.jsonl artifact, file-level gold, reuses recallAtK/rankFiles.
    if( !cfg.evalMined.empty() )
    {
        return runEvalMined( root, ing, g, std::string( cfg.evalMined ) );
    }

    // --eval-skills=FILE: labelled skill-ROUTING eval — ROOT is the skills
    // directory; FILE is the prompt→permitted-skill(s) corpus. Runs the shipping --for computation over
    // the skills ingest as one arm, so it dispatches here where ing+g are already built. Deterministic.
    if( !cfg.evalSkills.empty() )
    {
        return runEvalSkills( root, ing, g, std::string( cfg.evalSkills ) );
    }
    return std::nullopt;
}


// §P9 N5 / §B7.3: --affected walks the CALL graph to find tests that reach a change; test/*.sh gates that
// invoke the compiled BINARY as a subprocess are invisible to that walk. The counter used to live here, one
// verb wide; --test-gate and --situ inherit the SAME blindness from the SAME traversal and had no such
// tell, so it moved down to testmap.h (rw::scriptGatesUnmodelledCount) where all three read one number.
using rw::scriptGatesUnmodelledCount;

// §A9.1 — the INVERSE blindness, disclosed on the inverse verb. --affected discloses the script gates its
// call-graph walk cannot see (script_gates_unmodelled= above); --exercises walks the SAME edges in the
// other direction and had no such tell, so on a corpus whose gates are all shell scripts its modal answer
// was a bare `reaches="0"` — indistinguishable from "this test covers nothing". A shell harness invokes the
// compiled binary as a SUBPROCESS; there is no call edge from the script to the code it exercises, so the
// zero is a limit of the model, not a measurement of the test.
//
// Returns the harness class of the matched SEED files: "script" (every seed is a shell script — the whole
// answer comes from subprocess harnesses), "mixed" (some are), or nullptr (none — a .cpp/.py harness, whose
// calls ARE modelled, so the count needs no caveat and that output stays byte-identical).
inline const char* exercisesHarnessKind( const rw::IngestResult& ing, const std::vector<std::uint32_t>& seedFiles )
{
    std::size_t scriptSeedCount = 0;
    for( const std::uint32_t f : seedFiles )
    {
        const std::string& fp = ing.files[f];
        if( fp.size() >= 3 && fp.compare( fp.size() - 3, 3, ".sh" ) == 0 )
        {
            ++scriptSeedCount;
        }
    }
    if( scriptSeedCount == 0 )
    {
        return nullptr;
    }
    return scriptSeedCount == seedFiles.size() ? "script" : "mixed";
}

// The disclosure itself: ` harness="script|mixed" note="…"`, or "" when every seed's calls ARE modelled —
// so a .cpp/.py harness's output keeps the pre-§A9 bytes exactly.
inline std::string exercisesHarnessAttr( const rw::IngestResult& ing, const std::vector<std::uint32_t>& seedFiles )
{
    const char* kind = exercisesHarnessKind( ing, seedFiles );
    if( kind == nullptr )
    {
        return {};
    }
    return std::string( " harness=\"" ) + kind + "\" note=\"a shell gate invokes the compiled binary as a subprocess; "
           "script-to-binary edges are not modelled, so reaches= counts call-graph reach only and cannot see what the "
           "subprocess covers\"";
}

std::optional<int> runAffected( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;

    // --affected=F1,F2,... / --affected=SYM: test files that transitively reach the changed files OR the
    // changed SYMBOL (impact analysis for review, and — §P11.2a — for change PLANNING).
    if( !cfg.affectedFiles.empty() )
    {
        // §P11.2a: the map was file-granular, so "which tests cover the function I am about to change?" had
        // to be widened to its whole FILE first, over-reporting the obligation. Only the SEED SET changes
        // here: everything below (transitiveCallers → isTestPath → path-sorted rows) is the same traversal
        // --affected always ran. The file-first argument rule and its per-item refusal live in
        // testmap.h::resolveAffectedSeeds; only the did-you-mean wording is main's (withDidYouMean is).
        const rw::AffectedSeeds sel = rw::resolveAffectedSeeds( ing, cfg.affectedFiles );
        if( !sel.ok )
        {
            // §M7 (W3FIX): resolveAffectedSeeds accepts file:name and path::scope::name too, so a bad item gets
            // the shared file-half diagnosis appended to this arm's own two-reading sentence (which explains
            // WHY the item was tried twice, and therefore has to come first).
            std::fprintf( stderr, "ripwire: --affected: '%s' matches no indexed file path (as a path pattern) and no indexed "
                                  "symbol (as a symbol name; file:name and path::scope::name also accepted)%s\n",
                          sel.badItem.c_str(), rw::selectorFaultClause( ing, sel.badItem, "--affected=" ).c_str() );
            return 1;
        }
        const std::vector<NodeId>& seeds = sel.seeds;
        if( seeds.empty() ) { std::fprintf( stderr, "ripwire: --affected matched no symbols: %.*s\n", int( cfg.affectedFiles.size() ), cfg.affectedFiles.data() ); return 1; }
        const std::vector<NodeId>  reach = rw::transitiveCallers( g, seeds );
        std::vector<char>          fseen( ing.files.size(), 0 );
        std::vector<std::uint32_t> testFiles;
        for( NodeId n : reach ) { const std::uint32_t f = ing.symbols[n].fileId; if( !fseen[f] && rw::isTestPath( ing.files[f] ) ) { fseen[f] = 1; testFiles.push_back( f ); } }
        std::sort( testFiles.begin(), testFiles.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );
        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // seeded_by= is the honesty half of the file-first rule: the two readings answer DIFFERENT questions
        // over the same argument string and return different counts, so which one fired is a fact about the
        // measurement, not a detail. seeds= is the resolved seed-symbol count (1 for a lone function, ~84
        // for a header), which is what makes the two readings comparable at a glance.
        std::printf( "<!-- ripwire affected: test files that transitively reach the changed files/symbols (run these); seeded_by= says which reading the argument took. "
                     "script_gates_unmodelled= counts test/*.sh runners in the corpus (a path count; not every one invokes the binary) — "
                     "script-to-binary edges are NOT modelled, so those gates are invisible to this walk and never counted in tests=/reached= -->" );
        std::printf( "<affected changed=\"%s\" seeded_by=\"%s\" seeds=\"%zu\" tests=\"%zu\" reached=\"%zu\" script_gates_unmodelled=\"%zu\">",
                     ex( cfg.affectedFiles ).c_str(), rw::affectedSeededBy( sel ), seeds.size(), testFiles.size(), reach.size(), scriptGatesUnmodelledCount( ing ) );
        // §P11.4: run= where a REAL runner is derivable, absent where it is not. The index is constructed
        // here (not hoisted into MainDispatch) because it is lazy — a run with no test row reads no script.
        const rw::TestRunnerIndex runners( ing );
        for( std::uint32_t f : testFiles )
        {
            std::printf( "<test p=\"%s\"%s/>", ex( ing.files[f] ).c_str(), rw::runAttr( runners, f, ex ).c_str() );
        }
        std::printf( "</affected>" );
        return 0;
    }
    return std::nullopt;
}

// --exercises=TESTFILE (§P11.2b): the INVERSE of --affected. §P11.2 recorded the test<->code map as
// one-directional: the tool answered "which tests reach this code" and nothing answered "what does this
// test exercise?" — the FIRST question when a test fails and you hold its name and nothing else. One BFS
// over edges that already exist (graph.h forwardReach, the dual of the transitiveCallers --affected uses),
// minus the test partition.
//
// Its own handler rather than a branch of runChangeViews for the same reason as elsewhere:
// a verb with a resolve step, two refusals and a windowed emitter is a named handler, not an if-arm.
std::optional<int> runExercises( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;
    const Graph&        g   = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         exSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  exRootPrefix = exSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();

    if( !cfg.exercisesFlag )
    {
        return std::nullopt;
    }
    if( cfg.exercisesFile.empty() )
    {
        std::fprintf( stderr, "ripwire: --exercises needs a test file — e.g. --exercises=test/foo_harness.cpp "
                              "(the inverse of --affected: what that test transitively covers)\n" );
        return 1;
    }

    const ExerciseSeeds sel = resolveExerciseSeeds( ing, cfg.exercisesFile );
    if( !sel.anyFileMatched )
    {
        std::fprintf( stderr, "ripwire: --exercises: no indexed file path matches '%.*s' (the argument is a path pattern, "
                              "like --affected's; use --tree or --grep to find its spelling)\n",
                      int( cfg.exercisesFile.size() ), cfg.exercisesFile.data() );
        return 1;
    }
    if( sel.testFiles.empty() )
    {
        // The decided non-test behavior (--help states it): refuse, do not widen the verb. See testmap.h.
        std::fprintf( stderr, "ripwire: --exercises: '%.*s' matches %u indexed file(s), none of them a TEST path "
                              "(a test/ or tests/ directory segment, or a test_*/ *_test.* / *_spec.* filename). This verb "
                              "subtracts test code from its answer, which is meaningless for a non-test file — for \"what does "
                              "this call\", use --callees=SYM (1 hop) or --graph-query with a callees(...) closure\n",
                      int( cfg.exercisesFile.size() ), cfg.exercisesFile.data(), sel.nonTestMatches );
        return 1;
    }

    std::vector<NodeId> show = exercisedSymbols( ing, g, sel.seeds );
    const auto [ rank, prIters, prConverged ] = rankGraph( g );
    const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: the legend says "PageRank desc" — so disclose the run
    std::sort( show.begin(), show.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );

    // §P8 / src/pageview.h, THE TRUNCATION VOCABULARY: the symbol listing is the PRIMARY (--limit-windowed)
    // one, so it takes the paging half; the seed-file listing is a second, independent listing and discloses
    // through its own noun-prefixed pair (rules 1 and 6). 40 is --impact's default cap — this verb is its
    // forward dual and a reader crossing between them should not meet two different defaults.
    const PageWindow  epw       = pageWindow( show.size(), effectiveRowCap( cfg.pageLimit, 40 ), cfg.pageOffset );
    const std::size_t shownRows = epw.end - epw.begin;
    const std::size_t shownSeed = std::min<std::size_t>( sel.testFiles.size(), 20 );
    char              epab[ kPageDisclosureCap ];
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    // G4: an XML comment may not contain a double hyphen, so this text names sibling verbs WITHOUT their
    // leading dashes (the same reason every other doc comment in the tool writes "quality-delta", not the
    // flag spelling). xmllint is the gate that catches a regression here.
    const std::string harnessAttr = exercisesHarnessAttr( ing, sel.testFiles );   // §A9.1, empty for a .cpp/.py harness

    std::printf( "<!-- ripwire exercises: the NON-TEST symbols this test transitively calls into — what it covers (the inverse of the affected verb). "
                 "<t> = the seed test files the pattern matched; <s> = the covered symbols, PageRank desc. "
                 "harness=script|mixed says the seed set contains shell gates, whose subprocess coverage this walk cannot see. "
                 "%s-->%s", rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str(), rw::rootRelPathsLegend( exSingleRoot ) );
    const std::string exRootAttr = exSingleRoot ? ( " root=\"" + ex( cfg.roots[0] ) + "\"" ) : std::string();
    std::printf( "<exercises of=\"%s\" seed_files=\"%zu\" shown_seed_files=\"%zu\" seed_files_capped=\"%u\" test_symbols=\"%zu\" reaches=\"%zu\"%s%s%s>",
                 ex( cfg.exercisesFile ).c_str(), sel.testFiles.size(), shownSeed,
                 unsigned( shownSeed < sel.testFiles.size() ), sel.seeds.size(), show.size(), harnessAttr.c_str(),
                 ( pageDisclosure( epab, sizeof( epab ), shownRows, show.size(), epw.end, cfg.pageLimit, cfg.pageOffset, true )
                   + rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ) ).c_str(),
                 exRootAttr.c_str() );
    const rw::TestRunnerIndex runners( ing );      // §P11.4: the seed rows are the tests you are about to re-run
    for( std::size_t i = 0; i < shownSeed; ++i )
    {
        const std::string_view rp = exSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ sel.testFiles[i] ], exRootPrefix ) : std::string_view( ing.files[ sel.testFiles[i] ] );
        std::printf( "<t p=\"%s\"%s/>", ex( rp ).c_str(), rw::runAttr( runners, sel.testFiles[i], ex ).c_str() );
    }
    for( std::size_t i = epw.begin; i < epw.end; ++i )
    {
        const Symbol&           s  = ing.symbols[ show[i] ];
        const std::string_view  rp = exSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], exRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
        std::printf( "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line );
    }
    std::printf( "</exercises>" );
    return 0;
}

std::optional<int> runChangeViews( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::string&                root         = d.root;
    const bool                        multiRoot    = d.multiRoot;
    const std::vector<WorkspaceRoot>& ws           = d.ws;

    // --handoff: the continuation packet for the NEXT session (handoff.h). Multi-root refused earlier in
    // main() with its siblings; this handler only ever sees one root.
    if( cfg.handoff )
    {
        return writeHandoffPacket( stdout, root, ing, g, cfg.tokenBudget );
    }

    // --situ[=FILES]: situational awareness for a change set — blast radius + tests to run + co-change misses,
    // in one call. The daily-driver "what should I know after this edit" verb. Default change set = git diff.
    if( cfg.situ )
    {
        // Multi-root: the default diff is the UNION of per-root `git diff`s, emitted
        // as PER-ROOT sections — each root's changed files, tests_to_run and co-change partners come from its
        // OWN repo, but the blast radius runs on the ONE merged graph, so a service-repo change correctly
        // lists client-repo impact when an evidence edge exists (per-repo history, joint graph).
        if( multiRoot )
        {
            bool anyGit = false;
            std::vector<std::vector<char>> perRootChanged( ws.size() );
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                if( !cfg.situFiles.empty() )
                {
                    perRootChanged[r] = rw::changedMaskFromList( ing, cfg.situFiles );
                    for( std::size_t f = 0; f < perRootChanged[r].size(); ++f )
                    {
                        if( perRootChanged[r][f] && ing.fileRoot[f] != r )
                        {
                            perRootChanged[r][f] = 0;
                        }
                    }
                    anyGit = true;   // explicit file list — no git needed
                }
                else
                {
                    perRootChanged[r].assign( ing.files.size(), 0 );
                    if( gitChangedFiles( ws[r].arg, ing, perRootChanged[r], r ) )
                    {
                        anyGit = true;
                    }
                }
            }
            if( !anyGit )
            { std::fprintf( stderr, "ripwire --situ: no files given and no git diff in any root (use --situ=F1,F2)\n" ); return 1; }
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                std::fprintf( stdout, "=== root %s (%s) ===\n", ws[r].label.c_str(), ws[r].arg.c_str() );
                bool any = false;
                for( char c : perRootChanged[r] )
                {
                    if( c )
                    {
                        any = true;
                        break;
                    }
                }
                if( !any ) { std::fprintf( stdout, "  (no changed files in this root)\n" ); continue; }
                rw::writeSituation( stdout, ws[r].arg, ing, g, perRootChanged[r], r );
            }
            return 0;
        }

        std::vector<char> changed;
        if( !cfg.situFiles.empty() )
        {
            changed = rw::changedMaskFromList( ing, cfg.situFiles );
        }
        else
        {
            changed.assign( ing.files.size(), 0 );
            if( !gitChangedFiles( root, ing, changed ) )
            { std::fprintf( stderr, "ripwire --situ: no files given and no git diff (use --situ=F1,F2)\n" ); return 1; }
        }
        rw::writeSituation( stdout, root, ing, g, changed );
        return 0;
    }

    // --test-gate[=FILES] (A4-R2): TDAD-parity regression contract — the --situ/--affected machinery packaged as
    // one gate. Report (tests to run + untested blast radius) is ALWAYS printed; the EXIT CODE is the gate, like
    // --quality-delta. Default change set = git diff. exit 4 (not 2/3 — quality-delta=2, token-budget=3) when
    // there are obligations (impacted tests to run OR a non-empty untested blast radius); exit 0 when neither.
    if( cfg.testGate )
    {
        std::vector<char> changed;
        if( !cfg.testGateFiles.empty() )
        {
            // An unparseable FILES list REFUSES rather than reading as an all-zero mask ("your change
            // touches nothing") — the silent-zero defect and the refusal's whole argument live on
            // testGateRefusesFileList in situ.h. Gate: testgaterefusecheck.sh.
            rw::ChangedList list = rw::changedMaskFromListChecked( ing, cfg.testGateFiles );
            if( rw::testGateRefusesFileList( root, cfg.testGateFiles, list ) )
            {
                return 1;
            }
            changed = std::move( list.mask );
        }
        else
        {
            changed.assign( ing.files.size(), 0 );
            if( !gitChangedFiles( root, ing, changed ) )
            { std::fprintf( stderr, "ripwire --test-gate: no files given and no git diff (use --test-gate=F1,F2)\n" ); return 1; }
        }
        // §A3a: --test-gate joined the pageview.h paging vocabulary — the
        // <u> untested-row list honors --limit/--offset instead of a silent 25-row cap with no disclosure.
        // The gate decision (computeTestGate) is computed ONCE here and handed to whichever report emitter
        // runs, so the two report shapes can never disagree about tests/untested and never re-pay the
        // blast-radius traversal.
        const rw::TestGateResult tg = rw::computeTestGate( ing, g, changed );
        if( cfg.json )
        {
            rw::writeTestGateReportJson( stdout, ing, tg, root, cfg.pageLimit, cfg.pageOffset );
        }
        else
        {
            rw::writeTestGateReport( stdout, ing, tg, root, cfg.pageLimit, cfg.pageOffset );
        }
        return tg.hasObligations ? 4 : 0;
    }

    // --pr-context[=BASEREF]: Wave-4 no-LLM review-evidence bundle. Default change set = the working-tree
    // diff (git diff HEAD); --pr-context=BASEREF diffs against that ref. Composes the existing analysis
    // (callers / blast radius / affected tests / co-change / owners) into one deterministic per-file XML
    // section. Non-git / git-unavailable → clean degrade (explanatory comment, exit 0). The mask is built
    // via --numstat (not --name-only) so pure mode-flip entries (content-identical, e.g. a chmod) are
    // excluded from the changed set rather than counted as changed files (A3-F10).
    if( cfg.prContext )
    {
        const std::string baseLabel = cfg.prContextBase.empty() ? std::string( "working-tree" ) : std::string( cfg.prContextBase );

        // Multi-root: per-root diff SECTIONS over the ONE merged graph. Each root's
        // changed-file mask is built from its OWN `git diff` (gitDiffChangedMaskNumstat onlyRoot=r), and its
        // owners/co-change come from its own history (writePrContext onlyRoot=r) — git signals are per root,
        // never across (§5). The blast radius / tests / callers deliberately run on the merged graph inside
        // writePrContext, so a service-root change lists client-root impact through a real evidence edge. The
        // per-root <pr-context> sections are wrapped in ONE <pr-context-workspace> element so the document stays
        // single-rooted (G4: xmllint-clean). Trim ladder under --max-tokens: the budget is split PER ROOT,
        // proportional to each root's changed-file count (integer floor; the remainder goes to the
        // lexicographically-first label = ws[0], since ws is in canonical label order) — then each root runs the
        // landed PrTrim ladder against its share. This reuses writePrContext verbatim; it is simpler than forcing
        // one shared global trim level (which would need writePrContext to expose a forced-level render).
        if( multiRoot )
        {
            std::vector<rw::PrContextMask> masks( ws.size() );
            std::vector<std::uint32_t>      changedCount( ws.size(), 0 );
            std::uint32_t                   totalChanged = 0;
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                masks[r] = rw::gitDiffChangedMaskNumstat( ws[r].arg, ing, cfg.prContextBase, r );
                // P0.1/P2.8: this branch had NO refusal at all, so a typo'd — or option-shaped — base ref
                // rendered as an empty workspace bundle at exit 0. A root with no git history is not this
                // case (it still degrades to its own empty section); see prcontext.h §badRef.
                if( masks[r].badRef )
                {
                    std::fprintf( stderr, "ripwire: --pr-context: unknown base ref '%.*s' in root %s\n",
                                  int( cfg.prContextBase.size() ), cfg.prContextBase.data(), ws[r].arg.c_str() );
                    return 1;
                }
                for( char c : masks[r].mask )
                {
                    if( c )
                    {
                        ++changedCount[r];
                    }
                }
                totalChanged += changedCount[r];
            }

            // per-root token budget = proportional split of --max-tokens; remainder → ws[0] (lexicographically-first
            // label). A changed-but-rounded-to-0 root is clamped to 1 so it still runs the ladder (0 = UNLIMITED
            // sentinel in writePrContext, which would wrongly un-cap that root).
            std::vector<std::size_t> rootBudget( ws.size(), 0 );
            if( cfg.maxTokens > 0 && totalChanged > 0 )
            {
                std::size_t assigned = 0;
                for( std::uint32_t r = 0; r < ws.size(); ++r )
                { rootBudget[r] = std::size_t( cfg.maxTokens ) * changedCount[r] / totalChanged; assigned += rootBudget[r]; }
                rootBudget[0] += std::size_t( cfg.maxTokens ) - assigned;   // remainder → canonical-first label
                for( std::uint32_t r = 0; r < ws.size(); ++r )
                {
                    if( changedCount[r] > 0 && rootBudget[r] == 0 )
                    {
                        rootBudget[r] = 1;
                    }
                }
            }

            std::vector<char> prEsc;
            const std::string baseLabelEsc = std::string( escapeXml( std::string_view( baseLabel ), prEsc ) );
            std::printf( "<!-- ripwire pr-context (multi-root workspace): ONE <pr-context> section per root over the "
                         "MERGED graph — per-root changed files / owners / co-change from each repo's own history, "
                         "blast radius crossing roots via real evidence edges. base=%s. deterministic. -->", baseLabelEsc.c_str() );
            std::printf( "<pr-context-workspace base=\"%s\" roots=\"%zu\">", baseLabelEsc.c_str(), ws.size() );
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                rw::writePrContext( stdout, ws[r].arg, ing, g, masks[r].mask, baseLabel, masks[r].skippedModeOnly,
                                     rootBudget[r], r, ws[r].label, masks[r] );
            }
            std::printf( "</pr-context-workspace>" );
            return 0;
        }

        const rw::PrContextMask pcm = rw::gitDiffChangedMaskNumstat( root, ing, cfg.prContextBase );
        // P2.8: a base ref this repo does not contain is a REFUSAL, not a clean tree — it used to render
        // `<pr-context base="typo" files="0"/>` at exit 0, indistinguishable in CI from "nothing changed".
        // Kept ahead of the `!pcm.ok` degrade below, whose message would misname this failure.
        if( pcm.badRef )
        {
            std::fprintf( stderr, "ripwire: --pr-context: unknown base ref '%.*s'\n",
                          int( cfg.prContextBase.size() ), cfg.prContextBase.data() );
            return 1;
        }
        if( !pcm.ok )
        {
            // git unavailable / not a repo / bad ref: degrade to a single explanatory comment, exit 0. baseLabel
            // is the raw user-supplied --pr-context=REF, so it MUST be escaped before entering an XML attribute
            // (A4-F19b: a ref containing "/</& otherwise yields a non-well-formed document — the success path
            // escapes via writePrContext's ex(); this degrade path had forgotten to).
            std::vector<char>  prEsc;
            const std::string  baseLabelEsc = std::string( escapeXml( std::string_view( baseLabel ), prEsc ) );
            std::printf( "<!-- ripwire pr-context: not a git repository (or git unavailable / bad base ref) — nothing to bundle -->" );
            std::printf( "<pr-context base=\"%s\" files=\"0\"/>", baseLabelEsc.c_str() );
            return 0;
        }
        // R4 / lever 4: --max-tokens caps the (previously unbounded) bundle. 0 = no cap
        // → byte-identical to the pre-budget output; >0 → degrade DEPTH-first per file, structural counts kept
        // for ALL changed files, est_tokens/truncated= reported on the <pr-context> header (see writePrContext).
        return rw::writePrContext( stdout, root, ing, g, pcm.mask, baseLabel, pcm.skippedModeOnly,
                                    cfg.maxTokens > 0 ? std::size_t( cfg.maxTokens ) : 0,
                                    UINT32_MAX, std::string_view(), pcm );
    }

    // --export=cc.json[:FILE]: Wave-4 CodeCharta interchange export. Per-file metrics ripwire already
    // computes → the cc.json folder-tree a CodeCharta 3D city consumes. FILE or stdout, mirroring --html.
    if( cfg.exportCcJson )
    {
        std::vector<rw::CcFileMetrics> ccm = rw::ccComputeMetrics( ing, g );
        // churn: THE shared per-file pass (mineChurnPerFile — also --hotspots'/--ensemble's, and the
        // --html --color-by=churn lens below), multi-root §5 accumulation included. An empty `since`
        // leaves the scope inactive, so this is the default 18-month window: byte-identical to the
        // per-root loop this used to spell inline, and no longer a copy that can drift from the others.
        // 0 everywhere without git — clean degrade, churn simply omitted from the metrics below.
        std::vector<std::uint32_t> churn( ing.files.size(), 0 );
        const rw::SinceScope       ccScope;   // inactive: --export=cc.json has no --since form
        const bool ccChurnOk = mineChurnPerFile( ing, root, multiRoot, ws, std::string_view(), ccScope, "18 months ago", churn );
        if( ccChurnOk )
        {
            for( std::size_t f = 0; f < ccm.size() && f < churn.size(); ++f )
            {
                ccm[f].churn = churn[f];
            }
        }

        std::FILE* ccOut = stdout;
        if( !cfg.exportFile.empty() )
        {
            const std::string ccPath( cfg.exportFile );
            ccOut = std::fopen( ccPath.c_str(), "wb" );
            if( !ccOut )
            {
                DEGRADED_PATH_ALERT( "writeCcJson: could not open output file" );
                std::fprintf( stderr, "ripwire: --export=cc.json:%s: cannot open file for writing\n", ccPath.c_str() );
                return 1;
            }
        }
        rw::writeCcJson( ccOut, root, ing, ccm );
        if( ccOut != stdout )
        {
            std::fclose( ccOut );
        }
        return 0;
    }
    return std::nullopt;
}

// L2 — --from-trace helpers. tracein.h owns the pure frame extraction; the
// CORPUS resolution (a frame's path → indexed fileId, a frame's line → its enclosing symbol) and the whole
// bundle assembler now live in tracelocus.h (L4) as fromTraceBundleText() — shared verbatim with the MCP
// from_trace verb (mcpverbs.h's fromTraceText()). Only readTraceText (stdin/file reading — a CLI-only
// concern; the MCP verb takes the trace text as a request argument) stays here.

// read the --from-trace source into `text` — a FILE, or '-' for stdin (the --batch precedent). Returns false
// (after printing the reason) only when a NAMED file cannot be opened; '-' and an empty file are fine.
bool readTraceText( const std::string& src, std::string& text )
{
    if( src == "-" )
    {
        // R4: the same byte-safe reader the --mcp loop runs on. A stack trace / sanitizer report carries
        // non-ASCII routinely (a UTF-8 identifier, a quoted source line), and std::getline( std::cin, ... )
        // aborted the sanitizer build on the first such byte — see stdinline.h. Parity is exact.
        std::string l;
        while( rw::readByteSafeLine( stdin, l ) ) { text += l; text += '\n'; }
        return true;
    }
    std::FILE* f = std::fopen( src.c_str(), "rb" );
    if( !f ) { std::fprintf( stderr, "ripwire: --from-trace: cannot open '%s'\n", src.c_str() ); return false; }
    char buf[ 4096 ]; std::size_t n;
    while( ( n = std::fread( buf, 1, sizeof buf, f ) ) > 0 )
    {
        text.append( buf, n );
    }
    std::fclose( f );
    return true;
}

// L2 — --from-trace=FILE ('-'=stdin): trace-to-locus. Reads a stack trace /
// sanitizer report / compiler-error text and hands it to fromTraceBundleText() (tracelocus.h) — the ranked
// enclosing-symbol map, the suspects' signatures, and the innermost in-corpus symbol's full body. Composes
// with --token-budget. Unparseable input (zero frames) refuses loudly — never an empty map. Read-only,
// deterministic, no git.
std::optional<int> runFromTrace( const MainDispatch& d )
{
    using namespace rw;
    const Config&        cfg = d.cfg;
    const IngestResult&  ing = d.ing;
    const Graph&         g   = d.g;

    if( cfg.fromTrace.empty() )
    {
        return std::nullopt;
    }

    const std::string src( cfg.fromTrace );
    std::string       text;
    if( !readTraceText( src, text ) )
    {
        return 1;
    }

    FromTraceInputs in;
    in.bundleBudgetBytes = cfg.tokenBudget > 0
        ? std::size_t( double( cfg.tokenBudget ) * rw::kMinBytesPerToken * rw::kBudgetHeadroom )
        : rw::kForPayloadBudgetBytes;
    in.sigLadderBudgetBytes = cfg.packBudgetBytes;
    in.bodyBudgetBytes      = cfg.maxTokens > 0
        ? std::size_t( double( cfg.maxTokens ) * rw::kMinBytesPerToken * rw::kBudgetHeadroom )
        : cfg.packBudgetBytes;
    in.compress = cfg.compress;
    in.fanIn    = d.fanInPtr;
    in.impure   = d.impurePtr;
    in.tested   = d.testedPtr;
    in.amp      = d.ampPtr;
    in.redact   = d.redactPtr;
    in.notes    = d.notesPtr;
    in.rootArg  = ( ing.realPaths.empty() && cfg.roots.size() == 1 ) ? std::string_view( cfg.roots[0] )
                                                                    : std::string_view();   // R-R

    const FromTraceResult res = fromTraceBundleText( ing, g, text, src == "-" ? "<stdin>" : src, in );
    if( !res.ok )
    {
        std::fprintf( stderr, "ripwire: --from-trace: no stack-trace / sanitizer / compiler frames found in '%s' — nothing to map\n",
                      src == "-" ? "<stdin>" : src.c_str() );
        return 1;
    }
    std::fwrite( res.xml.data(), 1, res.xml.size(), stdout );
    reportRedactions( stderr, d.redactCounts );
    return 0;
}

// ── VT-1 — --run-trace="CMD": the exec-mode entry of the --from-trace family ─────────────────────────────
// An agent's fix loop today is three steps: run the build/test via its own shell, read the (possibly huge)
// output, paste the error into --from-trace. This collapses it to ONE call: execute CMD, capture its output,
// and on failure serve the EXISTING from-trace bundle (fromTraceBundleText — reuse, never a second mapper)
// plus a token-frugal <lines> view of the trace-relevant output lines. Trust model: `sh -c` at user
// privileges with the inherited environment, exactly like make — no sandbox, and the legend says so.
// Determinism, honestly scoped: the <run> record (duration_ms) and the captured output are MEASURED; every
// byte derived FROM the captured text (the lines cut, the mapping) is a deterministic function of it.

inline constexpr std::uint32_t kRunTraceTimeoutSecDefault = 600;                 // the cap when --run-timeout is not given
inline constexpr std::size_t   kRunTraceHeadCapBytes      = 8u * 1024 * 1024;    // capture cap: first 8 MB kept …
inline constexpr std::size_t   kRunTraceTailCapBytes      = 24u * 1024 * 1024;   // … plus the last 24 MB; the dropped middle is COUNTED
inline constexpr std::size_t   kRunTraceRelevantLinesCap  = 40;                  // <lines view="relevant"> cap (first/last half split past it)
inline constexpr std::size_t   kRunTraceTailLines         = 10;                  // success record: the disclosed tail length
inline constexpr std::size_t   kRunTraceFallbackTailLines = 25;                  // failure with zero relevant lines: fall back to this tail
inline constexpr int           kRunTraceExitCommandFailed = 4;                   // ripwire's own exit when the COMMAND failed/timed out (report served)

// the error-line marks the relevant-lines cut recognizes beyond frame-shaped lines: compiler/linker primary
// diagnostics, test failures, sanitizer banners, shell spawn errors. Substring match over a fixed table —
// deterministic; the legend names the classes rather than restating the spellings.
inline constexpr std::string_view kRunTraceErrorMarks[] =
{
    "error", "Error", "ERROR", "fatal", "FAIL", "fail", "Assertion", "assert", "Traceback", "panic",
    "Segmentation fault", "not found", "No such file", "Exception", "Sanitizer", "SUMMARY:", "Abort", "abort",
    "undefined reference", "Undefined symbols",
};

// everything one command execution produced, capture caps applied. The exit facts are decoded, never
// re-derived downstream: isExitedNormally/exitCode vs termSignal vs isTimedOut are three different truths.
struct RunCapture
{
    bool          isSpawnFailed    = false;   // ripwire's own machinery (pipe/fork) failed — nothing was executed
    bool          isTimedOut       = false;   // the cap killed the process group
    bool          isExitedNormally = false;   // WIFEXITED — exitCode is meaningful
    int           exitCode         = -1;
    int           termSignal       = 0;       // WTERMSIG when the command died to a signal (incl. our SIGKILL)
    std::uint64_t durationMs       = 0;
    std::uint64_t totalBytes       = 0;       // bytes the command actually produced (pre-cap)
    std::uint64_t droppedBytes     = 0;       // middle bytes the head+tail cap dropped — disclosed, never silent
    std::string   head;                        // first kRunTraceHeadCapBytes
    std::string   tail;                        // overflow past the head cap, trimmed from the front to the tail cap
};

// append one read() chunk under the head+tail cap. The head fills once; overflow accumulates in the tail,
// which is trimmed from the FRONT so the newest bytes always survive (a build log's failure is at the end).
void runCaptureAppend( RunCapture& cap, const char* data, std::size_t byteCount )
{
    cap.totalBytes += byteCount;
    std::size_t take = 0;
    if( cap.head.size() < kRunTraceHeadCapBytes )
    {
        take = std::min( byteCount, kRunTraceHeadCapBytes - cap.head.size() );
        cap.head.append( data, take );
    }
    if( take < byteCount )
    {
        cap.tail.append( data + take, byteCount - take );
        if( cap.tail.size() > 2 * kRunTraceTailCapBytes )
        {
            cap.droppedBytes += cap.tail.size() - kRunTraceTailCapBytes;
            cap.tail.erase( 0, cap.tail.size() - kRunTraceTailCapBytes );
        }
    }
}

// the captured text, reassembled for classification + mapping. A drop splices head onto tail: one newline at
// the seam keeps two partial lines from fusing into a frankenline (the drop itself is dropped_bytes=).
std::string runCaptureText( RunCapture& cap )
{
    if( cap.tail.size() > kRunTraceTailCapBytes )
    {
        cap.droppedBytes += cap.tail.size() - kRunTraceTailCapBytes;
        cap.tail.erase( 0, cap.tail.size() - kRunTraceTailCapBytes );
    }
    if( cap.tail.empty() )
    {
        return cap.head;
    }
    std::string text = cap.head;
    if( cap.droppedBytes > 0 )
    {
        text += '\n';
    }
    text += cap.tail;
    return text;
}

// fork/exec `sh -c CMD` in its own process group, drain the pipe under a poll() deadline, SIGKILL the whole
// group at the cap, and decode the exit honestly. Zero new dependencies — POSIX only (G3/G5).
RunCapture runCommandCapture( const std::string& cmd, std::uint32_t timeoutSec )
{
    RunCapture cap;
    int fds[2];
    if( pipe( fds ) != 0 )
    {
        cap.isSpawnFailed = true;
        return cap;
    }

    const auto t0 = std::chrono::steady_clock::now();
    const auto elapsedMs = [ & ]() -> std::int64_t
    { return std::chrono::duration_cast<std::chrono::milliseconds>( std::chrono::steady_clock::now() - t0 ).count(); };

    const pid_t childPid = fork();
    if( childPid < 0 )
    {
        close( fds[0] );  close( fds[1] );
        cap.isSpawnFailed = true;
        return cap;
    }
    if( childPid == 0 )
    {
        // child: own process group (the timeout kills the whole tree), stdin from /dev/null (a command that
        // reads its terminal must not hang the report), both streams into ONE pipe (interleaved, as a
        // terminal would see them), then the shell. _exit(127) mirrors sh's own command-not-found code.
        setpgid( 0, 0 );
        const int devNull = open( "/dev/null", O_RDONLY );
        if( devNull >= 0 ) { dup2( devNull, STDIN_FILENO );  close( devNull ); }
        dup2( fds[1], STDOUT_FILENO );  dup2( fds[1], STDERR_FILENO );
        close( fds[0] );  close( fds[1] );
        execl( "/bin/sh", "sh", "-c", cmd.c_str(), static_cast<char*>( nullptr ) );
        _exit( 127 );
    }

    setpgid( childPid, childPid );   // parent side of the same race — both settings agree, whichever runs first
    close( fds[1] );

    // ── drain the pipe under the deadline; after a kill, keep draining briefly (an orphaned grandchild may
    //    still hold the write side open — stop at the drain deadline rather than hanging on its EOF) ───────
    const std::int64_t timeoutMs     = std::int64_t( timeoutSec ) * 1000;
    const std::int64_t drainWindowMs = 2000;
    std::int64_t       drainDeadlineMs = 0;
    char               buf[ 65536 ];
    for( ;; )
    {
        const std::int64_t nowMs = elapsedMs();
        if( !cap.isTimedOut && nowMs >= timeoutMs )
        {
            cap.isTimedOut  = true;
            drainDeadlineMs = nowMs + drainWindowMs;
            kill( -childPid, SIGKILL );
            kill( childPid, SIGKILL );
        }
        if( cap.isTimedOut && elapsedMs() >= drainDeadlineMs )
        {
            break;
        }
        const std::int64_t untilMs = ( cap.isTimedOut ? drainDeadlineMs : timeoutMs ) - elapsedMs();
        struct pollfd pfd { fds[0], POLLIN, 0 };
        const int ready = poll( &pfd, 1, int( std::clamp<std::int64_t>( untilMs, 0, 1000 ) ) );
        if( ready > 0 )
        {
            const ssize_t n = read( fds[0], buf, sizeof buf );
            if( n <= 0 ) { break; }                       // EOF: every writer closed the pipe
            runCaptureAppend( cap, buf, std::size_t( n ) );
        }
        else if( ready < 0 && errno != EINTR )
        {
            break;
        }
    }
    close( fds[0] );

    // ── harvest the exit status, still under the cap: EOF can precede exit (a command that closed its own
    //    stdout/stderr and kept running), so the wait polls the SAME deadline instead of blocking past it ──
    int status = 0;
    for( ;; )
    {
        const pid_t waited = waitpid( childPid, &status, cap.isTimedOut ? 0 : WNOHANG );
        if( waited == childPid || waited < 0 )
        {
            break;
        }
        if( elapsedMs() >= timeoutMs )
        {
            cap.isTimedOut = true;
            kill( -childPid, SIGKILL );
            kill( childPid, SIGKILL );
            continue;                                      // next iteration blocks: the group is dead
        }
        poll( nullptr, 0, 20 );
    }
    cap.durationMs = std::uint64_t( elapsedMs() );
    if( WIFEXITED( status ) )
    {
        cap.isExitedNormally = true;
        cap.exitCode         = WEXITSTATUS( status );
    }
    else if( WIFSIGNALED( status ) )
    {
        cap.termSignal = WTERMSIG( status );
    }
    return cap;
}

// split the captured text into its NON-EMPTY lines (views into `text`) — wsdetail::segmentsOf is the shared
// split primitive (workspace.h), reused rather than re-rolled. Blank lines carry no signal for either the
// relevant cut or the tail, so lines= counts non-empty captured lines (the legend says so).
std::vector<std::string_view> runTraceSplitLines( std::string_view text )
{
    return rw::wsdetail::segmentsOf( text, '\n' );
}

// is this output line trace-relevant? An error mark (fixed table) or a frame-shaped line (the SAME per-line
// extractor the mapper runs, so "frames that mapped" and "lines shown" can never disagree about shape).
bool isRunTraceRelevantLine( std::string_view line )
{
    const bool hasErrorMark = std::any_of( std::begin( kRunTraceErrorMarks ), std::end( kRunTraceErrorMarks ),
                                           [ line ]( std::string_view mark ) { return line.find( mark ) != std::string_view::npos; } );
    return hasErrorMark || rw::tracein::extractFrames( line ).frameShapedLines > 0;
}

// the <lines> element: view="relevant" on failure (error-marked / frame-shaped lines, first+last halves kept
// past the cap, the omitted middle disclosed INLINE), view="tail" on success or when nothing classified.
// Empty capture ⇒ empty string (the <run> record's lines="0" already says why).
std::string renderRunTraceLines( const std::vector<std::string_view>& lines, bool isFailure )
{
    std::vector<std::size_t> picked;
    bool isRelevantView = false;
    bool isCapped       = false;
    std::size_t relevantCount = 0;

    if( isFailure )
    {
        std::vector<std::size_t> relevant;
        for( std::size_t i = 0; i < lines.size(); ++i )
        {
            if( isRunTraceRelevantLine( lines[i] ) )
            {
                relevant.push_back( i );
            }
        }
        relevantCount = relevant.size();
        if( !relevant.empty() )
        {
            isRelevantView = true;
            if( relevant.size() <= kRunTraceRelevantLinesCap )
            {
                picked = relevant;
            }
            else
            {
                isCapped = true;
                const std::size_t half = kRunTraceRelevantLinesCap / 2;
                picked.assign( relevant.begin(), relevant.begin() + std::ptrdiff_t( half ) );
                picked.insert( picked.end(), relevant.end() - std::ptrdiff_t( half ), relevant.end() );
            }
        }
    }
    if( !isRelevantView )
    {
        const std::size_t tailLines = isFailure ? kRunTraceFallbackTailLines : kRunTraceTailLines;
        const std::size_t begin     = lines.size() > tailLines ? lines.size() - tailLines : 0;
        for( std::size_t i = begin; i < lines.size(); ++i )
        {
            picked.push_back( i );
        }
    }
    if( picked.empty() )
    {
        return {};
    }

    std::string cdata;
    const std::size_t halfCount = kRunTraceRelevantLinesCap / 2;
    for( std::size_t k = 0; k < picked.size(); ++k )
    {
        if( k > 0 )
        {
            cdata += '\n';
        }
        if( isCapped && k == halfCount )
        {
            cdata += "[... ";
            cdata += std::to_string( relevantCount - kRunTraceRelevantLinesCap );
            cdata += " relevant lines omitted (middle) ...]\n";
        }
        rw::appendCdataSafe( lines[ picked[k] ], cdata );
    }

    std::string out = "<lines view=\"";
    out += isRelevantView ? "relevant" : "tail";
    out += "\" shown=\"";  out += std::to_string( picked.size() );
    if( isFailure )
    {
        out += "\" relevant=\"";  out += std::to_string( relevantCount );
    }
    out += "\" total=\"";  out += std::to_string( lines.size() );
    out += "\"";
    if( isCapped )
    {
        out += " capped=\"1\"";
    }
    out += "><![CDATA[";  out += cdata;  out += "]]></lines>";
    return out;
}

// the <run> record — the command's exit ALWAYS disclosed: exit= when it exited, signal= when a signal killed
// it, timed_out="1" when that signal was the cap's. framesFound carries the frameless-failure disclosure.
std::string renderRunTraceRecord( const RunCapture& cap, std::uint32_t timeoutSec, std::size_t lineCount, bool isFrameless )
{
    std::string r = "<run";
    if( cap.isTimedOut )
    {
        r += " timed_out=\"1\"";
    }
    if( cap.isExitedNormally )
    {
        r += " exit=\"";  r += std::to_string( cap.exitCode );  r += "\"";
    }
    else if( cap.termSignal != 0 )
    {
        r += " signal=\"";  r += std::to_string( cap.termSignal );  r += "\"";
    }
    r += " duration_ms=\"";  r += std::to_string( cap.durationMs );
    r += "\" timeout_s=\"";  r += std::to_string( timeoutSec );
    r += "\" lines=\"";      r += std::to_string( lineCount );
    r += "\" bytes=\"";      r += std::to_string( cap.totalBytes );
    r += "\"";
    if( cap.droppedBytes > 0 )
    {
        r += " dropped_bytes=\"";  r += std::to_string( cap.droppedBytes );  r += "\"";
    }
    if( isFrameless )
    {
        r += " frames=\"0\"";
    }
    r += "/>";
    return r;
}

// which of the three run-trace documents is this comment for? The legend body is shared; only the closing
// sentence differs, and each states its own truth plainly.
enum class RunTraceDocKind : std::uint8_t { Success, FramelessFailure, Bundle };

// the run-trace legend comment. NOTE the double-dash rule: an XML comment may not contain "--", so flag
// names appear single-dashed here and the command echo goes through xmlCommentText (the srcNote precedent).
std::string runTraceLegendComment( std::string_view cmd, RunTraceDocKind kind )
{
    std::string c = "<!-- ripwire run-trace: executed \"";
    c += rw::xmlCommentText( cmd );
    c += "\" under sh -c (the make trust model: your user, inherited environment, stdin=/dev/null, NO sandbox), "
         "stdout+stderr captured interleaved. On <run>: exit= the command's OWN exit code; signal= the signal that "
         "killed it; timed_out=\"1\" = the timeout_s= cap killed the whole process group (an honest TIMEOUT, never an "
         "empty success); duration_ms= wall clock; lines= the capture's non-empty line count; bytes= the whole "
         "capture; dropped_bytes= middle bytes the capture cap dropped (head+tail kept). duration_ms and the "
         "captured output are MEASURED, not deterministic "
         "(and not claimed to be); every byte derived FROM the captured text - the <lines> cut and any mapping - is a "
         "deterministic function of it. <lines view=\"tail\"> = the last shown= of total= output lines; "
         "view=\"relevant\" = shown= of the relevant= error-marked / frame-shaped lines out of total= (capped=\"1\" = "
         "first+last halves kept, the omitted middle disclosed inline). ";
    switch( kind )
    {
        case RunTraceDocKind::Success:
            c += "The command exited 0: nothing failed, so there is NOTHING TO MAP - no trace bundle is served for a "
                 "passing command.";
            break;
        case RunTraceDocKind::FramelessFailure:
            c += "The command FAILED but the captured output carried no stack-trace / sanitizer / compiler frames "
                 "(frames=\"0\" on <run>): nothing to map onto the corpus - the run record and lines here are the whole "
                 "answer.";
            break;
        case RunTraceDocKind::Bundle:
            c += "The command FAILED and the captured text carried mappable frames: the <trace>/<sigs>/<bodies> bundle "
                 "below is the byte-deterministic from-trace mapping of that text (its own legend precedes it above).";
            break;
    }
    c += " -->";
    return c;
}

// VT-1 — --run-trace="CMD": execute, capture, and on failure map. One call, one document, the whole
// fix-loop entry. Exit: 0 = the command succeeded; kRunTraceExitCommandFailed (4) = it failed or timed out
// (the report is on stdout either way); 1 = ripwire's own spawn machinery failed.
std::optional<int> runRunTrace( const MainDispatch& d )
{
    using namespace rw;
    const Config& cfg = d.cfg;
    if( cfg.runTrace.empty() )
    {
        return std::nullopt;
    }

    const std::string   cmd( cfg.runTrace );
    const std::uint32_t timeoutSec = cfg.runTimeoutSec > 0 ? std::uint32_t( cfg.runTimeoutSec ) : kRunTraceTimeoutSecDefault;

    RunCapture cap = runCommandCapture( cmd, timeoutSec );
    if( cap.isSpawnFailed )
    {
        std::fprintf( stderr, "ripwire: --run-trace: cannot spawn '/bin/sh -c' (pipe/fork failed) — nothing was executed\n" );
        return 1;
    }
    if( cap.isTimedOut )
    {
        std::fprintf( stderr, "ripwire: --run-trace: TIMEOUT — the command exceeded the %u s cap; its process group was killed\n", timeoutSec );
    }

    const std::string                   text    = runCaptureText( cap );
    const std::vector<std::string_view> lines   = runTraceSplitLines( text );
    const bool isSuccess = !cap.isTimedOut && cap.isExitedNormally && cap.exitCode == 0;
    const std::string label = "run-trace: " + cmd;

    // ── exit 0: the minimal success record — no bundle, and the legend says plainly why ─────────────────
    if( isSuccess )
    {
        std::string doc = ctxRootOpen( label, {} );
        doc += runTraceLegendComment( cmd, RunTraceDocKind::Success );
        doc += renderRunTraceRecord( cap, timeoutSec, lines.size(), /*isFrameless=*/false );
        doc += renderRunTraceLines( lines, /*isFailure=*/false );
        doc += "</ctx>";
        std::fwrite( doc.data(), 1, doc.size(), stdout );
        return 0;
    }

    // ── failure: the run record + relevant-lines cut ride INSIDE the from-trace bundle as its prelude, so
    //    the whole answer is ONE document under ONE budget ledger ─────────────────────────────────────────
    const std::string linesBlock = renderRunTraceLines( lines, /*isFailure=*/true );

    FromTraceInputs in;
    in.bundleBudgetBytes = cfg.tokenBudget > 0
        ? std::size_t( double( cfg.tokenBudget ) * rw::kMinBytesPerToken * rw::kBudgetHeadroom )
        : rw::kForPayloadBudgetBytes;
    in.sigLadderBudgetBytes = cfg.packBudgetBytes;
    in.bodyBudgetBytes      = cfg.packBudgetBytes;
    in.compress = cfg.compress;
    in.fanIn    = d.fanInPtr;
    in.impure   = d.impurePtr;
    in.tested   = d.testedPtr;
    in.amp      = d.ampPtr;
    in.redact   = d.redactPtr;
    in.notes    = d.notesPtr;
    in.rootArg  = ( d.ing.realPaths.empty() && cfg.roots.size() == 1 ) ? std::string_view( cfg.roots[0] )
                                                                      : std::string_view();   // R-R

    std::string prelude = runTraceLegendComment( cmd, RunTraceDocKind::Bundle );
    prelude += renderRunTraceRecord( cap, timeoutSec, lines.size(), /*isFrameless=*/false );
    prelude += linesBlock;
    in.preludeXml = prelude;

    const FromTraceResult res = fromTraceBundleText( d.ing, d.g, text, label, in );
    if( res.ok )
    {
        std::fwrite( res.xml.data(), 1, res.xml.size(), stdout );
        reportRedactions( stderr, d.redactCounts );
        return kRunTraceExitCommandFailed;
    }

    // ── failure with NO mappable frames: still a full report — never a refusal, never a silent success ──
    std::string doc = ctxRootOpen( label, {} );
    doc += runTraceLegendComment( cmd, RunTraceDocKind::FramelessFailure );
    doc += renderRunTraceRecord( cap, timeoutSec, lines.size(), /*isFrameless=*/true );
    doc += linesBlock;
    doc += "</ctx>";
    std::fwrite( doc.data(), 1, doc.size(), stdout );
    return kRunTraceExitCommandFailed;
}

// L3 — repo field notes: the WRITE side (surfacing at retrieval is wired into
// packSignatures/packBodies above). Two verbs share this handler:
//   --note-add="TARGET: text" — append a note to the committed, sorted root/.ripwire_notes and print the exact
//        written line. The date is git's committer clock (HEAD, %cs), NOT wall time, so the line is a pure
//        function of (commit state, target, text) — deterministic and stable across machines; a non-git root
//        degrades to the fixed epoch 1970-01-01 + a DEGRADED_PATH_ALERT (nothing to date against). MUTATES one
//        file and touches nothing else; the multi-root refusal lives with its siblings earlier in main().
//   --notes — list every note grouped by target; a target matching no indexed symbol canonical-id / file path
//        is flagged dangling="1" (legal — surfaced nowhere, listed here so the human can prune it). Read-only.
std::optional<int> runNotes( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;

    // ── --note-add: split "TARGET: text" on the FIRST ": " (a canonical id's "::" pairs carry no space, so
    //    they never false-match), sanitize both fields to the single-line/tab-free format invariant, then
    //    append+re-sort+write and print the written line verbatim. ────────────────────────────────────────
    if( cfg.noteAddFlag )
    {
        const std::string spec( cfg.noteAdd );
        const std::size_t sep = spec.find( ": " );
        if( sep == std::string::npos )
        {
            std::fprintf( stderr, "ripwire: --note-add: want \"TARGET: text\" (a canonical id path::scope::name or a file path, then ': ', then the note) — got '%s'\n", spec.c_str() );
            return 1;
        }
        // §S3 — sanitizeNoteField sanitizes AND decides (notes.h's header has the full finding): the old
        // `sanitizeField(...).empty()` pair refused an ASCII-blank note and accepted six other blank classes,
        // committing an invisible line into `.ripwire_notes`. `hasContent` is rw::hasVisibleContent, the same
        // derived predicate the MCP edit verbs' payload check reads.
        const notes::NoteField targetField = notes::sanitizeNoteField( std::string_view( spec ).substr( 0, sep ) );
        const notes::NoteField textField   = notes::sanitizeNoteField( std::string_view( spec ).substr( sep + 2 ) );
        const std::string&     rawTarget   = targetField.text;
        const std::string&     text        = textField.text;
        if( !targetField.hasContent || !textField.hasContent )
        {
            // §S3 — the refusal SPELLS an invisible value instead of echoing it, for blankPayloadSpelling's
            // own reason: echoing the bytes pastes a C1 control or a bidi override into the caller's terminal,
            // and `U+200E` is something they can grep for while the character itself is not. An EMPTY field
            // has nothing to spell, so it keeps the original sentence byte-for-byte — a caller who typed
            // `--note-add="alpha: "` sees exactly what they saw before.
            // blankPayloadSpelling's contract is "call me on a payload you have ALREADY ruled all-blank" —
            // on any other value it spells every code point in it, which would render a perfectly good
            // target as `U+0061 U+006C …`. So the three cases are separated here rather than inferred from
            // an empty spelling: a field that HAS content and the field that is genuinely absent both keep
            // the original quoted echo, and only the present-but-invisible one is spelled.
            const auto describeField = []( const notes::NoteField& field ) -> std::string
            {
                if( field.hasContent || field.text.empty() )
                {
                    return "'" + field.text + "'";
                }

                const auto [ blankCodePointCount, blankSpelling ] = rw::blankPayloadSpelling( field.text );
                return std::to_string( blankCodePointCount )
                     + ( blankCodePointCount == 1 ? " invisible code point: " : " invisible code points: " )
                     + blankSpelling;
            };
            std::fprintf( stderr, "ripwire: --note-add: both a target and a note text are required (got target=%s text=%s)\n",
                          describeField( targetField ).c_str(), describeField( textField ).c_str() );
            return 1;
        }
        // R6: a gentle stderr NUDGE (never a refusal — the add proceeds either way) when the text carries
        // no causal/decision marker. Decision-shaped notes retrieve better than plain prose; this is advice
        // on the text itself, so it prints regardless of what the target-normalization step below decides.
        // stderr only — never stdout, so it can never contaminate --note-add's printed line or a later
        // --for/--expand/default-map XML emission (notescheck.sh's det-gate covers this).
        if( !notes::isDecisionShaped( text ) )
        {
            std::fprintf( stderr, "ripwire: --note-add: tip: notes that say \"chose X over Y because Z\" surface better — consider adding the why\n" );
        }
        // D5: canonicalize the target's path component to ROOT-RELATIVE before it ever touches disk — the
        // portable-notes contract (.ripwire_notes is committed and must resolve on any other checkout). An
        // absolute target outside this root can never be reached from another checkout's crawl, so refuse
        // loudly instead of silently writing a note that surfaces nowhere, ever.
        bool outsideRoot = false;
        const std::string target = notes::normalizeNoteTarget( rawTarget, d.root, outsideRoot );
        if( outsideRoot )
        {
            std::fprintf( stderr, "ripwire: --note-add: target '%s' resolves outside the root '%s' — refusing (notes must stay root-relative/portable)\n", rawTarget.c_str(), d.root.c_str() );
            return 1;
        }
        std::string date = rw::quality::gitCommitterDateIso( d.root );
        if( date.empty() )
        {
            DEGRADED_PATH_ALERT( "notes: non-git root — dating the note at the fixed epoch 1970-01-01 for determinism" );
            date = "1970-01-01";
        }
        // provenance stamp (the day's costliest lesson): anchor the note to the commit it was written under.
        // gitHeadSha resolves empty exactly when date's own gitCommitterDateIso lookup would have (same
        // non-git-root / no-HEAD condition, already alerted above) — no second DEGRADED_PATH_ALERT needed.
        // "no sha shown rather than a wrong one": an empty sha here means addNote writes the plain LEGACY
        // 3-field line, never a hollow or guessed stamp.
        const std::string sha    = rw::quality::gitHeadSha( d.root );
        const std::string branch = sha.empty() ? std::string()
                                  : notes::sanitizeField( rw::quality::gitOneLine( d.root, "rev-parse --abbrev-ref HEAD 2>/dev/null" ) );
        const std::string path = notes::notesPath( d.root );
        const std::string line = notes::addNote( path, target, date, text, sha, branch );
        if( line.empty() )
        {
            std::fprintf( stderr, "ripwire: --note-add: could not write %s\n", path.c_str() );
            return 1;
        }
        std::fwrite( line.data(), 1, line.size(), stdout );
        std::fputc( '\n', stdout );
        return 0;
    }

    // ── --notes: list grouped by target, dangling targets flagged. ─────────────────────────────────────────
    if( cfg.notesList )
    {
        // D5: read + normalize every stored target to ROOT-RELATIVE (readNotesRelative) — a legacy absolute
        // entry from before this fix keeps matching correctly instead of always reading dangling="1".
        std::vector<notes::Note> all = notes::readNotesRelative( notes::notesPath( d.root ), d.root );
        notes::sortNotes( all );

        // the set of LIVE targets in the indexed tree: every symbol's canonical id + every file path, BOTH
        // relativized against d.root (relForHash) to match the root-relative `all` targets above.
        HashMap<std::string, std::uint8_t> live;
        live.reserve( ing.symbols.size() + ing.files.size() );
        for( NodeId i = 0; i < ing.symbols.size(); ++i )
        {
            const Symbol& s = ing.symbols[i];
            if( s.fileId < ing.files.size() )
            {
                live[canonicalId( relForHash( ing.files[s.fileId], d.root ), s.scope, s.name )] = 1;
            }
        }
        for( const std::string& fp : ing.files )
        {
            live[std::string( relForHash( fp, d.root ) )] = 1;
        }

        std::size_t targetCount = 0, danglingCount = 0;
        for( std::size_t i = 0; i < all.size(); )
        {
            std::size_t j = i;
            while( j < all.size() && all[j].target == all[i].target )
            {
                ++j;
            }
            ++targetCount;
            if( live.find( all[i].target ) == live.end() )
            {
                ++danglingCount;
            }
            i = j;
        }

        {
            XmlWriter        w( stdout );
            std::vector<char> esc;
            // The note-row attribute definitions live HERE because this header is the --notes reader's ONLY
            // legend (legendcoveragecheck arm A): d= ISO date, sha=/branch= the provenance stamp, whose
            // omitted-not-empty contract is appendOneNote's (serialize.h). NB: no `--` inside an XML comment.
            char hdr[ 512 ];
            std::snprintf( hdr, sizeof( hdr ),
                           "<ctx><!-- ripwire field notes: notes=%zu targets=%zu dangling=%zu (a target with no matching indexed symbol/file — legal: listed here, surfaced nowhere)."
                           " Each note row: d= is the ISO date it was recorded; sha= the abbreviated commit and branch= the branch checked out at record time,"
                           " both omitted entirely on a note stored before provenance stamping (absent means none recorded, never empty) -->",
                           all.size(), targetCount, danglingCount );
            w.write( hdr );
            w.write( "<notes>" );
            for( std::size_t i = 0; i < all.size(); )
            {
                std::size_t j = i;
                while( j < all.size() && all[j].target == all[i].target )
                {
                    ++j;
                }
                const bool dangling = ( live.find( all[i].target ) == live.end() );
                w.write( "<target id=\"" );  w.write( escapeXml( all[i].target, esc ) );
                w.write( dangling ? "\" dangling=\"1\">" : "\" dangling=\"0\">" );
                for( std::size_t k = i; k < j; ++k )
                {
                    appendOneNote( w, all[k], esc );
                }
                w.write( "</target>" );
                i = j;
            }
            w.write( "</notes></ctx>" );
        }
        std::fputc( '\n', stdout );
        return 0;
    }

    return std::nullopt;
}

// §L1 — the skipped verb's legend, hoisted to file scope. A 20-line string literal inside the emitter is
// 20 lines of runSkipped's measured LOC for zero branching, and this text is the reader's ONLY definition
// of every attribute below it, so it earns its own name. NB: a literal `--flag` spelling is illegal inside
// an XML comment (no `--` in a comment), so it names flags in prose and leans on the attribute names.
constexpr const char* kSkippedLegend =
    "<ctx><!-- ripwire skipped report: WHY the index does not contain a file, and which files it DOES contain but cannot"
                 " vouch for. Two row kinds. <f p= why= bytes= .../> = a file the crawl passed over, one row per drop, why= being"
                 " oversize (exceeded a size ceiling; limit= names which — the max-file-size flag's value in max_file_size=, or the fixed"
                 " .json/.yaml config ceilings that flag does not raise, json_ceiling=), excluded (matched an exclude substring; ext= is"
                 " its extension), or unsupported-ext (ext= has no grammar and no doc handler in this build — the class that hides a whole"
                 " LANGUAGE). <h p= why= .../> = a file that IS indexed and stays indexed, flagged for the reader: why=degraded-parse means"
                 " the parse contains ERROR/MISSING nodes (err= counts them, err_ratio= is the share of the file's bytes covered by top-most"
                 " ERROR spans) and is a PARSER-STATE fact, never a syntax verdict — a valid file in a dialect this grammar predates reads"
                 " degraded too; why=minified-suspect means whitespace frequency ws_freq= is under 0.070 across the leading 4096 bytes"
                 " (files under 256 bytes are never flagged — too little text to judge). Nothing here is dropped by these two flags."
                 " <lang n= files= symbols=/> = corpus composition BY LANGUAGE: one row per language this build extracted at"
                 " least one symbol OR one file for, sorted files DESC then name ASC, absent languages simply not rowed. files= is a"
                 " FLOOR (derived from symbol-bearing files only — a file with zero extracted symbols is not attributed to any"
                 " language); symbols= is exact, every run. unindexed= (below) is its mirror: languages this build could not read at"
                 " all; this is what it DID read, broken down."
                 " HEADER: indexed= is files= on the map; the ACCOUNTING INVARIANT is indexed= + oversize= + excluded= = the candidate"
                 " population the crawl ENUMERATED, at every ceiling and exclude setting. unsupported_ext= counts source/text-looking files"
                 " outside that population (binary/asset extensions are deliberately not counted — an unindexed .png is a picture, not a"
                 " language this build failed to read); its per-extension breakdown is the <e x= files=/> rows, which the map header rolls"
                 " up as unindexed= — a TOP-6 list, and the map's unindexed_exts= beside it names how many DISTINCT such"
                 " extensions exist, present exactly when that list was cut and absent when it is complete."
                 " excluded_dirs= counts SUBTREES an exclude pruned: the walk stopped at the directory, so how many files"
                 " are under them is UNKNOWN, not zero, and they are in no count here. pruned_dirs= counts the subtrees this build ALWAYS"
                 " prunes by policy — the committed noise/vendor/build denylist and any directory holding a CMakeCache.txt — with the same"
                 " consequence: the walk stopped there, their contents are UNKNOWN rather than zero, and they are in no count here. The two"
                 " are separate because the answer to \"why is my tree missing\" differs: one is a rule you passed, the other is a rule this"
                 " build carries. degraded_parse= / minified_suspect= count the h rows."
                 " unmeasured= counts indexed files this run never parsed (a doc-format file extracted by the doc pass, a binary sniff or"
                 " nesting guard refusal, a read failure) — they are absent from the health counts, not clean. rows_capped=\"1\" means a row"
                 " list hit its 500-row ceiling, so the rows are a SAMPLE of the count beside them; every count stays exact. A zero means"
                 " none found. -->";

// §L1 — one indexed file the health pass flagged. `fileIndex` indexes IngestResult::files.
struct SkipHealthFinding
{
    std::size_t fileIndex = 0;
    bool        degraded  = false;   // the parse holds ERROR/MISSING nodes
    bool        minified  = false;   // whitespace frequency under the threshold
};

// §L1 — the health pass's whole answer: the flagged files, plus the three counts the root discloses.
struct SkipHealthReport
{
    std::vector<SkipHealthFinding> findings;
    std::size_t                    degraded   = 0;
    std::size_t                    minified   = 0;
    std::size_t                    unmeasured = 0;   // indexed but never parsed — NOT the same as clean
};

// §L1 — classify every indexed file's recorded health against the two disclosure thresholds.
//
// The thresholds live HERE and not in ingest deliberately: the ingest carries facts (error-node counts,
// whitespace counts), this carries the presentation choice about where to draw a line, and keeping the two
// apart is what lets the legend state the threshold beside the raw numbers a reader would use to
// second-guess it. Cheap — four u32s per file, no I/O.
//
// fileBytes == 0 is the ingest's NOT-MEASURED sentinel (an indexed file always has a size): the file was
// never parsed — a doc-format file the doc post-pass extracted, a binary-sniff or nesting-guard refusal, a
// read failure. Those are counted as unmeasured and are absent from the other two counts, because "we did
// not look" is not "we looked and it was clean".
SkipHealthReport classifySkipHealth( const rw::IngestResult& ing )
{
    using namespace rw;
    SkipHealthReport out;
    for( std::size_t f = 0; f < ing.files.size(); ++f )
    {
        const FileHealth h = f < ing.fileHealth.size() ? ing.fileHealth[ f ] : FileHealth{};
        if( h.fileBytes == 0 )
        {
            ++out.unmeasured;
            continue;
        }
        const std::size_t   sample   = h.fileBytes < kHealthWsSampleBytes ? h.fileBytes : kHealthWsSampleBytes;
        const std::uint32_t wsPerMil = sample == 0 ? 1000u : std::uint32_t( ( std::uint64_t( h.wsBytes ) * 1000ull ) / sample );
        const bool          degraded = h.errNodes > 0;
        const bool          minified = h.fileBytes >= kMinifiedMinBytes && wsPerMil < kMinifiedWsPerMille;
        out.degraded += degraded ? 1u : 0u;
        out.minified += minified ? 1u : 0u;
        if( degraded || minified )
        {
            out.findings.push_back( { f, degraded, minified } );
        }
    }
    return out;
}

// §L1 — the <f why="oversize"> rows (§P0.5d's original population), each carrying the ceiling that dropped
// it so `bytes > limit` is self-evident per row.
// R-E (2026-08-17 harvest): rootPrefix empty ⇒ p= keeps sk.path unchanged (multi-root, or no single root to
// strip) — sk.path/sf.path/hr's ing.files[] lookup below are already-materialized copies of the crawl's own
// spelling (see emitGrepReport's note), so this relativizes them at PRINT time, same convention every other
// lens's pathRel uses.
void writeOversizeRows( rw::XmlWriter& w, std::vector<char>& esc, const std::vector<rw::SkippedOversize>& rows,
                        std::string_view rootPrefix = {} )
{
    for( const rw::SkippedOversize& sk : rows )
    {
        char row[ 96 ];
        const std::string_view rp = rootPrefix.empty() ? std::string_view( sk.path ) : rw::sarif::rootRelativeUri( sk.path, rootPrefix );
        w.write( "<f p=\"" );  w.write( rw::escapeXml( rp, esc ) );
        std::snprintf( row, sizeof( row ), "\" why=\"oversize\" bytes=\"%llu\" limit=\"%llu\"/>",
                       ( unsigned long long ) sk.sizeBytes, ( unsigned long long ) sk.limitBytes );
        w.write( row );
    }
}

// §L1 — the <f> rows for the two non-size drop classes. `why` is a caller-supplied literal from a CLOSED
// vocabulary (excluded / unsupported-ext), never data — see test/fixedbufsweep.sh's row for this buffer.
void writeDropRows( rw::XmlWriter& w, std::vector<char>& esc, const std::vector<rw::SkippedFile>& rows, const char* why,
                    std::string_view rootPrefix = {} )
{
    for( const rw::SkippedFile& sf : rows )
    {
        char row[ 96 ];
        const std::string_view rp = rootPrefix.empty() ? std::string_view( sf.path ) : rw::sarif::rootRelativeUri( sf.path, rootPrefix );
        w.write( "<f p=\"" );  w.write( rw::escapeXml( rp, esc ) );
        std::snprintf( row, sizeof( row ), "\" why=\"%s\" bytes=\"%llu\" ext=\"", why, ( unsigned long long ) sf.sizeBytes );
        w.write( row );
        w.write( rw::escapeXml( sf.ext, esc ) );
        w.write( "\"/>" );
    }
}

// §L1 — the <e> rows: the FULL unindexed-extension histogram. Uncapped here on purpose; the map header's
// unindexed= is the capped roll-up, and this verb is the surface a reader comes to for the whole list.
void writeUnindexedExtRows( rw::XmlWriter& w, std::vector<char>& esc, const std::vector<rw::UnindexedExt>& rows )
{
    for( const rw::UnindexedExt& ue : rows )
    {
        char row[ 64 ];
        w.write( "<e x=\"" );  w.write( rw::escapeXml( ue.ext, esc ) );
        std::snprintf( row, sizeof( row ), "\" files=\"%llu\"/>", ( unsigned long long ) ue.files );
        w.write( row );
    }
}

// §L1 — the <h> rows: files that ARE indexed and STAY indexed, flagged for the reader. Both raw numbers and
// both ratios are emitted on every row, whichever class fired, so a reader can second-guess either
// threshold without re-running anything. err_ratio is over the FILE's bytes; ws_freq is over the leading
// sample, which is its own denominator — hence two ratios and not one.
void writeHealthRows( rw::XmlWriter& w, std::vector<char>& esc, const rw::IngestResult& ing,
                      const std::vector<SkipHealthFinding>& findings, std::string_view rootPrefix = {} )
{
    for( const SkipHealthFinding& hr : findings )
    {
        const rw::FileHealth h       = ing.fileHealth[ hr.fileIndex ];
        const std::size_t    sample  = h.fileBytes < rw::kHealthWsSampleBytes ? h.fileBytes : rw::kHealthWsSampleBytes;
        const double         errFrac = double( h.errBytes ) / double( h.fileBytes );
        const double         wsFrac  = sample == 0 ? 1.0 : double( h.wsBytes ) / double( sample );
        char row[ 192 ];
        const std::string_view rp = rootPrefix.empty() ? std::string_view( ing.files[ hr.fileIndex ] ) : rw::sarif::rootRelativeUri( ing.files[ hr.fileIndex ], rootPrefix );
        w.write( "<h p=\"" );  w.write( rw::escapeXml( rp, esc ) );
        std::snprintf( row, sizeof( row ), "\" why=\"%s%s%s\" err=\"%u\" err_ratio=\"%.3f\" ws_freq=\"%.3f\" bytes=\"%u\"/>",
                       hr.degraded ? "degraded-parse" : "",
                       ( hr.degraded && hr.minified ) ? "," : "",
                       hr.minified ? "minified-suspect" : "",
                       h.errNodes, errFrac, wsFrac, h.fileBytes );
        w.write( row );
    }
}

// W3-S item 3 (2026-08-19) — corpus composition BY LANGUAGE. §L1 answers "what did the crawl DROP" in
// full (unindexed=, the <e>/<f>/<h> rows above); nothing answers "what IS this corpus, by language" —
// unindexed= names languages the build could not read at all, but a reader still cannot tell a
// 90%-Python repo from a 90%-C++ one from anything the tool prints. One count per rw::Lang, sorted
// deterministically (never hash-map iteration order — the same discipline unindexedExts' own
// lessUnindexedExt follows).
//
// files= is derived from SYMBOLS, not a second file-extension table: every symbol already carries the
// exact Lang ingest assigned it (Symbol::lang, ingest.cpp's real per-file grammar decision — the single
// source of truth), so re-deriving language from a hand-mirrored extension list (the way lintrules.h's
// langOfPath admittedly does, "kept in sync by hand", for its OWN narrower dependency-analysis purpose)
// would risk a SECOND, drifting classification for the same fact. Trade-off, stated once rather than
// buried in a caveat comment: a file that produced zero symbols (empty, or a language whose grammar
// found nothing extractable) is not attributed to any language row here. This under-counts files= by
// exactly that population — never inflates it, and never silently double-counts — so files= is a FLOOR
// on any given language's true file count, same convention as skipped_oversize=/unindexed= use
// elsewhere in this file (never a fabricated total). symbols= has no such gap: it is the exact,
// already-computed Symbol::lang tally, a total on every run.
struct LangCount { rw::Lang lang; std::uint64_t files = 0, symbols = 0; };

// files DESC, name ASC tiebreak — the SAME mixed-direction swapped-std::tie shape lessUnindexedExt
// (model.h) uses, so a reader who has already learned that ordering reads this one for free.
bool lessLangCount( const LangCount& a, const LangCount& b ) noexcept
{
    const std::string_view an = rw::langTag( a.lang ), bn = rw::langTag( b.lang );
    return std::tie( b.files, an ) < std::tie( a.files, bn );
}

std::vector<LangCount> computeLangCounts( const rw::IngestResult& ing )
{
    using namespace rw;
    // fileLangOf[f] = the Lang every symbol in file f agrees on (ingest parses one file under one
    // grammar, Metal/CUDA's C++/CUDA-as-a-language routing included, so there is nothing to disambiguate
    // — the last write among a file's own symbols is the same value every earlier one already wrote).
    std::vector<Lang> fileLangOf( ing.files.size(), Lang::Unknown );
    std::array<std::uint64_t, std::size_t( Lang::Lua ) + 1> symbolTally {};   // sized on the LAST enum member
    for( const Symbol& s : ing.symbols )
    {
        if( s.fileId < fileLangOf.size() )
        {
            fileLangOf[ s.fileId ] = s.lang;
        }
        if( std::size_t( s.lang ) < symbolTally.size() )
        {
            ++symbolTally[ std::size_t( s.lang ) ];
        }
    }
    std::array<std::uint64_t, std::size_t( Lang::Lua ) + 1> fileTally {};     // sized on the LAST enum member
    for( Lang l : fileLangOf )
    {
        if( l != Lang::Unknown && std::size_t( l ) < fileTally.size() )
        {
            ++fileTally[ std::size_t( l ) ];
        }
    }
    std::vector<LangCount> out;
    for( std::size_t i = 0; i < fileTally.size(); ++i )
    {
        if( fileTally[i] == 0 && symbolTally[i] == 0 )
        {
            continue;   // absent = this language contributed nothing, never a printed zero row
        }
        out.push_back( { Lang( i ), fileTally[i], symbolTally[i] } );
    }
    std::sort( out.begin(), out.end(), lessLangCount );
    return out;
}

void writeLangRows( rw::XmlWriter& w, std::vector<char>& esc, const std::vector<LangCount>& rows )
{
    for( const LangCount& lc : rows )
    {
        char row[ 64 ];
        w.write( "<lang n=\"" );  w.write( rw::escapeXml( rw::langTag( lc.lang ), esc ) );
        std::snprintf( row, sizeof( row ), "\" files=\"%llu\" symbols=\"%llu\"/>",
                       ( unsigned long long ) lc.files, ( unsigned long long ) lc.symbols );
        w.write( row );
    }
}

// §P0.5d / §L1 — --skipped: WHY the index does not contain a file, and which files it DOES contain but
// cannot vouch for. The disclosure doctrine ("every truncation is disclosed") applied to the corpus itself.
//
// §P0.5d built this verb around ONE drop reason: the header said HOW MANY files a size ceiling dropped and
// this verb named WHICH. §L1 closes what that left open — the verb answered `oversize="0"` on a tree it had
// passed over wholesale, which reads as "index complete" and is the honesty contract's own failure mode (a
// zero meaning "none exists" rather than "none found"). Two additions, both measured against real corpora:
//
//   * the DROP taxonomy grows why=excluded and why=unsupported-ext beside why=oversize. The second is the
//     load-bearing one: it is how a whole LANGUAGE disappears. On facebook/infer (11 923 files, ~60% OCaml,
//     which this build has no grammar for) the map's top-ranked symbols were meaningless test fixtures and
//     nothing anywhere said the primary language had contributed nothing.
//   * a SECOND row kind, <h>, for files that ARE indexed and stay indexed but whose extraction cannot be
//     vouched for: degraded-parse (ERROR/MISSING nodes in the tree) and minified-suspect (whitespace
//     frequency under the threshold). Run over 252 deliberately-invalid Python files this verb used to
//     report a clean bill of health while every symbol it had drawn from them was garbage. NOTHING is
//     dropped by either flag — this lane only ever adds disclosure.
//
// The binary-sniff and read-failure parse skips are still deliberately NOT drop rows: those files keep their
// fileId and stay inside files=. They now surface as unmeasured= instead — present in the corpus, absent
// from the health counts, which is the honest position for a file that was never parsed.
// Read-only; exit 0 always: a report, not a gate.
std::optional<int> runSkipped( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;
    if( !cfg.skippedList )
    {
        return std::nullopt;
    }
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         skSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  skRootPrefix = skSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  skRootEsc;
    const std::string  skRootAttr   = skSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], skRootEsc ) ) + "\"" ) : std::string();

    {
        XmlWriter         w( stdout );
        std::vector<char> esc;

        const SkipHealthReport health = classifySkipHealth( ing );

        w.write( kSkippedLegend );
        char hdr[ 640 ];   // twelve counters, each up to 20 digits — sized well clear of a truncated count
        // mirror ingest()'s own zero-ceiling clamp so the header states the EFFECTIVE bound, never a raw 0
        const std::size_t effectiveMax = cfg.maxFileBytes == 0 ? kDefaultMaxFileBytes : cfg.maxFileBytes;
        const CrawlSkips& cs           = ing.crawlSkips;
        const bool        rowsCapped   = cs.excluded.size() < cs.excludedFiles || cs.unsupported.size() < cs.unsupportedFiles;
        std::snprintf( hdr, sizeof( hdr ),
                       "<skipped indexed=\"%zu\" oversize=\"%zu\" excluded=\"%llu\" unsupported_ext=\"%llu\" excluded_dirs=\"%llu\""
                       " pruned_dirs=\"%llu\""
                       " degraded_parse=\"%zu\" minified_suspect=\"%zu\" unmeasured=\"%zu\" max_file_size=\"%zu\" json_ceiling=\"%zu\""
                       " yaml_ceiling=\"%zu\"%s",
                       ing.files.size(), ing.skippedOversize.size(),
                       ( unsigned long long ) cs.excludedFiles, ( unsigned long long ) cs.unsupportedFiles,
                       ( unsigned long long ) cs.excludedDirs, ( unsigned long long ) cs.prunedDirs,
                       health.degraded, health.minified, health.unmeasured,
                       effectiveMax, kMaxJsonConfigBytes, kMaxYamlConfigBytes,
                       rowsCapped ? " rows_capped=\"1\"" : "" );
        w.write( hdr );
        // R-E: root= is unbounded (a deep absolute path), so it is NOT folded into the fixed `hdr` buffer
        // above (the V1-1 truncation class main.cpp's own history warns about) — written separately as the
        // std::string it already is, then the tag is closed.
        w.write( skRootAttr );
        w.write( ">" );

        writeOversizeRows( w, esc, ing.skippedOversize, skRootPrefix );
        writeDropRows( w, esc, cs.excluded,    "excluded", skRootPrefix );
        writeDropRows( w, esc, cs.unsupported, "unsupported-ext", skRootPrefix );
        writeUnindexedExtRows( w, esc, cs.unindexedExts );
        writeHealthRows( w, esc, ing, health.findings, skRootPrefix );
        writeLangRows( w, esc, computeLangCounts( ing ) );   // W3-S item 3: corpus composition by language
        w.write( "</skipped></ctx>" );
    }
    std::fputc( '\n', stdout );
    return 0;
}


// L1 — --merge-scout=REF[,REF...]: the read-only cross-branch overlap
// oracle. mergescout.h owns the computation (materialize-and-diff, pairwise conflicts/risks, greedy
// landing order); this handler just resolves the flag, refuses loudly on a bad REF, and writes the XML.
// The multi-root refusal for --merge-scout lives with its siblings (--quality-delta/--test-gate/etc.)
// earlier in main(), before the single-root ingest pipeline runs — this handler never sees roots.size()>=2.
std::optional<int> runMergeScout( const MainDispatch& d )
{
    using namespace rw;
    const Config&        cfg = d.cfg;
    const IngestResult&  ing = d.ing;
    const std::string&   root = d.root;

    if( cfg.mergeScoutFlag )
    {
        if( cfg.mergeScout.empty() )
        {
            std::fprintf( stderr, "ripwire: --merge-scout needs REF[,REF...] (e.g. --merge-scout=branchA,branchB)\n" );
            return 1;
        }
        const mergescout::ScoutResult result = mergescout::computeMergeScout( root, cfg.mergeScout, ing, cfg.excludes, cfg.maxFileBytes );
        if( !result.ok )
        {
            // X9(a): a non-git root gets its OWN message — there is no offending ref to name, and "unknown
            // ref ''" would be a confusing refusal for a completely different reason (no git history at all).
            if( result.nonGitRoot )
            {
                std::fprintf( stderr, "ripwire: --merge-scout: %s is not a git repository (or has no HEAD commit) — nothing to scout\n", root.c_str() );
            }
            else
            {
                std::fprintf( stderr, "ripwire: --merge-scout: unknown ref '%s'\n", result.badRef.c_str() );
            }
            return 1;
        }
        mergescout::writeMergeScout( stdout, result );
        return 0;
    }
    return std::nullopt;
}

// ── --plan-lanes ──────────────────────────────────────────────────────────────────────────────────────────
// lanes.h owns the whole computation — the claim key, the synthetic-arm composition onto merge-scout's own
// conflict machinery, the three pair classes, the landing order, the JSON emitter. This handler resolves the
// flags, refuses loudly (writing NOTHING to stdout — a refusal must not ship a payload), and supplies the two
// inputs lanes.h is deliberately not allowed to compute for itself: the lens RANKING (computeLensRanking is
// THE ranking implementation, per the "do not reimplement ranking" mandate) and the per-file churn lens.

// One non-blank line per lane — the whole --brief format in v1 (anything richer is a v2 question, driven by
// real orchestration friction rather than designed up front). `ok=false` ⇒ the path could not be opened.
struct BriefFile { std::vector<std::string> lines; bool ok = false; };

BriefFile readBriefFile( const std::string& path )
{
    BriefFile  out;
    std::FILE* fp = std::fopen( path.c_str(), "rb" );
    if( !fp )
    {
        return out; // caller refuses loudly, naming the path
    }
    out.ok = true;

    char buf[ 4096 ];
    while( std::fgets( buf, sizeof( buf ), fp ) )
    {
        std::string line( buf );
        while( !line.empty() && ( line.back() == '\n' || line.back() == '\r' ) )
        {
            line.pop_back();
        }
        const std::size_t first = line.find_first_not_of( " \t" );
        if( first == std::string::npos )
        {
            continue; // blank (or whitespace-only) → not a lane
        }
        out.lines.push_back( line.substr( first, line.find_last_not_of( " \t" ) - first + 1 ) );
    }
    std::fclose( fp );
    return out;
}

// The corpus header's own five numbers, read from the SAME places serialize.h's `<!-- files= symbols= edges=
// ambiguous= unresolved= -->` preamble reads them, so a plan and the map it describes can never disagree.
rw::lanes::CorpusStats laneCorpusStats( const rw::IngestResult& ing, const rw::Graph& g )
{
    rw::lanes::CorpusStats c;
    c.files   = ing.files.size();
    c.symbols = ing.symbols.size();
    c.edges   = g.outTargets.size();
    for( std::uint32_t v : g.ambOut )
    {
        c.ambiguous += v;
    }
    for( std::uint32_t v : g.unresolvedOut )
    {
        c.unresolved += v;
    }
    return c;
}

std::optional<int> runPlanLanes( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg  = d.cfg;
    const IngestResult& ing  = d.ing;
    const Graph&        g    = d.g;
    const std::string&  root = d.root;

    if( !cfg.planLanesFlag )
    {
        return std::nullopt;
    }

    // cli.h has already enforced task-XOR-brief and the 2..16 range on the auto-carve form. What is left to
    // refuse here is what only the tree can answer: an unreadable brief, a brief whose lane count is out of
    // range, and an empty corpus (nothing to carve, and a plan over nothing would read as a clean answer).
    lanes::LanesInputs in;
    in.ing   = &ing;
    in.g     = &g;
    in.root  = &root;
    in.notes = d.notesPtr;

    BriefFile brief;
    if( !cfg.laneBrief.empty() )
    {
        const std::string briefPath( cfg.laneBrief );
        brief = readBriefFile( briefPath );
        if( !brief.ok )
        {
            std::fprintf( stderr, "ripwire: --plan-lanes: cannot read --brief=%s\n", briefPath.c_str() );
            return 1;
        }
        if( brief.lines.size() < lanes::kMinLanes || brief.lines.size() > lanes::kMaxLanes )
        {
            std::fprintf( stderr, "ripwire: --plan-lanes --brief=%s has %zu non-blank line(s) — one line per lane, and the lane "
                                  "count must be %u..%u (1 is not a fan-out)\n",
                          briefPath.c_str(), brief.lines.size(), lanes::kMinLanes, lanes::kMaxLanes );
            return 1;
        }
        in.autoCarve = false;
        in.laneTasks = brief.lines;
        in.requested = std::uint32_t( brief.lines.size() );
    }
    else
    {
        in.autoCarve = true;
        in.task      = std::string( cfg.laneTask );
        in.requested = std::uint32_t( cfg.planLaneCount );
    }

    if( ing.symbols.empty() )
    {
        std::fprintf( stderr, "ripwire: --plan-lanes: no indexed symbols under %s — there is nothing to split into lanes\n", root.c_str() );
        return 1;
    }

    // the rankings — ONE per lane in brief mode, one for the whole task in auto-carve. Same computeLensRanking
    // --for and --pack-task use, so every routing/mention/doc-mention behaviour applies identically here.
    LensRanking                     carveRanking;
    std::vector<std::vector<float>> laneRanks;
    if( in.autoCarve )
    {
        carveRanking  = computeLensRanking( d, in.task );
        in.carveRank  = &carveRanking.rank;
    }
    else
    {
        laneRanks.reserve( in.laneTasks.size() );
        for( const std::string& laneTask : in.laneTasks )
        {
            laneRanks.push_back( computeLensRanking( d, laneTask ).rank );
        }
        in.laneRanks = &laneRanks;
    }

    // the churn axis of claims.files' hotspot data — the SAME `git log --name-only` window --hotspots ranks on.
    // A non-git root simply leaves it zero (every hotspot_rank then emits null, never a fabricated rank).
    std::vector<std::uint32_t> churn( ing.files.size(), 0u );
    if( !gitChurnCounts( root, ing, churn, "12 months ago" ) )
    {
        DEGRADED_PATH_ALERT( "plan-lanes: no git churn history for this root — claims.files churn/hotspot_rank report 0/null" );
    }
    in.churn  = &churn;
    in.tested = d.testedPtr;
    in.corpus = laneCorpusStats( ing, g );

    lanes::writePlanLanes( stdout, lanes::computePlanLanes( in ) );
    return 0;
}

// --with-history (src/gitoracle.h): build the name-history index for a verb that wants it, or an empty one
// when the flag is absent. ONE body for both consumers below — they had grown the same four lines each,
// including the same stderr note, which is exactly the clone this repo's own --quality-delta flags. The
// caller OWNS the returned index and must outlive every view of it (both handlers keep it on the stack for
// the whole compute-then-write sequence). `verbNote` names what degrades, so the message stays specific.
rw::gitoracle::HistoryIndex buildHistoryIndex( const rw::Config& cfg, const std::string& root, const char* verbNote )
{
    if( !cfg.withHistory )
    {
        return {};
    }

    rw::gitoracle::HistoryIndex idx = rw::gitoracle::probeNameHistory( root );
    if( idx.nonGitRoot )
    {
        std::fprintf( stderr, "ripwire: --with-history: %s has no git history — %s\n", root.c_str(), verbNote );
    }
    return idx;
}

// `--flags --flip=NAME` — one gate's flip blast radius. Its own handler (not a branch inside runCrossRef)
// because unlike every other verb in that group it is INDEX-backed on both sides: it joins the lexical gate
// harvest to the call graph, so it consumes d.ing AND d.g. cli.h already refused a bare --flip and a --flip
// without --flags; what is left to refuse here is a name that is not a gate in THIS tree — loudly, with the
// near-misses the compute pass found, never an empty-looking success.
int runFlip( const MainDispatch& d )
{
    using namespace rw;
    const std::string& root = d.root;

    // Single-root only, and REFUSED rather than answered wrong: the gate harvest reads each ingested file by
    // its ing.files spelling, which in a merged workspace is the LABELED identity path, not a path on disk —
    // so a multi-root run harvests zero gates. Plain --flags returns an empty-looking `gates="0"` there
    // (a pre-existing gap in that verb); --flip must not turn the same gap into "no gate named X".
    if( d.multiRoot )
    {
        std::fprintf( stderr, "ripwire: --flip is single-root only (the gate harvest reads on-disk paths, which a merged "
                              "workspace relabels) — run it once per root\n" );
        return 1;
    }

    const flipimpact::FlipResult result = flipimpact::computeFlip( d.ing, d.g, root, d.cfg.excludes, d.cfg.flipGate );
    if( !result.ok )
    {
        std::string msg = "ripwire: --flip: no gate named '" + std::string( d.cfg.flipGate ) + "' in " + root;
        if( !result.nearMisses.empty() )
        {
            msg += " (did you mean";
            for( std::size_t i = 0; i < result.nearMisses.size(); ++i )
            {
                msg += ( i ? ", '" : " '" ) + result.nearMisses[i] + "'";
            }
            msg += "?)";
        }
        std::fprintf( stderr, "%s\n", msg.c_str() );
        std::fprintf( stderr, "ripwire: run `ripwire %s --flags` for the gate table\n", root.c_str() );
        return 1;
    }
    flipimpact::writeFlip( stdout, result, d.ing, root, d.cfg.detail ? SIZE_MAX : flipimpact::kMaxFlipRows );
    return 0;
}

// `--stray-content --abi` — the cross-branch ABI-BREAK gate (abicheck.h). Its own handler (not inlined into
// runCrossRef) because unlike --stray-content/--whereis it IS index-backed on the HEAD side: it needs
// d.ing to enumerate which structs HEAD declares and to model their working-tree fields, the same baseline
// --layout itself reads. cli.h already refused a bare --abi (without --stray-content); what is left to
// refuse here is the ref-namespace/root shape --stray-content already refuses for the same reason.
int runAbiCheck( const MainDispatch& d )
{
    using namespace rw;
    const std::string& root = d.root;

    const abicheck::AbiResult result = abicheck::computeAbiCheck( root, d.ing, d.cfg.strayFilter );
    if( !result.ok )
    {
        if( result.nonGitRoot )
        {
            std::fprintf( stderr, "ripwire: --abi: %s is not a git repository (or has no HEAD commit) — no refs to compare\n", root.c_str() );
        }
        else
        {
            std::fprintf( stderr, "ripwire: --abi: more than %u refs match — narrow it with --stray-content=SUBSTR\n", crossref::kMaxRefs );
        }
        return 1;
    }
    // --detail=N is this verb's ONE "show me everything" lever: it lifts the per-ref display cap AND prints
    // the kinds the default triage counts but does not list (rename/spelling/stub/head-moved).
    const bool listAll = d.cfg.detail != 0;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — --abi
    // is single-root by construction (cli.h already refuses the multi-root shape upstream).
    const std::string_view abiRootArg = d.ing.realPaths.empty() ? std::string_view( root ) : std::string_view();
    abicheck::writeAbiCheck( stdout, result, listAll ? SIZE_MAX : abicheck::kMaxStructsPerRef, listAll, abiRootArg );
    return abicheck::abiContractBroken( result ) ? 2 : 0;   // exit 2 = a real byte-contract drift on some branch
}

// The CROSS-BRANCH content verbs: --stray-content and --whereis. Both are
// git-driven rather than index-driven — they read OTHER refs' blobs, which this process never ingested — so
// neither consumes `d.ing`/`d.g`; they take only the root. Both are single-root by the same reasoning
// --merge-scout is: "which branch has this" is a question about ONE repository's ref graph, and a merged
// multi-root graph has no single ref namespace to answer it in. The one exception is `--stray-content --plan`
// just below: it composes the sweep with --merge-scout, which DOES need `d.ing` (the working tree's own
// already-ingested IngestResult, for merge-scout's implicit dirty-working-tree arm) — same reasoning
// runMergeScout itself uses.
// §A7: every place the parsed index defines `name`, keyed the way git spells a tree entry (arch.h::relForHash
// — the SAME root-relative join --abi uses to match ing.files against git paths). This is what lets --whereis
// stop GUESSING on HEAD rows: the tree scan reads committed blobs, the index knows where the definitions are,
// and the join is a single pass over the symbol table with no extra I/O.
inline std::vector<rw::crossref::IndexDefSite> whereisIndexDefSites( const rw::IngestResult& ing, std::string_view name, const std::string& root )
{
    std::vector<rw::crossref::IndexDefSite> sites;
    for( const rw::Symbol& s : ing.symbols )
    {
        if( s.name == name )
        {
            sites.push_back( rw::crossref::IndexDefSite{ std::string( rw::relForHash( ing.files[ s.fileId ], root ) ), s.line } );
        }
    }
    return sites;
}

std::optional<int> runCrossRef( const MainDispatch& d )
{
    using namespace rw;
    const Config&      cfg  = d.cfg;
    const std::string& root = d.root;

    if( cfg.strayContent && cfg.landingPlan )
    {
        if( d.multiRoot )
        {
            std::fprintf( stderr, "ripwire: --plan is single-root only (one repo = one ref namespace) — run it per root\n" );
            return 1;
        }
        const landingplan::PlanResult result = landingplan::computePlan( root, cfg.strayFilter, d.ing, cfg.excludes, cfg.maxFileBytes,
                                                                          cfg.detail ? SIZE_MAX : landingplan::kMaxPlanScout );
        if( !result.ok )
        {
            if( result.nonGitRoot )
            {
                std::fprintf( stderr, "ripwire: --plan: %s is not a git repository (or has no HEAD commit) — no refs to compare\n", root.c_str() );
            }
            else
            {
                std::fprintf( stderr, "ripwire: --plan: more than %u refs match — narrow it with --stray-content=SUBSTR\n", crossref::kMaxRefs );
            }
            return 1;
        }
        landingplan::writePlan( stdout, result );
        return 0;
    }

    if( cfg.strayContent )
    {
        if( d.multiRoot )
        {
            std::fprintf( stderr, "ripwire: --stray-content is single-root only (one repo = one ref namespace) — run it per root\n" );
            return 1;
        }
        if( cfg.abiFlag )
        {
            return runAbiCheck( d ); // --stray-content --abi: the cross-branch ABI-break gate
        }
        const crossref::StrayResult result = crossref::computeStrayContent( root, cfg.strayFilter );
        if( !result.ok )
        {
            if( result.nonGitRoot )
            {
                std::fprintf( stderr, "ripwire: --stray-content: %s is not a git repository (or has no HEAD commit) — no refs to compare\n", root.c_str() );
            }
            else
            {
                std::fprintf( stderr, "ripwire: --stray-content: more than %u refs match — narrow it with --stray-content=SUBSTR\n", crossref::kMaxRefs );
            }
            return 1;
        }
        // §P15/§P16: real paging over the outer, deterministically-sorted refs listing (see crossref.h's
        // writeStrayContentPage) — confirmed byte-stable across repeated runs on this repo before migrating.
        crossref::writeStrayContentPage( stdout, result, cfg.detail ? SIZE_MAX : crossref::kStrayFilesPerRef,
                                         cfg.pageLimit, cfg.pageOffset );
        return 0;
    }

    if( !cfg.evalStray.empty() )
    {
        const crossref::EvalReport rep = crossref::evalStray( root, std::string( cfg.evalStray ) );
        if( !rep.ok )
        {
            std::fprintf( stderr, "ripwire: --eval-stray: cannot read '%.*s', or %s is not a git repository\n",
                          int( cfg.evalStray.size() ), cfg.evalStray.data(), root.c_str() );
            return 1;
        }
        crossref::writeStrayEval( stdout, rep );
        return ( rep.correct == rep.cases.size() ) ? 0 : 3;   // exit 3 = some labelled case regressed
    }

    if( cfg.darkFlags )
    {
        if( cfg.flipFlag )
        {
            return runFlip( d ); // --flags --flip=NAME: one gate's radius
        }
        const darkflags::FlagsResult result = darkflags::computeFlags( d.ing, root, cfg.excludes, cfg.darkFlagsFilter );
        darkflags::writeFlags( stdout, result, cfg.detail ? SIZE_MAX : darkflags::kMaxSitesShown );
        return 0;
    }

    if( cfg.whereisFlag )
    {
        if( cfg.whereis.empty() )
        {
            std::fprintf( stderr, "ripwire: --whereis needs a symbol (e.g. --whereis=adoptValidatedLowBandContours)\n" );
            return 1;
        }
        if( d.multiRoot )
        {
            std::fprintf( stderr, "ripwire: --whereis is single-root only (one repo = one ref namespace) — run it per root\n" );
            return 1;
        }
        // --with-history: ONE git-history walk (memoized per repo+HEAD sha), giving --whereis the lane a tree
        // scan structurally cannot have — whether HEAD's history ever REMOVED this name. Owned here, in the
        // handler, so the index outlives both the compute and the write that hold non-owning views of it.
        const gitoracle::HistoryIndex history = buildHistoryIndex( cfg, root, "the fate lane reports probed=\"0\"" );

        // §A7: HEAD's rows are documented as the PARSED answer, so hand the tree scan what the index knows.
        const std::vector<crossref::IndexDefSite> indexDefs = whereisIndexDefSites( d.ing, cfg.whereis, root );

        const crossref::WhereResult result = crossref::computeWhereis( root, cfg.whereis, cfg.strayFilter,
                                                                       crossref::WhereisEvidence{ cfg.withHistory ? &history : nullptr, indexDefs } );
        if( !result.ok )
        {
            std::fprintf( stderr, "ripwire: --whereis: %s is not a git repository (or has no HEAD commit) — no refs to search\n", root.c_str() );
            return 1;
        }
        crossref::writeWhereisPage( stdout, result, cfg.detail ? SIZE_MAX : crossref::kWhereisHits, cfg.pageLimit, cfg.pageOffset );
        return 0;
    }
    return std::nullopt;
}

// --doc-drift[=SUBSTR]: the markdown docs' CHECKABLE anchors, verified
// against the live index. Index-backed (it needs the crawled file list and the symbol table), so unlike the
// cross-branch verbs above it DOES consume `d.ing` — and unlike them it is multi-root safe: every anchor is
// resolved through the same labeled file identities the rest of the pipeline uses. Always exits 0; drift is
// a report, not a gate (a doc is allowed to be behind while you are mid-change).
std::optional<int> runDocDrift( const MainDispatch& d )
{
    using namespace rw;
    if( !d.cfg.docDrift )
    {
        return std::nullopt;
    }

    // --with-history (opt-in): the git-history name oracle that splits the mention lane's why="undefined"
    // into "this repo deleted it" (rot) and "this repo never had it" (a plan doc naming unbuilt work, not
    // rot). Owned here so both the compute and the write hold non-owning views; without the flag this is an
    // empty index and a nullptr, which is byte-for-byte the pre-flag behaviour.
    const gitoracle::HistoryIndex history =
        buildHistoryIndex( d.cfg, d.root, "the mention lane falls back to why=\"undefined\"" );

    const docdrift::DriftResult result = docdrift::computeDocDrift( d.ing, d.root, d.cfg.excludes, d.cfg.docDriftFilter,
                                                                    d.cfg.withHistory ? &history : nullptr );
    docdrift::writeDocDriftPage( stdout, result, d.cfg.detail ? SIZE_MAX : docdrift::kMaxAnchorsShown, d.cfg.gateabilityFlag,
                                 d.cfg.pageLimit, d.cfg.pageOffset );
    return 0;
}

// The CPU/GPU CONTRACT verb: --layout=STRUCT. layout.h owns the whole
// computation (the lexical field walk, the offset arithmetic, the static_assert sweep, the mirror diff);
// this handler resolves the flag, refuses loudly on a bare/unknown name, and maps the verdict to an exit
// code. Deliberately MULTI-ROOT capable — "does the service's copy of this struct still match the client's"
// is exactly a merged-graph question, and the mirror check is the reason the field note asked for it.
std::optional<int> runLayout( const MainDispatch& d )
{
    using namespace rw;
    const Config& cfg = d.cfg;

    if( !cfg.layoutFlag )
    {
        return std::nullopt;
    }

    if( cfg.layoutStruct.empty() )
    {
        std::fprintf( stderr, "ripwire: --layout needs a struct/class name (e.g. --layout=AudioUniforms, or --layout=file.h:Name)\n" );
        return 1;
    }

    const layout::LayoutResult result = layout::computeLayout( d.ing, cfg.layoutStruct );
    if( !result.found )
    {
        // Three very different refusals. A name that IS indexed but carries no C-family aggregate body is a
        // Python/Java/Go/Rust/Swift class or a forward declaration — saying "no such struct" there would be
        // flatly wrong and send the reader hunting for a spelling mistake that does not exist. An `enum`/
        // `enum class`/`enum struct` (§P6.11) is its own case, named explicitly: it used to fall through to
        // findDefBody's generic aggregate scan (a scoped enum's head contains the word "class"/"struct" too)
        // and silently degrade to a confident modeled="1" zero-field struct instead of refusing.
        if( result.enumCandidates > 0 )
        {
            std::fprintf( stderr, "ripwire: --layout: '%.*s' is an enum, --layout models structs (a scoped/unscoped enum's underlying type is not a byte layout)\n",
                          int( cfg.layoutStruct.size() ), cfg.layoutStruct.data() );
        }
        else if( result.bodilessCandidates > 0 )
        {
            std::fprintf( stderr, "ripwire: --layout: '%.*s' is indexed but has no C-family aggregate body — this verb models C/C++/ObjC byte layout only\n",
                          int( cfg.layoutStruct.size() ), cfg.layoutStruct.data() );
        }
        else
        {
            std::fprintf( stderr, "ripwire: --layout: no indexed struct/class named '%.*s' (try --grep=%.*s to find its spelling)\n",
                          int( cfg.layoutStruct.size() ), cfg.layoutStruct.data(),
                          int( cfg.layoutStruct.size() ), cfg.layoutStruct.data() );
        }
        return 1;
    }
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const std::string_view layoutRootArg = ( d.ing.realPaths.empty() && cfg.roots.size() == 1 ) ? cfg.roots[0] : std::string_view();
    layout::writeLayout( stdout, result, layoutRootArg );
    return layout::layoutContractBroken( result ) ? 2 : 0;   // exit 2 = mirror drift or a contradicted tripwire
}

// --field-affinity[=STRUCT]: the CACHE-LOCALITY lens. src/fieldaffinity.h owns the whole computation (the
// aggregate modelling pass, the member-access enumeration, the affinity graph, Chilimbi's separation weight
// and the two findings); this handler resolves the flag, refuses a filter that names nothing modelable, and
// emits. Exit 0 ALWAYS on a successful run — this is a report and its findings are ADVICE, so wiring it to a
// non-zero exit would make a non-monotonic axis (see the header's Go-fieldalignment caution) into a gate.
// Single-root by construction: the offset model reads on-disk paths, which a merged workspace relabels.
std::optional<int> runFieldAffinity( const MainDispatch& d )
{
    using namespace rw;
    const Config& cfg = d.cfg;

    if( !cfg.fieldAffinity )
    {
        return std::nullopt;
    }
    if( d.multiRoot )
    {
        std::fprintf( stderr, "ripwire: --field-affinity is single-root only (the offset model reads on-disk paths, "
                              "which a merged workspace relabels) — run it once per root\n" );
        return 1;
    }

    const fieldaffinity::AffResult res =
        fieldaffinity::computeFieldAffinity( d.ing, d.fanIn, cfg.fieldAffinityStruct );

    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — always
    // true here (the multi-root refusal above already returned), but ing.realPaths.empty() is still the
    // canonical guard so this cannot silently diverge if that invariant ever changes.
    const bool         faSingleRoot = d.ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  faRootPrefix = faSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  faRootEsc;
    const std::string  faRootAttr   = faSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], faRootEsc ) ) + "\"" ) : std::string();

    // A filter that matched no modelable aggregate is a REFUSAL, not an empty report: an empty
    // <fieldaffinity/> reads as "this struct has no co-access", which is a different and much stronger
    // claim than "this name never resolved to a C-family aggregate body this verb can model".
    if( !cfg.fieldAffinityStruct.empty() && res.rows.empty() && res.structsTotal == 0 )
    {
        std::fprintf( stderr, "ripwire: --field-affinity: no indexed C-family struct/class named '%.*s' with any attributed "
                              "field access (this verb models C/C++/ObjC only; try --layout=%.*s for its declared layout)\n",
                      int( cfg.fieldAffinityStruct.size() ), cfg.fieldAffinityStruct.data(),
                      int( cfg.fieldAffinityStruct.size() ), cfg.fieldAffinityStruct.data() );
        return 1;
    }

    fieldaffinity::writeFieldAffinity( stdout, res, faRootPrefix, faRootAttr );
    return 0;
}

// §A8.6: "how many communities count as a real module" — size>=2, i.e. NOT an isolated singleton. Shared by
// emitCommunitiesReport (below) and emitCommunityDrill's `modules=`, so the two verbs' modules= counts use
// the identical predicate and cannot drift into two different numbers under one attribute name.
std::uint32_t nonIsolatedModuleCount( const CommunityMembers& members )
{
    std::uint32_t modules = 0;
    for( const rw::SmallVec<rw::NodeId, 2>& mem : members )
    {
        if( mem.size() >= 2 )
        {
            ++modules;
        }
    }
    return modules;
}

// --communities: cluster the call graph into cohesive modules (Louvain) + cross-module bridge edges.
// Its own function (the named-verb-handler shape): §P8 added a
// real windowing step to the module row list, and the emitter was already the whole of runCommunities.
int emitCommunitiesReport( const rw::Config& cfg, const rw::IngestResult& ing, const rw::Graph& g )
{
    using namespace rw;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         cmSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  cmRootPrefix = cmSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  cmRootEsc;
    const std::string  cmRootAttr   = cmSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], cmRootEsc ) ) + "\"" ) : std::string();

    const rw::Communities   cm   = rw::communities( g );
    const auto [ rank, prIters, prConverged ] = rankGraph( g );
    const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this document is PageRank-ordered
    const std::uint32_t      K    = cm.count;
    const std::uint32_t      N    = std::uint32_t( ing.symbols.size() );

    CommunityMembers members( K );
    for( NodeId i = 0; i < N; ++i )
    {
        members[cm.comm[i]].push_back( i );
    }
    const CommunityPresentation presentation = communityPresentation( ing, g, members, rank, cmRootPrefix );

    HashMap<std::uint64_t, std::uint32_t> bridge;   // (min,max) community pair → inter-module edge count
    for( NodeId u = 0; u < N; ++u )
    {
        for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
        {
            const std::uint32_t cu = cm.comm[u], cv = cm.comm[ g.outTargets[k] ];
            if( cu == cv )
            {
                continue;
            }
            const std::uint32_t a = std::min( cu, cv ), b = std::max( cu, cv );
            ++bridge[ ( std::uint64_t( a ) << 32 ) | b ];
        }
    }

    // V6: rank mass (sum of PageRank over a community's members) is the primary ordering key — see
    // communityRankMass's comment for why raw size alone under-ranks small load-bearing hubs.
    std::vector<float> mass( K );
    for( std::uint32_t c = 0; c < K; ++c )
    {
        mass[c] = communityRankMass( members[c], rank );
    }
    std::vector<std::uint32_t> order( K );
    for( std::uint32_t c = 0; c < K; ++c )
    {
        order[c] = c;
    }
    std::sort( order.begin(), order.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return massSizeIdLess( a, b, mass, members ); } );

    const std::uint32_t modules  = nonIsolatedModuleCount( members );
    const IsolateStats  isolates = isolateStats( ing, g, members );

    // §P8: --limit/--offset were accepted and ignored — the listing always emitted the same 30 largest
    // modules. The row list is `order` filtered to real modules (size>=2), already deterministic
    // (V6: rank-mass desc, then size desc, then community id), so materialize it once and window it.
    // --limit raises or lowers the historic 30 cap; the bridge listing keeps its own 12 cap (it is a
    // second, independent report, not a continuation of the module rows), which is why shown_bridges=
    // keeps its own count.
    std::vector<std::uint32_t> moduleOrder;
    moduleOrder.reserve( modules );
    for( std::uint32_t c : order )
    {
        if( members[c].size() >= 2 )
        {
            moduleOrder.push_back( c );
        }
    }
    const PageWindow  cmpw = pageWindow( moduleOrder.size(), effectiveRowCap( cfg.pageLimit, 30 ), cfg.pageOffset );
    char              cmab[ 192 ];

    // §P8 vocabulary — src/pageview.h, THE TRUNCATION VOCABULARY, rules 1+3+6. TWO independent listings, so
    // the noun-prefixed shown_<noun>= form stays (a bare shown= cannot serve both) and each gains the
    // <noun>_capped="0|1" bit it lacked: shown_modules="30" beside modules="207" left the subtraction to
    // the caller. Only the module listing is --limit-windowed, so only it takes the paging half.
    //
    // §P8/N4: and ONLY the paging half — pagingDisclosure, not pageDisclosure. The full helper also emitted
    // a bare shown=/capped= for that same module listing, so a paged <communities> carried shown_modules="3"
    // AND shown="3" (always equal, by construction — both are cmpw's width). Two names for one fact is the
    // vocabulary drift §P8 exists to remove, and here it was worse than drift: a parser that summed the two
    // listings would double-count the modules. The noun-prefixed pair is the one rule 1 requires when
    // several listings coexist, so it is the one that survives.
    const std::uint32_t shownModules     = std::uint32_t( cmpw.end - cmpw.begin );
    const std::size_t   shownBridges     = std::min<std::size_t>( bridge.size(), 12 );
    const unsigned      isModulesCapped  = unsigned( shownModules < moduleOrder.size() );
    const unsigned      isBridgesCapped  = unsigned( shownBridges < bridge.size() );
    // §B8.1 (CA4): each <community> row printed size= beside a member listing silently cut at 5, with no
    // shown=/capped= companion — pageview.h rules 2+3, on the one listing in this report that lacked them
    // (the root's two listings have carried shown_<noun>=/<noun>_capped= since §P8). The drill verb on the
    // SAME module id emits shown=/capped= for the identical listing, so the two views of one module
    // disagreed about whether a cut had happened. Per rule 2, size= IS this element's total, so the pair is
    // the bare shown=/capped= form the drill verb uses, not a noun-prefixed one.
    std::printf( "<!-- ripwire communities: cohesive call-graph modules (Louvain); bridge=cross-module edges; isolated=call-graph-edgeless symbols; "
                 "drill= names the verb that takes an id= from a row below. On each module row size= is its TRUE member count while "
                 "shown=/capped= describe the member list printed here: this listing is fixed at the 5 top-ranked members and is NOT "
                 "widened by limit=/offset= (those page the MODULE rows). capped=1 means members were dropped; drill= names the verb "
                 "that pages the full member list of one module. raise the default cap with limit=N (offset=M pages). "
                 "%s-->%s", rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str(), rw::rootRelPathsLegend( cmSingleRoot ) );
    // §P11.6 drill=: the id= values below were the only identifiers this tool emitted that no verb took
    // back. The follow-up verb is named ON THE ROOT ELEMENT rather than in the doc comment, because an XML
    // comment may not contain a double hyphen (G4) and its entity escapes are NOT expanded — a caller would
    // read a literal "&#45;&#45;". As an attribute value the flag is exact, parseable and pasteable.
    std::printf( "<communities drill=\"--community=ID\" modules=\"%u\" shown_modules=\"%u\" modules_capped=\"%u\" bridges=\"%zu\" shown_bridges=\"%zu\" bridges_capped=\"%u\" isolated=\"%u\" isolated_decl=\"%u\" isolated_header=\"%u\" isolated_source=\"%u\" isolated_doc=\"%u\" connected_singletons=\"%u\" symbols=\"%u\"%s%s>",
                 modules, shownModules, isModulesCapped,
                 bridge.size(), shownBridges, isBridgesCapped, isolates.total, isolates.declaration,
                 isolates.header, isolates.source, isolates.document, isolates.connectedSingletons, N,
                 ( pagingDisclosure( cmab, sizeof( cmab ), moduleOrder.size(), cmpw.end, cfg.pageLimit, cfg.pageOffset )
                   + rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ) ).c_str(),
                 cmRootAttr.c_str() );
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    for( std::size_t moduleIndex = cmpw.begin; moduleIndex < cmpw.end; ++moduleIndex )
    {
        const std::uint32_t      c   = moduleOrder[ moduleIndex ];
        rw::SmallVec<NodeId, 2>& mem = members[c];
        std::sort( mem.begin(), mem.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );
        const std::size_t topN = std::min<std::size_t>( 5, mem.size() );
        std::printf( "<community id=\"%u\" size=\"%zu\" dir=\"%s\" label=\"%s\" shown=\"%zu\" capped=\"%u\">", c, std::size_t( mem.size() ),
                     ex( presentation.directory[c] ).c_str(), ex( presentation.label[c] ).c_str(),
                     topN, unsigned( topN < mem.size() ) );   // §B8.1: rules 2+3 — size= is the total, this pair is the cut
        for( std::size_t i = 0; i < topN; ++i )
        {
            const Symbol&           s  = ing.symbols[ mem[i] ];
            const std::string_view  rp = cmSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], cmRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            std::printf( "<member t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line );
        }
        std::printf( "</community>" );
    }
    std::vector<std::pair<std::uint64_t, std::uint32_t>> br( bridge.begin(), bridge.end() );
    std::sort( br.begin(), br.end(), []( const auto& a, const auto& b ) { return a.second != b.second ? a.second > b.second : a.first < b.first; } );
    const std::size_t topB = shownBridges;
    for( std::size_t i = 0; i < topB; ++i )
    {
        const std::uint32_t a = std::uint32_t( br[i].first >> 32 );
        const std::uint32_t b = std::uint32_t( br[i].first & 0xffffffffu );
        std::printf( "<bridge a=\"%u\" b=\"%u\" from_label=\"%s\" to_label=\"%s\" edges=\"%u\"/>", a, b,
                     ex( presentation.label[a] ).c_str(), ex( presentation.label[b] ).c_str(), br[i].second );
    }
    std::printf( "</communities>" );
    return 0;
}

std::optional<int> runCommunities( const MainDispatch& d )
{
    if( d.cfg.communities )
    {
        return emitCommunitiesReport( d.cfg, d.ing, d.g ); // body: emitCommunitiesReport() above
    }
    return std::nullopt;
}

// --community=ID (§P11.6): drill into ONE module. --communities and --zoom PRINT module ids and no verb
// ACCEPTED one — a 274-member module showed five members and the chain ended there. Those ids were the
// only identifiers the tool emitted that nothing took back, which is §P8's selector-chain gap at module
// granularity, on the two verbs whose entire output is module ids.
//
// The id space is the FULL Louvain partition (0..count-1), not the size>=2 subset --communities LISTS: an
// id is a fact about the partition, and refusing a legal-but-unlisted singleton would mean the drill-down
// disagreed with the clustering it drills into. A singleton simply reports size="1".
int emitCommunityDrill( const rw::Config& cfg, const rw::IngestResult& ing, const rw::Graph& g )
{
    using namespace rw;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         cdSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  cdRootPrefix = cdSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  cdRootEsc;
    const std::string  cdRootAttr   = cdSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], cdRootEsc ) ) + "\"" ) : std::string();

    const Communities   cm = communities( g );
    const std::uint32_t K  = cm.count;
    const std::uint32_t N  = std::uint32_t( ing.symbols.size() );

    // The id is a number or it is a typo — a non-numeric value must never be read as module 0. §P0: an id
    // outside the partition is a mistake, not an empty module, so the refusal names the legal range AND
    // the nearest legal id (the caller is holding a number and needs to know which numbers exist).
    std::uint64_t parsed  = 0;
    bool          numeric = !cfg.communityId.empty();
    for( char ch : cfg.communityId )
    {
        if( ch < '0' || ch > '9' ) { numeric = false; break; }
        parsed = std::min<std::uint64_t>( parsed * 10 + std::uint64_t( ch - '0' ), 0xffffffffull );
    }
    if( !numeric || parsed >= K )
    {
        if( K == 0 )
        { std::fprintf( stderr, "ripwire: --community: this corpus has no call-graph modules to drill into\n" );  return 1; }
        std::fprintf( stderr, "ripwire: --community: '%.*s' is not a module id — valid ids are 0..%u (the id= values --communities "
                              "and --zoom print); nearest valid id: %u\n",
                      int( cfg.communityId.size() ), cfg.communityId.data(), K - 1,
                      numeric ? K - 1 : 0u );
        return 1;
    }
    const std::uint32_t want = std::uint32_t( parsed );

    CommunityMembers members( K );
    for( NodeId i = 0; i < N; ++i )
    {
        members[cm.comm[i]].push_back( i );
    }

    // §A8.6: this root used to print the FULL partition size (K, isolated singletons included) under the
    // SAME attribute name (`modules=`) the parent uses for the non-isolated count — 9x apart on this repo.
    // `partition=` (below) now carries the full label space; `modules=` uses nonIsolatedModuleCount(), the
    // PARENT's exact predicate, so the two agree.
    const std::uint32_t modulesNonIsolated = nonIsolatedModuleCount( members );

    // dir=/label= come from the SAME communityPresentation the parent uses, so the two rows for one id
    // cannot drift into two derivations of "what is this module called".
    const auto [ rank, prIters, prConverged ] = rankGraph( g );
    const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this document is PageRank-ordered
    const CommunityPresentation presentation = communityPresentation( ing, g, members, rank, cdRootPrefix );

    rw::SmallVec<NodeId, 2>& mem = members[ want ];
    std::sort( mem.begin(), mem.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );

    // bridges: this module's cross-module edges only, counted per PEER module (both directions summed —
    // the parent's <bridge> is undirected too, so "how coupled are these two" means the same thing here).
    HashMap<std::uint32_t, std::uint32_t> peerEdges;
    for( NodeId u = 0; u < N; ++u )
    {
        for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
        {
            const std::uint32_t cu = cm.comm[u], cv = cm.comm[ g.outTargets[k] ];
            if( cu == cv )
            {
                continue;
            }
            if( cu == want )
            {
                ++peerEdges[cv];
            }
            else if( cv == want )
            {
                ++peerEdges[cu];
            }
        }
    }
    std::vector<std::pair<std::uint32_t, std::uint32_t>> peers( peerEdges.begin(), peerEdges.end() );
    std::sort( peers.begin(), peers.end(), []( const auto& a, const auto& b )
               { return a.second != b.second ? a.second > b.second : a.first < b.first; } );

    // §P8 / src/pageview.h: the MEMBER listing is the primary windowed one (rule 6) — this is the verb that
    // exists because five preview rows were not enough, so its cap must be raisable. The bridge listing is
    // independent and discloses through its own noun-prefixed pair.
    const PageWindow  mpw          = pageWindow( mem.size(), effectiveRowCap( cfg.pageLimit, 40 ), cfg.pageOffset );
    const std::size_t shownMembers = mpw.end - mpw.begin;
    const std::size_t shownBridges = std::min<std::size_t>( peers.size(), 12 );
    char              mpab[ kPageDisclosureCap ];
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    std::printf( "<!-- ripwire community: ONE module from the communities/zoom partition — its ranked members and its bridge edges to "
                 "other modules. size= is the module's TRUE member count; shown=/capped= are this page. partition= is the FULL label "
                 "space (every id 0..partition-1, incl. isolated singletons) — the range the id= argument ranges over; modules= counts "
                 "the NON-isolated communities (size>=2), the SAME predicate the communities-listing verb's modules= uses, so parent "
                 "and child agree. %s-->%s", rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str(), rw::rootRelPathsLegend( cdSingleRoot ) );
    std::printf( "<community id=\"%u\" size=\"%zu\" dir=\"%s\" label=\"%s\" bridges=\"%zu\" shown_bridges=\"%zu\" bridges_capped=\"%u\" partition=\"%u\" modules=\"%u\"%s%s>",
                 want, std::size_t( mem.size() ), ex( presentation.directory[ want ] ).c_str(), ex( presentation.label[ want ] ).c_str(),
                 peers.size(), shownBridges, unsigned( shownBridges < peers.size() ), K, modulesNonIsolated,
                 ( pageDisclosure( mpab, sizeof( mpab ), shownMembers, mem.size(), mpw.end, cfg.pageLimit, cfg.pageOffset, true )
                   + rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ) ).c_str(),
                 cdRootAttr.c_str() );
    for( std::size_t i = mpw.begin; i < mpw.end; ++i )
    {
        const Symbol&           s  = ing.symbols[ mem[i] ];
        const std::string_view  rp = cdSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], cdRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
        std::printf( "<member t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line );
    }
    for( std::size_t i = 0; i < shownBridges; ++i )
    {
        std::printf( "<bridge to=\"%u\" to_label=\"%s\" edges=\"%u\"/>", peers[i].first, ex( presentation.label[ peers[i].first ] ).c_str(), peers[i].second );
    }
    std::printf( "</community>" );
    return 0;
}

std::optional<int> runCommunityDrill( const MainDispatch& d )
{
    if( !d.cfg.communityFlag )
    {
        return std::nullopt;
    }
    if( d.cfg.communityId.empty() )
    {
        std::fprintf( stderr, "ripwire: --community needs a module ID — take one from the id= values --communities "
                              "or --zoom print, e.g. --community=12\n" );
        return 1;
    }
    return emitCommunityDrill( d.cfg, d.ing, d.g );
}

std::optional<int> runZoom( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;

    // --zoom[=depth]: the NESTED module hierarchy (multi-level Louvain) — contract each community into a
    // super-node and re-run Louvain, repeatedly, until the top has ≤10 modules (or `=depth` levels). Output is
    // an INDENTED tree (top module → child modules → … → the finest community's top-ranked symbols); each node
    // is labelled by its dominant directory + symbol count. Cross-module BRIDGES at the top level are always
    // shown, ranked by traffic. `--zoom --mermaid` emits the same hierarchy as a nested-subgraph diagram.
    // Deterministic: multiLevelCommunities is byte-stable (id-order local-moving at every level); the renderer
    // visits children/symbols in a fixed (V6: rank-mass desc, size desc, id asc / rank desc, id asc) order.
    if( cfg.zoom )
    {
        const std::uint32_t N = std::uint32_t( ing.symbols.size() );
        // depth: --zoom=D caps at D levels (≥1). default (0) = auto: contract until ≤10 top modules.
        const std::uint32_t maxLevels = cfg.zoomDepth > 0 ? std::uint32_t( cfg.zoomDepth ) : 8u;
        const std::uint32_t maxTop    = cfg.zoomDepth > 0 ? 1u : 10u;   // explicit depth ⇒ contract as far as the cap allows
        const rw::ZoomHierarchy h    = rw::multiLevelCommunities( g, maxTop, maxLevels );
        const auto [ rank, prIters, prConverged ] = rankGraph( g );
        const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this document is PageRank-ordered

        const std::size_t        L    = h.levels.size();                // ≥1 always (level 0 present)

        // per-level, per-group: member symbol ids (for size, dominant dir, and leaf top-symbols). members[l][gid].
        std::vector<CommunityMembers> members( L );
        for( std::size_t l = 0; l < L; ++l )
        {
            members[l].assign( h.counts[l], {} );
            for( NodeId i = 0; i < N; ++i )
            {
                members[l][h.levels[l][i]].push_back( i );
            }
        }

        // V6: per-level rank mass — see communityRankMass's comment (--communities uses the identical key)
        // and perLevelRankMass's comment (why this is precomputed once rather than per comparator call).
        const std::vector<std::vector<float>> mass = perLevelRankMass( members, rank );

        // children[l][gid] = the level-(l-1) groups whose parent is gid (l≥1). Inverts h.parentOf[l-1].
        std::vector<std::vector<std::vector<std::uint32_t>>> children( L );
        for( std::size_t l = 1; l < L; ++l )
        {
            children[l].assign( h.counts[l], {} );
            const std::vector<std::uint32_t>& par = h.parentOf[l - 1];   // level (l-1) group → level l group
            for( std::uint32_t cg = 0; cg < h.counts[l - 1]; ++cg )
            {
                children[l][par[cg]].push_back( cg );
            }
        }

        // dominant directory of a level-l group (most-frequent parent dir of its member files; ties → lexicographically first).
        const auto domDirOf = [ & ]( std::size_t l, std::uint32_t gid ) -> std::string
        {
            rw::HashMap<std::string, std::uint32_t> dirCount;
            for( NodeId n : members[l][gid] )
            {
                std::string_view  p  = ing.files[ ing.symbols[n].fileId ];
                const std::size_t sl = p.rfind( '/' );
                ++dirCount[ std::string( sl == std::string_view::npos ? p : p.substr( 0, sl ) ) ];
            }
            std::string d;  std::uint32_t best = 0;
            for( const auto& [dir, cnt] : dirCount )
            {
                if( cnt > best || ( cnt == best && dir < d ) )
                {
                    best = cnt;
                    d = dir;
                }
            }
            return d;
        };

        // top-level modules (groups with ≥2 symbols), highest rank-mass first, size- then id-tiebroken — the
        // same "a lone symbol is not a module" rule as --communities, and (V6) the same ordering key.
        const std::size_t        topL = L - 1;
        std::vector<std::uint32_t> topOrder;
        for( std::uint32_t gid = 0; gid < h.counts[topL]; ++gid )
        {
            if( members[topL][gid].size() >= 2 )
            {
                topOrder.push_back( gid );
            }
        }
        std::sort( topOrder.begin(), topOrder.end(),
                  [ & ]( std::uint32_t a, std::uint32_t b ) { return massSizeIdLess( a, b, mass[topL], members[topL] ); } );

        // top-level cross-module bridges (between the FINEST communities, summed onto top-module pairs), ranked.
        // We count finest-community→finest-community call edges, then lift each endpoint to its top-level module.
        const std::vector<std::uint32_t>& topOf = h.levels[topL];        // symbol → top module
        rw::HashMap<std::uint64_t, std::uint32_t> bridge;               // (min,max) top-module pair → edge count
        for( NodeId u = 0; u < N; ++u )
        {
            for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
            {
                const std::uint32_t tu = topOf[u], tv = topOf[ g.outTargets[k] ];
                if( tu == tv )
                {
                    continue;
                }
                const std::uint32_t a = std::min( tu, tv ), b = std::max( tu, tv );
                ++bridge[ ( std::uint64_t( a ) << 32 ) | b ];
            }
        }

        if( cfg.mermaid )
        {
            // nested-subgraph diagram: one subgraph per top module; its child modules (next-finer level) are
            // nodes inside; bridge edges connect top modules. Deterministic node ids = "L<level>_<gid>".
            // W2-F: mermaid has no attribute grammar — the note is emitted ONLY on the truncating exit, as a
            // mermaid COMMENT so the diagram still renders with the warning attached.
            std::printf( "%s", rw::renderDisclosure( prD, rw::DiscloseAs::MermaidNote ).c_str() );
            std::printf( "%%%% ripwire --zoom --mermaid: nested module hierarchy (multi-level Louvain). subgraph = top module, inner node = sub-module (dir, symbol count); edge = cross-module call count. Render at mermaid.live.\n" );
            std::printf( "flowchart TB\n" );
            std::vector<char> esc;
            const auto ex = [ & ]( std::string_view s ) -> std::string { std::string r( s ); for( char& ch : r ) { if( ch == '"' ) { ch = '\''; } } return r; };
            const std::size_t maxTopShown = std::min<std::size_t>( 10, topOrder.size() );
            for( std::size_t ti = 0; ti < maxTopShown; ++ti )
            {
                const std::uint32_t t = topOrder[ti];
                std::printf( "  subgraph sgL%zu_%u [\"%s<br/>%zu\"]\n", topL, t, ex( domDirOf( topL, t ) ).c_str(), std::size_t( members[topL][t].size() ) );
                if( topL >= 1 )
                {
                    std::vector<std::uint32_t> kids = children[topL][t];
                    std::sort( kids.begin(), kids.end(),
                              [ & ]( std::uint32_t a, std::uint32_t b ) { return massSizeIdLess( a, b, mass[topL - 1], members[topL - 1] ); } );
                    const std::size_t maxKids = std::min<std::size_t>( 8, kids.size() );
                    for( std::size_t ki = 0; ki < maxKids; ++ki )
                    {
                        std::printf( "    nL%zu_%u[\"%s<br/>%zu\"]\n", topL - 1, kids[ki], ex( domDirOf( topL - 1, kids[ki] ) ).c_str(), std::size_t( members[topL - 1][ kids[ki] ].size() ) );
                    }
                }
                else   // single-level (no coarsening happened): show the module's top symbols as inner nodes
                {
                    rw::SmallVec<NodeId, 2> mem = members[topL][t];
                    std::sort( mem.begin(), mem.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );
                    const std::size_t maxS = std::min<std::size_t>( 5, mem.size() );
                    for( std::size_t si = 0; si < maxS; ++si )
                    {
                        std::printf( "    sL%zu_%u_%zu[\"%s\"]\n", topL, t, si, ex( ing.symbols[ mem[si] ].name ).c_str() );
                    }
                }
                std::printf( "  end\n" );
            }
            std::vector<char> shownTop( h.counts[topL], 0 );
            for( std::size_t ti = 0; ti < maxTopShown; ++ti )
            {
                shownTop[topOrder[ti]] = 1;
            }
            std::vector<std::pair<std::uint64_t, std::uint32_t>> br( bridge.begin(), bridge.end() );
            std::sort( br.begin(), br.end(), []( const auto& a, const auto& b ) { return a.second != b.second ? a.second > b.second : a.first < b.first; } );
            for( const auto& [ key, w ] : br )
            {
                const std::uint32_t a = std::uint32_t( key >> 32 ), b = std::uint32_t( key & 0xffffffffu );
                if( !shownTop[a] || !shownTop[b] )
                {
                    continue;
                }
                std::printf( "  sgL%zu_%u -->|%u| sgL%zu_%u\n", topL, a, w, topL, b );
            }
            return 0;
        }

        // INDENTED text tree. recurse top → finer levels; at level 0 (finest community) list the top symbols.
        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // §B12.1 + §B8.1 (CA4). Two arithmetic silences on one screen, and neither is closeable from this
        // document: (1) symbols= counts the WHOLE corpus while the hierarchy holds only symbols that landed
        // in a top-level module of 2 or more — the difference (call-graph singletons) is the number the
        // sibling verb publishes as isolated= and this one published nowhere, so a reader summing the size=
        // values came up short with no clause to explain it; (2) each level-0 module printed size= beside a
        // member list silently cut at 5, with no shown=/capped= (pageview.h rules 2+3). isolated= here is
        // derived from THIS verb's own hierarchy (symbols minus the members of every top-level module,
        // shown or not), so the identity below is exact by construction rather than by agreeing with
        // another verb's independently-computed number.
        std::size_t inHierarchy = 0;
        for( std::uint32_t gid : topOrder )
        {
            inHierarchy += members[topL][gid].size();
        }
        const std::uint32_t isolatedCount = N - std::uint32_t( inHierarchy );
        std::printf( "<!-- ripwire zoom: NESTED module hierarchy (multi-level Louvain); indent = one level deeper; module = dominant-dir(symbol-count); leaf lists top-ranked symbols; bridge = cross-top-module call traffic. "
                     "symbols= is the whole corpus; isolated= is the symbols in NO top-level module (a group of one — the same rule that makes top_modules= count only groups of 2 or more), and they reconcile exactly: "
                     "symbols= equals isolated= plus the sum of the TOP-LEVEL size= values, every one of them, including any this page did not print. "
                     "On a level-0 module size= is its true member count and shown=/capped= describe the member list printed here, which is fixed at the 5 top-ranked members and is not widened by limit=/offset= (those page the TOP-LEVEL modules); "
                     "the community drill verb pages one module's full member list by its level-0 id. A module above level 0 lists every child module, so it carries no shown=/capped= pair. %s-->",
                     rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str() );
        // §P15/§P16: top_modules= is a real, deterministically-ordered row list (size desc, id asc — the same
        // rule --communities' module listing uses) that used to print EVERY top module unconditionally, so a
        // repo with hundreds of top modules had no way to page it. --limit/--offset now window it like --uses
        // (no historic display cap, discloseCap=false ⇒ the un-paginated tag is byte-identical). --mermaid is
        // a fixed-shape diagram, not a row list (its own hard-coded top-10/top-8/top-5 caps are unaffected —
        // honorsPaging() excludes the --zoom --mermaid combination for the same reason plain --mermaid refuses).
        const PageWindow  zoomPw = pageWindow( topOrder.size(), cfg.pageLimit, cfg.pageOffset );
        char              zoomAb[ kPageDisclosureCap ];
        std::printf( "<zoom levels=\"%zu\" top_modules=\"%zu\" symbols=\"%u\" isolated=\"%u\"%s>", L, topOrder.size(), N, isolatedCount,
                     ( pageDisclosure( zoomAb, sizeof( zoomAb ), zoomPw.end - zoomPw.begin, topOrder.size(), zoomPw.end,
                                       cfg.pageLimit, cfg.pageOffset, false )
                       + rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ) ).c_str() );

        // a stack-free recursion via an explicit lambda (std::function — not hot). Emits <module> elements
        // nested by level; the finest level emits <member> leaves.
        std::function<void( std::size_t, std::uint32_t )> emit = [ & ]( std::size_t l, std::uint32_t gid )
        {
            // §B8.1: the shown=/capped= pair belongs ONLY to the level-0 rows — they are the ones whose
            // listing is cut. A level>0 row emits every child module, so per rule 3 ("if a verb emits no
            // shown=, it emits no capped= either") it stays a bare size= row, and the legend says which is
            // which rather than leaving a reader to infer it from an absent attribute.
            const std::size_t leafShown = ( l == 0 ) ? std::min<std::size_t>( 5, members[0][gid].size() ) : 0;
            std::printf( "<module level=\"%zu\" id=\"%u\" size=\"%zu\" dir=\"%s\"", l, gid, std::size_t( members[l][gid].size() ), ex( domDirOf( l, gid ) ).c_str() );
            if( l == 0 )
            {
                std::printf( " shown=\"%zu\" capped=\"%u\"", leafShown, unsigned( leafShown < members[0][gid].size() ) );
            }
            std::printf( ">" );
            if( l == 0 )   // finest community → list its top-ranked symbols
            {
                rw::SmallVec<NodeId, 2> mem = members[0][gid];
                std::sort( mem.begin(), mem.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );
                const std::size_t topN = leafShown;
                for( std::size_t i = 0; i < topN; ++i )
                {
                    const Symbol& s = ing.symbols[ mem[i] ];
                    std::printf( "<member t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( ing.files[ s.fileId ] ).c_str(), s.line );
                }
            }
            else           // recurse into child modules (next-finer level), highest rank-mass first (V6)
            {
                std::vector<std::uint32_t> kids = children[l][gid];
                std::sort( kids.begin(), kids.end(),
                          [ & ]( std::uint32_t a, std::uint32_t b ) { return massSizeIdLess( a, b, mass[l - 1], members[l - 1] ); } );
                for( std::uint32_t cg : kids )
                {
                    emit( l - 1, cg );
                }
            }
            std::printf( "</module>" );
        };
        for( std::size_t ti = zoomPw.begin; ti < zoomPw.end; ++ti )
        {
            emit( topL, topOrder[ti] );
        }

        std::vector<std::pair<std::uint64_t, std::uint32_t>> br( bridge.begin(), bridge.end() );
        std::sort( br.begin(), br.end(), []( const auto& a, const auto& b ) { return a.second != b.second ? a.second > b.second : a.first < b.first; } );
        const std::size_t topB = std::min<std::size_t>( 12, br.size() );
        for( std::size_t i = 0; i < topB; ++i )
        {
            std::printf( "<bridge a=\"%u\" b=\"%u\" edges=\"%u\"/>", std::uint32_t( br[i].first >> 32 ), std::uint32_t( br[i].first & 0xffffffffu ), br[i].second );
        }
        std::printf( "</zoom>" );
        return 0;
    }
    return std::nullopt;
}

// §P11.8 — --tree is the session-start ORIENTATION map, and it emitted files in path order: the one order an
// orientation map must not use. On ripwire's own tree a cold agent's first 40 lines were audit-document
// section titles (long process-doc names, `AGENTS.md` among them — every one of them sorts above `src/`) and the
// code it had landed to read was pages down.
//
// Order files by their BEST symbol's rank instead — the same PageRank the per-file symbol list is already
// ordered by, so the file order and the row order finally agree on what "top" means. Path breaks ties, so the
// result is still a total, deterministic order (a sort has no tolerance band; the det-gate is what proves it,
// exactly as for the per-file symbol sort). One O(N) max-reduce, not a per-file sort: the symbol lists are
// still sorted only for the files the current page actually emits.
inline void orderFilesByBestSymbolRank( std::vector<std::uint32_t>& ford, const rw::IngestResult& ing,
                                        const std::vector<float>& rank )
{
    std::vector<float> bestRankByFile( ing.files.size(), -1.0f );
    for( rw::NodeId i = 0; i < ing.symbols.size(); ++i )
    {
        const std::uint32_t sf = ing.symbols[i].fileId;
        if( rank[i] > bestRankByFile[sf] )
        {
            bestRankByFile[sf] = rank[i];
        }
    }
    rw::orderIdsByKeyDescPathAsc( ford, bestRankByFile, ing.files );
}

std::optional<int> runStructureText( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::string&                root         = d.root;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         stSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  stRootPrefix = stSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  stRootEsc;
    const std::string  stRootAttr   = stSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], stRootEsc ) ) + "\"" ) : std::string();

    // --seams: cross-module call seams (community bridges) that NO test transitively reaches — the untested
    // inter-module connections. The graph-leveraged slice of testing: an integration test guards a seam
    // between two modules. A FACT (these edges are never exercised from a test), never a mandate to test them.
    if( cfg.seams )
    {
        const auto [ rank, prIters, prConverged ] = rankGraph( g );
        const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this document is PageRank-ordered
        const std::uint32_t      N    = std::uint32_t( ing.symbols.size() );

        // module = immediate parent DIRECTORY (the real subsystem) — NOT a Louvain community (one-level
        // Louvain is too fine; bridges land within one dir). A seam = a call edge crossing a dir boundary.
        std::vector<std::uint32_t> symDir;
        std::vector<std::string>   dirName;
        computeDirModules( ing, symDir, dirName, stRootPrefix );

        // testReach = everything transitively called from test files → a seam u→v is exercised if testReach[u]
        std::vector<NodeId> testSeeds;
        for( NodeId i = 0; i < N; ++i )
        {
            if( rw::isTestPath( ing.files[ing.symbols[i].fileId] ) )
            {
                testSeeds.push_back( i );
            }
        }
        const std::vector<char> testReach = rw::forwardReach( g, testSeeds );
        std::vector<char> isTestFile( ing.files.size(), 0 );
        for( NodeId s : testSeeds )
        {
            isTestFile[ing.symbols[s].fileId] = 1;
        }
        std::uint32_t testFileCount = 0;
        for( char c : isTestFile )
        {
            testFileCount += c;
        }

        // untested cross-directory edges, grouped by DIRECTED dir pair (caller-module → callee-module)
        struct SeamEdge { NodeId u, v; };
        HashMap<std::uint64_t, std::vector<SeamEdge>> grp;
        std::uint32_t bridges = 0, untested = 0;
        for( NodeId u = 0; u < N; ++u )
        {
            for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
            {
                const NodeId        v  = g.outTargets[k];
                const std::uint32_t du = symDir[u], dv = symDir[ v ];
                if( du == dv )
                {
                    continue; // same directory — not a seam
                }
                ++bridges;
                if( u < testReach.size() && testReach[u] )
                {
                    continue; // a test reaches the caller → exercised
                }
                ++untested;
                grp[ ( std::uint64_t( du ) << 32 ) | dv ].push_back( { u, v } );
            }
        }

        std::vector<std::pair<std::uint64_t, std::vector<SeamEdge>*>> pairs;
        for( auto& kv : grp )
        {
            pairs.push_back( { kv.first, &kv.second } );
        }
        std::sort( pairs.begin(), pairs.end(), [ & ]( const auto& a, const auto& b )
                   { return a.second->size() != b.second->size() ? a.second->size() > b.second->size() : a.first < b.first; } );

        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // §B12.5 — the UNIT clause is the same sentence on all three verbs that spell `untested=` (see
        // situ.h's kTestGateLegend and flipimpact.h's writeFlipHeader). Each legend was locally honest,
        // which is precisely why a reader comparing two of the numbers is misled.
        std::printf( "<!-- ripwire seams: cross-directory call edges NO test reaches (untested integration seams; a fact, not a mandate). module = parent dir; seam = caller-dir -> callee-dir, spelled from= and to=. Each seam pages its own edge rows with shown=/capped=; an edge names caller= at site p= calling callee= at site cp=. UNIT: untested= here counts cross-directory call EDGES. The test gate verb spells untested= over impacted SYMBOLS and the flip verb over the defs a gate lights, so the three numbers count three different things and must never be compared or summed across verbs. raise the default cap with limit=N (offset=M pages). %s-->%s",
                     rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str(), rw::rootRelPathsLegend( stSingleRoot ) );
        // P2.1: two nested caps, neither previously marked — at most 20 seam PAIRS, and at most 5 example
        // EDGES inside each. Each <seam> gains shown= alongside its true untested= count.
        //
        // §P8 vocabulary (see src/pageview.h, THE TRUNCATION VOCABULARY): this root used to spell BOTH
        // conventions at once — the noun-prefixed shown_seam_pairs= AND the bare capped= — so one element
        // answered "how many rows" in --communities' dialect and "were rows dropped" in --grep's. Reconciled
        // to the bare pair (rule 1): the root has exactly ONE listing (the seam pairs), and the noun-prefixed
        // form exists only to disambiguate SEVERAL listings in one element. modules=/bridges=/untested=/
        // test_files= are corpus counts, not listings, so they need no shown= companion. The <seam> children
        // already carried the target untested=/shown=/capped= and are unchanged.
        //
        // §P15/§P16: the seam-PAIR listing is deterministically sorted (size desc, dir-pair asc) — a real
        // row model, so --limit/--offset now WINDOW it instead of the fixed 20-pair display cap; --limit
        // raises or lowers that historic default exactly like --impact's 40. pageDisclosure replaces the
        // hand-rolled shown=/capped= pair with the identical bytes plus the paging half when active.
        const PageWindow  seamsPw     = pageWindow( pairs.size(), effectiveRowCap( cfg.pageLimit, 20 ), cfg.pageOffset );
        const std::size_t shownPairs  = seamsPw.end - seamsPw.begin;
        char              seamsAb[ kPageDisclosureCap ];
        std::printf( "<seams modules=\"%zu\" bridges=\"%u\" untested=\"%u\" test_files=\"%u\" seam_pairs=\"%zu\"%s%s>",
                     dirName.size(), bridges, untested, testFileCount, pairs.size(),
                     ( pageDisclosure( seamsAb, sizeof( seamsAb ), shownPairs, pairs.size(), seamsPw.end,
                                       cfg.pageLimit, cfg.pageOffset, true )
                       + rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ) ).c_str(),
                     stRootAttr.c_str() );
        for( std::size_t pi = seamsPw.begin; pi < seamsPw.end; ++pi )
        {
            const std::uint32_t    cu    = std::uint32_t( pairs[pi].first >> 32 ), cv = std::uint32_t( pairs[pi].first & 0xffffffffu );
            std::vector<SeamEdge>& edges = *pairs[pi].second;
            std::sort( edges.begin(), edges.end(), [ & ]( const SeamEdge& a, const SeamEdge& b )
                       { return rank[a.u] != rank[b.u] ? rank[a.u] > rank[b.u] : a.u < b.u; } );
            const std::size_t topE = std::min<std::size_t>( 5, edges.size() );
            std::printf( "<seam from=\"%s\" to=\"%s\" untested=\"%zu\" shown=\"%zu\" capped=\"%d\">",
                         ex( dirName[cu] ).c_str(), ex( dirName[cv] ).c_str(), edges.size(), topE, topE < edges.size() ? 1 : 0 );
            for( std::size_t i = 0; i < topE; ++i )
            {
                const Symbol&           su  = ing.symbols[ edges[i].u ];
                const Symbol&           sv  = ing.symbols[ edges[i].v ];
                const std::string_view  rpu = stSingleRoot ? rw::sarif::rootRelativeUri( ing.files[su.fileId], stRootPrefix ) : std::string_view( ing.files[su.fileId] );
                const std::string_view  rpv = stSingleRoot ? rw::sarif::rootRelativeUri( ing.files[sv.fileId], stRootPrefix ) : std::string_view( ing.files[sv.fileId] );
                std::printf( "<edge caller=\"%s\" p=\"%s:%u\" callee=\"%s\" cp=\"%s:%u\"/>",
                             ex( su.name ).c_str(), ex( rpu ).c_str(), su.line,
                             ex( sv.name ).c_str(), ex( rpv ).c_str(), sv.line );
            }
            std::printf( "</seam>" );
        }
        std::printf( "</seams>" );
        return 0;
    }

    // --mermaid: the module (directory) dependency graph as a Mermaid diagram — a HUMAN-viewable architecture
    // map. Node = directory (subsystem) sized by symbol count; edge = inter-module call count. Renders at
    // mermaid.live or in any Markdown that supports mermaid (GitHub/Obsidian/VS Code). Deterministic, no LLM.
    if( cfg.mermaid )
    {
        const std::uint32_t N = std::uint32_t( ing.symbols.size() );
        std::vector<std::uint32_t> symDir;
        std::vector<std::string>   dirName;
        computeDirModules( ing, symDir, dirName, stRootPrefix );
        const std::uint32_t M = std::uint32_t( dirName.size() );

        std::vector<std::uint32_t> sz( M, 0 );
        for( NodeId i = 0; i < N; ++i )
        {
            ++sz[symDir[i]];
        }
        HashMap<std::uint64_t, std::uint32_t> w;                       // (du<<32|dv) → cross-module call count
        for( NodeId u = 0; u < N; ++u )
        {
            for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
            {
                const std::uint32_t du = symDir[u], dv = symDir[ g.outTargets[k] ];
                if( du != dv )
                {
                    ++w[( std::uint64_t( du ) << 32 ) | dv];
                }
            }
        }

        std::vector<std::uint32_t> order( M );                         // top modules by symbol count
        for( std::uint32_t c = 0; c < M; ++c )
        {
            order[c] = c;
        }
        std::sort( order.begin(), order.end(), [ & ]( std::uint32_t a, std::uint32_t b )
                   { return sz[a] != sz[b] ? sz[a] > sz[b] : dirName[a] < dirName[b]; } );
        const std::size_t  nShown = std::min<std::size_t>( 30, M );
        std::vector<char>  shown( M, 0 );
        for( std::size_t i = 0; i < nShown; ++i )
        {
            shown[order[i]] = 1;
        }

        const std::string base = root + "/";                          // clean labels: strip the corpus root prefix
        const auto        label = [ & ]( std::uint32_t c ) -> std::string
        {
            std::string s = dirName[c];
            if( s == root )
            {
                s = "(root)";
            }
            else if( s.rfind( base, 0 ) == 0 )
            {
                s = s.substr( base.size() );
            }
            for( char& ch : s )
            {
                if( ch == '"' )
                {
                    ch = '\''; // mermaid label safety
                }
            }
            return s;
        };

        constexpr std::uint32_t minW = 3;                              // hide trivial edges for readability
        std::printf( "%%%% ripwire --mermaid: module (directory) dependency graph — node = dir (symbol count), edge = inter-module calls (>= %u). Render at mermaid.live.\n", minW );
        std::printf( "flowchart LR\n" );
        // group shown nodes by TOP-LEVEL directory component → mermaid subgraphs (visual subsystem clusters)
        HashMap<std::string, std::vector<std::uint32_t>> groups;
        std::vector<std::string>                         groupOrder;
        for( std::size_t i = 0; i < nShown; ++i )
        {
            const std::uint32_t c   = order[i];
            const std::string   lab = label( c );
            const std::size_t   sl  = lab.find( '/' );
            const auto [ it, ins ]  = groups.try_emplace( sl == std::string::npos ? lab : lab.substr( 0, sl ) );
            if( ins )
            {
                groupOrder.push_back( it->first );
            }
            it->second.push_back( c );
        }
        std::size_t gi = 0;
        for( const std::string& gname : groupOrder )
        {
            const std::vector<std::uint32_t>& gnodes = groups[ gname ];
            const bool wrap = gnodes.size() > 1;                       // wrap multi-node subsystems; lone dirs stay bare
            if( wrap )
            {
                std::printf( "  subgraph sg%zu [\"%s\"]\n", gi, gname.c_str() );
            }
            for( std::uint32_t c : gnodes )
            {
                std::printf( "%sn%u[\"%s<br/>%u\"]\n", wrap ? "    " : "  ", c, label( c ).c_str(), sz[c] );
            }
            if( wrap )
            {
                std::printf( "  end\n" );
            }
            ++gi;
        }
        std::vector<std::pair<std::uint64_t, std::uint32_t>> edges( w.begin(), w.end() );
        std::sort( edges.begin(), edges.end(), []( const auto& a, const auto& b ) { return a.first < b.first; } );
        for( const auto& [ key, weight ] : edges )
        {
            const std::uint32_t du = std::uint32_t( key >> 32 ), dv = std::uint32_t( key & 0xffffffffu );
            if( weight < minW || !shown[du] || !shown[dv] )
            {
                continue;
            }
            std::printf( "  n%u -->|%u| n%u\n", du, weight, dv );
        }
        return 0;
    }

    // --report: an at-a-glance architecture summary (markdown) — modules + god-files + cycles + top symbols
    // + cross-module bridges. Synthesizes the deterministic analyses; no git, no LLM. (graphify's GRAPH_REPORT)
    if( cfg.report )
    {
        const std::uint32_t      N    = std::uint32_t( ing.symbols.size() );
        const std::uint32_t      F    = std::uint32_t( ing.files.size() );
        const rw::Communities   cm   = rw::communities( g );
        const auto [ rank, prIters, prConverged ] = rankGraph( g );
        const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this document is PageRank-ordered

        CommunityMembers members( cm.count );
        for( NodeId i = 0; i < N; ++i )
        {
            members[cm.comm[i]].push_back( i );
        }
        const CommunityPresentation presentation = communityPresentation( ing, g, members, rank, stRootPrefix );
        for( auto& m : members )
        {
            std::sort( m.begin(), m.end(), [ & ]( NodeId a, NodeId b )
                       { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );
        }

        std::uint32_t modules = 0;
        for( std::uint32_t c = 0; c < cm.count; ++c )
        {
            if( members[c].size() >= 2 )
            {
                ++modules;
            }
        }
        const IsolateStats isolates = isolateStats( ing, g, members );

        const auto                 adj = resolveIncludeAdj( ing );
        std::vector<std::uint32_t> afferent( F, 0 );
        for( std::size_t a = 0; a < adj.size(); ++a )
        {
            for( std::uint32_t b : adj[a] )
            {
                if( b < F )
                {
                    ++afferent[b];
                }
            }
        }
        const auto cycles = sccCycles( adj );

        // §P7 embedding contract: this markdown never contains a run of 4-or-more backticks, so a consumer's
        // 5-backtick fence always safely embeds it whole (test/mdembedcheck.sh pins this). Every element below
        // is SYNTHESIZED (counts, sorted names, fixed section labels) — no verbatim file content is embedded,
        // which is what makes this an enforceable guarantee rather than an incidental one (contrast --recall).
        std::printf( "<!-- ripwire markdown: no run of 4-or-more backticks in this output — safe to embed inside a wider fence -->\n\n" );
        // W2-F: markdown has no attribute grammar — the note is emitted ONLY on the truncating exit.
        std::printf( "%s", rw::renderDisclosure( prD, rw::DiscloseAs::MarkdownNote ).c_str() );
        std::printf( "# ripwire architecture report\n\n%u files · %u symbols · %u edges · %u modules (%u call-graph isolated)\n\n",
                     F, N, std::uint32_t( g.outTargets.size() ), modules, isolates.total );
        // R-E (2026-08-17 harvest): paths below are root-relative on a single-root run (same convention every
        // other verb's root= attribute states); this line is the markdown twin — the ONLY place the absolute
        // root is spelled, so it stays recoverable from the document per the honesty rule every other verb follows.
        if( stSingleRoot )
        {
            std::printf( "Root: `%.*s`\n\n", int( cfg.roots[0].size() ), cfg.roots[0].data() );
        }
        std::printf( "Call-graph isolate provenance: %u declaration, %u header, %u source, %u document; %u connected Louvain singletons\n\n",
                     isolates.declaration, isolates.header, isolates.source, isolates.document, isolates.connectedSingletons );

        std::vector<std::uint32_t> ord( cm.count );
        for( std::uint32_t c = 0; c < cm.count; ++c )
        {
            ord[c] = c;
        }
        std::sort( ord.begin(), ord.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return members[a].size() != members[b].size() ? members[a].size() > members[b].size() : a < b; } );
        const std::uint32_t reportModules = std::min<std::uint32_t>( modules, 12 );
        std::printf( "## Modules (call-graph clusters; showing %u of %u)\n", reportModules, modules );
        std::uint32_t shown = 0;
        // §P6.2: no separate "(lead: ...)" annotation — the label above IS the semantic anchor now (highest
        // fan-in non-accessor member), so a second "top PageRank member" field would just reintroduce the
        // accessor name (push_back/empty/...) this fix exists to keep out of the reader's first screen.
        for( std::uint32_t c : ord )
        {
            if( members[c].size() < 2 )
            {
                continue;
            }
            if( shown++ >= 12 )
            {
                break;
            }
            std::printf( "- **%s** — %zu symbols\n", presentation.label[c].c_str(), std::size_t( members[c].size() ) );
        }

        std::vector<std::uint32_t> ford( F );
        for( std::uint32_t f = 0; f < F; ++f )
        {
            ford[f] = f;
        }
        std::sort( ford.begin(), ford.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return afferent[a] != afferent[b] ? afferent[a] > afferent[b] : a < b; } );
        const std::size_t godFileCount = std::count_if( afferent.begin(), afferent.end(), []( std::uint32_t count ) { return count > 0; } );
        const std::size_t reportGodFiles = std::min<std::size_t>( godFileCount, 10 );
        std::printf( "\n## God files (most depended-on; showing %zu of %zu)\n", reportGodFiles, godFileCount );
        bool anyGod = false;
        for( std::uint32_t i = 0; i < F && i < 10; ++i )
        {
            if( afferent[ford[i]] == 0 )
            {
                break;
            }
            anyGod = true;
            const std::string_view rp = stSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ford[i]], stRootPrefix ) : std::string_view( ing.files[ford[i]] );
            std::printf( "- `%.*s` — %u dependents\n", int( rp.size() ), rp.data(), afferent[ford[i]] );
        }
        if( !anyGod )
        {
            std::printf( "- (no include/import edges captured)\n" );
        }

        const std::size_t reportCycles = std::min<std::size_t>( cycles.size(), 6 );
        std::printf( "\n## Dependency cycles (showing %zu of %zu)\n", reportCycles, cycles.size() );
        if( cycles.empty() )
        {
            std::printf( "- none (acyclic)\n" );
        }
        else
        {
            for( std::size_t i = 0; i < cycles.size() && i < 6; ++i )
            {
                std::printf( "- " );
                for( std::size_t j = 0; j < cycles[i].size(); ++j )
                {
                    const std::string_view rp = stSingleRoot ? rw::sarif::rootRelativeUri( ing.files[cycles[i][j]], stRootPrefix ) : std::string_view( ing.files[cycles[i][j]] );
                    std::printf( "%s`%.*s`", j ? " ↔ " : "", int( rp.size() ), rp.data() );
                }
                std::printf( "\n" );
            }
        }

        std::vector<NodeId> ts( N );
        for( NodeId i = 0; i < N; ++i )
        {
            ts[i] = i;
        }
        std::sort( ts.begin(), ts.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );
        const std::uint32_t reportTopSymbols = std::min<std::uint32_t>( N, 10 );
        std::printf( "\n## Top symbols (PageRank; showing %u of %u)\n", reportTopSymbols, N );
        for( std::uint32_t i = 0; i < N && i < 10; ++i )
        {
            const Symbol&           s  = ing.symbols[ ts[i] ];
            const std::string_view  rp = stSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], stRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            std::printf( "- `%s` (%.*s:%u)\n", s.name.c_str(), int( rp.size() ), rp.data(), s.line );
        }

        HashMap<std::uint64_t, std::uint32_t> bridge;
        for( NodeId u = 0; u < N; ++u )
        {
            for( std::uint32_t k = g.outOff[u]; k < g.outOff[u + 1]; ++k )
            {
                const std::uint32_t cu = cm.comm[u], cv = cm.comm[g.outTargets[k]];
                if( cu == cv )
                {
                    continue;
                }
                const std::uint32_t a = std::min( cu, cv ), b = std::max( cu, cv );
                ++bridge[( std::uint64_t( a ) << 32 ) | b];
            }
        }
        std::vector<std::pair<std::uint64_t, std::uint32_t>> br( bridge.begin(), bridge.end() );
        std::sort( br.begin(), br.end(), []( const auto& a, const auto& b ) { return a.second != b.second ? a.second > b.second : a.first < b.first; } );
        const std::size_t reportBridges = std::min<std::size_t>( br.size(), 8 );
        std::printf( "\n## Cross-module bridges (showing %zu of %zu)\n", reportBridges, br.size() );
        if( br.empty() )
        {
            std::printf( "- (none)\n" );
        }
        else
        {
            for( std::size_t i = 0; i < br.size() && i < 8; ++i )
            {
                const std::uint32_t a = std::uint32_t( br[i].first >> 32 ), b = std::uint32_t( br[i].first & 0xffffffffu );
                std::printf( "- %s ↔ %s (%u edges)\n", presentation.label[a].c_str(), presentation.label[b].c_str(), br[i].second );
            }
        }
        return 0;
    }

    // --tree: a file-by-file orientation map — each file with its top symbols by rank. The agentmap
    // "frontmatter for source files" idea: a cheap session-start overview. Deterministic (files by best
    // symbol rank, path breaking ties; symbols within a file by rank, id breaking ties).
    if( cfg.tree )
    {
        const auto [ rank, prIters, prConverged ] = rankGraph( g );
        const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this document is PageRank-ordered
        const std::uint32_t      F    = std::uint32_t( ing.files.size() );
        SymbolsByFile              byFile = symbolsByFileInIdOrder( ing, []( const Symbol& ) { return true; } );
        std::vector<std::uint32_t> ford;  ford.reserve( F );   // ONLY non-empty files (the emitted set)
        for( std::uint32_t f = 0; f < F; ++f )
        {
            if( !byFile[f].empty() )
            {
                ford.push_back( f );
            }
        }

        // §P11.8: files lead by their best symbol's rank, not asciibetically — see the function above.
        orderFilesByBestSymbolRank( ford, ing, rank );
        // §A8.5: files= (the TRUE indexed corpus, comment below) exceeded the complete row set (ford, the
        // listable non-empty subset) with the divergence documented only in this comment — a reader outside
        // the source never learned WHY the two counts disagreed. files_unlisted= closes it: the count of
        // symbol-less files files= includes but no <file> row can ever list (fine — a file with no symbols
        // has nothing to preview — but silent until now).
        const std::uint32_t filesUnlisted = F - std::uint32_t( ford.size() );
        // ── verifier FINDING E1 (2026-08-19): --tree was the single largest absolute-path emitter left in the
        //    tool — 1,212 rows on ripwire's own corpus, more than every verb rootrelcheck already covered put
        //    together — and it is the session-start orientation map the skills route to FIRST. Same shape as
        //    every other verb's root=: the single-root condition from sarif.h, the shared legend clause from
        //    graphlegend.h emitted exactly when the attribute is, and root= appended AFTER the paging and
        //    PageRank disclosures so nothing already on this element moves.
        const bool         trSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
        const std::string  trRootPrefix = trSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
        std::vector<char>  trRootEsc;
        const std::string  trRootAttr   = trSingleRoot ? ( " root=\"" + std::string( rw::escapeXml( cfg.roots[0], trRootEsc ) ) + "\"" ) : std::string();
        std::printf( "<!-- ripwire tree: each file + its top symbols by rank, files ordered by their best "
                     "symbol's rank (path breaks ties) — a session-start orientation map. files= is the indexed "
                     "corpus; rows list files WITH symbols; files_unlisted= holds the symbol-less remainder "
                     // W3FIX NIT: "files equals the listed rows plus files_unlisted on every run" reads FALSE on
                     // a paged run, where the rows below are one WINDOW of the listable set (files=825
                     // files_unlisted=21 total=804 shown=2). One sentence now carries both cases by naming the
                     // pre-paging set, and introduces total= as the number the identity is actually about.
                     "— files equals files_unlisted plus the LISTABLE file set, which is what the rows below "
                     "enumerate before any paging window is applied; under explicit paging (limit=/offset=) that "
                     "listable count is emitted as total= and shown= says how many of it these rows are. "
                     "%s-->%s", rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str(),
                     rw::rootRelPathsLegend( trSingleRoot ) );
        // T2 + §P8 G1: --limit/--offset paginate over the (sorted) non-empty file set. files= stays the TRUE
        // total of INDEXED files (all of them, matching pre-T2) — deliberately NOT the paging total, because
        // the emitted rows are the non-empty subset `ford`, and total= must be the count a next_offset walks
        // toward. The two therefore differ on any tree with symbol-less files, which is why total= is the one
        // pageview emits and files= is left exactly as it was. discloseCap=false: --tree has no display cap,
        // so the un-paginated tag is byte-identical. See src/pageview.h, THE TRUNCATION VOCABULARY.
        const PageWindow  pw = pageWindow( ford.size(), cfg.pageLimit, cfg.pageOffset );
        char              pab[ kPageDisclosureCap ];
        std::printf( "<tree files=\"%u\" files_unlisted=\"%u\"%s%s>", F, filesUnlisted,
                     ( pageDisclosure( pab, sizeof( pab ), pw.end - pw.begin, ford.size(), pw.end,
                                       cfg.pageLimit, cfg.pageOffset, false )
                       + rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ) ).c_str(),
                     trRootAttr.c_str() );
        std::vector<char> trEsc;
        for( std::size_t fi = pw.begin; fi < pw.end; ++fi )
        {
            const std::uint32_t f    = ford[fi];
            FileSymbols&        syms = byFile[f];
            std::sort( syms.begin(), syms.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );
            // path and symbol names may contain & < > " — escape them to keep XML well-formed.
            const auto ep = rw::escapeXml( trSingleRoot ? rw::sarif::rootRelativeUri( ing.files[f], trRootPrefix )
                                                        : std::string_view( ing.files[f] ), trEsc );
            std::printf( "<file p=\"%.*s\" symbols=\"%zu\">", int( ep.size() ), ep.data(), std::size_t( syms.size() ) );
            const std::size_t topN = std::min<std::size_t>( 3, syms.size() );
            for( std::size_t i = 0; i < topN; ++i )
            {
                const Symbol& s = ing.symbols[ syms[i] ];
                const auto en = rw::escapeXml( s.name, trEsc );
                std::printf( "<s t=\"%s\" n=\"%.*s\"/>", symTag( s.kind ), int( en.size() ), en.data() );
            }
            std::printf( "</file>" );
        }
        std::printf( "</tree>" );
        return 0;
    }
    return std::nullopt;
}

// --grep=STR: parallel literal search; each hit annotated with its enclosing symbol (code-aware, not just
// file:line). Shares grepCollect() with the MCP `grep` verb so they never diverge. Its own function (the
// named-verb-handler shape): §P8 added a windowing step over the
// hit list, and the emitter was all of runGrep.
// §P11.1: grepCollect() returns TIER-then-path order (source → test/bench → docs), so the row cap and the
// --limit/--offset window below both walk an order that puts code first. This emitter never re-sorts, which
// is what keeps the CLI verb and the MCP `grep` verb on one order.
//
// §A0/§A1 — COLLECT, then SORT, then WINDOW, and in that order. §P8 made `cap` BOTH the row cap and the
// scan's collection budget, so `--limit`/`--offset` decided what was ever collected: the tier sort then ran
// over a different set per page (rows dropped and duplicated across seams, `total=` growing as the offset
// advanced) and `cfg.pageOffset + rowCap` overflowed `int` at --limit=536870912 into a confident hits="0".
// Both die with the same rule: the window is a pure slice of the fully-collected, fully-sorted list, and
// nothing derived from --limit/--offset reaches grepCollect() at all.
// R1b <enc> emission, lifted out of emitGrepReport (the named-verb-handler shape — the emitter stays the
// window/disclosure logic, the enrichment block is its own concern). Row semantics live in search.h's
// grepEnclosingRows; this is pure serialization. amp/tested follow serialize.h's lean lens grammar:
// only when the vector exists AND the value is worth a token, max/any over the row's name group.
struct GrepEncOptions
{
    const std::vector<std::uint32_t>* amp;
    const std::vector<std::uint8_t>*  tested;
    bool                              handles;
    std::string_view                  root;
    std::vector<char>&                esc;
};

class GrepHandleAttrs
{
public:
    GrepHandleAttrs( const rw::IngestResult& ing, const rw::Graph& g, bool enabled, std::string_view root )
        : ing_( ing ), g_( g ), enabled_( enabled ), root_( root ) {}

    std::string forRow( const rw::GrepEncRow& row )
    {
        if( !enabled_ )
        {
            return {};
        }
        if( row.defCount != 1 || row.ids.size() != 1 )
        {
            return " handle_omitted=\"ambiguous\"";
        }
        const rw::NodeId id = row.ids.front();
        const rw::Symbol& s = ing_.symbols[id];
        if( s.kind == rw::SymKind::Section )
        {
            return " handle_omitted=\"non-code\"";
        }
        const std::uint64_t contentHash = hashFor( s.fileId );
        const std::string handle = rw::sourceHandleFor( ing_, g_, root_, id, contentHash );
        return handle.empty() ? " handle_omitted=\"unreadable\"" : " h=\"" + handle + "\"";
    }

private:
    std::uint64_t hashFor( std::uint32_t fileId )
    {
        const auto cached = fileHashes_.find( fileId );
        if( cached != fileHashes_.end() )
        {
            return cached->second;
        }
        bool readOk = false;
        const std::string bytes = rw::mcpdetail::readFileBytes( rw::diskPath( ing_, fileId ), readOk );
        const std::uint64_t hash = readOk ? rw::mcpdetail::byteHash( bytes.data(), bytes.size() ) : 0;
        fileHashes_.emplace( fileId, hash );
        return hash;
    }

    const rw::IngestResult& ing_;
    const rw::Graph&        g_;
    bool                    enabled_;
    std::string_view        root_;
    rw::HashMap<std::uint32_t, std::uint64_t> fileHashes_;
};

void emitGrepHandleLegend( bool enabled )
{
    if( !enabled )
    {
        return;
    }
    std::printf( "<!-- ripwire grep handles: h= is sym#<stable-identity-hash>@<whole-file-content-hash>; "
                 "the content half pins the exact file bytes scanned, so an edit after any file change refuses as stale. "
                 "Only one editable enclosing definition receives h=. handle_omitted=ambiguous means the name grouped "
                 "several definitions; non-code means a document/data section has no safe definition span; unreadable "
                 "means no content hash could be proven. -->" );
}

void emitGrepEncRows( const rw::IngestResult& ing, const rw::Graph& g, std::span<const rw::GrepHit> hits,
                      const GrepEncOptions& opt )
{
    using namespace rw;
    GrepHandleAttrs handleAttrs( ing, g, opt.handles, opt.root );
    for( const GrepEncRow& row : grepEnclosingRows( ing, g, hits ) )
    {
        const auto en = rw::escapeXml( row.chain, opt.esc );
        std::printf( "<enc n=\"%.*s\" callers=\"%u\"", int( en.size() ), en.data(), row.callerCount );
        if( row.defCount > 1 )
        {
            std::printf( " defs=\"%u\"", row.defCount );
        }
        if( row.cx > 0 )
        {
            std::printf( " cx=\"%u\"", row.cx );
        }
        std::uint32_t ampMax = 0;  bool anyTested = false;
        for( const NodeId id : row.ids )
        {
            if( opt.amp && id < opt.amp->size() )
            {
                ampMax = std::max( ampMax, (*opt.amp)[id] );
            }
            if( opt.tested && id < opt.tested->size() && (*opt.tested)[id] )
            {
                anyTested = true;
            }
        }
        if( ampMax > 0 )
        {
            std::printf( " amp=\"%u\"", ampMax );
        }
        if( anyTested )
        {
            std::printf( " tested=\"1\"" );
        }
        std::fputs( handleAttrs.forRow( row ).c_str(), stdout );
        std::printf( "/>" );
    }
}

// R1a <suggest> emission, lifted out of emitGrepReport for the same reason. What to suggest is
// search.h's grepZeroHitSuggestions (shared with the MCP twin); this is pure serialization.
void emitGrepSuggest( const rw::IngestResult& ing, const std::string& pat, bool regex, std::vector<char>& esc )
{
    using namespace rw;
    const GrepZeroHitSuggestions sug = grepZeroHitSuggestions( ing, pat, regex );
    if( sug.near.empty() && !sug.offerFor )
    {
        return;
    }
    std::printf( "<suggest" );
    if( !sug.near.empty() )
    {
        const auto nn = rw::escapeXml( sug.near, esc );
        std::printf( " near=\"%.*s\"", int( nn.size() ), nn.data() );
    }
    if( sug.offerFor )
    {
        const auto fp = rw::escapeXml( pat, esc );
        std::printf( " next=\"--for=&quot;%.*s&quot;\"", int( fp.size() ), fp.data() );
    }
    std::printf( "/>" );
}

// §R-J: the three root attributes unindexed_files_scanned=/unindexed_files_skipped=/
// unindexed_candidates_capped= as one string fragment — a pure function of the aux collection, lifted out
// so emitGrepReport's own body states only "compute aux, then ask what it discloses" rather than the
// three-attribute assembly itself. unindexed_files_scanned= is unconditional (0 is informative: it means
// no unsupported-ext candidate existed, or none survived the size/binary guard — never "this build lacks
// the feature"); the other two follow corpus_excluded='s convention above: absent means zero/false.
std::string grepUnindexedAttrs( const rw::GrepAuxCollection& aux )
{
    const std::uint32_t skipped = aux.filesSkippedOversize + aux.filesSkippedBinary + aux.filesUnreadable;
    std::string          attr    = " unindexed_files_scanned=\"" + std::to_string( aux.filesScanned ) + "\"";
    if( skipped > 0 )
    {
        attr += " unindexed_files_skipped=\"" + std::to_string( skipped ) + "\"";
    }
    if( aux.candidatesCapped )
    {
        attr += " unindexed_candidates_capped=\"1\"";
    }
    return attr;
}

// §R-J <unindexed> emission, lifted out of emitGrepReport for the same reason emitGrepEncRows/
// emitGrepSuggest above were: pure serialization of an already-collected list (search.h's grepCollectAux),
// so the "collapse by contiguous path" grouping loop is a helper's job, not emitGrepReport's. Omitted
// entirely (prints nothing) when there is nothing to say — the same "absent means none" convention
// corpus_excluded=/corpus_oversize= use, so a caller never needs an empty-check before calling this.
void emitGrepUnindexed( const std::vector<rw::GrepAuxHit>& hits, bool singleRoot, const std::string& rootPrefix, std::vector<char>& esc )
{
    using namespace rw;
    if( hits.empty() )
    {
        return;
    }
    const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    std::printf( "<unindexed>" );
    for( std::size_t i = 0; i < hits.size(); )
    {
        std::size_t j = i;
        std::printf( "<f p=\"%s\">", ex( singleRoot ? rw::sarif::rootRelativeUri( hits[i].path, rootPrefix )
                                                     : std::string_view( hits[i].path ) ).c_str() );
        for( ; j < hits.size() && hits[j].path == hits[i].path; ++j )
        {
            const GrepAuxHit& h = hits[j];
            std::string        safe;
            appendCdataSafe( h.text, safe );
            std::printf( "<hit l=\"%u\"><m><![CDATA[", h.line );
            std::fwrite( safe.data(), 1, safe.size(), stdout );
            std::printf( "]]></m></hit>" );
        }
        std::printf( "</f>" );
        i = j;
    }
    std::printf( "</unindexed>" );
}

// R-H span tiers: the legend clause and the root attributes, lifted out of emitGrepReport for exactly the
// reason emitGrepUnindexed/grepUnindexedAttrs above were — pure serialization of an already-computed
// report, gated on ONE predicate (GrepTierReport::hasDisclosure), so the emitter's own body says "print the
// tier disclosure" rather than carrying six conditional appends. Both return empty when the run held
// nothing back, which is the byte-identical-to-untiered contract.
//
// Kept DENSE on purpose (G4): this clause rides every answer that holds a row back, and on a small answer
// legend prose IS the answer — an early draft cost ~1.2 KB and ate the row saving whole.
const char* grepTierLegend( const rw::GrepTierReport& tier )
{
    if( !tier.hasDisclosure() )
    {
        return "";
    }
    return "SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves "
           "the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not "
           "code, so a pattern living only in prose is answered, never emptied. "
           "suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the "
           "reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand "
           "under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, "
           "present only then), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. ";
}

// Present only when this answer actually held something back or stopped short — absent-means-nothing-was-
// tiered, the same convention corpus_excluded= follows. tier= is narrowed further to the NON-DEFAULT case:
// naming the code tier on every answer would be ~12 bytes restating the default on the overwhelming
// majority that serve it.
std::string grepTierAttrs( const rw::GrepTierReport& tier )
{
    if( !tier.hasDisclosure() )
    {
        return {};
    }
    std::string attrs;
    if( tier.suppressedComment > 0 )
    {
        attrs += " suppressed_comment=\"" + std::to_string( tier.suppressedComment ) + "\"";
    }
    if( tier.suppressedString > 0 )
    {
        attrs += " suppressed_string=\"" + std::to_string( tier.suppressedString ) + "\"";
    }
    if( std::strcmp( tier.emittedTier, "code" ) != 0 )
    {
        attrs += std::string( " tier=\"" ) + tier.emittedTier + "\"";
    }
    attrs += " tier_parsed=\"" + std::to_string( tier.tieredFileCount ) + "\"";
    if( tier.unclassifiedHits > 0 )
    {
        attrs += " tier_unclassified=\"" + std::to_string( tier.unclassifiedHits ) + "\"";
    }
    if( tier.budgetHit != nullptr )
    {
        attrs += std::string( " tier_budget=\"" ) + tier.budgetHit + "\"";
    }
    return attrs;
}

std::vector<rw::GrepTerm> makeGrepTerms( const rw::Config& cfg )
{
    std::vector<rw::GrepTerm> terms;
    terms.reserve( cfg.grepAnd.size() + cfg.grepNot.size() );
    for( const std::string_view t : cfg.grepAnd ) { terms.push_back( rw::GrepTerm{ std::string( t ), false } ); }
    for( const std::string_view t : cfg.grepNot ) { terms.push_back( rw::GrepTerm{ std::string( t ), true } ); }
    return terms;
}

void emitCompactGrepLegend()
{
    std::printf( "<!-- ripwire grep ripwire.grep/v1: files group source-ordered hits; l=line, m=matched text, "
                 "in=enclosing name when known. shown/capped disclose the printed window; hits_capped=1 makes hits a floor; "
                 "complete=1 only for an exhaustive literal scan whose whole unfiltered window printed. root anchors relative p; "
                 "enc callers remain a call-graph floor; tier/suppressed and unindexed/corpus attrs disclose excluded populations. -->" );
}

std::string grepTermsAttrs( std::string_view pattern, std::span<const rw::GrepTerm> terms, rw::GrepScope scope,
                            std::uint32_t suppressed, std::vector<char>& esc )
{
    if( terms.empty() ) { return {}; }
    std::string termsList( rw::escapeXml( pattern, esc ) );
    for( const rw::GrepTerm& term : terms )
    {
        termsList += term.negated ? " -" : " +";
        termsList += rw::escapeXml( term.term, esc );
    }
    return " terms=\"" + termsList + "\" scope=\"" + ( scope == rw::GrepScope::File ? "file" : "line" )
         + "\" terms_suppressed=\"" + std::to_string( suppressed ) + "\"";
}

std::string grepCorpusAttrs( const rw::IngestResult& ing )
{
    std::string attrs;
    if( ing.crawlSkips.excludedFiles > 0 )
    {
        attrs += " corpus_excluded=\"" + std::to_string( ing.crawlSkips.excludedFiles ) + "\"";
    }
    if( !ing.skippedOversize.empty() )
    {
        attrs += " corpus_oversize=\"" + std::to_string( ing.skippedOversize.size() ) + "\"";
    }
    return attrs;
}

// R1 (the 2026-08-12 usage mine) widened the signature beyond (cfg, ing): `g` feeds the <enc> rows'
// callers= (in-edge CSR — data the graph already holds, zero new analysis), and amp/tested ride along
// ONLY when a co-run (--metrics) already computed them — grep itself never triggers the qmetrics pass
// or the git popen. Null pointers are the normal case and emit nothing.
int emitGrepReport( const rw::Config& cfg, const rw::IngestResult& ing, const rw::Graph& g,
                    const std::vector<std::uint32_t>* amp, const std::vector<std::uint8_t>* tested )
{
    using namespace rw;
    const std::string          pat( cfg.grep );
    const int                  histCap = cfg.packTopN > 0 ? cfg.packTopN : 100;
    const int                  rowCap  = effectiveRowCap( cfg.pageLimit, histCap );

    // §P0.4: an invalid --regex used to scan nothing and print hits="0" at exit 0 with an EMPTY stderr —
    // indistinguishable from a true negative on every channel. Refuse before scanning, so the prefilter
    // and --no-prefilter paths refuse identically and no <grep> element is produced at all.
    if( cfg.grepRegex )
    {
        if( const std::optional<std::string> reErr = regexCompileError( pat ) )
        {
            // The lead-in is deliberately NEUTRAL ("refused", not "invalid"): regexCompileError() also
            // refuses patterns that are perfectly valid ECMAScript — L5's non-portable escapes and M2's
            // catastrophic-backtracking family — so "is not a valid regular expression" would be false
            // for two of its three verdicts. The reason string itself names which case it was.
            std::fprintf( stderr, "ripwire: --regex='%s' refused, nothing was scanned: %s "
                                  "(a hits=\"0\" here would be a failure, not a measurement — fix the pattern, e.g. ripwire <dir> --regex='fnv1a\\w+')\n",
                          pat.c_str(), reErr->c_str() );
            return 1;
        }
    }

    // --regex uses the sound Russ-Cox trigram prefilter by default; --no-prefilter forces a full scan
    // (the oracle the soundness gate compares against — prefiltered must equal full-scan).
    // grepBefore/grepAfter default to 0 (--grep-context/-before/-after unset) ⇒ GrepHit::before/after
    // stay empty and the <hit> emission below takes the ORIGINAL self-closing path byte-for-byte —
    // this is the byte-identical-when-unset contract.
    GrepCollection             found    = grepCollect( ing, pat, cfg.grepRegex, cfg.noPrefilter );
    // G3 (2026-08-15 harvest, report-ugrep §F2): boolean AND/NOT as a post-filter over the collected raw
    // hits — literal-only, already refused together with --regex in validateConfig. Built here (not in
    // Config) so the CLI value strings (string_views into argv) become owned std::strings exactly once.
    std::vector<GrepTerm> grepTerms = makeGrepTerms( cfg );
    const GrepScope    grepScopeVal    = ( cfg.grepScope == "file" ) ? GrepScope::File : GrepScope::Line;
    std::uint32_t      termsSuppressed = 0;
    if( !grepTerms.empty() )
    {
        found = grepApplyBooleanTerms( ing, std::move( found ), std::span<const GrepTerm>( grepTerms ), grepScopeVal, termsSuppressed );
    }
    // R-H (2026-08-15 harvest report-ugrep §F3/§F4, funded by wave-2 E5): SPAN TIERS — classify each
    // surviving hit by the tree-sitter span it sits in and serve the tightest NON-EMPTY tier. Runs AFTER the
    // boolean filter on purpose: tiering the survivors is both cheaper and the only reading that matches
    // what this answer will print. The bounded on-demand parse and its disclosed bail-out live in
    // search.h::grepApplySpanTiers (which owns the budget), never in astQuery — see its header.
    GrepTierReport tierReport;
    found = grepApplySpanTiers( ing, std::move( found ), ( cfg.grepIn == "any" ) ? GrepIn::Any : GrepIn::Code, tierReport );
    // §R-J: additive scan over CrawlSkips::unsupported — the "unsupported-ext, text-looking" population the
    // crawl already computed at ingest time (queries/*/tags.scm and its siblings). Reuses the SAME per-file
    // ceiling the crawl applies to indexed files, so a huge unsupported-ext file is excluded exactly like an
    // oversized indexed one would be. See search.h's grepCollectAux for the honesty fields and why this is a
    // separate hit type rather than a widened GrepRawHit::fileId domain (the lane report has the option write-up).
    const std::size_t       maxAuxFileBytes = cfg.maxFileBytes == 0 ? kDefaultMaxFileBytes : cfg.maxFileBytes;
    const GrepAuxCollection aux             = grepCollectAux( ing.crawlSkips, pat, cfg.grepRegex, maxAuxFileBytes );

    const std::size_t          hitCount = found.raw.size();
    // files= counts the whole COLLECTED set, never the printed page — it is a property of the search, so it
    // must read the same on every page of a walk (it used to be counted over the window's rows).
    std::uint32_t prev = UINT32_MAX;  int filesMatched = 0;
    for( const GrepRawHit& r : found.raw )
    {
        if( r.fileId != prev )
        {
            ++filesMatched;
            prev = r.fileId;
        } // hits sorted by file
    }
    // the WINDOW: a pure slice of the sorted list. pageWindow() clamps a past-the-end offset to an empty
    // page, so a 64-bit offset can never index out of range.
    const PageWindow           grepPage = pageWindow( hitCount, rowCap, cfg.pageOffset );
    const std::vector<GrepHit> hits     = grepEnrich( ing, std::span<const GrepRawHit>( found.raw ).subspan( grepPage.begin, grepPage.end - grepPage.begin ),
                                                      cfg.grepBefore, cfg.grepAfter );
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    // CDATA-safe a context block: split any ]]> (would prematurely close the CDATA) and scrub XML-illegal
    // control bytes (G4) — same rule serialize.h applies to <src>/<bodies> bodies, kept local per this
    // agent's scope (search.h/main.cpp only, serialize.h owned by another concurrent agent).
    const auto cdataSafe = [ & ]( std::string_view body ) -> std::string
    {
        std::string safe;
        safe.reserve( body.size() );
        for( std::size_t i = 0; i < body.size(); ++i )
        {
            if( i + 2 < body.size() && body[i] == ']' && body[i + 1] == ']' && body[i + 2] == '>' )
            { safe += "]]]]><![CDATA[>"; i += 2; }
            else
            { safe += xmlSafeByte( body[i] ); }
        }
        return safe;
    };
    // P2.1: hits= counted everything, the listing stopped at the row cap, and nothing said so.
    // shown=/capped= (the --communities / --graph-query vocabulary) close it.
    // hits_capped= is a SECOND, deeper cut this emitter does not own: grepCollect() stops COLLECTING at the
    // fixed kGrepCollectionBudget raw matches (search.h), so on a pattern common enough to exhaust it
    // `hits=` is itself a FLOOR, not a total. §A1: that ceiling no longer moves with --limit/--offset, so
    // hits=/files=/total= now read the SAME on every page of a walk.
    const int         hitsCapped = found.isBudgetReached ? 1 : 0;
    // T1 (completeness claims — the mirror of the floor vocabulary). complete="1" appears on the root
    // exactly when this listing is EXHAUSTIVE over the index, so a consumer need not re-derive (re-grep)
    // the answer. Four conditions, each with a mutation arm in test/completecheck.sh:
    //   scan   — every indexed file read end to end: LITERAL scans only. A regex answer never claims, in
    //            EITHER prefilter mode: prefiltered, the claim would rest on the analyzer rather than on a
    //            full read; and no-prefilter may not claim what prefiltered does not, because the two modes
    //            are contractually byte-identical (test/regexcheck.sh's soundness oracle diffs them — the
    //            prefilter is a performance switch, never an answer switch);
    //   ceiling — the collection budget was not reached (hits_capped="0"), or hits= is itself a floor;
    //   read   — no indexed file was unreadable and no worker degraded (found's own honesty bits);
    //   window — the printed page starts at row 0 and reaches the last hit (shown == hits).
    // A FALSE claim here is the worst bug this tool can ship; when any condition fails, NOTHING is added
    // (the floor/truncation vocabulary already covers partial answers — no complete="0" noise).
    //   tier   — R-H: a tier-filtered listing did NOT print every hit it found, so it may not wear the
    //            claim either. This is the same rule the window arm applies to a page: complete= says "a hit
    //            absent above is absent from every indexed file", and that is false the moment a comment or
    //            string row was held back. --grep-in=any (no filtering) keeps the claim, which is what makes
    //            the claim recoverable rather than lost.
    const bool scanExhaustive = found.cleanScan() && !cfg.grepRegex;
    const bool windowWhole    = grepPage.begin == 0 && grepPage.end == hitCount;
    const bool nothingHeldBack = tierReport.suppressedComment == 0 && tierReport.suppressedString == 0;
    const char* const completeAttr = ( scanExhaustive && windowWhole && nothingHeldBack ) ? " complete=\"1\"" : "";
    char              grab[ 192 ];
    // G1 (2026-08-15 harvest, report-memgraph §F6): a single-root run's `ing.files` carry the crawl root's
    // OWN spelling (a leading "./" for a relative root, the full absolute path for an absolute one — see
    // sarif.h's rootRelativeUri, which this reuses rather than re-deriving the same strip). Multi-root
    // workspaces already carry the compact `<label>/<relpath>` identity (model.h) and are left untouched —
    // scoped out here, not silently degraded: `root=` is simply absent and `p=` reads as it always did.
    const bool        singleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string rootPrefix = singleRoot ? rw::sarif::rootPrefixOf( std::string( cfg.roots[0] ) ) : std::string();
    const auto         pathFor   = [ & ]( std::uint32_t fileId ) -> std::string_view
    {
        return singleRoot ? rw::sarif::rootRelativeUri( ing.files[ fileId ], rootPrefix ) : std::string_view( ing.files[ fileId ] );
    };
    std::string rootAttr;
    if( singleRoot )
    {
        rootAttr = " root=\"" + ex( cfg.roots[0] ) + "\"";
    }
    // Collapse (byte-identical match text within one file folding into one <hit> + <at> sites, search.h's
    // grepGroupByFile) is safe only on the UNPAGINATED default view: paging math runs upstream in RAW-hit
    // space (the §A0/§A1 seam contract, test/grepseamcheck.sh) and a paged window's <hit> COUNT must stay
    // the window size shown= already promises. Context lines are per-site too — folding would drop them.
    const bool collapseOn = cfg.pageLimit == 0 && cfg.pageOffset == 0 && cfg.grepBefore == 0 && cfg.grepAfter == 0;
    // §P8 collision, documented not renamed: both `in=` meanings are load-bearing (10 and 13+ consumers,
    // two byte-exact goldens, five SKILL.md files), so the legend names the other one instead.
    // §A10.3: the ORDER is stated, because the rows are silently reordered otherwise — whereis's legend
    // states its ordering in full and grep's said nothing.
    // §B12.4 in-band (W3FIX): same shared clause as --impact, so limit="0" is DEFINED on the first screen of
    // the two verbs an agent walks most, not only in --help and pageview.h.
    if( cfg.legend == "compact" )
    {
        emitCompactGrepLegend();
    }
    else
    {
    std::printf( "<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p=\"…\">, each <hit> carrying its LINE "
                 "(l=), matched text (m) and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; "
                 "ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope). "
                 "root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the "
                 "path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. "
                 "shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> "
                 "elements); hits_capped=\"1\" ⇒ hits= is a FLOOR (collection budget reached). " );
    // G3 (2026-08-15 harvest): terms=/scope=/terms_suppressed= appear ONLY when the run passed and/not —
    // deliberately no literal "--and"/"--not" substring (illegal "--" digraph inside an XML comment; spelled
    // without the leading dashes, matching this legend's own convention) — and so does the PROSE defining
    // them. It is ~630 B that used to ride on EVERY answer, including the overwhelming majority that can
    // never emit those three attributes: a zero-hit answer paid 631 of its bytes defining what was not
    // there. Legend text is the one part of a grep answer that does NOT amortize over hits, so on small
    // answers it IS the answer. legendcoveragecheck is unharmed by construction — it asks whether every
    // attribute the answer EMITS is defined where the reader meets it, and a clause gated on exactly its
    // attributes' own condition is present precisely when it can be needed. Gates: grepbytescheck's
    // uncapped small-hit arm; grepandcheck (4d)/(4e) still assert the prose IS there on an and/not run.
    if( !grepTerms.empty() )
    {
        std::printf( "terms= (present only with and/not) restates the whole boolean query as it was EVALUATED: the base pattern, then "
                     "each and term prefixed +, each not term prefixed -. scope=line (default) requires every term on the SAME matched "
                     "line as the base pattern; scope=file requires every term ANYWHERE in the file, independent of which line matched. "
                     "terms_suppressed= counts the raw hits the boolean filter REJECTED — a different axis from hits_capped= (a collection-"
                     "budget ceiling): hits=/shown=/etc. already read the FILTERED count, so terms_suppressed= exists only so a reader can "
                     "recover how many the un-filtered scan would have shown. " );
    }
    // R-H span tiers: the prose is gated on exactly the condition its own attributes are (the terms= clause
    // above set the precedent, and legendcoveragecheck's rule is "define what you EMIT"). An answer that
    // held nothing back emits no tier attribute and pays no tier prose — byte-identical to the pre-tier
    // verb, which is the "purely additive" contract. Helper above; empty string when there is nothing to say.
    std::printf( "%s", grepTierLegend( tierReport ) );
    std::printf(
                 // G1 (2026-08-15 harvest): byte-identical match text within one file's hits on the UNPAGINATED default view folds into
                 // ONE <hit> row plus <at l=… in=…/> children for the extra sites — n= on the <hit> (present only when >1) is 1+the <at>
                 // count, so summing n= across a page's <hit> rows recovers shown=. Paging or --grep-context/-before/-after disables the
                 // fold (a paged window's row count must stay honest; context lines are per-site and would be lost by folding).
                 // Deliberately no literal "<at " substring above (space after the tag name): row-counting
                 // gates that scan this legend's OWN comment for "<hit "/"<at " row markers (test/pagingsweepcheck.sh's
                 // disclose()) would double-count the illustrated example as a real row otherwise.
                 "A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged "
                 "sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes "
                 "omitted, illegal in an XML comment), where every site keeps its own <hit>. "
                 // R1 (the 2026-08-12 usage mine): the two follow-up answers, defined in-band — the legend is the only prose a mid-task agent
                 // reads, so it carries the honesty duties: <suggest> is labeled SUGGESTIONS (a zero stays "none found"), callers= carries the FLOOR caveat.
                 // Deliberately NO attribute=value literal in the added sentences ("a zero-hit answer", never a quoted hits value): several gates
                 // parse this verb's header counters by grep, and a quoted numeric example here would be matched first — the quality-delta legend's rule.
                 "After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, "
                 "unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; "
                 "amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed "
                 "symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. "
                 // T1: the completeness claim, defined where it appears (no attribute=value literal in these
                 // sentences, same rule as the R1 additions above — gates parse this legend by grep).
                 "COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: "
                 "a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on "
                 "this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is "
                 "complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly "
                 "which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by "
                 "complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the "
                 "prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, "
                 "or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless "
                 "— complete= speaks for the hit rows alone. "
                 // §R-J (Wave-2 harvest item R-J): queries/*/tags.scm (and any other unsupported-ext file that
                 // still reads as text) used to be invisible to EVERY verb — including the H-severity bug hunt
                 // whose root cause lived at that exact path. This is the fix: additively scan the crawl's own
                 // unsupported-ext/text-looking population and print its hits in a trailing block, never
                 // folded into the indexed count above and never claimed by complete=.
                 "unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's "
                 "own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a "
                 "trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as "
                 "above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file "
                 "scope. unindexed_files_skipped= (present only when nonzero) counts "
                 "candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. "
                 "unindexed_candidates_capped=\"1\" (present only when true) means the CANDIDATE list itself (the skipped verb's own "
                 "500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb "
                 "for every row. "
                 // G4 (2026-08-15 harvest): corpus_excluded=/corpus_oversize= — present only when non-zero,
                 // same absent-means-none convention as skippedOversize itself (model.h). Deliberately no
                 // literal 'hits="0"' example below (a quoted numeric example — the quality-delta legend's
                 // own rule, restated here after it bit a naive ` hits="N"` extraction downstream twice).
                 "corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; "
                 "corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an "
                 "otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped "
                 "verb itemizes the rows behind either count. "
                 "%s -->", rw::kPageRaiseCapClause );
    }
    emitGrepHandleLegend( cfg.grepHandles );
    // G3: terms=/scope=/suppressed= — only when AND/NOT was actually given, so a plain --grep answer
    // stays byte-identical to before G3 landed (the "purely additive" rule every ripwire flag follows).
    const std::string termsAttr = grepTermsAttrs( pat, grepTerms, grepScopeVal, termsSuppressed, esc );
    // G4 (2026-08-15 harvest, report-ugrep §F6): corpus_excluded=/corpus_oversize= — so hits="0" can
    // distinguish "not in this repo" from "in a file the crawl never scanned" (an --exclude= match, or a
    // file past --max-file-size). Absent when zero, matching skippedOversize's own "absent means nothing
    // was skipped" convention (model.h) — never a re-run hint (--skipped already itemizes the rows).
    const std::string corpusAttr = grepCorpusAttrs( ing );
    // R-H: the tier disclosure (helper above) — empty when nothing was held back.
    const std::string tierAttr = grepTierAttrs( tierReport );
    // §R-J: unindexed_files_scanned=/unindexed_files_skipped=/unindexed_candidates_capped= (helper above).
    const std::string auxAttr = grepUnindexedAttrs( aux );
    const char* schemaAttr = cfg.legend == "compact" ? " schema=\"ripwire.grep/v1\"" : "";
    std::printf( "<grep pattern=\"%s\"%s%s%s files=\"%d\" hits=\"%zu\"%s hits_capped=\"%d\"%s%s%s%s>",
                 ex( pat ).c_str(), schemaAttr, rootAttr.c_str(), termsAttr.c_str(), filesMatched, hitCount,
                 pageDisclosure( grab, sizeof( grab ), grepPage.end - grepPage.begin, hitCount, grepPage.end,
                                 cfg.pageLimit, cfg.pageOffset, true ),
                 hitsCapped, completeAttr, tierAttr.c_str(), corpusAttr.c_str(), auxAttr.c_str() );
    // G1 (2026-08-15 harvest): hits GROUP by file under <f p="…">, root-relative when this is a single-root
    // run (report-memgraph §F6: the absolute root prefix alone was 42.5% of a real --grep payload; the
    // repeated-per-hit path was report-octocode §F1's 31.4%). Byte-identical text within one file's group
    // folds via grepGroupByFile (search.h) when collapseOn — n= on the row (present only >1) plus <at l=…
    // in=…/> children carry the folded sites (report-graphrag Finding 2, 18.7% on a real corpus).
    // <m> = the Matched line itself, in the same one-letter CDATA shape as <b>efore and <a>fter (P5:
    // a hit used to say WHERE the pattern is but never WHAT it matched — with the context flags it
    // printed the lines around the hit and skipped the hit's own line, and without them it printed no
    // text at all, so in either mode the agent had to re-read the file to see what it had searched
    // for). Always emitted, in before → matched → after reading order, so a <hit> is never
    // self-closing now. appendCdataSafe (serialize.h) rather than the local cdataSafe lambda: the
    // matched line is arbitrary file bytes, so invalid UTF-8 must be scrubbed too, not just C0.
    for( const GrepFileGroup& group : grepGroupByFile( std::span<const GrepHit>( hits ), collapseOn ) )
    {
        std::printf( "<f p=\"%s\">", ex( pathFor( group.fileId ) ).c_str() );
        for( const GrepCollapsedHit& c : group.hits )
        {
            const GrepHit& h = c.hit;
            std::printf( "<hit l=\"%u\"", h.line );
            if( !h.enclosing.empty() )                // in= honesty: ABSENT means no enclosing symbol, never in=""
            {
                std::printf( " in=\"%s\"", ex( h.enclosing ).c_str() );
            }
            if( !c.more.empty() )
            {
                std::printf( " n=\"%zu\"", c.more.size() + 1 );   // 1 (this row) + the folded sites — sums to shown=
            }
            std::printf( ">" );
            if( !h.before.empty() )
            {
                const std::string safe = cdataSafe( h.before );
                std::printf( "<b><![CDATA[" );  std::fwrite( safe.data(), 1, safe.size(), stdout );  std::printf( "]]></b>" );
            }
            {
                std::string safe;
                appendCdataSafe( h.text, safe );
                std::printf( "<m><![CDATA[" );  std::fwrite( safe.data(), 1, safe.size(), stdout );  std::printf( "]]></m>" );
            }
            if( !h.after.empty() )
            {
                const std::string safe = cdataSafe( h.after );
                std::printf( "<a><![CDATA[" );  std::fwrite( safe.data(), 1, safe.size(), stdout );  std::printf( "]]></a>" );
            }
            for( const GrepHitSite& site : c.more )
            {
                std::printf( "<at l=\"%u\"", site.line );
                if( !site.enclosing.empty() )
                {
                    std::printf( " in=\"%s\"", ex( site.enclosing ).c_str() );
                }
                std::printf( "/>" );
            }
            std::printf( "</hit>" );
        }
        std::printf( "</f>" );
    }

    // ── §R-J: the aux block — files OUTSIDE the index (see unindexed_files_scanned= above), wrapped in its
    // OWN <unindexed> element (helper above) rather than left as bare <f> rows appended to the indexed
    // list. That boundary is load-bearing, not decoration: without it a reader (or a naive tag-walker)
    // cannot tell an indexed hit from a query/config file the crawl never parsed, which is exactly the
    // ambiguity complete= and in='s honesty rules exist to prevent elsewhere in this answer. Printed
    // strictly AFTER the indexed block (indexed source always outranks a query/config file for a reader's
    // attention) — and deliberately never folded/collapsed like grepGroupByFile does above: the candidate
    // population is already crawl-bounded (kMaxSkipRowsPerClass), so the folding machinery would add
    // complexity for a set too small to need it. No in= — see GrepAuxHit's own comment in search.h for why
    // that is a missing FIELD, not an omitted attribute.
    emitGrepUnindexed( aux.hits, singleRoot, rootPrefix, esc );

    // ── R1b: the <enc> block — the map's context on the answer, no second call (helper above) ──────
    const GrepEncOptions encOpt{ amp, tested, cfg.grepHandles,
                                cfg.roots.size() == 1 ? cfg.roots[0] : std::string_view(), esc };
    emitGrepEncRows( ing, g, std::span<const GrepHit>( hits ), encOpt );

    // ── R1a: the zero-hit follow-up — suggestions, labeled as such, never matches (helper above) ───
    // §R-J: also suppressed when the AUX block found the pattern — a real hit in queries/cpp/tags.scm is not
    // a zero-hit answer just because it sits outside the index, and printing SUGGESTIONS beside real matches
    // would misdescribe an answer that already found what it was looking for.
    if( hitCount == 0 && aux.hits.empty() )
    {
        emitGrepSuggest( ing, pat, cfg.grepRegex, esc );
    }
    std::printf( "</grep>" );
    return 0;
}

std::optional<int> runGrep( const MainDispatch& d )
{
    if( d.cfg.grep.empty() )
    {
        return std::nullopt; // not this verb — fall through the dispatch chain
    }
    // body: emitGrepReport() above. amp/tested are non-null only when a co-run (--metrics) computed
    // them at dispatch build time — grep itself never asks for the analysis (R1's no-new-analysis rule).
    return emitGrepReport( d.cfg, d.ing, d.g, d.ampPtr, d.testedPtr );
}


// §P6.8: when --token-budget is set, the map body must be MEASURED before any byte of it reaches the real
// stdout — the whole reason a caller sets a budget is to keep an oversized artifact out of a CI log, and
// streaming it anyway (even behind a non-zero exit) defeats that; a CI log then holds the exact artifact
// the gate just rejected. Mirrors --recall's own fix for the identical class (src/recall.h's
// emitRecallBudgeted: "measure, decide, then write — the order lives here, beside buildRecall, so no
// caller can re-order it") via the SAME open_memstream technique --max-tokens' own binary search uses.
// Lifted out of runDefaultMap (same reason as lintSymbolLevelChecks/dedupeLintFindings above it) so that
// function stays under the complexity/verbosity bar.
struct TokenBudgetBuffer
{
    std::FILE*  mem = nullptr;   // the open memstream, or nullptr when unbuffered (flag unset / open failed)
    char*       buf = nullptr;   // memstream's backing buffer — owned until finishTokenBudgetGate frees it
    std::size_t sz  = 0;
    std::FILE*  out = nullptr;   // what the caller should write the map body to: `mem` when buffering, else `real`
};

// Open the buffer. A memstream-open failure degrades to `real` directly (DEGRADED_PATH_ALERT) rather than
// losing the map — the budget is still ASSERTED afterward by finishTokenBudgetGate, it just can no longer
// WITHHOLD an over-budget map on that one run (buf stays null, so finishTokenBudgetGate's write-or-withhold
// branch is a no-op and the content — already streamed straight to `real` — is left exactly where it is).
inline TokenBudgetBuffer openTokenBudgetBuffer( std::size_t tokenBudget, std::FILE* real )
{
    TokenBudgetBuffer tb;
    if( tokenBudget == 0 ) { tb.out = real; return tb; }
    tb.mem = open_memstream( &tb.buf, &tb.sz );
    if( !tb.mem )
    {
        DEGRADED_PATH_ALERT( "openTokenBudgetBuffer: open_memstream failed — falling back to direct stdout" );
        tb.out = real;
        return tb;
    }
    tb.out = tb.mem;
    return tb;
}

// Close the buffer, decide against the budget, and either flush the buffered body to `real` (under budget
// — byte-identical to the unflagged run, measuring never shapes) or withhold it and print a small refusal
// record instead (shaped as XML or JSON to match what the caller asked for), naming actual vs budget on
// stderr. Returns 3 when over budget (the caller must return it immediately — nothing may write to `real`
// after that), std::nullopt otherwise (caller continues normally).
inline std::optional<int> finishTokenBudgetGate( TokenBudgetBuffer& tb, std::FILE* real,
                                                 std::size_t mapEstTokens, std::size_t tokenBudget, bool asJson )
{
    if( tb.mem ) { std::fflush( tb.mem ); std::fclose( tb.mem ); }
    if( tokenBudget > 0 && mapEstTokens > tokenBudget )
    {
        // §B7.8 — withheld_est_tokens=, not est_tokens=. `est_tokens` is normatively about what THIS RUN
        // PRINTED (pageview.h's truncation vocabulary, rule 1), and on this record the run printed the record
        // itself and nothing else: the number describes the artifact the caller did NOT receive. --recall
        // renamed the identical semantic for exactly that reason (recall.h's emitRecallBudgeted, N3) and this
        // sibling — inside the same round's own fix — kept the old spelling. Same vocabulary now, all three
        // channels (XML record, JSON record, stderr), so a script can key on one name.
        std::fprintf( stderr, "ripwire: --token-budget exceeded: withheld_est_tokens=%zu > budget=%zu\n", mapEstTokens, tokenBudget );
        if( tb.buf )
        {
            if( asJson )
            {
                std::fprintf( real, "{\"withheld_est_tokens\":%zu,\"budget\":%zu,\"withheld\":true}", mapEstTokens, tokenBudget );
            }
            else
            {
                std::fprintf( real, "<r withheld_est_tokens=\"%zu\" budget=\"%zu\" withheld=\"1\"/>", mapEstTokens, tokenBudget );
            }
        }
        std::free( tb.buf );
        return 3;
    }
    if( tb.buf ) { std::fwrite( tb.buf, 1, tb.sz, real ); std::free( tb.buf ); }
    return std::nullopt;
}

// §A9.6 — --rank-by=churn's teleport AND the window label the map has to disclose, as ONE answer. git
// change-frequency as the PageRank teleport is a proven prior (bias importance toward where the action is);
// no git in PATH / no history → churnTeleport returns uniform, so the whole verb degrades cleanly.
// --since=REV|DATE scopes the window to recent churn instead of the fixed 18-month default; an
// unresolvable value degrades to inactive → the default window, and the label says so.
//
// Lifted out of runDefaultMap because the ranking and its label are the same decision — which window was
// mined — and returning only the ranking left the caller to re-derive the label from cfg. That split is
// exactly how the churn map came to ship byte-shaped like a PageRank map for a whole release line.
// Multi-root has no per-root --since resolution (the workspace teleport mines the default window; churn is
// a rank prior there, not a report), so it reports the default label.
// §B2.2: whether the window mined ANY commits is the THIRD part of the same decision, and it belongs here for
// the same reason the label does. A window that mined nothing returns the uniform prior, so the ranking IS the
// structural one (ranks byte-identical to --rank-by=pagerank, stderr empty before this) and the label alone
// cannot tell the reader which of the two they are holding. So this function stamps the disclosure into the
// window (churnWindowStamp, the machine surface) AND prints the human line, in the shape --map-diff's
// git-unavailable degrade uses ("using uniform ranking") — one place owns "which window was mined, what to
// call it, and saying so when it was empty". Multi-root emits no stamp at all (mapAnn is single-root), which
// makes stderr its ONLY disclosure — another reason for the note to live on this side of the return.
// W2-F: `pr` rides along because churn ranking IS a PageRank run — a teleport variant, not a separate
// method — so the map it produces owes the same pr_iters= / pr_converged= disclosure a uniform one does.
struct ChurnRanking { std::vector<float> rank; std::string window; rw::RankDisclosure pr; };

// P0-4: the DEFAULT window label of each churn ranker, which is also the difference between them that a
// reader has to see. Plain churn mines a bounded 18-month wall-clock window; churn-decay mines the whole
// history and lets the half-life do the windowing, so its label says so AND names the half-life — the
// constant is a choice, and a choice that is not in the output is not disclosed.
inline std::string churnDecayWindowLabel( std::string_view minedSpan )
{
    std::string label{ minedSpan };
    label += " half-life=";
    label += std::to_string( int( rw::kChurnDecayHalfLifeDays ) );
    label += "d";
    return label;
}

inline ChurnRanking churnRankedGraph( const MainDispatch& d )
{
    using namespace rw;
    const bool isDecay          = ( d.cfg.rankBy == RankBy::ChurnDecay );
    const char* const verbLabel = isDecay ? "--rank-by=churn-decay" : "--rank-by=churn";
    bool hasChurnEvidence       = false;

    const auto discloseEmptyChurn = [ & ]( const std::string& windowStamp )
    {
        if( hasChurnEvidence )
        {
            return;
        }
        std::fprintf( stderr, "ripwire: %s found no commits in its window; using uniform (structural) ranking — this map is "
                              "byte-identical to --rank-by=pagerank (header: window=\"%s\")\n", verbLabel, windowStamp.c_str() );
    };

    if( d.multiRoot )
    {
        std::vector<std::string> rootDirs;
        for( const WorkspaceRoot& r : d.ws )
        {
            rootDirs.push_back( r.arg );
        }
        rw::RankedGraph    ranked = isDecay ? rankGraphTeleport( d.g, churnDecayTeleportWorkspace( rootDirs, d.ing, &hasChurnEvidence ) )
                                            : rankGraphTeleport( d.g, churnTeleportWorkspace( rootDirs, d.ing, "18 months ago", &hasChurnEvidence ) );
        std::string        window = churnWindowStamp( isDecay ? churnDecayWindowLabel( "all-history" ) : std::string( "18mo" ), hasChurnEvidence );
        discloseEmptyChurn( window );
        return { std::move( ranked.rank ), std::move( window ), { ranked.iterationCount, ranked.hasConverged, true } };
    }

    const SinceScope sinceScope = resolveSinceScope( d.root, d.cfg.since );
    const bool       isScoped   = !d.cfg.since.empty() && sinceScope.active;   // the §P9 N7 rule, one verb over
    if( isDecay )
    {
        rw::RankedGraph    ranked = rankGraphTeleport( d.g, churnDecayTeleport( d.root, d.ing, d.cfg.since.empty() ? nullptr : &sinceScope, &hasChurnEvidence ) );
        std::string        window = churnWindowStamp( churnDecayWindowLabel( isScoped ? std::string_view( d.cfg.since ) : std::string_view( "all-history" ) ),
                                                      hasChurnEvidence );
        discloseEmptyChurn( window );
        return { std::move( ranked.rank ), std::move( window ), { ranked.iterationCount, ranked.hasConverged, true } };
    }
    rw::RankedGraph    ranked = rankGraphTeleport( d.g, churnTeleport( d.root, d.ing, "18 months ago", d.cfg.since.empty() ? nullptr : &sinceScope, &hasChurnEvidence ) );
    std::string        window = churnWindowStamp( isScoped ? std::string_view( d.cfg.since ) : std::string_view( "18mo" ), hasChurnEvidence );
    discloseEmptyChurn( window );
    return { std::move( ranked.rank ), std::move( window ), { ranked.iterationCount, ranked.hasConverged, true } };
}

// ── M6 (density audit 2026-08-08): --expand cheapest-complete-answer serving, the two decisions ──────
// Hoisted out of runDefaultMap (already this file's largest dispatcher) because both are nameable
// concepts with pure inputs; the emission stays in runDefaultMap where the streams live.
//
// THE SCOPE: a bare --expand and nothing else. No explicit --top-k (the agent asked for the map, or for
// its absence at 0 — serve exactly that), no --outline/--pack-signatures/--pack-top-n (composed payloads
// keep the classic envelope), no --query/--adaptive/--max-tokens (all three shape the MAP, so the map is
// wanted), no --json (it refuses --expand anyway), no range slice (SYM:START-END asks for LESS than the
// symbol — serving the whole file would invert the ask; test/expandrangecheck.sh pins that contract),
// and only when the §H7 pre-render succeeded — a degraded render has no measured bytes to compare.
// D2 (audit regressions, 2026-08-08): --compress and --pack-budget-bytes are deliberately NOT in this
// predicate — they are body-SHAPING modifiers, and shaping COMPOSES with mode selection instead of
// disabling it: renderWholeFiles compresses the whole-file candidate, chooseExpandServe holds the
// whole-file candidate to the same pack budget packBodies enforces on the bundle, and the reason=
// disclosure compares the shaped candidates. Gates: compresscheck / overbudgetcommentcheck.
inline bool expandAutoServeScope( const rw::Config& cfg, bool anyExpandRange, bool bodiesRendered )
{
    return !cfg.expand.empty() && !cfg.topKExplicit && !cfg.json
        && cfg.outline.empty() && !cfg.packSignatures && cfg.packTopN == 0
        && cfg.query.empty() && !cfg.adaptive && cfg.maxTokens == 0
        && !anyExpandRange && bodiesRendered;
}

// THE CHOICE: whole-file when the served file bytes undercut the measured bundle, else bundle; ties go
// to the bundle (the richer answer at equal cost). A wf.complete=false render (a file unreadable NOW)
// makes whole-file not a candidate, and the reason says so instead of fabricating a byte comparison.
// D2 (audit regressions, 2026-08-08): both candidates are SHAPED before they are compared — wf.rawBytes
// is post---compress when that flag is on (renderWholeFiles), and bundleBytes was always the shaped
// bundle — so the disclosure never claims a comparison between two forms the caller was not offered.
// And --pack-budget-bytes composes rather than being silently outrun: a whole file cannot be
// budget-truncated and still be "the complete answer", so a file over the budget is NOT a candidate
// (the bundle's packBodies enforces that same budget with its over-budget omission markers), with the
// reason saying exactly that. The disclosure is mandatory and deterministic — every number is measured,
// never estimated. &lt; in the reason spelling: a raw '<' is ill-formed inside an XML attribute (G4).
struct ExpandServeChoice
{
    bool        serveWholeFile = false;
    std::string ctxOpen;
};

inline ExpandServeChoice chooseExpandServe( std::size_t bundleBytes, const rw::WholeFileRender& wf, std::size_t budgetBytes )
{
    char open[ 160 ];
    ExpandServeChoice c;
    if( wf.complete && wf.rawBytes > budgetBytes )
    {
        std::snprintf( open, sizeof( open ), "<ctx mode=\"bundle\" reason=\"whole-file %zuB over pack-budget %zuB\">",
                       wf.rawBytes, budgetBytes );
    }
    else if( wf.complete && wf.rawBytes < bundleBytes )
    {
        c.serveWholeFile = true;
        std::snprintf( open, sizeof( open ), "<ctx mode=\"whole-file\" reason=\"file %zuB &lt; bundle %zuB\">",
                       wf.rawBytes, bundleBytes );
    }
    else if( wf.complete )
    {
        std::snprintf( open, sizeof( open ), "<ctx mode=\"bundle\" reason=\"bundle %zuB &lt;= file %zuB\">",
                       bundleBytes, wf.rawBytes );
    }
    else
    {
        std::snprintf( open, sizeof( open ), "<ctx mode=\"bundle\" reason=\"whole-file unavailable (file unreadable)\">" );
    }
    c.ctxOpen = open;
    return c;
}

int runDefaultMap( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::string&                root         = d.root;
    const bool                        multiRoot    = d.multiRoot;
    const std::vector<WorkspaceRoot>& ws           = d.ws;
    const std::vector<std::uint32_t>* fanInPtr     = d.fanInPtr;
    const std::vector<std::uint32_t>* cboPtr       = d.cboPtr;
    const std::vector<std::uint8_t>*  testedPtr    = d.testedPtr;
    const std::vector<std::uint32_t>* lcom4Ptr     = d.lcom4Ptr;
    const std::vector<std::uint32_t>* ampPtr       = d.ampPtr;
    const std::vector<char>*          impurePtr    = d.impurePtr;
    RedactCounts*                     redactPtr    = d.redactPtr;
    RedactCounts&                     redactCounts = d.redactCounts;
    // R-E (2026-08-17 harvest): the SAME single-root condition emitGrepReport uses, so the default map's
    // root="…" and --grep's cannot diverge on when it appears. Multi-root already carries its own
    // roots=/<root label=…> disclosure inside serialize() and is untouched (rootArg stays empty there).
    const bool             mapSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view mapRootArg    = mapSingleRoot ? cfg.roots[0] : std::string_view();

    std::vector<float> rank;
    // W2-F: the map header's pr_iters= / pr_converged= (src/prconverge.h). Default-constructed is
    // isPageRank=false — CORRECT for the arms below that run no power iteration (a lexical query score, the
    // HITS vectors that overwrite `rank`); the PageRank arms fill it via rw::takeRank (graph.h), never apart.
    rw::RankDisclosure rankDisclosure;
    std::string        queryRouteNote;   // leading routed comment for --query (empty under --no-route)
    std::size_t        mapDiffChanged = 0;      // D6: teleport-seed file count, only meaningful when mapDiffActive
    bool               mapDiffActive  = false;  // true only under --map-diff — gates the header's changed= attribute
    std::string        churnWindowLabel = "18mo";   // §A9.6: churn's window label; an ACTIVE --since overrides it below
    if( !cfg.query.empty() )
    {
        // --query: PURE lexical (BM25) relevance. eval-at-scale showed fusing PageRank importance
        // into the lexical signal HURTS relatedness (RRF(struct,lex) lost to lex on 25/35 commits) —
        // PageRank ranks centrality, not relevance-to-a-query. So --query is lexical only.
        // ROUTING (default on, same confidence-gated classifier as --for): name-exact when the query NAMES a
        // symbol, else subtoken+body. --no-route forces subtoken+body (the pre-default behavior, byte-identical).
        // The map header comes from serialize (not ours to extend), so the routed pick is a LEADING comment
        // before the map, mirroring how --adaptive on --query surfaces its cut.
        // §P4 tier de-prioritization — same query-independent multiplier as --for's computeLensRanking
        // (filter.h): --query is a ranking lens too. --recall (docs lane) deliberately does NOT take this.
        const std::vector<float> tierMul = rankTierSymbolMultipliers( ing );
        if( !cfg.noRoute )
        {
            const RouteChoice rc = chooseForRanker( ing, cfg.query );
            rank = ( rc.which == LexMode::NameExact ) ? lexicalScoresNameExactRanked( ing, cfg.query, &tierMul )
                                                      : lexicalScoresTiered( ing, g.outOff, g.outTargets, cfg.query, 0, nullptr, &tierMul );
            // §B4 (capture-audit-4) — the SEVENTH comment-echo site, and the only one W3FIX M3 missed. It
            // hand-rolled the std::unique dash collapse that xmlCommentText's header names as the pattern it
            // replaced, and scrubbed NEITHER control bytes nor invalid UTF-8 — while RouteChoice::reason
            // embeds `identifierHit`, the user's own query token (lexical.h). So `--query=$'parseArgs\001x'`
            // put a raw 0x01 inside an XML comment and `--query=$'parseArgs\377x'` an invalid UTF-8 byte:
            // ripwire exited 0 and xmllint rejected the whole document, which is a G4 breach at exit 0 —
            // the ONE real breach a control byte swept through 19 value-taking verbs found.
            //
            // The dash collapse is byte-identical to what stood here (both reduce a run of '-' to one), so
            // every input that carried no control byte and no invalid sequence emits exactly the bytes it did
            // before; the fix is purely what the hand-rolled version could not see. The wrapping <!-- / -->
            // delimiters are still added AFTER, so they stay intact.
            queryRouteNote = "<!-- routed: " + std::string( rw::xmlCommentText( rc.reason ) ) + " -->";
        }
        else
        {
            rank = lexicalScoresTiered( ing, g.outOff, g.outTargets, cfg.query, 0, nullptr, &tierMul );
        }
    }
    else if( cfg.mapDiff )
    {
        // Multi-root (§5 / A8): the teleport seed is the UNION of the per-root diffs, each mined per repo.
        std::vector<char> changed( ing.files.size(), 0 );
        bool gitOk = false;
        if( multiRoot )
        {
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                if( gitChangedFiles( ws[r].arg, ing, changed, r ) )
                {
                    gitOk = true;
                }
            }
        }
        else
        {
            gitOk = gitChangedFiles( root, ing, changed );
        }
        mapDiffActive = true;   // D6: header emits changed= regardless of gitOk — 0 on a clean tree / no-git degrade too
        for( char c : changed )
        {
            if( c )
            {
                ++mapDiffChanged;
            }
        }
        if( gitOk )
        {
            rank = rw::takeRank( rankGraphTeleport( g, diffTeleport( ing, changed ) ), rankDisclosure );
        }
        else
        {
            std::fprintf( stderr, "ripwire: --map-diff requires git in PATH; using uniform ranking\n" );
            rank = rw::takeRank( rankGraph( g ), rankDisclosure );
        }
    }
    else if( cfg.rankBy == RankBy::Churn || cfg.rankBy == RankBy::ChurnDecay )
    {
        ChurnRanking cr = churnRankedGraph( d );        // §A9.6: the ranking and the window label it must disclose
        rank             = std::move( cr.rank );
        rankDisclosure   = cr.pr;                    // W2-F: churn is a PageRank TELEPORT variant — it runs the power iteration too
        churnWindowLabel = std::move( cr.window );   // §B2.2: already carries "(no churn evidence)" when the window mined nothing
    }
    else
    {
        rank = rw::takeRank( rankGraph( g ), rankDisclosure );
    }

    // HITS: surface hubs (entrypoints/orchestrators) or authorities (core APIs) instead of the default
    // PageRank order. (Churn is a PageRank-teleport variant handled above, not a HITS axis.)
    if( cfg.rankBy == RankBy::Authority || cfg.rankBy == RankBy::Hub || cfg.rankBy == RankBy::Rrf )
    {
        auto [ authority, hub ] = hits( g );
        if( cfg.rankBy == RankBy::Rrf )
        {
            rank = rrfFuse( { &rank, &authority, &hub } );   // fuse pagerank + authority + hub
        }
        else
        {
            // W2-F: hub and authority REPLACE the PageRank vector, so its disclosure must not survive either
            // (rrf above KEEPS it — pagerank is one of the three vectors it fuses, so that run shaped the order).
            rankDisclosure = rw::RankDisclosure{};
            rank           = ( cfg.rankBy == RankBy::Hub ) ? std::move( hub ) : std::move( authority );
        }
    }

    // R6 (A4-R6) — --format=candidates on --query: the same FLAT top-K export as the --for path, over the
    // lexical (BM25) rank. Bypasses the map/adaptive/html emission below (a single <candidates> root, G4-clean).
    // Guarded to a real --query (cli.h refuses --format=candidates without --for/--query); capped by --top-k.
    //
    // §P12.2 fix: --adaptive used to no-op here for the same "bypasses adaptive" reason stated above —
    // emitCandidates() now cuts BEFORE the bypass, exactly like --query's own default-map cut below
    // (scanFullDistribution=false: --query's ceiling is already the full top-k, no "capped at 40" to correct).
    if( cfg.candidates && !cfg.query.empty() )
    {
        // §A4f: --query does not go through --for's ranker router at all — it exports the query-personalized
        // graph rank, so route= names THAT and anchored= is 0 by construction (the §B8 mention anchor is a
        // --for-lens stage). Naming it explicitly beats leaving a reranker to assume the --for scale.
        emitCandidates( stdout, ing, rank, cfg.topK, cfg.adaptive, /*scanFullDistribution=*/false,
                        CandidateProvenance{ "query-personalized", 0, false }, redactPtr, mapRootArg );
        reportRedactions( stderr, d.redactCounts );      // W3-N1: same seam, same disclosure, on the --query arm
        return 0;
    }

    // --max-tokens=N: binary-search the largest top-K whose serialized map fits ~N tokens. T1: the map
    // output tokenizes at ~2.4-2.6 B/tok (MEASURED vs tiktoken; NOT 4) — the old ×4 over-filled by ~1.6×.
    // We size the byte budget with kMinBytesPerToken (the DENSEST language rate) × kBudgetHeadroom (90%)
    // so N is a real CEILING: the packed map's actual token count stays under N for any language mix.
    // (Claude's tokenizer isn't public → calibration + headroom, never a vendored BPE table; §2f.)
    //
    // §B13.4 — the two Ns are NOT the same unit, and now the map says so. --max-tokens=N fits BYTES
    // (N x 2.36 x 0.90) while est_tokens reports this corpus's own language-weighted rate, so a conformant fit
    // lands under N in the reported currency — MEASURED on src/: N=1500 honoured 3155 of its 3186-byte ceiling
    // and reported est_tokens=1216, i.e. 81% of the budget, with the shortfall disclosed nowhere and a --help
    // that invited composing --max-tokens with --token-budget as though the numbers were comparable. The
    // conservative ceiling STAYS — a cap that can be overshot is not a cap, and the tokenizer we are estimating
    // against is not public, so the densest-language rate plus a headroom factor is the only bound that holds
    // for any corpus. What was wrong was the silence, so mapAnn below carries max_tokens= and fit_bytes= onto
    // the shaped map, kMaxTokensFitLegend defines them, and --help states the relationship.
    // §F5 — THE ANNOTATIONS, RESOLVED ONCE, so the probe below and the emission at the bottom of this function
    // cannot describe two different documents. `mapAnn` used to be built ~250 lines down, AFTER the search, and
    // the search hand-built a second, SHORTER one (`probeAnn`: the fit only). Every annotation the probe did not
    // carry became a silent ceiling breach in the emitted map — MEASURED on src/: `--map-diff` +31 B (changed=,
    // at=) over the cap at N=3000/6000/12000, `--rank-by=churn` +118..204 B (rank_by=, window=, kChurnRankLegend)
    // over it at nearly every N up to 12000. `at=` is the one part that costs anything to compute, and its guard
    // is unchanged, so this hoist adds no git subprocess to any path that did not already run one.
    const bool        isChurnRanked = ( cfg.rankBy == RankBy::Churn || cfg.rankBy == RankBy::ChurnDecay ) && !multiRoot;
    const std::string mapDiffAt     = ( mapDiffActive && !multiRoot ) || isChurnRanked ? gitstamp::stampAt( root ) : std::string();
    // §A4d: BOTH serializations take the same per-edge provenance vector — resolved once here rather than
    // spelled as the same empty-check ternary on each arm, so the two formats cannot drift on this input.
    const std::vector<std::uint8_t>* mapProvPtr = g.outProv.empty() ? nullptr : &g.outProv;

    int                               mapTopK = cfg.topK;
    rw::MapAnnotations::MaxTokensFit maxTokensFit;
    // §B1.2: the run-provenance annotations, resolved ONCE for both serializations for the same reason
    // mapProvPtr is — the churn stamp used to be spelled on the XML arm only, so `--rank-by=churn --json`
    // and `--rank-by=pagerank --json` emitted keyset-identical headers over differently-meaning k=.
    // §B2.1: the windowless ranker label, from the ONE table serialize.h holds — so "which rankers stamp"
    // is a property of that table rather than of a switch here that a new ranker could be added without.
    // Churn is deliberately excluded: it stamps through churnWindowLabel (it has a window to disclose), and
    // the two fields are mutually exclusive by construction, which is what the serializer's `else if` asserts.
    const char* const rankByLabel = ( cfg.rankBy == RankBy::Authority ) ? "authority"
                                  : ( cfg.rankBy == RankBy::Hub )       ? "hub"
                                  : ( cfg.rankBy == RankBy::Rrf )       ? "rrf"
                                                                       : nullptr;
    const rw::MapAnnotations mapAnn{ mapDiffActive ? &mapDiffChanged : nullptr, &mapDiffAt,
                                      isChurnRanked ? &churnWindowLabel : nullptr,
                                      cfg.rankBy == RankBy::ChurnDecay ? "churn-decay" : "churn",   // P0-4
                                      cfg.maxTokens > 0 ? &maxTokensFit : nullptr,   // §B13.4
                                      rankByLabel,                                   // §B2.1
                                      rankDisclosure };                              // W2-F: pr_iters= / pr_converged=
    // T3's auto-flip changes the order= spelling ("important-last(auto:fill)" is 11 bytes longer than
    // "important-first"), so it is a BYTE fact, not only an ordering one — the comment that used to sit here
    // claimed the search was "unaffected by emit order", and at N=20000 on src/ the flip fires. One value,
    // read by the probe and by the emission.
    const bool mapAutoOrder = !cfg.noAutoOrder;

    // §F5 — ONE measurement of the map's own emitted bytes, used by the --max-tokens search below AND by the
    // ceiling VERDICT taken further down (`maxTokensFit.isOverCeiling`). Parameterized on extraPayloadTokens
    // because est_tokens is printed twice in the map's own header, so charging an appended §H7 payload grows
    // the map's own digit count: MEASURED on src/ at N=6000 --pack-signatures the map portion is 12 749 B
    // against a 12 744 B cap — 5 bytes over, from digits alone. The SEARCH prices the map alone (that is what
    // --max-tokens has always shaped, and the payload is not charged until ~250 lines below); the VERDICT is
    // taken afterwards, with the real number, so the label cannot miss that member either.
    //
    // DEGRADE: open_memstream failure returns 0, which reads as "fits" — the pre-§F5 behaviour, and the safe
    // direction here: a size this path could not measure must not mint an over_ceiling label it cannot support.
    const auto measureMapBytes = [ & ]( int k, std::size_t extraPayloadTokens ) -> std::size_t
    {
        char*       buf = nullptr;
        std::size_t sz  = 0;
        std::FILE*  m   = rw::openChargeBuffer( &buf, &sz );
        if( !m )
        {
            DEGRADED_PATH_ALERT( "runDefaultMap: open_memstream failed for the --max-tokens fit probe — the map is emitted unshaped and its ceiling unverified" );
            return 0;
        }
        serialize( m, ing, rank, g.outOff, g.outTargets, k, cfg.mostImportantLast, cfg.metrics, fanInPtr, &g.ambOut, cfg.stable, mapProvPtr, cboPtr, testedPtr, lcom4Ptr, ampPtr, &g.unresolvedOut, g.bindLabel.empty() ? nullptr : &g.bindLabel, mapAutoOrder, /*outEstTokens=*/nullptr, extraPayloadTokens, mapAnn, /*statsFirstScreen=*/false, mapRootArg );
        std::fflush( m );  std::fclose( m );  std::free( buf );
        return sz;
    };

    // §C4 (capture-audit-4, wave 3) — the same measurement in THE DIALECT THAT WILL ACTUALLY BE BUILT.
    //
    // measureMapBytes above calls serialize(), i.e. it prices the XML rendering, and under --json the document
    // that reaches stdout is serializeJson()'s. serialize.h's own §C4 note calls that out and records the fix as
    // "a main.cpp change, not smuggled in here" — this is that change, taken at the VERDICT and deliberately
    // NOT at the search (see the verdict site below for why the split, and what is still routed).
    //
    // MEASURED on src/, sweeping --max-tokens: the JSON document is under the ceiling up to N≈6000 and OVER it
    // from N≈6500 — +49 B at 6500, +319 B at 10000, +1545 B at 20000 — with no over_ceiling label anywhere,
    // because the label was decided from the XML measurement. So this is not a hypothetical dialect mismatch:
    // `--max-tokens=10000 --json` emitted 21559 B against the fit_bytes=21240 it printed in its own header and
    // called the cap honoured. Trap #8, on the key that exists to stop exactly that.
    //
    // serializeJson takes no extraPayloadTokens because it has no payload to take: jsonUnsupportedVerb refuses
    // every payload verb (--expand/--outline/--pack-signatures/--pack-top-n) under --json, so that argument is
    // provably 0 on this path — asserted rather than assumed.
    const auto measureEmittedMapBytes = [ & ]( int k, std::size_t extraPayloadTokens ) -> std::size_t
    {
        if( !cfg.json )
        {
            return measureMapBytes( k, extraPayloadTokens );
        }

        VERIFY( extraPayloadTokens == 0 );          // the payload verbs are all refused under --json
        char*       buf = nullptr;
        std::size_t sz  = 0;
        std::FILE*  m   = rw::openChargeBuffer( &buf, &sz );
        if( !m )
        {
            DEGRADED_PATH_ALERT( "runDefaultMap: open_memstream failed for the --max-tokens JSON ceiling probe — the ceiling verdict is unverified" );
            return 0;                                // reads as "fits" — the same safe direction measureMapBytes takes
        }
        serializeJson( m, ing, rank, g.outOff, g.outTargets, k, cfg.mostImportantLast, cfg.metrics,
                       fanInPtr, &g.ambOut, cfg.stable, cboPtr, testedPtr, lcom4Ptr, ampPtr, &g.unresolvedOut,
                       g.bindLabel.empty() ? nullptr : &g.bindLabel, mapAutoOrder, /*outEstTokens=*/nullptr, mapProvPtr, mapAnn, mapRootArg );
        std::fflush( m );
        std::fclose( m );
        std::free( buf );
        return sz;
    };
    const std::size_t maxTokensCeilingBytes = std::size_t( double( cfg.maxTokens ) * kMinBytesPerToken * kBudgetHeadroom );
    // §F5 (cont.) — THE <ctx> WRAPPER IS PART OF THE MAP PORTION THE CALLER RECEIVES. A payload verb
    // (--pack-signatures / --pack-top-n / --expand / --outline) opens `<ctx>` BEFORE serialize()'s own bytes
    // (the fprintf below, ahead of the §H7 pre-render), so everything through `</r>` is 5 bytes larger than
    // what measureMapBytes measures — and neither the search nor the verdict charged them: MEASURED on src/
    // at N=6000 --pack-signatures, serialize's own portion fit the 12 744 B cap by 4 bytes and the delivered
    // map portion was 12 745 B — 1 byte over, unlabelled (estchargecheck #5b's exact red). Charged in BOTH
    // the search and the verdict so the two keep describing the same delivered document. Computed from
    // `hasExtension` itself (hoisted to here — pure cfg, nothing the search changes) so the charge and the
    // wrapper fprintf below can never drift; every payload verb is refused under --json, so the JSON path's
    // charge is provably 0. The closing `</ctx>` lands AFTER `</r>`, in payload territory, and stays
    // charged to est_tokens like the rest of the payload, not to fit_bytes.
    const bool        hasExtension    = cfg.packSignatures || cfg.packTopN > 0 || !cfg.expand.empty() || !cfg.outline.empty();
    const std::size_t mapCtxOpenBytes = ( hasExtension && !cfg.json ) ? sizeof( "<ctx>" ) - 1 : 0;
    if( cfg.maxTokens > 0 )
    {
        maxTokensFit = { std::size_t( cfg.maxTokens ), maxTokensCeilingBytes, /*isOverCeiling=*/false };   // maxTokens is > 0 here (guarded above)
        // §B13.4 — the probe must price the shape it will actually BUILD. The disclosure this item adds
        // (max_tokens=/fit_bytes= plus kMaxTokensFitLegend) is ~215 bytes charged against this very ceiling, so
        // a probe that did not carry the same annotations chose a top-K whose real emission overran the ceiling
        // by exactly the disclosure's own size — MEASURED at N=1200: 3029 B against a 2548 B cap, caught by
        // estchargecheck #5. climbCeilingLadder states the general rule ("a caller can never price a shape it
        // then fails to build"); this is that rule at the map's own ceiling, and §F5 is the same rule again for
        // the three annotations the hand-built probeAnn dropped — hence `mapAnn`, the one the emission uses.
        int lo = 1, hi = int( ing.symbols.size() ), best = 1;
        while( lo <= hi )
        {
            const int mid = lo + ( hi - lo ) / 2;
            if( measureMapBytes( mid, 0 ) + mapCtxOpenBytes <= maxTokensCeilingBytes ) { best = mid; lo = mid + 1; }
            else
            {
                hi = mid - 1;
            }
        }
        mapTopK = best;
    }

    // routed pick for --query: a LEADING comment before the map (serialize owns the map header, not ours to
    // extend) — mirrors how --adaptive surfaces its cut. Emitted only for a real --query with routing on, and
    // NOT on the --html path (which returns above with its own document). Under --no-route the note is empty.
    if( !cfg.query.empty() && !cfg.html && !queryRouteNote.empty() )
    {
        std::fputs( queryRouteNote.c_str(), stdout );
    }

    // --adaptive on --query (lever 2): cut the ranked map at the relevance cliff, exactly like
    // the --for path. --query's rank IS the lexical score, so the cliff is meaningful; floor=5, ceiling=the
    // current mapTopK (post --max-tokens). We emit the note as a LEADING comment (the map header comes from
    // serialize and is not ours to extend). Only fires with --query (the guard in cli.h requires --for OR
    // --query); on a plain map cfg.adaptive is false → mapTopK untouched, output byte-identical.
    if( cfg.adaptive && !cfg.query.empty() )
    {
        const AdaptiveCut ac = adaptiveCut( rank, 5, std::size_t( mapTopK ) );
        char nb[ 208 ];
        if( !ac.hitCeiling && ac.cliffRank < ac.kept )
        {
            std::snprintf( nb, sizeof( nb ), "<!-- adaptive: kept %zu of %d - sharp cliff at rank %zu (%d%% drop), clamped up to the floor of %zu -->",
                           ac.kept, mapTopK, ac.cliffRank, ac.dropPct, ac.kept );
        }
        else if( !ac.hitCeiling )
        {
            std::snprintf( nb, sizeof( nb ), "<!-- adaptive: kept %zu of %d - cliff at rank %zu, %d%% drop -->",
                           ac.kept, mapTopK, ac.cliffRank, ac.dropPct );
        }
        else if( ac.positiveHits <= ac.kept )
        {
            std::snprintf( nb, sizeof( nb ), "<!-- adaptive: kept %zu of %d - only %zu symbols matched this query (sharp query, short tail) -->",
                           ac.kept, mapTopK, ac.positiveHits );
        }
        else
        {
            std::snprintf( nb, sizeof( nb ), "<!-- adaptive: kept %zu of %d - no relevance cliff (broad query saturates the score); capped at the ceiling -->",
                           ac.kept, mapTopK );
        }
        std::fputs( nb, stdout );
        mapTopK = int( ac.kept );
    }

    // --html[=FILE]: emit self-contained HTML force-directed graph instead of the default XML map.
    // Purely additive: when absent the default path is completely unchanged.
    if( cfg.html )
    {
        // churn for the --color-by=churn lens: THE shared per-file pass (mineChurnPerFile — also
        // --export=cc.json's and --hotspots'). Costs one git subprocess per root, matching cc.json's
        // posture; no evidence ⇒ the page's CHURN_OK legend note discloses instead of lying zeros.
        std::vector<std::uint32_t> htmlChurn( ing.files.size(), 0 );
        const rw::SinceScope       htmlScope;   // inactive: --html has no --since form
        const bool htmlChurnOk = mineChurnPerFile( ing, root, multiRoot, ws, std::string_view(), htmlScope, "18 months ago", htmlChurn );

        // tested for the --color-by=tested lens: QMetrics is computed upstream only under
        // --metrics/--for/--exemplar, so on a bare --html run testedPtr is null and every node would
        // read ts:0 — a "not computed" masquerading as "untested". Compute it here instead
        // (computeQMetrics is pure graph work, no git subprocess) so ts= is always a measured fact.
        QMetrics htmlQm;
        if( !testedPtr )
        {
            htmlQm    = computeQMetrics( ing, g );
            testedPtr = &htmlQm.tested;
        }

        std::FILE* htmlOut = stdout;
        if( !cfg.htmlFile.empty() )
        {
            // open the target file for writing; report failure and exit cleanly
            const std::string htmlPath( cfg.htmlFile );
            htmlOut = std::fopen( htmlPath.c_str(), "wb" );
            if( !htmlOut )
            {
                DEGRADED_PATH_ALERT( "writeHtml: could not open output file" );
                std::fprintf( stderr, "ripwire: --html=%s: cannot open file for writing\n", htmlPath.c_str() );
                return 1;
            }
        }
        writeHtml( htmlOut, ing, rank, g, mapTopK, HtmlColorExtras{ testedPtr, &htmlChurn, htmlChurnOk, cfg.colorBy }, mapRootArg );   // R-R
        if( htmlOut != stdout )
        {
            std::fclose( htmlOut );
        }
        return 0;
    }

    // When an extension verb appends additional blocks after the main <r> map, the combined output
    // would have multiple XML root elements — invalid per the XML spec (G4 violation). Fix: wrap
    // the ENTIRE output (map + extension blocks) in a single <ctx> root whenever extension output
    // is present. The DEFAULT map (no extension verb) is emitted UNwrapped, exactly as before, so
    // the golden and all existing callers that parse the bare <r>…</r> are unaffected.
    // (`hasExtension` itself is defined beside mapCtxOpenBytes above, so the wrapper's 5 delivered
    // bytes and the --max-tokens search/verdict that charge them read the same predicate.)

    // --expand est_tokens bugfix: the <bodies> block that packBodies appends AFTER the map is
    // part of the payload the caller receives, so the header's est_tokens must include it (before this fix it
    // reported the map only — a --token-budget gate on a large --expand under-budgeted by ~2×). Resolve the
    // expand nodes HERE (once) so both the header estimate below and the packBodies emission later reuse the
    // SAME node/range set — no drift between "estimated" and "emitted", and no double name-resolution.
    // D7: a miss exits 1, like --callers/--impact.
    // r27-emitters T3: the resolution now runs BEFORE the first stdout byte, and a miss returns immediately —
    // --expand was the only verb that paired a refusal (exit 1) with a 22 KB payload of UNRELATED map, which
    // reads to a caller as "here is your answer" with a stray non-zero code. Refuse and write nothing, exactly
    // like --callers/--callees/--impact/--lego/--around/--edit-check.
    std::vector<NodeId>         expandNodes;
    HashMap<NodeId, LineRange>  expandRanges;
    if( !cfg.expand.empty() )
    {
        bool expandMissed = false;
        for( const std::string& tok : cfg.expand )
        {
            // §P8 seam 1: resolveAllByNameQualified — the SAME resolver --callers/--callees/--impact use,
            // so `file:name` / `file:line:name` / a canonical id / a bare name all mean here exactly what
            // they mean there. On a bare name it is byte-identical to the resolveAllByName it replaces.
            const ExpandToken         et      = parseExpandToken( tok, "--expand" );
            const std::vector<NodeId> matches = resolveAllByNameQualified( ing, et.selector );
            if( matches.empty() )
            {
                // §M7 (W3FIX): --expand takes the same file:name grammar as --uses/--callers and refused in the
                // pre-§B4.2 dialect — a bare did-you-mean about a NAME that may well exist, when the fault is
                // the path half. selectorFaultClause does the split (and states when the path itself is
                // unindexed); this arm keeps its own flag-first sentence byte-for-byte ahead of it.
                expandMissed = true;
                std::fprintf( stderr, "ripwire: --expand=%s matched no symbol%s\n", et.selector.c_str(),
                              rw::selectorFaultClause( ing, et.selector, "--expand=" ).c_str() );
            }
            else if( matches.size() > 8 )
            { // final-segment names (reset/size/update) collide widely
                std::fprintf( stderr, "ripwire: --expand=%s matches %zu symbols; emitting all up to --pack-budget-bytes (qualify with file:name to narrow)\n",
                              et.selector.c_str(), matches.size() );
            }
            for( NodeId id : matches )
            {
                expandNodes.push_back( id );
                if( et.range.hasRange )
                {
                    expandRanges[id] = et.range; // same range applies to every match of this token
                }
            }
        }
        if( expandMissed )
        {
            return 1; // refusal + empty stdout — nothing has been printed yet
        }
    }

    // V1 (routing note ugrep RN2, 2026-08-15): an EXACT-NAME --expand — one token that resolved to exactly
    // one symbol — needs no orientation map: the caller already named the exact target, so the top-200
    // ranked map is pure overhead in front of the one body it exists to summarize (MEASURED on this repo:
    // 12,944 est_tokens of map ahead of a ~1.4 KB body). Default top-k to 0 for this shape. An explicit
    // --top-k=N (0 included) always overrides — see the explicit-top-k guard just below. A MULTI-match name
    // (matches.size() > 1) or a multi-token --expand keep the caller's ordinary default: there IS something
    // to disambiguate/orient there, the exact reason expandAutoServeScope's lean-does-not-auto-compete
    // rationale still holds. Composed verbs already claim the map for their own purpose, so they are
    // excluded here exactly like expandAutoServeScope excludes them below.
    const bool exactNameExpandDefault = cfg.expand.size() == 1 && expandNodes.size() == 1 && !cfg.topKExplicit
        && cfg.outline.empty() && !cfg.packSignatures && cfg.packTopN == 0 && cfg.query.empty()
        && !cfg.adaptive && cfg.maxTokens == 0 && !cfg.json;
    if( exactNameExpandDefault )
    {
        mapTopK = 0;
    }

    // --outline=NAME,...: same resolution, same refusal contract. A miss used to emit the map and exit 0,
    // so a typo'd outline was indistinguishable from a successful one.
    std::vector<NodeId> outlineNodes;
    if( !cfg.outline.empty() )
    {
        bool outlineMissed = false;
        for( const std::string& rawNm : cfg.outline )
        {
            // --outline has no range form (a control-flow skeleton is a whole-symbol shape), but SYM:START-END
            // is the muscle memory --expand teaches. Strip the range and say so, rather than letting the
            // literal "SYM:5-10" miss and get reported as a TYPO with a did-you-mean — the name was fine.
            // §P10 X7: `verb` is passed so a malformed range on --outline no longer emits a note blaming
            // --expand. §P8 seam 1: the file:name / file:line:name selector resolves here exactly as it does
            // on --expand and --callers (same resolveAllByNameQualified), so an --outline of ONE overload is
            // finally expressible.
            const ExpandToken ot = parseExpandToken( rawNm, "--outline" );
            const std::string nm = ot.range.hasRange ? ot.selector : rawNm;
            if( ot.range.hasRange )
            {
                std::fprintf( stderr, "ripwire: --outline=%s: --outline has no line-range form — outlining the whole symbol "
                                      "(use --expand=%s:%u-%u for a body slice)\n",
                              rawNm.c_str(), ot.selector.c_str(), ot.range.startLine, ot.range.endLine );
            }

            const std::vector<NodeId> matches = resolveAllByNameQualified( ing, nm );
            if( matches.empty() )
            {
                // §M7 (W3FIX): same grammar, same shared refusal as --expand above.
                outlineMissed = true;
                std::fprintf( stderr, "ripwire: --outline=%s matched no symbol%s\n", nm.c_str(),
                              rw::selectorFaultClause( ing, nm, "--outline=" ).c_str() );
            }
            for( NodeId id : matches )
            {
                outlineNodes.push_back( id );
            }
        }
        if( outlineMissed )
        {
            return 1;
        }
    }

    // §P6.8: `out` replaces every `stdout` from here through the map body's closing tag, so nothing reaches
    // the real stdout until finishTokenBudgetGate below has measured and decided (see openTokenBudgetBuffer's
    // comment above runDefaultMap). No-op when --token-budget is unset — `out` is just `stdout`.
    TokenBudgetBuffer tbBuf = openTokenBudgetBuffer( cfg.tokenBudget, stdout );
    std::FILE* const  out   = tbBuf.out;

    // (M6: the `<ctx>` opener used to be printed HERE, before the §H7 pre-render. Nothing writes to `out`
    // between here and the emission below — the pre-render goes to memstreams — so the open moved down to
    // where the mode decision can decorate it; byte order on the wire is unchanged.)

    // §H7 — PRE-RENDER every block that gets appended after the map, and CHARGE it from its own emitted bytes.
    // The ordering constraint is real and it is the whole reason this block sits HERE, above serialize(): the
    // header states est_tokens, so it can only be written once the payload it describes has been measured, but
    // it is written FIRST in the document. Before this, only --expand fed the header (through a bespoke
    // ~90-line estimator), and <sigs>/<src>/<outline> fed it nothing — so a --token-budget gate saw a 507-token
    // map and let 67 KB through (§H7's own repro). Each section is charged at the rate for what its bytes ARE:
    // <sigs> is markup + signatures (the mid-band rate the --for lens's own bundle estimate uses), while <src>,
    // <bodies> and <outline> are code TEXT, which BPE merges far more aggressively (kBytesPerTokenBody).
    // rw::chargeSection degrades to isRendered=false, and the emission below then streams that section
    // directly — uncharged for that one run, with an alert, never a fabricated number.
    rw::ChargedSection sigsSection, srcSection, bodiesSection, outlineSection;
    if( cfg.packSignatures )
    {
        sigsSection = rw::chargeSection( [ & ]( std::FILE* f )
            { packSignatures( f, ing, rank, cfg.packTopN > 0 ? cfg.packTopN : 50, cfg.packBudgetBytes, false, nullptr, impurePtr, redactPtr,
                              nullptr, nullptr, nullptr, nullptr, false, 0, nullptr, mapRootArg ); },
            rw::kBytesPerTokenDefault );
    }
    else if( cfg.packTopN > 0 )
    {
        srcSection = rw::chargeSection( [ & ]( std::FILE* f )
            { packSource( f, ing, rank, cfg.packTopN, cfg.packBudgetBytes, redactPtr ); },
            rw::kBytesPerTokenBody );
    }
    if( !expandNodes.empty() )
    {
        bodiesSection = rw::chargeSection( [ & ]( std::FILE* f )
            { packBodies( f, ing, expandNodes, cfg.packBudgetBytes, g.outOff, g.outTargets, cfg.compress, redactPtr,
                          expandRanges.empty() ? nullptr : &expandRanges, d.notesPtr, /*outEmitted=*/nullptr,
                          /*truncateOversizedFirst=*/true, /*withFileContext=*/true, mapRootArg ); },   // V1: octocode F2 sibs=/inc=
            rw::kBytesPerTokenBody );
    }
    if( !outlineNodes.empty() )
    {
        outlineSection = rw::chargeSection( [ & ]( std::FILE* f )
            { packOutline( f, ing, outlineNodes, cfg.packBudgetBytes, cfg.compress, redactPtr, mapRootArg ); },
            rw::kBytesPerTokenBody );
    }

    // The --expand fallback: estimateExpandBodyTokens is no longer the primary estimate (measured bytes are),
    // but it remains the honest answer on the degrade path — better than dropping the <bodies> block out of the
    // charge entirely, which is the defect this whole item is about.
    const std::size_t payloadTokens = sigsSection.tokens + srcSection.tokens + outlineSection.tokens
        + ( ( !expandNodes.empty() && !bodiesSection.isRendered )
                ? estimateExpandBodyTokens( ing, expandNodes, cfg.packBudgetBytes, g.outOff, g.outTargets, cfg.compress,
                                            expandRanges.empty() ? nullptr : &expandRanges )
                : bodiesSection.tokens );

    // ── M6 (density audit 2026-08-08, owner directive: ONE call does the smart thing, no two-step) ──────
    // CHEAPEST-COMPLETE-ANSWER SERVING for a BARE --expand. The verb could always serve three forms:
    //   (a) bundle     = ranked map + <bodies> (+ inline callee sigs) — today's default;
    //   (b) lean       = the --top-k=0 bodies-only form;
    //   (c) whole-file = the requested symbols' own file(s), CDATA-wrapped, line anchors kept.
    // Measured on this repo, (a) is 5.65x LARGER than the whole file for a small-file symbol
    // (--expand=pageRankDouble: 27,890 B vs src/pagerank.cpp 4,936 B — and even (b) is 1.08x the file),
    // while on a big file (a) saves ~26x over reading the file. So with NO explicit --top-k the verb now
    // compares (a) against (c) — both rendered-and-measured, not estimated — and emits the smaller,
    // disclosing the choice deterministically on the root: mode="bundle|whole-file" reason="the two byte
    // counts compared". (b) deliberately does NOT compete in the auto choice: it is a strict byte-subset
    // of (a), so a three-way minimum could never serve the map and a bare --expand would silently lose its
    // orientation value — lean stays the caller's EXPLICIT choice. An explicit --top-k=N (including 0)
    // overrides auto-selection entirely and keeps the legacy undecorated shape: the agent asked for the
    // map (or its absence), serve exactly that. Ties go to the bundle (the richer answer at equal cost).
    // Scope and choice are the two free functions above runDefaultMap (expandAutoServeScope /
    // chooseExpandServe — the rationale lives on them); the emission below stays here with the streams.
    // Gate: test/expandmodecheck.sh.
    bool                serveWholeFile = false;
    rw::WholeFileRender wholeFile;
    // V1: the exact-name default's root disclosure — "assert absence + a root attribute" (ugrep RN2). Set as
    // the INITIAL value so it survives even when expandAutoServeScope below does not run (a range slice, or
    // a pre-render degrade) — every path exactNameExpandDefault can reach ends up with SOME <ctx ...> to
    // decorate, since hasExtension is provably true whenever --expand is non-empty.
    std::string         ctxOpenStr = exactNameExpandDefault ? "<ctx topk_default=\"0\">" : "<ctx>";
    // R-E fix (2026-08-19): the payload document root DISCLOSES the root its p= are relative to, on the two
    // shapes where the ride-along map's <r root=…> is NOT there to do it — no map at all (mapTopK==0, which
    // the exact-name --expand default always picks) and whole-file mode. The first R-E landing made
    // packBodies/packOutline emit root-relative p= and left both of those serving relative paths against an
    // unnamed root. Gated on the map's absence rather than emitted unconditionally because rootrelcheck.sh's
    // own contract is that a document discloses its root ONCE — a <ctx root=> beside an <r root=> is two.
    // Computed HERE, ahead of the bundle price below, because those bytes are part of the document that
    // price describes (expandtopk0check §G-b compares the priced number to the real --top-k=0 byte count).
    std::vector<char>  ctxRootEsc;
    const std::string  ctxRootAttr = ( mapRootArg.empty() || cfg.json )
                                   ? std::string()
                                   : ( " root=\"" + std::string( rw::escapeXml( mapRootArg, ctxRootEsc ) ) + "\"" );
    const std::size_t  ctxRootBytesWhenNoMap = ( mapTopK == 0 ) ? ctxRootAttr.size() : 0;
    if( expandAutoServeScope( cfg, !expandRanges.empty(), bodiesSection.isRendered ) )
    {
        // Bundle total = "<ctx>" + the map as it would actually be emitted (payload token digits included)
        // + the pre-rendered <bodies> + "</ctx>". Rendering-and-measuring beats arithmetic here: the map's
        // est_tokens digits depend on the payload charge, and a probe that prices a shape it then fails to
        // build is the exact climbCeilingLadder failure mode this file already documents.
        // V1 fix (verifier finding 1, 2026-08-15): mapTopK==0 means UNLIMITED inside serialize(), not "no
        // map" — an unguarded call here priced the whole-repo map (~1MB on this tree) that the emission
        // path below never prints (mapTopK==0 skips straight to the topK>0 branch's `else`, see the two
        // guarded siblings at the ceiling verdict and the topK>0 emission gate). Same guard here: a map
        // that will not be emitted must not be charged, exactly like every other measureEmittedMapBytes
        // call site in this function.
        const std::size_t bundleBytes = ( sizeof( "<ctx>" ) - 1 ) + ctxRootBytesWhenNoMap
                                      + ( mapTopK > 0 ? measureEmittedMapBytes( mapTopK, payloadTokens ) : 0 )
                                      + bodiesSection.xml.size() + ( sizeof( "</ctx>" ) - 1 );
        wholeFile = rw::renderWholeFiles( ing, expandNodes, redactPtr, d.notesPtr, cfg.compress, mapRootArg );   // D2: shaped candidate (R-R: root-relative <src p=>)
        ExpandServeChoice choice = chooseExpandServe( bundleBytes, wholeFile, cfg.packBudgetBytes );
        serveWholeFile = choice.serveWholeFile;
        ctxOpenStr     = std::move( choice.ctxOpen );
        if( exactNameExpandDefault )
        {
            // chooseExpandServe's four formatted opens all start "<ctx mode=\"...\" reason=\"...\">" — insert
            // right after "<ctx" so the self-describing default rides alongside whichever mode/reason M6
            // independently picked (bundle-without-a-map still beats a huge whole-file, so this composes).
            VERIFY( ctxOpenStr.rfind( "<ctx", 0 ) == 0 );
            ctxOpenStr.insert( 4, " topk_default=\"0\"" );
        }
    }
    // …and the insert itself, same technique topk_default= uses right above (the four chooseExpandServe
    // openers all start with that literal). Fires only where no map will carry the disclosure — see the
    // ctxRootAttr comment above the bundle price.
    if( !ctxRootAttr.empty() && ( serveWholeFile || mapTopK == 0 ) )
    {
        VERIFY( ctxOpenStr.rfind( "<ctx", 0 ) == 0 );
        ctxOpenStr.insert( 4, ctxRootAttr );
    }

    // r27-emitters T2: the ride-along map. A bare `--expand=SYM` costs ~24 KB for a ~1.4 KB body because the
    // 200-symbol default map is emitted alongside it, and nothing ever said so. The M6 auto-selection above
    // now drops the whole bundle when the FILE is cheaper; when the bundle (map included) IS the cheaper
    // complete answer, the map still rides and the caller is still TOLD, once, on stderr (stdout stays
    // byte-identical), with --top-k=0 as the documented off switch. Fires only when the user did not choose
    // a top-k themselves, and never in whole-file mode (there is no map riding along to warn about).
    // V1: also never fires when mapTopK==0 via exactNameExpandDefault — there is no map riding along to warn
    // about there either, and printing "top-0 map rides along" would be both false and confusing.
    if( !cfg.topKExplicit && ( !cfg.expand.empty() || !cfg.outline.empty() ) && !cfg.json
        && !serveWholeFile && mapTopK > 0 )
    {
        std::fprintf( stderr, "ripwire: note — the ranked top-%d map rides along with your requested bodies; add --top-k=0 for the bodies alone (or --top-k=1 for a minimal map)\n", mapTopK );
    }

    // §F5 — THE CEILING VERDICT, taken here because this is the first point where every input to the map's own
    // byte count is settled: mapTopK (post --max-tokens, post --adaptive) and payloadTokens (the §H7 charge that
    // grows the header's est_tokens digits). `best` in the search above is INITIALISED to 1 — "emit one symbol
    // even if nothing fits" — and nothing ever checked that floor against the ceiling: on src/ at N<=450 the
    // floor alone (envelope + legend + this round's own disclosure clause) is 975 B against an 849 B cap, i.e.
    // 15% over at rc=0 with empty stderr and the 849 printed inside the 975-byte document. A cap that can be
    // overshot is not a cap, so where the map provably does not fit, it SAYS so — the over_ceiling treatment
    // --for/--pack-task/--recall already give the identical state. MEASURED, never assumed. Monotone: the label
    // only ADDS bytes to a document already past the ceiling, so there is no verdict to iterate.
    //
    // §C4 (wave 3): the verdict measures the EMITTED dialect (measureEmittedMapBytes), the search above still
    // prices XML. That split is deliberate and it is the honest half of a two-part fix:
    //   * the VERDICT is a claim about the document the caller receives, so it must measure that document —
    //     and it is entirely inside this file, so it lands here, complete;
    //   * the SEARCH picking a top-K from the XML rendering is disclosed by serialize.h's
    //     `fit_measured_in":"xml"`, which is TRUE today and becomes FALSE the moment the search changes
    //     dialect. That one word lives in serialize.h, which this lane does not own, so changing the search
    //     here would ship a document whose own disclosure contradicts it. ROUTED, with the measurement, to
    //     whoever owns both halves — the cap does not yet HOLD under --json, but from here it is LABELLED.
    // §F5 (cont.): + mapCtxOpenBytes — the `<ctx>` opener a payload verb prints ahead of serialize()'s bytes
    // is inside the delivered map portion (everything through `</r>`), so the verdict charges it exactly as
    // the search above did; see mapCtxOpenBytes's own comment for the 1-byte-over measurement that found it.
    if( cfg.maxTokens > 0 && mapTopK > 0
        && measureEmittedMapBytes( mapTopK, cfg.json ? 0 : payloadTokens ) + mapCtxOpenBytes > maxTokensCeilingBytes )
    {
        maxTokensFit.isOverCeiling = true;
    }

    std::size_t mapEstTokens = 0;   // --token-budget reads this — the SAME value serialize() puts in the header, never a second counter
    if( serveWholeFile )
    {
        // M6 whole-file serving: the file IS the complete answer — no map, no <bodies>. The bytes were
        // rendered (and the choice measured) above; --token-budget still gates the real document, charged
        // at the BODY rate because this payload is raw code text, exactly like <src>/<bodies> sections.
        std::fwrite( ctxOpenStr.data(), 1, ctxOpenStr.size(), out );
        std::fwrite( wholeFile.xml.data(), 1, wholeFile.xml.size(), out );
        std::fputs( "</ctx>", out );
        mapEstTokens = rw::tokensForEmittedBytes( ctxOpenStr.size() + wholeFile.xml.size() + ( sizeof( "</ctx>" ) - 1 ),
                                                  rw::kBytesPerTokenBody );
    }
    else if( mapTopK > 0 )          // --top-k=0: payload only — skip the ranked map entirely (never the payload below)
    {
        if( hasExtension )
        {
            std::fwrite( ctxOpenStr.data(), 1, ctxOpenStr.size(), out );   // "<ctx>", or M6 bundle mode's decorated form
        }
        // T3: fill-aware auto important-last — ONLY on this, the default map emission. --no-auto-order opts
        // out; an explicit --most-important-last or --stable always wins (serialize.h). test/fixture
        // (est_tokens=619) and src/ (~10.6K) both stay under the ~16K threshold, so the default/golden output is
        // unchanged — this only engages on large maps. §F5: the flip also LENGTHENS the order= spelling by 11
        // bytes, which the --max-tokens probe above now prices because it reads the same `mapAutoOrder`; the
        // comment that used to sit here asserted the opposite ("cannot affect the --max-tokens binary search").
        PROFILE_SCOPE_DESCRIBE( "emit: serialize ranked map" );
        // L2: --json's default-map sibling. jsonUnsupportedVerb() already refused every combination this
        // path doesn't cover (--scip/--map-diff/--pack-signatures/--expand/--outline/--pack-top-n), so the
        // extension blocks below (hasExtension) are correctly no-ops since their trigger flags are all
        // refused above. §A4b: MULTI-ROOT was never in that refusal list despite serialize.h's comment
        // claiming it was — the JSON sibling emits the roots table itself now, as the XML always has.
        // §F5: mapAnn / mapProvPtr / mapAutoOrder are resolved once, ABOVE the --max-tokens search, so the
        // probe and this emission describe the same document — see their definitions there (that hoist carries
        // the r26-stamp / §A9.6 / §A4d / §B1.2 rationale the ternaries used to carry here).
        if( cfg.json )
        {
            serializeJson( out, ing, rank, g.outOff, g.outTargets, mapTopK, cfg.mostImportantLast, cfg.metrics,
                           fanInPtr, &g.ambOut, cfg.stable, cboPtr, testedPtr, lcom4Ptr, ampPtr, &g.unresolvedOut,
                           g.bindLabel.empty() ? nullptr : &g.bindLabel, mapAutoOrder, &mapEstTokens, mapProvPtr, mapAnn, mapRootArg );
        }
        else
        {
            serialize( out, ing, rank, g.outOff, g.outTargets, mapTopK, cfg.mostImportantLast, cfg.metrics, fanInPtr, &g.ambOut, cfg.stable, mapProvPtr, cboPtr, testedPtr, lcom4Ptr, ampPtr, &g.unresolvedOut, g.bindLabel.empty() ? nullptr : &g.bindLabel, mapAutoOrder, &mapEstTokens, payloadTokens, mapAnn, /*statsFirstScreen=*/false, mapRootArg );
        }
    }
    else
    {
        // --top-k=0: serialize() (which normally folds payloadTokens into mapEstTokens for exactly this
        // reason) never ran, so --token-budget would gate on 0 and pass no matter how large the payload is.
        // The payload IS the emitted output here — budget against it. (Explicit --top-k=0 never enters the
        // M6 auto scope, so ctxOpenStr is the bare "<ctx>" on this path.)
        if( hasExtension )
        {
            std::fwrite( ctxOpenStr.data(), 1, ctxOpenStr.size(), out );
        }
        mapEstTokens = payloadTokens;
    }

    // §H7: the appended sections, in the same order as before — from the bytes already RENDERED and CHARGED
    // above, so what the header priced and what stdout receives are the same bytes by construction, not by two
    // pieces of code agreeing. A section whose pre-render degraded (isRendered=false) is emitted here directly.
    //
    // --expand=NAME,... or --expand=NAME:START-END,...: the full (or, with a range, a SLICED) def bodies for
    // the named symbols — the L4 "one definition, not the whole file" rung, plus octocode's partial-fetch rung
    // on top of it. --outline=NAME,...: control-flow skeletons (L3), the ladder's middle rung. Both compose
    // with --pack-signatures (skeleton + bodies).
    // §F1: this was a local lambda; it is now rw::emitChargedSection, shared with the four emission points
    // the --for / --pack-task / --around lenses gained (serialize.h, beside chargeSection — the two halves of
    // one contract belong together).
    const auto emitSection = [ & ]( const rw::ChargedSection& sec, auto&& renderDirect )
    { rw::emitChargedSection( out, sec, renderDirect ); };
    if( cfg.packSignatures )
    {
        emitSection( sigsSection, [ & ]{ packSignatures( out, ing, rank, cfg.packTopN > 0 ? cfg.packTopN : 50, cfg.packBudgetBytes, false, nullptr, impurePtr, redactPtr,
                                                         nullptr, nullptr, nullptr, nullptr, false, 0, nullptr, mapRootArg ); } );
    }
    else if( cfg.packTopN > 0 )
    {
        emitSection( srcSection, [ & ]{ packSource( out, ing, rank, cfg.packTopN, cfg.packBudgetBytes, redactPtr ); } );
    }
    if( !expandNodes.empty() && !serveWholeFile )   // M6: whole-file mode already served the file itself
    {
        emitSection( bodiesSection, [ & ]{ packBodies( out, ing, expandNodes, cfg.packBudgetBytes, g.outOff, g.outTargets, cfg.compress, redactPtr,
                                                       expandRanges.empty() ? nullptr : &expandRanges, d.notesPtr, /*outEmitted=*/nullptr,
                                                       /*truncateOversizedFirst=*/true, /*withFileContext=*/true, mapRootArg ); } );   // L3: --expand bodies surface notes; V1: sibs=/inc=
    }
    if( !outlineNodes.empty() )
    { // resolved (and refused on a miss) above, before the first stdout byte
        emitSection( outlineSection, [ & ]{ packOutline( out, ing, outlineNodes, cfg.packBudgetBytes, cfg.compress, redactPtr, mapRootArg ); } );
    }

    if( hasExtension && !serveWholeFile )   // M6: the whole-file branch closed its own root
    {
        std::fprintf( out, "</ctx>" );
    }

    reportRedactions( stderr, redactCounts );

    // --token-budget=N: repomix-style CI contract — ASSERTS the emitted map's est_tokens against a ceiling
    // (composes freely with --max-tokens, which SHAPES the map to hit a target instead). §P6.8: closes the
    // buffer, and on exit 3 the buffered body never reaches stdout (finishTokenBudgetGate's own comment has
    // the full reasoning) — a small refusal record instead, shaped to match --json.
    if( std::optional<int> gated = finishTokenBudgetGate( tbBuf, stdout, mapEstTokens, cfg.tokenBudget, cfg.json ) )
    {
        return *gated;
    }

    // A4-F18: a short fwrite anywhere in the emitters (disk full, closed pipe) sets ferror(stdout);
    // fail loudly instead of exiting 0 with a silently-truncated map (CI gates trust the exit code)
    if( std::fflush( stdout ) != 0 || std::ferror( stdout ) )
    {
        std::fprintf( stderr, "ripwire: write error — output truncated\n" );
        return 1;
    }

    return 0;
}

// L2: --json is scoped to the CI/scripting core verbs (default map, --for, --pack-task,
// --callers/--callees/--impact, --quality-delta, --test-gate, --metrics).
// Returns the flag name to name in the refusal, or nullptr when the request is one of the 7 supported
// shapes. Deliberately enumerates every OTHER verb-selecting flag (the ALLOW list is exactly 7 things;
// everything else defaults to REFUSED) rather than trying to recognize "is this the plain default map" —
// a newly-added verb this list forgets to update stays safely refused under --json instead of silently
// emitting stale/wrong XML, the safe failure direction for an additive flag.
//
// §B1.1 (capture-audit-4, 2026-07-30, owner ruling: REFUSE-ALL): eight verb surfaces reached a --json
// caller with NO arm here at all — whereis/stray-content/abi/exercises/community=ID/doc-drift/flags
// (darkFlags)/layout — so they fell all the way through to `return nullptr` and dispatched normally,
// emitting XML at exit 0 under --json. That falsified this function's own contract ("everything else
// defaults to REFUSED"): the contract was true of every verb this list knew about, not every verb that
// dispatches. Added below as their own group so the next verb added to main() is the only thing that can
// go stale again — not this whole tail.
//
// §B1.4: the tail of this list is NOT verbs — --format=columnar/candidates, --detail and --scip are output-
// SHAPE modifiers, and a refusal that enumerates them against "supported verbs" sends the reader hunting for
// a verb to drop instead of an encoding to pick. The return value says which kind it found, so the caller can
// word the two cases differently.
// §B11.4 — THE REPORT-VERB PRECEDENCE TABLE, in ripwire's real DISPATCH order (main()'s handler chain, then
// each handler's own arm order). One row per verb-selecting flag, so adding a verb is adding a ROW rather
// than editing a message — the house rule for exactly this shape.
//
// §M1 (audit 2026-08-08) — this table used to EXCLUDE --for/--query/--pack-task, on the claim that "X9(c)
// above already discloses those three". That claim was false in the direction that mattered: X9(c) discloses
// collisions AMONG the three and nothing else, so a query-family flag paired with any of the ~50 report verbs
// below was dropped in TOTAL silence — stderr empty, exit 0 — the exact hazard this table exists to close.
// The silence was also not uniform, so no caller could infer the rule from one observation: --for dispatches
// ahead of the whole table, --query behind all of it, and --pack-task in between (it loses to --skipped and
// wins over --lint). All three are now ROWS, at their real dispatch positions, which is this table's own
// house rule — a verb is a row, not a special case. M1 changed no behaviour: the same verb still won every
// pair; only the silence was gone.
//
// §A2 (audit 2026-08-08) — M1 disclosed the order and, in doing so, made it legible enough to see it was
// indefensible: three flags of one family gave three different answers to "does a typed task outrank a
// report verb?". The family now dispatches UNIFORMLY FIRST, so the three rows below are contiguous at the
// TOP. A typed task is the caller's PRIMARY intent; a report verb passed alongside it is incidental. This IS
// a behaviour change — --skipped/--hotspots no longer beat --pack-task, and no report verb beats --query —
// and it is the point, not a side effect. Intra-family order stays X9(c)'s: --for > --pack-task > --query.
//
// The one true half of the old claim is kept as `isQueryFamily`: one run must never print two warnings about
// the same collision, so an ignored query-family flag is skipped when the WINNER is also query-family —
// that pair is X9(c)'s, and X9(c) words it better. Every other combination is this table's.
//
// §F1 (audit 2026-08-08) — the adversarial verifier found the table was still INCOMPLETE, in the same way
// and with the same symptom M1 had closed for the query family: eleven verb-shaped flags selected a handler
// yet owned no row, so each collided with a real verb at stderr-EMPTY, exit 0. `--quality-panel --lint`
// emitted panel bytes and said nothing; `--expand=SYM --lint` emitted LINT bytes and threw --expand away. A
// sweep of --help against this table (rather than trusting the reported list) turned up all of them:
//
//   --index-out                                            pre-ingest, ahead of EVERY verb incl. the family
//   --ensemble, --context-ratio                            runMaintenanceViews arms 1-2, ahead of --hotspots
//   --readability, --comment-coherence, --nonlocal-state,   runQualityViews arms 1-6, ahead of --dead-code
//   --quality-panel, --naming-calibration, --naming-consistency
//   --handoff                                              runChangeViews arm 1, ahead of --situ
//   --field-affinity                                       between --layout and --doc-drift
//
// All eleven are rows now, at their REAL dispatch positions. Like M1, this changed no behaviour: the same
// verb still wins every pair; only the silence is gone. --quality-panel losing to --hotspots and beating
// --lint is not the §A2 non-uniformity — §A2 was about ONE FAMILY answering one question three ways. A
// single flag sitting at one position and being disclosed there is exactly what every other row does.
//
// --index-out is the one row that can beat a query-family flag, because it runs before ingest (it IS the
// ingest-artifact generator). That is why X9(c) is now gated on the family actually winning: a run that
// --index-out answered must not also print "--for takes precedence".
//
// Still excludes pure MODIFIERS (--metrics, --stable, --format=, --top-k, --rank-by…), which shape whatever
// verb runs rather than selecting one, and --scan-skills/--scan-skill, which dispatch before the graph is
// built and never reach this chain. §F1 verified the modifier side too: every refuse-alone flag
// (--compress, --with-graph, --gateability, --plan, --adaptive…) already names its host verb, and --metrics/
// --rank-by/--top-k tune the SAME <r> map document rather than replacing it.
//
// §F1 also introduces a THIRD class these two never covered — see kMapModifiers below.
//
// The order below is not asserted by reading: test/dispatchordercheck.sh runs every PAIR and checks that the
// verb this table names as the winner is the verb whose bytes actually came out, so a table that rots reds
// by name instead of shipping a confident lie.
// isQueryFamily marks the three flags X9(c) speaks for; it defaults to false, so the ~50 report rows below
// stay two-field and only the three query-family rows spell the third value.
struct ReportVerbSlot { const char* flag; bool isActive; bool isQueryFamily = false; };

// The scan is separate from the printing because TWO callers need the winner: this table's own warning, and
// X9(c), which may only speak when the query family is the thing that actually answered (§F1 — --index-out
// is a row ahead of the family, so "the family always wins if present" stopped being true).
struct VerbPrecedence
{
    const char* winner              = nullptr;
    bool        winnerIsQueryFamily = false;
    std::string ignored;
};

VerbPrecedence scanReportVerbPrecedence( const rw::Config& c )
{
    const ReportVerbSlot slots[] = {
        // §F1: --index-out dispatches BEFORE ingest, so it outranks even the query family. One row, at the top.
        { "--index-out",        !c.indexOut.empty()       },
        { "--help-task",        !c.helpTask.empty()       },
        // §A2: the query family, contiguous and first among the report verbs — these three outrank every one below.
        { "--for",              !c.forTask.empty(), true  }, { "--pack-task",     c.packTaskFlag,    true },
        { "--query",            !c.query.empty(),   true  },
        { "--lego",             !c.legoType.empty()       }, { "--exemplar",     !c.exemplar.empty()      },
        { "--recall",           !c.recall.empty()         }, { "--deps",          c.deps                  },
        { "--arch",             !c.archRules.empty()      },
        { "--ensemble",          c.ensemble               }, { "--context-ratio", c.contextRatio          },   // §F1: runMaintenanceViews arms 1-2
        { "--hotspots",          c.hotspots               },
        { "--clones",            c.clones                 }, { "--cochange",      c.cochange              },
        { "--owners",            c.owners                 }, { "--quality-baseline", c.qualityBaseline    },
        { "--quality-delta",     c.qualityDelta           }, { "--dmm",           c.dmm                   },
        // §F1: runQualityViews' six lenses, in its own arm order, all ahead of --dead-code
        { "--readability",       c.readability            }, { "--comment-coherence", c.commentCoherence  },
        { "--nonlocal-state",    c.nonlocalState          }, { "--quality-panel", c.qualityPanel          },
        { "--naming-calibration", c.namingCalibration     }, { "--naming-consistency", c.namingConsistency },
        { "--dead-code",         c.deadCode               },   // the row order IS the dispatch order (test/dispatchordercheck.sh pins every pair) — never re-pair for layout
        { "--edit-check",       !c.editCheckSym.empty()   }, { "--safe-delete",  !c.safeDeleteSym.empty()  },
        { "--slice",            !c.sliceSpec.empty()      },   // lane/paper-slice: dispatches right after --safe-delete (runSlice)
        { "--eval",              c.eval                   },
        { "--eval-retrieval",    c.evalRetrieval          }, { "--eval-skills",  !c.evalSkills.empty()    },
        { "--callers",          !c.callers.empty()        }, { "--callees",      !c.callees.empty()       },
        { "--graph-query",      !c.graphQuery.empty()     }, { "--uses",         !c.usesSym.empty()       },
        { "--verify",           !c.verifyClaim.empty()    },   // G4: dispatches between --uses and --external-surface (runVerify)
        { "--external-surface",  c.externalSurface        }, { "--path",         !c.pathSpec.empty()      },
        { "--connect",          !c.connectSpec.empty()    }, { "--impact",       !c.impactSym.empty()     },
        { "--mentions",         !c.mentionsSym.empty()    }, { "--affected",     !c.affectedFiles.empty() },
        { "--exercises",         c.exercisesFlag          },
        { "--handoff",           c.handoff                },   // §F1: runChangeViews' first arm, ahead of --situ
        { "--situ",              c.situ                   },
        { "--test-gate",         c.testGate               }, { "--pr-context",    c.prContext             },
        { "--export=cc.json",    c.exportCcJson           }, { "--merge-scout",   c.mergeScoutFlag        },
        { "--plan-lanes",        c.planLanesFlag          }, { "--stray-content", c.strayContent          },
        { "--abi",               c.abiFlag                }, { "--eval-stray",   !c.evalStray.empty()     },
        { "--flags",             c.darkFlags              }, { "--whereis",       c.whereisFlag           },
        { "--layout",            c.layoutFlag             },
        { "--field-affinity",    c.fieldAffinity          },   // §F1: runFieldAffinity, between --layout and --doc-drift
        { "--doc-drift",         c.docDrift               },
        { "--from-trace",       !c.fromTrace.empty()      }, { "--run-trace",     !c.runTrace.empty()     },
        { "--note-add",          c.noteAddFlag            },
        { "--notes",             c.notesList              }, { "--skipped",       c.skippedList           },
        { "--communities",       c.communities            },
        { "--community",         c.communityFlag          }, { "--zoom",          c.zoom                  },
        { "--seams",             c.seams                  }, { "--report",        c.report                },
        { "--tree",              c.tree                   }, { "--grep",         !c.grep.empty()          },
        { "--match",            !c.match.empty()          }, { "--pattern",      !c.pattern.empty()       },
        { "--lint",              c.lint                   },
        { "--around",           !c.around.empty()         },
    };

    VerbPrecedence prec;
    for( const ReportVerbSlot& s : slots )
    {
        if( !s.isActive )
        {
            continue;
        }
        if( prec.winner == nullptr )
        {
            prec.winner              = s.flag;
            prec.winnerIsQueryFamily = s.isQueryFamily;
            continue;
        }
        if( s.isQueryFamily && prec.winnerIsQueryFamily )
        {
            continue;   // X9(c) already disclosed this exact pair — one collision, one warning
        }
        if( !prec.ignored.empty() )
        {
            prec.ignored += ", ";
        }
        prec.ignored += s.flag;
    }
    return prec;
}

void warnReportVerbPrecedence( const VerbPrecedence& prec )
{
    if( prec.ignored.empty() )
    {
        return; // 0 or 1 verb — nothing was dropped, so nothing is said
    }

    std::fprintf( stderr, "ripwire: %s takes precedence when several verbs are given — IGNORED this run: %s. "
                          "The winner is fixed by ripwire's dispatch order, NOT by the order you typed them; "
                          "pass one verb per run.\n", prec.winner, prec.ignored.c_str() );
}

// §F1 — THE MAP-MODIFIER CLASS, the third kind §B11.4's two classes never covered.
//
// --expand / --outline / --pack-signatures / --pack-top-n / --map-diff are NOT verbs: not one of them selects
// a handler. They shape what runDefaultMap RENDERS, and runDefaultMap serves exactly two runs — a flagless
// map, and --query (which, as main() puts it, "owns no handler of its own: runDefaultMap serves it and is
// also this chain's fallback"). That single architectural fact settles the question the audit called hard,
// and settles it UNIFORMLY:
//
//   a map-modifier COMPOSES with any run that reaches the default map, and is VOIDED by any report verb that
//   answers before it — and being voided is DISCLOSED.
//
// So --expand is a modifier, always; it is never a verb that "lost". It does not lose to --lint — --lint
// returns before the map it shapes is ever rendered. Giving it a table ROW would encode the opposite claim
// and would be provably wrong in one case the gate pins: under `--query --expand` stdout is NOT --query's
// solo output, because the two compose, and a row means winner-or-loser with nothing in between.
//
// The disclosure is not cosmetic. A silently dropped --expand does not return a thinner answer to the
// caller's question the way a dropped --top-k would; it returns an answer to a DIFFERENT question — the
// bodies that were asked for are simply absent — which is precisely non-negotiable #3's "a zero means none
// found, never none exists".
//
// composesWithQuery / composesWithFor are per-flag because the composition genuinely is: --pack-top-n also
// budgets --for's bodies, and --map-diff is the one --query overrides (its lexical-rank branch replaces the
// diff scope). Both are measured facts, pinned pair-by-pair in test/dispatchordercheck.sh's mapmod arm, not
// assertions of intent.
struct MapModifierSlot
{
    const char* flag;
    bool        isActive;
    bool        composesWithQuery;
    bool        composesWithFor;
};

void warnMapModifierDiscarded( const rw::Config& c, const VerbPrecedence& prec )
{
    if( prec.winner == nullptr )
    {
        return;   // no verb answered, so the default map IS the run — every map-modifier applied
    }

    const MapModifierSlot mods[] = {
        { "--expand",           !c.expand.empty(),   true,  false },
        { "--outline",          !c.outline.empty(),  true,  false },
        { "--pack-signatures",   c.packSignatures,   true,  false },
        { "--pack-top-n",        c.packTopN > 0,     true,  true  },
        { "--map-diff",          c.mapDiff,          false, false },
    };

    const bool winnerIsQuery = std::strcmp( prec.winner, "--query" ) == 0;
    const bool winnerIsFor   = std::strcmp( prec.winner, "--for" )   == 0;

    std::string discarded;
    for( const MapModifierSlot& m : mods )
    {
        if( !m.isActive )
        {
            continue;
        }
        if( ( winnerIsQuery && m.composesWithQuery ) || ( winnerIsFor && m.composesWithFor ) )
        {
            continue;   // this one composed with the winner — nothing was dropped, so nothing is said
        }
        if( !discarded.empty() )
        {
            discarded += ", ";
        }
        discarded += m.flag;
    }
    if( discarded.empty() )
    {
        return;
    }

    std::fprintf( stderr, "ripwire: %s answered, so the default map never rendered — DISCARDED this run: %s. "
                          "Those flags shape the map only; pass them with --query=TERMS or with no verb at all.\n",
                  prec.winner, discarded.c_str() );
}

const char* jsonUnsupportedVerb( const rw::Config& c )
{
    if( !c.helpTask.empty() )
    {
        return "--help-task";
    }
    if( c.mcp )
    {
        return "--mcp";
    }
    if( c.mapDiff )
    {
        return "--map-diff";
    }
    if( c.packSignatures )
    {
        return "--pack-signatures";
    }
    if( c.packTopN > 0 )
    {
        return "--pack-top-n";
    }
    if( !c.query.empty() )
    {
        return "--query";
    }
    // §B1.4: `--regex=PAT` sets BOTH c.grep and c.grepRegex, so a separate --grep arm ahead of the --regex
    // arm told a --regex caller that "--grep" was unsupported — a flag they never typed. One arm, and the
    // spelling comes from what was actually parsed.
    if( !c.grep.empty() || c.grepRegex )
    {
        return c.grepRegex ? "--regex" : "--grep";
    }
    if( !c.match.empty() )
    {
        return "--match";
    }
    if( !c.pattern.empty() )
    {
        return "--pattern";
    }
    if( c.lint )
    {
        return "--lint";
    }
    if( !c.lintRulesDir.empty() )
    {
        return "--lint-rules";
    }
    if( !c.expand.empty() )
    {
        return "--expand";
    }
    if( !c.outline.empty() )
    {
        return "--outline";
    }
    if( !c.legoType.empty() )
    {
        return "--lego";
    }
    if( !c.exemplar.empty() )
    {
        return "--exemplar";
    }
    if( !c.recall.empty() )
    {
        return "--recall";
    }
    if( c.deps )
    {
        return "--deps";
    }
    if( c.hotspots )
    {
        return "--hotspots";
    }
    if( c.clones )
    {
        return "--clones";
    }
    if( c.cochange )
    {
        return "--cochange";
    }
    if( !c.archRules.empty() )
    {
        return "--arch";
    }
    if( c.communities )
    {
        return "--communities";
    }
    if( c.zoom )
    {
        return "--zoom";
    }
    if( c.report )
    {
        return "--report";
    }
    if( c.tree )
    {
        return "--tree";
    }
    if( c.seams )
    {
        return "--seams";
    }
    if( c.mermaid )
    {
        return "--mermaid";
    }
    if( !c.pathSpec.empty() )
    {
        return "--path";
    }
    if( !c.connectSpec.empty() )
    {
        return "--connect";
    }
    if( !c.mentionsSym.empty() )
    {
        return "--mentions";
    }
    if( !c.affectedFiles.empty() )
    {
        return "--affected";
    }
    if( c.situ )
    {
        return "--situ";
    }
    if( !c.usesSym.empty() )
    {
        return "--uses";
    }
    if( !c.verifyClaim.empty() )
    {
        return "--verify";
    }
    if( !c.graphQuery.empty() )
    {
        return "--graph-query";
    }
    if( c.externalSurface )
    {
        return "--external-surface";
    }
    if( c.scanSkills )
    {
        return "--scan-skills";
    }
    if( !c.scanSkillFile.empty() )
    {
        return "--scan-skill";
    }
    if( !c.batchFile.empty() )
    {
        return "--batch";
    }
    if( c.html )
    {
        return "--html";
    }
    if( c.owners )
    {
        return "--owners";
    }
    if( c.baseline )
    {
        return "--baseline";
    }
    if( c.baselineUpdate )
    {
        return "--baseline-update";
    }
    if( c.deadCode )
    {
        return "--dead-code";
    }
    if( c.qualityBaseline )
    {
        return "--quality-baseline";
    }
    if( c.qualityAck )
    {
        return "--quality-ack";
    }
    if( !c.editCheckSym.empty() )
    {
        return "--edit-check";
    }
    if( c.prContext )
    {
        return "--pr-context";
    }
    if( c.mergeScoutFlag )
    {
        return "--merge-scout";
    }
    if( !c.fromTrace.empty() )
    {
        return "--from-trace";
    }
    if( !c.runTrace.empty() )
    {
        return "--run-trace";
    }
    if( c.noteAddFlag )
    {
        return "--note-add";
    }
    if( c.notesList )
    {
        return "--notes";
    }
    if( c.skippedList )
    {
        return "--skipped";
    }
    if( c.exportCcJson )
    {
        return "--export=cc.json";
    }
    if( c.doctor )
    {
        return "--doctor";
    }
    if( !c.around.empty() )
    {
        return "--around";
    }
    // §B1.1: the eight verb surfaces this list forgot — see the header comment above. abiFlag is checked
    // ahead of strayContent (it only ever fires nested inside `--stray-content --abi`, main.cpp's
    // runCrossRef) so the refusal names the more specific sub-verb the caller actually typed, the same
    // specific-before-general order the --regex/--grep arm above already uses.
    if( c.abiFlag )
    {
        return "--abi";
    }
    if( c.strayContent )
    {
        return "--stray-content";
    }
    if( c.whereisFlag )
    {
        return "--whereis";
    }
    if( c.exercisesFlag )
    {
        return "--exercises";
    }
    if( !c.communityId.empty() )
    {
        return "--community";
    }
    if( c.docDrift )
    {
        return "--doc-drift";
    }
    if( c.darkFlags )
    {
        return "--flags";
    }
    if( c.layoutFlag )
    {
        return "--layout";
    }
    // §B1.5 (capture-audit-4, wave 3) — the FIVE self-eval verbs, as one group. The wave-2 verifier's
    // 96-flag sweep found exactly one flag still emitting XML at exit 0 under --json (--eval-stray) and
    // concluded the class was down to one; it was not, because the sweep's tell was "does it emit XML".
    // --eval / --eval-retrieval / --eval-mined / --eval-skills emit PLAIN TEXT tables, so they are invisible
    // to an XML-shaped probe while accepting and ignoring --json exactly as loudly. All five measured
    // byte-identical with and without the flag on shapes where they actually SUCCEED (a corpus with
    // doc-commented symbols, a real minedpair.jsonl, a real labels TSV, the skills tree) — which is the
    // distinction the §B9 caveat names: exercise the shape where the flag would bind, not the one where the
    // verb refuses for an unrelated reason. Owner ruling 4's REFUSE-ALL shape, verbatim.
    if( c.eval )
    {
        return "--eval";
    }
    if( c.evalRetrieval )
    {
        return "--eval-retrieval";
    }
    if( !c.evalMined.empty() )
    {
        return "--eval-mined";
    }
    if( !c.evalSkills.empty() )
    {
        return "--eval-skills";
    }
    if( !c.evalStray.empty() )
    {
        return "--eval-stray";
    }
    // output-shape modifiers not (yet) mirrored in JSON — refuse rather than silently drop them.
    // §B1.4: these four are the SHAPE half; kJsonShapeModifiers below names the same four so the refusal can
    // word them as encodings rather than verbs.
    if( c.columnar )
    {
        return "--format=columnar";
    }
    if( c.candidates )
    {
        return "--format=candidates";
    }
    if( c.detail > 0 )
    {
        return "--detail";
    }
    if( !c.scipIndex.empty() )
    {
        return "--scip";
    }
    return nullptr;
}

// §B1.4: the output-SHAPE members of the list above, as a table rather than a second if-chain. A flag in
// here selects an ENCODING for rows some verb already produced, so "--json is not supported for X" is the
// wrong sentence about it — the caller has picked two encodings, not an unsupported verb.
inline constexpr const char* kJsonShapeModifiers[] = { "--format=columnar", "--format=candidates", "--detail", "--scip" };

inline bool isJsonShapeModifier( const char* flag ) noexcept
{
    VERIFY( flag != nullptr );
    for( const char* s : kJsonShapeModifiers )
    {
        if( std::strcmp( s, flag ) == 0 )
        {
            return true;
        }
    }
    return false;
}

int runHelpTask( const rw::Config& cfg, const rw::IngestResult& ing, const std::string& root )
{
    const std::string stamp = rw::gitstamp::stampAt( root );
    const bool        git   = !stamp.empty();
    const bool        dirty = stamp.ends_with( "+dirty" );
    const rw::taskroute::TaskRouteResult route = rw::taskroute::classify( cfg.helpTask, root, ing, git, dirty );

    std::vector<char> esc;
    const auto ex = [&]( std::string_view s ) { return std::string( rw::escapeXml( s, esc ) ); };
    std::string out = "<task-route status=\"";
    out += rw::taskroute::statusName( route.status );
    out += "\" confidence=\"";
    out += route.status == rw::taskroute::RouteStatus::Recommend ? "high" :
           route.status == rw::taskroute::RouteStatus::Ambiguous ? "low" : "none";
    out += "\" score=\"" + std::to_string( route.score ) + "\" margin=\"" + std::to_string( route.margin ) + "\">";
    out += "<facts git=\"" + std::to_string( int( route.facts.git ) ) + "\" dirty=\"" + std::to_string( int( route.facts.dirty ) );
    out += "\" trace=\"" + std::to_string( int( route.facts.trace ) ) + "\" resolved_symbols=\"";
    out += std::to_string( route.facts.resolvedSymbols.size() ) + "\"/>";
    for( const rw::taskroute::RouteChoice& choice : route.choices )
    {
        out += "<choice intent=\"" + ex( choice.id ) + "\" skill=\"" + ex( choice.skill ) + "\" reason=\"" + ex( choice.reason );
        out += "\" score=\"" + std::to_string( choice.score ) + "\"><run>" + ex( choice.command ) + "</run></choice>";
    }
    out += "</task-route>\n";
    std::fputs( out.c_str(), stdout );
    return 0;
}

std::optional<int> runCliEditPlan( const rw::Config& cfg )
{
    const bool hasMode = cfg.editPlanDryRun || cfg.editPlanApply;
    if( cfg.editPlan.empty() && !hasMode ) { return std::nullopt; }
    if( cfg.editPlan.empty() )
    {
        std::fprintf( stderr, "ripwire: --dry-run/--apply requires --edit-plan=FILE\n" );
        return 1;
    }
    if( cfg.editPlanDryRun == cfg.editPlanApply )
    {
        std::fprintf( stderr, "ripwire: --edit-plan requires exactly one of --dry-run or --apply\n" );
        return 1;
    }
    if( cfg.roots.size() != 1 )
    {
        std::fprintf( stderr, "ripwire: --edit-plan is single-root only; pass one <dir>\n" );
        return 1;
    }
    const rw::editplan::Outcome outcome = rw::editplan::run( std::string( cfg.rootPath ), std::string( cfg.editPlan ),
                                                             cfg.editPlanApply, cfg.maxFileBytes );
    if( !outcome.ok )
    {
        std::fprintf( stderr, "ripwire edit-plan: %s\n", outcome.message.c_str() );
        return 1;
    }
    std::puts( outcome.receipt.c_str() );
    return 0;
}

std::optional<int> runCliEdit( const rw::Config& cfg )
{
    const int editCount = int( !cfg.replaceSymbolBody.empty() ) + int( !cfg.insertBeforeSymbol.empty() )
                        + int( !cfg.insertAfterSymbol.empty() );
    const bool hasModifier = !cfg.editPayload.empty() || !cfg.editTargetFile.empty();
    if( editCount == 0 && !hasModifier )
    {
        return std::nullopt;
    }
    if( editCount == 0 )
    {
        std::fprintf( stderr, "ripwire: --edit-payload/--edit-target-file requires one of --replace-symbol-body, "
                              "--insert-before-symbol or --insert-after-symbol\n" );
        return 1;
    }
    if( editCount != 1 )
    {
        std::fprintf( stderr, "ripwire: pass exactly one CLI edit verb per invocation\n" );
        return 1;
    }
    if( cfg.roots.size() != 1 )
    {
        std::fprintf( stderr, "ripwire: CLI edit verbs are single-root only; pass one <dir>\n" );
        return 1;
    }
    if( cfg.editPayload.empty() )
    {
        std::fprintf( stderr, "ripwire: a CLI edit requires --edit-payload=FILE (or --edit-payload=- for stdin); "
                              "an absent payload never means delete\n" );
        return 1;
    }

    std::string payload;
    if( cfg.editPayload == "-" )
    {
        std::array<char, 8192> buf{};
        for( ;; )
        {
            const std::size_t n = std::fread( buf.data(), 1, buf.size(), stdin );
            payload.append( buf.data(), n );
            if( n < buf.size() )
            {
                if( std::ferror( stdin ) )
                {
                    std::fprintf( stderr, "ripwire: could not read --edit-payload=- from stdin\n" );
                    return 1;
                }
                break;
            }
        }
    }
    else
    {
        bool readOk = false;
        payload = rw::mcpdetail::readFileBytes( std::string( cfg.editPayload ), readOk );
        if( !readOk )
        {
            std::fprintf( stderr, "ripwire: could not read edit payload '%.*s'\n", int( cfg.editPayload.size() ), cfg.editPayload.data() );
            return 1;
        }
    }
    if( payload.empty() )
    {
        std::fprintf( stderr, "ripwire: --edit-payload is empty; empty never means delete\n" );
        return 1;
    }
    if( payload.size() > cfg.maxFileBytes )
    {
        std::fprintf( stderr, "ripwire: edit payload is %zu bytes, over the --max-file-size ceiling of %zu bytes\n",
                      payload.size(), cfg.maxFileBytes );
        return 1;
    }
    // A1: the THIRD arm of the payload gate, beside empty and oversize. The engine refuses this too
    // (mcpedit::kBinaryPayloadRefusal, which is what covers MCP), but the CLI arm names the FLAG the bytes
    // arrived through — the agent's next move is to fix that file or that pipe, not the edit engine.
    if( rw::looksBinary( payload ) )
    {
        std::fprintf( stderr, "ripwire: --edit-payload %.*s\n",
                      int( rw::mcpedit::kBinaryPayloadRefusal.size() ), rw::mcpedit::kBinaryPayloadRefusal.data() );
        return 1;
    }

    const rw::mcpedit::Op op = !cfg.replaceSymbolBody.empty() ? rw::mcpedit::Op::ReplaceBody
                                 : !cfg.insertBeforeSymbol.empty() ? rw::mcpedit::Op::InsertBefore
                                                                  : rw::mcpedit::Op::InsertAfter;
    const std::string_view sym = !cfg.replaceSymbolBody.empty() ? cfg.replaceSymbolBody
                                 : !cfg.insertBeforeSymbol.empty() ? cfg.insertBeforeSymbol : cfg.insertAfterSymbol;
    const rw::mcpedit::Outcome outcome = rw::runEditVerb( std::string( cfg.rootPath ), op, std::string( sym ),
                                                          std::string( cfg.editTargetFile ), payload );
    if( !outcome.ok )
    {
        std::fprintf( stderr, "ripwire edit: %s\n", outcome.message.c_str() );
        return 1;
    }

    std::fputs( outcome.resultJson.c_str(), stdout );
    std::fputc( '\n', stdout );
    // A4: print the RESOLVED file:symbol, never the caller's own argument. `sym` may be a sym# handle, which
    // --edit-check does not accept — so the printed command used to fail every time after a handle-addressed
    // edit — and a bare name narrowed by --edit-target-file would point --edit-check at a different
    // same-named definition. Both follow-ups are now spelled out concretely enough to paste.
    std::fprintf( stderr, "ripwire edit: applied atomically; verify with --edit-check=%s:%s, then --affected=%s\n",
                  outcome.file.c_str(), outcome.symbol.c_str(), outcome.file.c_str() );
    return 0;
}

}   // namespace

int main( int argc, char** argv )
{
    using namespace rw;

    if( argc >= 2 && std::string_view( argv[1] ) == "wrap" )
    { // adoption recipe (subcommand, not a flag)
        return runWrap( argc, argv, selfExecutablePath( argv[0] ) );
    }

    const Config cfg = parseArgs( argc, argv );
    if( !cfg.ok )
    {
        return 1;
    }

    // CLI-first edit verbs reuse the MCP transaction engine and therefore own their own indexed pass.
    // Dispatch before the ordinary ingest pipeline so the preferred CLI path never parses the tree twice.
    if( std::optional<int> planned = runCliEditPlan( cfg ) )
    {
        return *planned;
    }
    if( std::optional<int> edited = runCliEdit( cfg ) )
    {
        return *edited;
    }

    // §B11.4's table is SCANNED here and printed further down, because X9(c) below needs the winner too. The
    // scan is pure; nothing is emitted by this line.
    const VerbPrecedence verbPrec = scanReportVerbPrecedence( cfg );

    // X9(c): mode flags have a hidden precedence when more than one is given at once — the earlier-checked
    // one silently wins and the rest are ignored outright, with no signal to the caller that anything was
    // dropped. Warn once, on stderr, one line per conflict; behavior is UNCHANGED (the same flag still wins).
    // §F1: gated on the query family actually WINNING. Until --index-out became a row, a run containing a
    // family flag always had one answer, so the guard was free; --index-out dispatches before ingest and
    // beats all three, and X9(c) announcing "--for takes precedence" in a run --for never answered would be
    // a confident lie of exactly the kind this whole section exists to delete.
    if( verbPrec.winnerIsQueryFamily && !cfg.forTask.empty() && ( !cfg.query.empty() || cfg.packTaskFlag ) )
    {
        std::fprintf( stderr, "ripwire: --for takes precedence over --query/--pack-task when both are given (the others are ignored)\n" );
    }
    else if( verbPrec.winnerIsQueryFamily && cfg.packTaskFlag && !cfg.query.empty() )
    {
        std::fprintf( stderr, "ripwire: --pack-task takes precedence over --query when both are given (--query is ignored)\n" );
    }
    if( cfg.stable && cfg.mostImportantLast )
    {
        std::fprintf( stderr, "ripwire: --stable takes precedence over --most-important-last when both are given (emit order stays path/id order)\n" );
    }

    // §B11.4 (CA4) — the SAME hazard X9(c) discloses for three flags, on the ~50 report verbs it never
    // reached. `--hotspots --clones` emits hotspots only, exit 0, stderr EMPTY; `--owners --clones` emits
    // CLONES — because the winner is fixed by ripwire's internal DISPATCH ORDER, not by the order the flags
    // were typed, which is the part no caller can guess. Behaviour is unchanged: the same verb still wins,
    // and this only says so. Warns ONCE per run, listing every verb that was dropped.
    // §M1: the three flags X9(c) speaks for are rows here too now, so a CROSS-family pair (`--pack-task
    // --skipped`, `--for --hotspots`) discloses like every other pair instead of dropping one in silence.
    // X9(c) keeps the intra-family pair; the row table skips it rather than repeat it.
    // §A2: those three rows are now contiguous at the TOP of the table — the family dispatches first, so in
    // every cross-family pair the query-family flag is the WINNER and the report verb is the one disclosed.
    // §F1: the eleven verb-shaped flags that owned no row are rows now, so a pair like `--quality-panel
    // --lint` discloses instead of dropping one in silence.
    warnReportVerbPrecedence( verbPrec );

    // §F1: and the third class — a map-modifier voided because a report verb answered first says so, while
    // one that COMPOSED (--query --expand) stays quiet, because nothing was dropped.
    warnMapModifierDiscarded( cfg, verbPrec );

    // L2: --json refuses LOUDLY for any verb it doesn't (yet) support — see jsonUnsupportedVerb's ALLOW-list
    // rationale. Checked before ANY dispatch (incl. --mcp / --doctor / the multi-root refusals below) so an
    // unsupported combination never reaches a handler that would silently ignore --json and emit XML.
    // §B1.4: two sentences, because there are two failures here. An unsupported VERB is told the supported
    // set plus ONE RUNNABLE EXAMPLE (the --format=columnar refusal has carried one since §A5b; this one did
    // not). An output-SHAPE modifier is told it collided with another encoding — enumerating "supported
    // verbs" at someone who typed --format=columnar names nothing they can act on.
    if( cfg.json )
    {
        if( const char* unsupported = jsonUnsupportedVerb( cfg ) )
        {
            if( isJsonShapeModifier( unsupported ) )
            {
                std::fprintf( stderr, "ripwire: --json and %s are two output SHAPES for the same rows — pass one, not both "
                              "(e.g. ripwire <dir> --callers=SYM --json, or ripwire <dir> --callers=SYM %s)\n", unsupported, unsupported );
            }
            else
            {
                // §B1.2: the enumeration used to stop at --test-gate and never mention --metrics, which HAS
                // had a full JSON twin (row keys amp/cbo/ccx/cx/in/loc/nest/out/params/role/tested) since it
                // was never added to the deny-chain above — so a caller obeying THIS refusal never learned
                // the one flag it was actually looking for existed. Corrected in the same commit as the
                // eight new arms above, so the sentence changes exactly once.
                std::fprintf( stderr, "ripwire: --json is not yet supported for %s — supported: the default map, "
                              "--for, --pack-task, --callers/--callees, --impact, --quality-delta, --test-gate, "
                              "--metrics (e.g. ripwire <dir> --callers=SYM --json)\n", unsupported );
            }
            return 1;
        }
    }

    // §B1.5 (capture-audit-4, wave 3) — --plan-lanes is the INERT case, and it wants a different answer from
    // the five eval verbs above. Those emit a dialect --json asked them to change and silently did not; this
    // one emits JSON natively, byte-identical with and without the flag, because JSON is the only thing it
    // has ever spoken. Refusing it would be the worst of the three options: the caller who asked for JSON
    // would be turned away by the one verb that produces nothing else. Implementing it is a no-op. So it is
    // ACCEPTED and DISCLOSED — the §P15.3 "accepted and silently ignored" class is about a caller who cannot
    // tell a no-op from a typo, and one line on stderr closes exactly that gap while changing no output byte.
    // Deliberately not a refusal, and deliberately not silence.
    if( cfg.json && cfg.planLanesFlag )
    {
        std::fprintf( stderr, "ripwire: --plan-lanes always emits JSON — --json is redundant here and changes nothing\n" );
    }

    if( cfg.mcp )
    {
        // --listen picks the remote Streamable-HTTP transport; otherwise stdio. Both
        // route every request through the SAME shared handler (mcp.h dispatchMcpLine) — byte-identical payloads.
        if( !cfg.listen.empty() )
        {
            McpHttpConfig hc;
            hc.listenSpec = std::string( cfg.listen );
            hc.token      = std::string( cfg.mcpToken );
            if( hc.token.empty() )
            {
                if( const char* envTok = std::getenv( "RIPWIRE_MCP_TOKEN" ); envTok && *envTok )
                {
                    hc.token = envTok; // env fallback (avoids the secret in argv/ps)
                }
            }
            hc.root             = std::string( cfg.rootPath );
            for( std::string_view r : cfg.roots )
            {
                hc.roots.emplace_back( r );
            }
            hc.topK             = cfg.topK;
            hc.stable           = cfg.stable;
            hc.noRedact         = cfg.noRedact;
            hc.allowRemoteEdits = cfg.allowRemoteEdits;
            return runMcpHttp( hc );
        }
        // X7 (D3/D4): thread the SAME positional-root plumbing the HTTP branch above uses into the stdio
        // loop too — a bare `ripwire --mcp` (no root) keeps the pre-X7 "every request names its own path"
        // behavior (roots empty ⇒ runMcp's defaultRoot stays ""); `ripwire <root> --mcp` now actually uses it.
        std::vector<std::string> mcpRoots;
        for( std::string_view r : cfg.roots )
        {
            mcpRoots.emplace_back( r );
        }
        return runMcp( cfg.topK, cfg.stable, cfg.noRedact, std::string( cfg.rootPath ), mcpRoots );   // P2-C: --mcp turns --stable on by default (set in parseArgs); A3-F3: the server redacts by default like the CLI
    }

    // ── multi-root workspace refusals: each cut verb refuses with ONE clear stderr
    //    line + exit 1 (a refusal, not a regression verdict — never exit 2/3/4). All quarantined behind
    //    roots.size() >= 2 so every single-root invocation is byte-identical to today.
    if( cfg.roots.size() >= 2 )
    {
        const auto refuse = [ & ]( const char* what, const char* why ) -> int
        {
            std::fprintf( stderr, "ripwire: %s is single-root only in a multi-root workspace — %s\n", what, why );
            return 1;
        };
        if( cfg.qualityDelta || cfg.qualityBaseline )
        {
            return refuse( "--quality-delta/--quality-baseline", "its baseline is keyed to ONE repo's HEAD; run it per root" );
        }
        if( !cfg.helpTask.empty() )
        {
            return refuse( "--help-task", "its repository applicability and exact-symbol facts are single-root; run it per root" );
        }
        if( cfg.dmm )
        {
            return refuse( "--dmm", "it diffs ONE repo's committed trees, and pooling two histories into one ratio would be meaningless; run it per root" );
        }
        if( !cfg.editCheckSym.empty() )
        {
            return refuse( "--edit-check", "its git-HEAD baseline (computeHeadSnapshot) is keyed to ONE repo; run it per root" );
        }
        if( cfg.testGate )
        {
            return refuse( "--test-gate", "its HEAD-keyed contract is per-repo; run it per root" );
        }
        if( cfg.handoff )
        {
            return refuse( "--handoff", "its branch/sha/diff provenance is keyed to ONE repo's HEAD; run it per root" );
        }
        if( cfg.eval || cfg.evalRetrieval || !cfg.evalMined.empty() || !cfg.evalSkills.empty() )
        {
            return refuse( "--eval/--eval-retrieval/--eval-mined/--eval-skills", "corpora, goldens and scoreboards are single-root artifacts; run it per root" );
        }
        if( !cfg.archRules.empty() && ( cfg.baseline || cfg.baselineUpdate ) )
        {
            return refuse( "--arch --baseline/--baseline-update", "a committed baseline sidecar lives in ONE repo; run it per root" );
        }
        if( !cfg.indexOut.empty() )
        {
            return refuse( "--index-out", "the committable index artifact is per-repo; generate one per root" );
        }
        if( !cfg.cacheFile.empty() )
        {
            return refuse( "--cache=PATH", "a workspace uses one auto cache blob PER root (drop --cache, or use --no-cache)" );
        }
        if( !cfg.scipIndex.empty() )
        {
            return refuse( "--scip", "a SCIP index describes ONE repo; overlays across roots are deferred" );
        }
        // §B6 (capture-audit-4, wave 3) — the ONE deliberate CLI/MCP divergence on this list, DECIDED and
        // RECORDED rather than left silent. The wave-2 MCP lane left `batch` diverging and argued the CLI
        // restriction is the questionable side; verified before deciding — the MCP verb with
        // `paths:["svc","web"]` really does answer a MERGED two-root batch (a grep sub-query returns
        // files=2 across both roots), so "run against ONE root in v1" was false about the TOOL, not merely
        // restrictive about this surface.
        //
        // The restriction STAYS and the sentence changes. Why the restriction: the CLI batch path resolves
        // each sub-query's index from a single root STRING (runBatchSub( root, … ) with cfg.rootPath), while
        // the MCP surface resolves it from a registered workspace KEY that stands for N roots. Lifting it is
        // not a message change, it is teaching the CLI path to register into that workspace registry —
        // a feature, in a file this lane does not own, at the end of a disclosure wave. Why the sentence
        // changes anyway: a refusal that implies a capability does not exist, when it does and the caller may
        // already be using it on the other surface, is the §B1-class defect this whole round is about.
        if( !cfg.batchFile.empty() )
        {
            return refuse( "--batch", "each CLI sub-query resolves its index from ONE root path — run it per root, "
                                      "or use the MCP `batch` verb with a `paths` array, which DOES answer a merged "
                                      "multi-root batch (the two surfaces deliberately differ here)" );
        }
        if( cfg.doctor )
        {
            return refuse( "--doctor", "its cache-dir/git checks are per-repo; run it per root" );
        }
        if( cfg.mergeScoutFlag )
        {
            return refuse( "--merge-scout", "its git history/branches are per-repo; run it per root" );
        }
        if( cfg.planLanesFlag )
        {
            return refuse( "--plan-lanes", "the carve, the at= stamp and the churn/hotspot lens are all per-repo; run it per root" );
        }
        if( cfg.noteAddFlag || cfg.notesList )
        {
            return refuse( "--note-add/--notes", "the .ripwire_notes file lives at ONE repo root (its targets are that root's canonical ids); run it per root" );
        }
    }

    // ── --doctor: self-diagnosis, before the heavy ingest pipeline (like --scan-skill above) ─────
    if( cfg.doctor )
    {
        return runDoctor( cfg, argv[0] );
    }

    // ── P1-C security scan — purely additive, exits before the heavy ingest pipeline ─────────────
    // --scan-skill=FILE: scan one skill file; emit a `<skillscan>` artifact; exit with skillScanExitCode.
    // --scan-skills[=DIR]: scan DIR, or the repo-local, Claude, and Codex skill homes.
    // Output: §P6.9 — a single deterministic `<skillscan files=".." findings=".." verdict="..">` XML
    // artifact to stdout (one `<f p="path:line" rule=".." sev=".."/>` per finding, capped) + the existing
    // tally line to stderr. Exit 0/1/2 = a scan VERDICT (clean/WARN/CRITICAL). exit 3 = REFUSAL — the path
    // could not be scanned at all (missing, permission-denied, or a file arg that is a directory) — kept
    // off 0/1/2 on purpose (§P0.5a): those three are already all spoken for
    // as verdicts, so a "never scanned it" refusal needs a code a caller cannot mistake for "scanned it and
    // it was clean" (matches this codebase's existing convention of reserving a code beyond a verb's own
    // 0..N verdict range for a distinct non-verdict signal — see --token-budget's exit 3 "not 2, so a
    // script can tell 'too big' apart from 'new debt'"). The refusal `return 3`s below happen strictly
    // BEFORE the `<skillscan>` artifact is ever built, so a refused scan's stdout stays byte-empty
    // (test/skillscanreadcheck.sh pins this — no clean-scan-shaped output on a refusal).
    if( !cfg.scanSkillFile.empty() )
    {
        const std::string path( cfg.scanSkillFile );
        const SkillFileReadResult result = scanSkillFileChecked( path );
        if( !result.readable )
        {
            std::fprintf( stderr, "ripwire: --scan-skill: cannot read '%s' — no scan performed\n", path.c_str() );
            return 3;
        }
        std::vector<SkillScanRow> rows;
        rows.reserve( result.findings.size() );
        for( const SkillFinding& f : result.findings )
        {
            rows.push_back( { path, f } );
        }
        printSkillScanArtifact( stdout, rows, /*filesScanned=*/1 );
        std::fprintf( stderr, "ripwire scan: %d finding(s) in %s\n", int( result.findings.size() ), path.c_str() );
        return skillScanExitCode( result.findings );
    }

    if( cfg.scanSkills )
    {
        // An EXPLICIT --scan-skills=DIR that cannot be read is a typo, not "no default skill homes
        // configured" — refuse instead of silently walking zero dirs and reporting a clean "0 finding(s)
        // total" (the same false-safe as the single-file case above). The unconfigured DEFAULT dirs
        // below stay optional-by-design: e.g. no ~/.codex/skills is normal, not an error.
        if( !cfg.scanSkillsDir.empty() )
        {
            namespace fs = std::filesystem;
            std::error_code ec;
            const bool exists = fs::exists( cfg.scanSkillsDir, ec ) && !ec;
            ec.clear();
            const bool isDir = exists && fs::is_directory( cfg.scanSkillsDir, ec ) && !ec;
            if( !exists || !isDir )
            {
                std::fprintf( stderr, "ripwire: --scan-skills: cannot read '%.*s' — no scan performed\n",
                              int( cfg.scanSkillsDir.size() ), cfg.scanSkillsDir.data() );
                return 3;
            }
        }

        // Determine directories to scan: explicit dir, or defaults. De-duplicate because CODEX_HOME may
        // intentionally name one of the other roots in an isolated/managed environment.
        std::vector<std::string> dirs;
        const auto addDir = [&]( std::string dir )
        {
            if( std::find( dirs.begin(), dirs.end(), dir ) == dirs.end() )
            {
                dirs.push_back( std::move( dir ) );
            }
        };
        if( !cfg.scanSkillsDir.empty() )
        {
            addDir( std::string( cfg.scanSkillsDir ) );
        }
        else
        {
            addDir( ".agents/skills" );
            const char* homeEnv = std::getenv( "HOME" );
            if( homeEnv && *homeEnv )
            {
                addDir( std::string( homeEnv ) + "/.claude/skills" );
            }

            const char* codexHomeEnv = std::getenv( "CODEX_HOME" );
            if( codexHomeEnv && *codexHomeEnv )
            {
                addDir( std::string( codexHomeEnv ) + "/skills" );
            }
            else if( homeEnv && *homeEnv )
            {
                addDir( std::string( homeEnv ) + "/.codex/skills" );
            }
        }

        // Scan each dir; accumulate findings per-file (deterministic dir/file order), then emit ONE
        // combined `<skillscan>` artifact across every file, instead of streaming a print per file.
        //
        // §B13.3 — WHAT COUNTS AS A SKILL FILE, and why this walk no longer says ".md".
        // It used to collect `.md` only. `files="22"` was honest about what it scanned and silent about what
        // it did not: this repo's skills/ holds 24 files, and the two it never opened are `skills/install.sh`
        // and `hooks/ripwire-nudge.sh` — under `verdict="clean"`, with no counter and no legend clause.
        // An injection scanner's directory verdict silently excluded that directory's two EXECUTABLES, which
        // are the files most worth scanning. The single-file form has no such filter (`--scan-skill=<any
        // file>` scans it), so the two entry points disagreed about their own subject.
        // They now agree: every regular file is a candidate. The two exclusions that remain are properties of
        // a RECURSIVE walk, not of what a skill file is, and neither is silent —
        //   • a file whose first 8 KB contain a NUL is BINARY (git's own buffer_is_binary rule, reused from
        //     binstale.h): a text-pattern injection scanner cannot read it, and a `.DS_Store` or a packed
        //     git object is not a skill. COUNTED, and reported as skipped= on the artifact;
        //   • a file that cannot be READ at all. Previously scanSkillFile collapsed that to "zero findings",
        //     i.e. a file that could not be opened contributed to a `verdict="clean"`. scanSkillFileChecked
        //     is the seam that tells the two apart (it exists for exactly this reason on the single-file
        //     path); such a file is COUNTED as skipped, never scanned-with-zero-findings;
        //   • a denylisted DIRECTORY subtree (.git, node_modules, build, …) is not descended, through the ONE
        //     shared table both crawlers already use (rw::isSkippedCrawlDir). Without it, pointing the verb
        //     at a cloned skill repo means opening every packed object. The number of pruned subtrees is
        //     named on the stderr tally, so the walk's shape is stated rather than assumed.
        std::sort( dirs.begin(), dirs.end() );
        std::vector<SkillScanRow> allRows;
        int      totalFindings = 0;
        int      filesScanned  = 0;
        int      filesSkipped  = 0;          // seen but not scannable: binary, or unreadable
        int      prunedDirs    = 0;          // denylisted subtrees not descended
        int      maxSev        = 0;          // 0=clean, 1=warn, 2=critical

        for( const std::string& dir : dirs )
        {
            // Walk dir manually so file order stays deterministic across the whole directory tree.
            namespace fs = std::filesystem;
            std::error_code ec;
            if( !fs::exists( dir, ec ) || ec )
            {
                continue;
            }

            // follow_directory_symlink, because a skills HOME is normally built out of symlinks: on this
            // machine every entry of ~/.claude/skills is a link to the skill's source directory, and
            // .agents/skills is itself a link to ~/.claude/skills. Without following them the verb walked
            // ZERO files and still said so as `files="0" findings="0" verdict="clean"` at exit 0 — measured
            // on a two-line fixture whose one symlinked skill carries a CRITICAL injection phrase. That is the
            // §P0.5a false-safe the single-file form refuses (exit 3), reappearing through the layout instead
            // of through the path.
            // Following symlinks means CYCLES, so canonical directory identity is tracked and a directory
            // already entered is pruned rather than re-entered — `a -> ..` is a real thing to find in a
            // hand-built skills home, and an unbounded walk there never terminates.
            std::vector<std::string>     skillPaths;
            std::vector<std::string>     visitedDirs;                  // canonical paths already descended
            const auto isFirstVisit = [ &visitedDirs ]( const fs::path& d )
            {
                std::error_code cec;
                const fs::path  canon = fs::canonical( d, cec );
                const std::string key = cec ? d.string() : canon.string();   // unresolvable ⇒ its own identity
                if( std::find( visitedDirs.begin(), visitedDirs.end(), key ) != visitedDirs.end() )
                {
                    return false;
                }
                visitedDirs.push_back( key );
                return true;
            };
            isFirstVisit( fs::path( dir ) );                            // the root itself, so a link back to it is a cycle

            fs::recursive_directory_iterator it( dir, fs::directory_options::skip_permission_denied
                                                    | fs::directory_options::follow_directory_symlink, ec );
            for( ec.clear(); it != fs::recursive_directory_iterator(); it.increment( ec ), ec.clear() )
            {
                if( ec ) { ec.clear(); continue; }

                const fs::path& p = it->path();
                if( it->is_directory( ec ) && !ec )
                {
                    if( rw::isSkippedCrawlDir( p.filename().string() ) || !isFirstVisit( p ) )
                    { ++prunedDirs;  it.disable_recursion_pending(); }
                    ec.clear();
                    continue;
                }
                ec.clear();
                if( !it->is_regular_file( ec ) || ec ) { ec.clear(); continue; }

                if( rw::binstale::looksBinary( p.string() ) ) { ++filesSkipped;  continue; }
                skillPaths.push_back( p.string() );
            }
            std::sort( skillPaths.begin(), skillPaths.end() );

            for( const std::string& p : skillPaths )
            {
                const SkillFileReadResult res = scanSkillFileChecked( p );
                if( !res.readable ) { ++filesSkipped;  continue; }   // never a scanned-with-zero-findings "clean"

                ++filesScanned;
                for( const SkillFinding& f : res.findings )
                {
                    allRows.push_back( { p, f } );
                }
                totalFindings += int( res.findings.size() );
                const int code = skillScanExitCode( res.findings );
                if( code > maxSev )
                {
                    maxSev = code;
                }
            }
        }

        printSkillScanArtifact( stdout, allRows, filesScanned, filesSkipped );

        // Honest zero: "0 finding(s)" alone doesn't say whether that's because nothing was WARN/CRITICAL
        // or because there was nothing readable to scan. Naming the file count keeps a genuine "scanned
        // 0 skill files" (an empty/unpopulated dir — a real measurement) legible on its own, distinct from
        // this same verb's exit-3 refusal above (which never gets here). §B13.3 adds the other half of the
        // population to the same line: what the walk saw and could not scan, and what it did not descend.
        std::fprintf( stderr, "ripwire scan: %d finding(s) total (%d skill file(s) scanned, %d unscannable file(s) skipped, %d denylisted subtree(s) not descended)\n",
                      totalFindings, filesScanned, filesSkipped, prunedDirs );
        return maxSev;
    }

    // ── A4-R3 CLI batch: one-turn context sweep from a `verb:arg` file (or stdin) ─────────────────
    // The shell-pipeline counterpart of the MCP `batch` verb. Reuses the EXACT shared machinery
    // (runBatchSub + batchText from mcp.h) — each `verb:arg` line becomes the same JSON sub-query the
    // MCP verb parses, so a CLI batch answer is byte-identical to the MCP one (and to the standalone
    // verbs). Blank lines and `#`-comment lines are ignored; over kBatchCap lines are counted but not
    // processed (capped="1", honest n<requested), never silently dropped.
    if( !cfg.batchFile.empty() )
    {
        const std::string root( cfg.rootPath );

        std::string content;
        if( cfg.batchFile == "-" )
        {
            // R4: byte-safe reader (stdinline.h). --batch=- lines carry arbitrary verb arguments — a
            // non-ASCII --grep pattern is ordinary input — and std::getline( std::cin, ... ) aborted the
            // sanitizer build on the first high byte. Parity is exact, so batch answers are unchanged.
            std::string l;
            while( rw::readByteSafeLine( stdin, l ) ) { content += l; content += '\n'; }
        }
        else
        {
            const std::string bf( cfg.batchFile );
            std::FILE* f = std::fopen( bf.c_str(), "rb" );
            if( !f ) { std::fprintf( stderr, "ripwire: --batch: cannot open '%s'\n", bf.c_str() ); return 1; }
            char buf[ 4096 ]; std::size_t n;
            while( ( n = std::fread( buf, 1, sizeof buf, f ) ) > 0 )
            {
                content.append( buf, n );
            }
            std::fclose( f );
        }

        // one `verb:arg` line → the same JSON sub-query object the MCP `queries` array carries, so
        // runBatchSub sees identical input on both surfaces. Values are JSON-escaped (an arg may hold
        // any byte). path_between takes `from,to` (split on the first comma); analyze takes no arg.
        const auto cliBatchObject = []( const std::string& verb, const std::string& arg ) -> std::string
        {
            const auto j = []( const std::string& s ) { return rw::mcpdetail::jsonEscape( s ); };
            std::string obj = "{\"verb\":\"" + j( verb ) + "\"";
            if( verb == "path_between" )
            {
                const std::size_t comma = arg.find( ',' );
                const std::string from  = ( comma == std::string::npos ) ? arg : arg.substr( 0, comma );
                const std::string to    = ( comma == std::string::npos ) ? std::string{} : arg.substr( comma + 1 );
                obj += ",\"from\":\"" + j( from ) + "\",\"to\":\"" + j( to ) + "\"";
            }
            else if( !arg.empty() )
            {
                const char* key = "symbol";                          // callers/callees/impact/uses/mentions/owners/find_*
                if( verb == "for" || verb == "exemplar" )
                {
                    key = "task";
                }
                else if( verb == "grep" )
                {
                    key = "pattern";
                }
                else if( verb == "lego" )
                {
                    key = "type";
                }
                else if( verb == "cochange" )
                {
                    key = "file";
                }
                else if( verb == "fetch_body" )
                {
                    key = "handle";
                }
                obj += ",\"" + std::string( key ) + "\":\"" + j( arg ) + "\"";
            }
            obj += "}";
            return obj;
        };

        RedactCounts        rc;
        RedactCounts* const rp = cfg.noRedact ? nullptr : &rc;

        std::vector<BatchSub> subs;
        std::size_t           requested = 0;
        std::size_t           pos       = 0;
        while( pos < content.size() )
        {
            const std::size_t nl   = content.find( '\n', pos );
            std::string       line = content.substr( pos, nl == std::string::npos ? std::string::npos : nl - pos );
            pos = ( nl == std::string::npos ) ? content.size() : nl + 1;

            // trim surrounding whitespace (incl. a trailing '\r' from CRLF)
            const std::size_t b = line.find_first_not_of( " \t\r" );
            if( b == std::string::npos )
            {
                continue; // blank line
            }
            const std::size_t e = line.find_last_not_of( " \t\r" );
            line = line.substr( b, e - b + 1 );
            if( line.empty() || line[0] == '#' )
            {
                continue; // comment
            }

            ++requested;
            if( subs.size() >= kBatchCap )
            {
                continue; // count, don't process past the cap
            }

            const std::size_t colon = line.find( ':' );
            const std::string verb  = ( colon == std::string::npos ) ? line : line.substr( 0, colon );
            const std::string arg   = ( colon == std::string::npos ) ? std::string{} : line.substr( colon + 1 );
            subs.push_back( runBatchSub( root, cliBatchObject( verb, arg ), cfg.topK, cfg.stable, rp ) );
        }

        std::fputs( batchText( subs, requested, kBatchCap ).c_str(), stdout );
        std::fputc( '\n', stdout );
        reportRedactions( stderr, rc );
        return 0;
    }

    // Wave-4 remote ergonomics: a git-URL positional (https:// or git@) is shallow-cloned to a per-URL
    // cache dir and mapped from there. A plain path passes through unchanged (no clone attempted).
    // S3: --refetch forces a fresh clone instead of silently reusing an arbitrarily-old cached one.
    // Multi-root: EVERY positional resolves the same way; roots are then deduped (realpath, stderr note),
    // nested roots hard-error, labels assigned, and the set canonically ordered (workspace.h — §2/§2.1).
    std::vector<std::string> resolvedRoots;
    for( const std::string_view rootArg : cfg.roots )
    {
        const auto [ resolvedRoot, cloneOk ] = resolveRemoteRoot( std::string( rootArg ), cfg.refetch );
        if( !cloneOk )
        {
            return 1;
        }

        // a root that does not EXIST is caller error (a typo'd path), not a degradable runtime condition —
        // exit 1 with empty stdout so agent pipelines can detect it. A readable-but-empty directory still
        // maps to a valid empty result (exit 0): "nothing there" and "no such place" are different answers.
        {
            namespace fs = std::filesystem;
            std::error_code rootEc;
            if( !fs::exists( fs::path( resolvedRoot ), rootEc ) || rootEc )
            {
                // If the path looks like a flag (contains '='), suggest the flag spelling
                if( resolvedRoot.find( '=' ) != std::string::npos )
                {
                    const auto eqPos = resolvedRoot.find( '=' );
                    const std::string flagName = resolvedRoot.substr( 0, eqPos );
                    std::fprintf( stderr, "ripwire: root path does not exist: %s\n", resolvedRoot.c_str() );
                    std::fprintf( stderr, "ripwire: did you mean --%s=%s ?\n", flagName.c_str(), resolvedRoot.substr( eqPos + 1 ).c_str() );
                }
                else
                {
                    std::fprintf( stderr, "ripwire: root path does not exist: %s\n", resolvedRoot.c_str() );
                }
                return 1;
            }
        }
        resolvedRoots.push_back( resolvedRoot );
    }

    // workspace hygiene: dedupe can collapse a repeated root back to N=1 (proceed single-root, byte-identical);
    // nested roots are a hard error. `ws` holds ≥2 entries ONLY for a real multi-root run.
    std::vector<WorkspaceRoot> ws;
    if( resolvedRoots.size() >= 2 )
    {
        if( !buildWorkspaceRoots( resolvedRoots, ws ) )
        {
            return 1;
        }
        if( ws.size() == 1 ) { resolvedRoots.assign( 1, ws[0].arg );  ws.clear(); }
    }
    const bool        multiRoot = ws.size() >= 2;
    const std::string root( multiRoot ? ws[0].arg : resolvedRoots[0] );   // single-root alias; multi-root sites branch on `ws`

    // --index-out=BASE (both-families amendment): the CI generate-and-exit path.
    // Cold-parse the tree TWICE — once lean, once rich — writing BASE.lean.ripwirecache and
    // BASE.rich.ripwirecache, then exit 0 WITHOUT emitting a map. Both families ship because the flagship
    // orientation verbs (--for/--exemplar/--metrics/--uses) ingest RICH and a lean-only artifact leaves
    // them cold (measured: lean 1.46 MB, rich 2.80 MB on this repo). This is sugar over --cache, not a
    // second write path — it reuses ingest()'s existing saveCache machinery, one ingest per explicit cache
    // path. force-rebuild: an existing target is removed first so a stale warm file cannot shadow a fresh
    // generate. --exclude shapes the crawl (fewer files → fewer symbols → smaller blob). The blobs are NOT
    // byte-identical run-to-run — the v8 header stamps the blob write wall-time (the statgate racy rule) —
    // so the gated contract is RESTORE-EQUIVALENCE (a --cache restore == a cold parse), not blob-byte-identity.
    if( !cfg.indexOut.empty() )
    {
        const std::string       base( cfg.indexOut );
        struct Family { const char* suffix; bool rich; };
        const Family families[2] = { { ".lean.ripwirecache", false }, { ".rich.ripwirecache", true } };

        int rc = 0;
        for( const Family& fam : families )
        {
            const std::string path = base + fam.suffix;
            std::remove( path.c_str() );                     // force-rebuild: a stale warm file must not shadow the generate

            IngestResult r = ingest( root.c_str(), cfg.excludes, path, cfg.maxFileBytes, fam.rich );
            (void)r;

            std::error_code       ec;
            const std::uintmax_t  sz = std::filesystem::file_size( std::filesystem::path( path ), ec );
            if( ec || sz == 0 )
            {
                std::fprintf( stderr, "ripwire: --index-out: failed to write %s\n", path.c_str() );
                rc = 1;
            }
            else
            {
                std::fprintf( stderr, "ripwire: --index-out wrote %s (%llu bytes, %s family)\n",
                              path.c_str(), static_cast<unsigned long long>( sz ), fam.rich ? "rich" : "lean" );
            }
        }
        return rc;
    }

    // Warm by default: with no explicit --cache and without --no-cache, use a per-root TMPDIR cache so a
    // repeated invocation (e.g. successive --grep / --around / --for on the same tree) re-parses only what
    // changed. Verified output-identical to a cold parse (regression: cache transparency).
    // A4-P4: the verb class (rich=captureValueUses vs lean) is needed BEFORE choosing the auto-cache path
    // so each class keys its own warm cache file (no cross-class thrash). Rich = --for/--metrics/--uses/--exemplar
    // /--context-ratio/--nonlocal-state/--quality-panel — the local-reasoning lens counts read/write sites, and
    // nonlocal-state's attribution is read/write USE SITES by definition, so a lean ingest would hand either a
    // confident, wrong zero; --quality-panel builds two of its six families out of exactly those two lenses.
    const bool needsValueUses = !cfg.usesSym.empty() || cfg.metrics || !cfg.forTask.empty() || !cfg.exemplar.empty()
                                || cfg.contextRatio || cfg.nonlocalState || cfg.qualityPanel
                                || !cfg.verifyClaim.empty();   // G4: uses()/unused() claims count read/write use-sites — a lean ingest would hand a confident, wrong zero
    IngestResult ing;
    if( multiRoot )
    {
        // Multi-root ingest: ONE existing per-root cache blob per root (the exact
        // defaultCachePath keying, label-free content), each root crawled + parsed independently in canonical
        // order, then merged by one id-offset pass. Incrementality is structural: an edit in root2 dirties
        // ONLY root2's blob — root1's load is a pure warm hit (RIPWIRE_CACHE_STATS proves it per root).
        std::vector<IngestResult> parts;
        parts.reserve( ws.size() );
        for( const WorkspaceRoot& r : ws )
        {
            std::string cachePath;
            if( !cfg.noCache )
            {
                cachePath = defaultCachePath( r.arg, needsValueUses );
            }
            parts.push_back( ingest( r.arg.c_str(), cfg.excludes, cachePath, cfg.maxFileBytes, needsValueUses,
                                     /*excludeLabel=*/r.label ) );
        }
        ing = mergeWorkspaceIngests( ws, parts );
    }
    else
    {
        std::string      autoCache;
        std::string_view cacheArg = cfg.cacheFile;
        if( cacheArg.empty() && !cfg.noCache )
        {
            autoCache = defaultCachePath( root, needsValueUses );
            cacheArg  = autoCache;
        }
        ing = ingest( root.c_str(), cfg.excludes, cacheArg, cfg.maxFileBytes, needsValueUses );
    }
    if( cfg.ignoreTests )
    {
        applyIgnoreTests( ing );
    }

    // Enhanced help needs only the parsed symbol inventory plus cheap Git facts. Answer before graph/QMetrics/
    // history mining so a hook or agent asking where to start pays the least repository-aware cost available.
    if( !cfg.helpTask.empty() )
    {
        return runHelpTask( cfg, ing, root );
    }

    if( std::getenv( "RIPWIRE_STATS" ) )   // how many std::strings the stored model holds (+ their bytes)
    {
        std::size_t pathB = 0, nameB = 0, calleeB = 0, incB = 0;
        for( const auto& f : ing.files )
        {
            pathB += f.size();
        }
        for( const auto& s : ing.symbols )
        {
            nameB += s.name.size();
        }
        for( const auto& r : ing.references )
        {
            calleeB += r.calleeName.size();
        }
        for( const auto& i : ing.includes )
        {
            incB += i.target.size();
        }
        const std::size_t total  = ing.files.size() + ing.symbols.size() + ing.references.size() + ing.includes.size();
        const std::size_t bytes  = pathB + nameB + calleeB + incB;
        std::fprintf( stderr,
            "[stats] stored std::strings = %zu  (%zu bytes of char data)\n"
            "        files/paths       = %zu (%zu B)\n"
            "        symbols/names      = %zu (%zu B)\n"
            "        references/callees = %zu (%zu B)\n"
            "        includes/targets   = %zu (%zu B)\n",
            total, bytes, ing.files.size(), pathB, ing.symbols.size(), nameB, ing.references.size(), calleeB, ing.includes.size(), incB );
    }
    // SCIP precision overlay: parse the index (if --scip given) → map to ripwire ids → hand to
    // buildGraph as an optional parameter. A missing/corrupt/mismatched index yields an EMPTY overlay
    // (one DEGRADED_PATH_ALERT + stderr note) and the build proceeds name-based, byte-identical to no --scip.
    ScipOverlay scipOverlay;
    if( !cfg.scipIndex.empty() )
    {
        scipOverlay = loadScipOverlay( cfg.scipIndex, ing );
    }
    // An EMPTY overlay (no --scip, OR a missing/corrupt/mismatched index that already alerted) is treated as
    // no overlay at all: scipPtr stays nullptr so buildGraph/serialize produce output BYTE-IDENTICAL to a
    // run with no --scip (the degrade contract — a bad index must never change the map, only stderr).
    const ScipOverlay* scipPtr = scipOverlay.empty() ? nullptr : &scipOverlay;
    const Graph       g   = buildGraph( ing, scipPtr );

    // --metrics: fan-in per symbol from the in-edge CSR (free graph query) — the descriptive
    // "this is reused N×, prefer reusing it" signal. fan-out + cx come from serialize/Symbol.
    std::vector<std::uint32_t> fanIn;
    if( cfg.metrics || !cfg.forTask.empty() || !cfg.exemplar.empty() )
    {
        fanIn.assign( ing.symbols.size(), 0 );
        const auto* ro = g.inEdges.rowOffsets();
        for( std::size_t i = 0; i < ing.symbols.size(); ++i )
        {
            fanIn[i] = ro[i + 1] - ro[i];
        }
    }
    const std::vector<std::uint32_t>* fanInPtr = fanIn.empty() ? nullptr : &fanIn;

    // Q-compute metrics (Q2/Q4/Q5): cbo / tested= / lcom4 / change-amplification — descriptive facts surfaced
    // on --metrics ONLY (never gates — steering thesis). Computed once here so all serialize call-sites share
    // it. amp = |direct callers| (symbol-level, in-edge CSR) + |co-change partners of the symbol's FILE|
    // (file-level, gitmine) — a GRANULARITY MIX documented in the serialize emit comment. amp DEGRADES to
    // callers-only when git/history is unavailable (co-change term = 0), so a git-less repo still gets amp.
    QMetrics                          qmetrics;
    std::vector<std::uint32_t>        amp;
    const std::vector<std::uint32_t>* cboPtr    = nullptr;
    const std::vector<std::uint8_t>*  testedPtr = nullptr;
    const std::vector<std::uint32_t>* lcom4Ptr  = nullptr;
    const std::vector<std::uint32_t>* ampPtr    = nullptr;
    // Also computed for --for (Q3) and --exemplar (Q7): the quality lens folds tested=/amp= onto the read-time
    // bundle, and --exemplar selects best-in-class by tested/fan-in/ccx. cbo/lcom4 are consumed only by
    // serialize() (the map path, which both verbs return before reaching) — harmless to set.
    // A4-P6: the --for path used to spawn TWO git popens — an 18-month `gitCommitFileSets` here (for amp) and a
    // 12-month `gitChurnCounts` in the --for block below (for the quality lens' churn=). Both are now derived
    // from ONE 18-month `git log --name-only` walk (gitCoChangeAndChurn), bucketed by commit epoch so each
    // number keeps its own window. forChurn is hoisted here so the --for block can read it without re-mining.
    std::vector<std::uint32_t> forChurn;
    if( cfg.metrics || !cfg.forTask.empty() || !cfg.exemplar.empty() )
    {
        PROFILE_SCOPE_DESCRIBE( "main: computeQMetrics + change-amplification" );
        qmetrics = computeQMetrics( ing, g );
        cboPtr    = &qmetrics.cbo;
        testedPtr = &qmetrics.tested;
        lcom4Ptr  = &qmetrics.lcom4;

        // change-amplification: per-FILE co-change partner count (git; one popen over `git log --name-only`),
        // shared by every symbol in that file, ADDED to that symbol's direct-caller count. No git / no history
        // → coPartnersPerFile stays 0 (clean degrade to callers-only). The single popen is measured (§ gate f).
        std::vector<std::uint32_t> coPartnersPerFile( ing.files.size(), 0u );
        {
            // ONE popen: 18-month co-change file-sets (for amp) + — only when --for needs it — the 12-month
            // per-file churn (folded into the same walk, A4-P6). --metrics/--exemplar pass churnMonths=0 → no
            // churn work, sets byte-identical to the old gitCommitFileSets("18 months ago", 30).
            // Multi-root (§5): one popen PER root, each resolved only against its own files; the per-commit
            // sets concatenate (commits are disjoint across repos) and churn accumulates per file.
            std::vector<std::vector<std::uint32_t>> commits;
            if( multiRoot )
            {
                std::vector<std::uint32_t> rootChurn;
                for( std::uint32_t r = 0; r < ws.size(); ++r )
                {
                    // Y2: the memoized form — skips the 431 ms `git log --name-only` walk on a
                    // warm (repo, HEAD sha, window, boundary-sha) hit; see quality.h's qchurn family.
                    std::vector<std::vector<std::uint32_t>> part =
                        quality::gitCoChangeAndChurnCached( ws[r].arg, ing, "18 months ago", 30,
                                             cfg.forTask.empty() ? 0u : 12u,
                                             cfg.forTask.empty() ? nullptr : &rootChurn, r );
                    for( std::vector<std::uint32_t>& c : part )
                    {
                        commits.push_back( std::move( c ) );
                    }
                    if( !cfg.forTask.empty() )
                    {
                        if( forChurn.size() != ing.files.size() )
                        {
                            forChurn.assign( ing.files.size(), 0u );
                        }
                        for( std::size_t f = 0; f < forChurn.size() && f < rootChurn.size(); ++f )
                        {
                            forChurn[f] += rootChurn[f];
                        }
                    }
                }
            }
            else
            {
                // Y2: memoized — see the multi-root branch above.
                commits = quality::gitCoChangeAndChurnCached( root, ing, "18 months ago", 30,
                                               cfg.forTask.empty() ? 0u : 12u,
                                               cfg.forTask.empty() ? nullptr : &forChurn );
            }
            if( !commits.empty() )
            {
                // co-change degree per file = # of OTHER files that share ≥1 commit with it (file-level).
                std::vector<HashMap<std::uint32_t, char>> partners( ing.files.size() );
                for( const std::vector<std::uint32_t>& c : commits )
                {
                    for( std::size_t i = 0; i < c.size(); ++i )
                    {
                        for( std::size_t j = i + 1; j < c.size(); ++j )
                        {
                            const std::uint32_t a = c[i], b = c[j];
                            if( a < ing.files.size() && b < ing.files.size() ) { partners[a][b] = 1; partners[b][a] = 1; }
                        }
                    }
                }
                for( std::size_t f = 0; f < ing.files.size(); ++f )
                {
                    coPartnersPerFile[f] = std::uint32_t( partners[f].size() );
                }
            }
        }
        amp.assign( ing.symbols.size(), 0u );
        for( std::size_t i = 0; i < ing.symbols.size(); ++i )
        {
            amp[i] = qmetrics.callerCount[i] + coPartnersPerFile[ ing.symbols[i].fileId ];
        }
        ampPtr = &amp;
    }

    // purity fixpoint (only when emitting signatures): impure[] demotes a const method's pure= flag
    // if it transitively does I/O — so pure="1" means "const AND no transitive side-effects".
    //
    // §B6 M3 [BROKEN — and the CLI was the wrong arm]: this gate listed only the two ORIGINAL signature
    // emitters, but --from-trace and --pack-task grew their own packSignatures call sites (FromTraceInputs
    // ::impure / PackTaskInputs::impure, both fed from this pointer) without joining it. With impurePtr null
    // the fixpoint never runs, so those two bundles emitted pure="1" on symbols the fixpoint demotes —
    // `runMcp`, the stdio loop, being the demonstration: --for correctly omits pure= on it while
    // --from-trace and --pack-task both claimed it. The MCP twins of both verbs compute computeImpure
    // themselves and were already right. The gate now names every signature-emitting verb; the condition is
    // "will something below ask for impurePtr", and a verb that reads d.impurePtr must appear here.
    std::vector<char>        impure;
    const std::vector<char>* impurePtr = nullptr;
    if( !cfg.forTask.empty() || cfg.packSignatures || !cfg.fromTrace.empty() || !cfg.runTrace.empty() || cfg.packTaskFlag )
    {
        impure    = computeImpure( ing, g );
        impurePtr = &impure;
    }

    // RedactCounts: one per-run secret-redaction tally, shared across every body-emission seam so a single stderr
    // summary aggregates them. `redactPtr` is null under --no-redact (redaction disabled at every seam) —
    // then no seam touches the bytes and the output is verbatim. Bodies (CDATA / recalled docs) go through
    // it; symbol names / signatures in the default map never do (identifiers are not secrets, and the
    // default map must stay byte-stable — a repo with no secrets produces byte-identical output either way).
    RedactCounts        redactCounts;
    RedactCounts* const redactPtr = cfg.noRedact ? nullptr : &redactCounts;

    // L3 field notes: load root/.ripwire_notes ONCE (a small file) into the surfacing index. Single-root only
    // (a workspace has no single repo root — notes are a per-repo artifact), and nullptr when EMPTY so every
    // surfacing seam (--for/--expand/MCP) stays byte-identical when there is nothing to show — the inertness
    // contract. Retrieval handlers below read notesPtr; --note-add/--notes have their own handler.
    const rw::notes::NoteIndex noteIndex = multiRoot ? rw::notes::NoteIndex{} : rw::notes::loadNoteIndex( root );
    const rw::notes::NoteIndex* const notesPtr = ( !multiRoot && !noteIndex.empty() ) ? &noteIndex : nullptr;

    // Phase B7.2: bundle the shared post-graph state; each verb handler below reads what it needs.
    const MainDispatch dsp{ cfg, ing, g, root, multiRoot, ws, fanIn, fanInPtr, qmetrics,
                           ampPtr, cboPtr, testedPtr, lcom4Ptr, impurePtr, forChurn, redactCounts, redactPtr, notesPtr };

    if( std::optional<int> handled = runForLens( dsp ) )
    {
        return *handled;
    }

    // §A2 (audit 2026-08-08) — the query family dispatches FIRST, as one contiguous block. A typed task
    // (--for/--pack-task/--query) is the caller's PRIMARY intent; a report verb handed in alongside it is the
    // incidental one, so the task answers and the report verb is disclosed as ignored by §B11.4's table.
    // Before this, the family had three different answers to that one question — --for won everything,
    // --pack-task lost to --skipped/--hotspots but beat --lint, and --query lost to all ~50 — an order nobody
    // designed and no caller could infer. Intra-family order is X9(c)'s and UNCHANGED: --for (above) >
    // --pack-task > --query. Deliberate behaviour change; test/dispatchordercheck.sh pins every pair.
    if( std::optional<int> handled = runPackTask( dsp ) )
    {
        return *handled;
    }

    // --query owns no handler of its own: runDefaultMap serves it (the lexical-rank branch at its top) and is
    // also this chain's fallback, so hoisting the CALL is what moves --query's precedence. Reaching
    // runDefaultMap from here is byte-identical to falling through to it — every handler in between takes
    // `const MainDispatch&` and none mutate it, so skipping them changes which verb answers and nothing else.
    // Guarded on --query, so a run without it still falls through the whole table exactly as before.
    if( !cfg.query.empty() )
    {
        return runDefaultMap( dsp );
    }

    if( std::optional<int> handled = runTargetedViews( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runArchViews( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runMaintenanceViews( dsp ) )
    {
        return *handled;
    }

    // §6.3: --quality-baseline/--quality-delta, then --dead-code — the two branches of the old
    // runQualityViews, in the order that chain evaluated them.
    if( std::optional<int> handled = runQualityDelta( dsp ) )
    {
        return *handled;
    }

    // --dmm sits immediately after --quality-delta, which is also its precedence: a run that passes both
    // gets the per-kind report, because that one can gate and this one deliberately cannot.
    if( std::optional<int> handled = runDmm( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runQualityViews( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runEditCheck( dsp ) )
    {
        return *handled;
    }

    // lane/safe-delete: dispatches right after --edit-check — the same "one already-resolved SYM, one
    // composed answer" family, outside the pinned nine navigate verbs (test/dispatchordercheck.sh).
    if( std::optional<int> handled = runSafeDelete( dsp ) )
    {
        return *handled;
    }

    // lane/paper-slice: same family, right after --safe-delete — the row order in scanReportVerbPrecedence
    // mirrors this seam (test/dispatchordercheck.sh pins pairs by that table).
    if( std::optional<int> handled = runSlice( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runEvalViews( dsp ) )
    {
        return *handled;
    }

    // The nine navigate verbs, in the SAME order the old runNavigateVerbs if-chain evaluated them. The order
    // is behaviour, not layout: a run passing two of these flags gets exactly one answer, and which one is
    // decided here. test/dispatchordercheck.sh pins every seam below.
    if( std::optional<int> handled = runCallHierarchy( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runGraphQuery( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runUses( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runVerify( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runExternalSurface( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runPath( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runConnect( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runImpact( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runMentions( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runAffected( dsp ) )
    {
        return *handled;
    }

    // §P11.2b: the inverse direction of the same map, immediately after it — the two are read together and
    // neither can shadow the other (one takes --affected=, the other --exercises=).
    if( std::optional<int> handled = runExercises( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runChangeViews( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runMergeScout( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runPlanLanes( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runCrossRef( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runLayout( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runFieldAffinity( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runDocDrift( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runFromTrace( dsp ) )
    {
        return *handled;
    }

    // VT-1: the exec-mode sibling, immediately after --from-trace (the two are read together; a command line
    // passing both is answered by the file/stdin form, and the X9 slots table discloses the collision).
    if( std::optional<int> handled = runRunTrace( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runNotes( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runSkipped( dsp ) )
    {
        return *handled;
    }

    // §A2: runPackTask used to sit HERE, between --skipped and --communities. It now dispatches with the rest
    // of the query family, immediately after runForLens.

    if( std::optional<int> handled = runCommunities( dsp ) )
    {
        return *handled;
    }

    // §P11.6: the drill-down for the ids runCommunities/runZoom print, immediately after its parent.
    if( std::optional<int> handled = runCommunityDrill( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runZoom( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runStructureText( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runGrep( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runLint( dsp ) )
    {
        return *handled;
    }

    if( std::optional<int> handled = runAround( dsp ) )
    {
        return *handled;
    }

    return runDefaultMap( dsp );
}
