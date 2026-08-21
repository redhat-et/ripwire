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
#include "mcp.h"
#include "mcpserver.h"             // the optional remote MCP transport (--listen), picked below
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

// Mark ing.files that the working-tree diff against git HEAD reports as changed. false ⇒ git unavailable
// (an EMPTY diff at status 0 is a CLEAN TREE, not a failure, and returns true with nothing marked).
// onlyRoot (multi-root): != UINT32_MAX ⇒ mark ONLY files of that root — one repo's
// diff must never suffix-match a same-named file in another root. Default = all files (single-root, unchanged).
//
// THE MASK IS NOT BUILT HERE. It comes from situ.h's gitDiffChangedMask — the same call mcpindex.h and
// mcpverbs.h make — which delegates to prcontext.h's gitDiffChangedMaskNumstat. Until this delegation, the
// CLI and the MCP form of ONE verb disagreed about a mass chmod: situ.h's builder is `--numstat`-based and
// drops a content-identical entry (git reports "0<TAB>0<TAB>path" for a pure mode flip), while this function
// ran `--name-only`, which cannot tell a mode flip from a real edit. So `--situ` and `--test-gate` from the
// CLI inflated their change set with the exact 272-file chmod incident that situ.h's own header records as
// fixed, and the MCP verb of the same name did not. One helper, both arms — the alternative is two
// implementations that agree today.
//
// Union, never overwrite: --map-diff's multi-root teleport seed calls this once per root with the SAME
// accumulator, so the per-root masks must OR together (each root's call is already narrowed by onlyRoot).
bool gitChangedFiles( const std::string& root, const rw::IngestResult& ing, std::vector<char>& out,
                      std::uint32_t onlyRoot = UINT32_MAX )
{
    const auto [ mask, isGitOk ] = rw::gitDiffChangedMask( root, ing, onlyRoot );
    if( !isGitOk )
    {
        return false;
    }

    const std::size_t markCount = std::min( out.size(), mask.size() );
    for( std::size_t fileIndex = 0; fileIndex < markCount; ++fileIndex )
    {
        if( mask[fileIndex] )
        {
            out[fileIndex] = 1;
        }
    }
    return true;
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

// Per-file commit count over a recent window (`git log -c --since=... --name-only`; the `-c` is
// gitmine.h::kMergeDiffArgs — a merge commit's own content is mined, and merged-branch work is not
// double-counted. Without it this walk was silent about every merge, and a file whose only history is a
// merge commit read churn=0 with nothing disclosing it). Churn is the
// orthogonal-to-complexity axis: hotspot = complexity × churn (CodeScene's key insight — complex code
// that never changes costs nothing; complex code that changes constantly is where bugs live).
// `scope`: nullptr (default) reproduces the pre-flag `--since=<since>` window byte-for-byte; a non-null
// active scope (CLI --since=REV|DATE, see gitmine.h resolveSinceScope) overrides it with the resolved
// window — REV form as a deterministic `REV..` range, date form as `--since=DATE` (wall-clock-relative).
bool gitChurnCounts( const std::string& root, const rw::IngestResult& ing, std::vector<std::uint32_t>& out, const char* since, const rw::SinceScope* scope = nullptr,
                     std::uint32_t onlyRoot = UINT32_MAX )   // multi-root §5: count ONLY files of that root
{
    const std::string windowArgs = scope ? rw::sinceLogArgs( *scope, since ) : ( "--since=" + shSingleQuote( since ) + " " );
    const rw::GitCommandLines touched = rw::gitCommandLines(
        "git -c core.quotepath=false -C " + shSingleQuote( root ) + " log " + rw::kMergeDiffArgs + windowArgs + "--name-only --format= 2>/dev/null" );
    if( !touched.isStarted )
    {
        return false;
    }

    rw::HashMap<std::string, std::uint32_t> counts;   // repo-relative path → # commits touching it
    for( const std::string& p : touched.lines )
    {
        ++counts[p];
    }
    if( counts.empty() )
    {
        return false;   // no in-window commit touched anything — the caller's "empty churn" case, NOT an error (see --hotspots' two causes)
    }

    // Map the per-path tally onto ingested fileIds through THE ONE specificity-ordered mapper (§H6,
    // gitmine.h::mapChurnCountsOntoFiles). This loop used to be spelled here AND in gitmine.h's
    // resolveCommitStream, both ending in "first match in the bucket wins" — so a root-level file's count
    // silently overwrote a subdirectory file's with the same basename, on --hotspots and on --for's churn=
    // lens alike. The shared mapper prefers an EXACT repo-relative match, otherwise the least-unexplained
    // prefix, and refuses (disclosing it) on a tie.
    rw::mapChurnCountsOntoFiles( counts, ing, out, onlyRoot );
    return true;
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

// L2: the `[{"t":..,"n":..,"p":"file:line"},...]` JSON row array shared by --callers/--callees/--impact's
// --json branches (identical shape, different surrounding header fields — see each call site). Avoids
// carrying two copies of the same per-row loop (--quality-delta flagged the pre-extraction duplicate).
// File-scope (not inside `using namespace rw;`, unlike its callers) — every rw:: type/fn spelled out.
// R-E (2026-08-17 harvest): rootPrefix empty ⇒ p= stays the ing.files[] spelling unchanged (multi-root, or
// a caller with no single root to strip) — same convention as serialize()'s pathRel.
inline void printJsonSymbolRows( const rw::IngestResult& ing, const std::vector<rw::NodeId>& ids, std::size_t begin, std::size_t end,
                                 std::string_view rootPrefix = {} )
{
    for( std::size_t i = begin; i < end; ++i )
    {
        const rw::Symbol&      s = ing.symbols[ ids[i] ];
        const std::string_view p = rootPrefix.empty() ? std::string_view( ing.files[ s.fileId ] )
                                                       : rw::sarif::rootRelativeUri( ing.files[ s.fileId ], rootPrefix );
        std::printf( "%s{\"t\":\"%s\",\"n\":\"%s\",\"p\":\"%s:%u\"}", i == begin ? "" : ",",
                     rw::symTag( s.kind ), rw::jsonStr( s.name ).c_str(), rw::jsonStr( p ).c_str(), s.line );
    }
}

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

bool isHeaderPath( std::string_view path ) noexcept
{
    const std::size_t dot = path.rfind( '.' );
    if( dot == std::string_view::npos )
    {
        return false;
    }
    const std::string_view extension = path.substr( dot + 1 );
    return extension == "h" || extension == "hpp" || extension == "hh" || extension == "hxx";
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

// Magic-number filtering is semantic, not spelling-based: decimal forms such as 0.0, 1.0f, 2.0 and
// -1 are the same universal control/count idioms as their integer spellings. Base-prefixed literals are
// an explicit syntax allow-list for masks, protocol fields and character encodings; without type/dataflow
// evidence, calling 0x80 a maintenance defect creates much more noise than signal.
bool isUniversalOrAllowlistedNumber( std::string_view spelling ) noexcept
{
    std::string normalized;
    normalized.reserve( spelling.size() );
    for( char c : spelling )
    {
        if( c != '\'' )
        {
            normalized.push_back( c );
        }
    }

    std::string_view valueText = normalized;
    if( !valueText.empty() && ( valueText.front() == '+' || valueText.front() == '-' ) )
    {
        valueText.remove_prefix( 1 );
    }
    constexpr std::string_view kBasePrefixes[] = { "0x", "0X", "0b", "0B" };
    for( std::string_view prefix : kBasePrefixes )
    {
        if( valueText.rfind( prefix, 0 ) == 0 )
        {
            return true;
        }
    }

    while( !normalized.empty() )
    {
        const char suffix = normalized.back();
        if( suffix != 'u' && suffix != 'U' && suffix != 'l' && suffix != 'L' && suffix != 'f' && suffix != 'F' )
        {
            break;
        }
        normalized.pop_back();
    }
    if( normalized.empty() )
    {
        return false;
    }

    double parsed = 0.0;
    const auto [ end, error ] = rw::parseFloating( normalized.data(), normalized.data() + normalized.size(), parsed );
    if( error != std::errc {} || end != normalized.data() + normalized.size() )
    {
        return false;
    }
    return parsed == -2.0 || parsed == -1.0 || parsed == 0.0 || parsed == 1.0 || parsed == 2.0;
}

// A number captured inside a local const/constexpr initializer is named policy, not a magic number. Walk
// only to the current statement/block boundary: a `const` in an earlier statement must not pardon this one.
bool isConstantInitializerNumber( std::string_view src, std::size_t numberByte ) noexcept
{
    if( numberByte > src.size() )
    {
        return false;
    }
    std::size_t statementStart = numberByte;
    while( statementStart > 0 )
    {
        const char c = src[ statementStart - 1 ];
        if( c == ';' || c == '{' || c == '}' )
        {
            break;
        }
        --statementStart;
    }
    const std::string_view head = src.substr( statementStart, numberByte - statementStart );
    const std::size_t      eq   = head.rfind( '=' );
    if( eq == std::string_view::npos || ( eq > 0 && std::strchr( "=!<>+-*/%&|^~", head[ eq - 1 ] ) != nullptr ) )
    {
        return false;
    }
    return rw::darkflags::containsWord( head.substr( 0, eq ), "constexpr" ) || rw::darkflags::containsWord( head.substr( 0, eq ), "const" );
}

// The raw-body return scanner deliberately avoids a second AST pass. A nested lambda body is the one C++
// callable shape an outer function's byte span contains without a separately indexed Symbol; recognise its
// capture list between the previous statement/block boundary and this opening brace.
bool opensLambdaBody( std::string_view src, std::size_t bodyStart, std::size_t braceByte ) noexcept
{
    std::size_t headStart = braceByte;
    while( headStart > bodyStart )
    {
        const char c = src[ headStart - 1 ];
        if( c == ';' || c == '{' || c == '}' )
        {
            break;
        }
        --headStart;
    }
    const std::string_view head  = src.substr( headStart, braceByte - headStart );
    const std::size_t      close = head.rfind( ']' );
    if( close == std::string_view::npos )
    {
        return false;
    }
    const std::size_t open = head.rfind( '[', close );
    if( open == std::string_view::npos )
    {
        return false;
    }
    std::string_view prefix = rw::darkflags::trimView( head.substr( 0, open ) );
    if( prefix.empty() )
    {
        return true; // immediately-invoked `[]{ ... }()`
    }
    if( rw::darkflags::identByte( (unsigned char)prefix.back() ) )
    {
        const std::size_t returnAt = prefix.size() >= 6 ? prefix.size() - 6 : std::string_view::npos;
        return returnAt != std::string_view::npos && prefix.substr( returnAt ) == "return"
            && ( returnAt == 0 || !rw::darkflags::identByte( (unsigned char)prefix[ returnAt - 1 ] ) );
    }
    return prefix.back() != ']' && prefix.back() != ')';   // `flags[i]` / `(array)[i]` are subscripts, not captures
}

// Return the first bare-return line only when this callable also owns a value return. Nested lambda returns
// are outside that contract even though their bytes lie inside the outer function's indexed span.
std::optional<std::uint32_t> inconsistentReturnLine( std::string_view src, std::uint32_t bodyStart, std::uint32_t bodyEnd ) noexcept
{
    bool hasValue = false, hasBare = false;
    std::uint32_t bareLine = 1, currentLine = rw::layout::lineOf( src, bodyStart );
    std::uint32_t braceDepth = 0, lambdaRootDepth = 0;
    bool          sawOuterBrace = false;
    for( std::uint32_t i = bodyStart; i < bodyEnd; )
    {
        const char c = src[i];
        const std::size_t inertEnd = rw::layout::skipInert( src, i );
        if( inertEnd != i )
        {
            const std::size_t scanEnd = std::min<std::size_t>( inertEnd, bodyEnd );
            currentLine += static_cast<std::uint32_t>( std::count( src.begin() + i, src.begin() + scanEnd, '\n' ) );
            i = static_cast<std::uint32_t>( scanEnd );
            continue;
        }
        if( c == '\n' ) { ++currentLine; ++i; continue; }
        if( c == '{' )
        {
            const bool isLambdaRoot = sawOuterBrace && lambdaRootDepth == 0 && opensLambdaBody( src, bodyStart, i );
            ++braceDepth;
            if( isLambdaRoot )
            {
                lambdaRootDepth = braceDepth;
            }
            sawOuterBrace = true;
            ++i;
            continue;
        }
        if( c == '}' )
        {
            if( lambdaRootDepth == braceDepth )
            {
                lambdaRootDepth = 0;
            }
            if( braceDepth > 0 )
            {
                --braceDepth;
            }
            ++i;
            continue;
        }
        if( lambdaRootDepth == 0 && c == 'r' && i + 6 <= bodyEnd
            && src[i+1]=='e' && src[i+2]=='t' && src[i+3]=='u' && src[i+4]=='r' && src[i+5]=='n'
            && ( i + 6 == bodyEnd || !std::isalnum( (unsigned char)src[i+6] ) && src[i+6] != '_' ) )
        {
            std::uint32_t j = i + 6;
            while( j < bodyEnd && ( src[j] == ' ' || src[j] == '\t' ) )
            {
                ++j;
            }
            if( j < bodyEnd && src[j] == ';' )
            {
                hasBare = true;
                bareLine = currentLine;
            }
            else if( j < bodyEnd && src[j] != '}' )
            {
                hasValue = true;
            }
            i = j;
            continue;
        }
        ++i;
    }
    return hasValue && hasBare ? std::optional<std::uint32_t>( bareLine ) : std::nullopt;
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

// ─── --doctor: self-diagnosis (standing item) ─────────────────────────────────────────────────────
// A DIAGNOSTIC verb, not the deterministic map: every check below reports on THIS machine's
// environment (binary identity, PATH resolution, filesystem, git, tree-sitter grammars) — by
// construction its output varies run-to-run and machine-to-machine, so the det-gate
// ("byte-identical run-to-run") does NOT apply to --doctor. Never crashes: every probe degrades to
// ok="0" (or a "can't tell" attr) on failure, never aborts. Single-root only for v1 — refused
// earlier in main() alongside --eval/--test-gate/--quality-delta (each check below is per-repo or
// per-machine, not something a multi-root workspace composes cleanly).
//
// Kept OUT of ingest.cpp/ingest.h/mcp.h/quality.h by task scope: the grammar-probe check (2) compiles
// the same configure-generated immutable query views as ingest, without consulting the source checkout.
extern "C"
{
    const TSLanguage* tree_sitter_cpp( void );
    const TSLanguage* tree_sitter_python( void );
    const TSLanguage* tree_sitter_go( void );
    const TSLanguage* tree_sitter_rust( void );
    const TSLanguage* tree_sitter_typescript( void );
    const TSLanguage* tree_sitter_tsx( void );
    const TSLanguage* tree_sitter_swift( void );
    const TSLanguage* tree_sitter_objc( void );
    const TSLanguage* tree_sitter_javascript( void );
    const TSLanguage* tree_sitter_bash( void );
    const TSLanguage* tree_sitter_java( void );
    const TSLanguage* tree_sitter_ruby( void );
    const TSLanguage* tree_sitter_json( void );
    const TSLanguage* tree_sitter_toml( void );
    const TSLanguage* tree_sitter_yaml( void );
    const TSLanguage* tree_sitter_c_sharp( void );
    const TSLanguage* tree_sitter_c( void );
    const TSLanguage* tree_sitter_cuda( void );
    const TSLanguage* tree_sitter_markdown( void );
}

// This process's own executable path, realpath'd. macOS uses _NSGetExecutablePath and Linux uses
// /proc/self/exe because argv[0] is often just "ripwire" after shell PATH resolution. Other platforms
// fall back to realpath(argv0), then an explicit PATH search. Never crashes: failure degrades to "".
inline std::string selfExecutablePath( const char* argv0 )
{
#if defined( __APPLE__ )
    char          buf[ PATH_MAX ];
    std::uint32_t size = sizeof( buf );
    if( _NSGetExecutablePath( buf, &size ) == 0 )
    {
        char resolved[ PATH_MAX ];
        if( ::realpath( buf, resolved ) )
        {
            return std::string( resolved );
        }
        return std::string( buf );
    }
#elif defined( __linux__ )
    char          buf[ PATH_MAX ];
    const ssize_t byteCount = ::readlink( "/proc/self/exe", buf, sizeof( buf ) - 1 );
    if( byteCount > 0 )
    {
        buf[ byteCount ] = '\0';
        char resolved[ PATH_MAX ];
        if( ::realpath( buf, resolved ) )
        {
            return std::string( resolved );
        }
        return std::string( buf );
    }
#endif
    char resolved[ PATH_MAX ];
    if( argv0 && ::realpath( argv0, resolved ) )
    {
        return std::string( resolved );
    }

    // Last-resort PATH search for platforms without a process-executable API. Returning a bare argv0
    // would recreate the exact Codex Desktop failure this path is used to prevent.
    if( argv0 && *argv0 && !std::strchr( argv0, '/' ) )
    {
        const char* pathEnv = std::getenv( "PATH" );
        std::string_view remaining = pathEnv ? std::string_view( pathEnv ) : std::string_view();
        while( !remaining.empty() )
        {
            const std::size_t split = remaining.find( ':' );
            const std::string_view dir = remaining.substr( 0, split );
            const std::string candidate = std::string( dir.empty() ? "." : dir ) + "/" + argv0;
            if( ::realpath( candidate.c_str(), resolved ) && ::access( resolved, X_OK ) == 0 )
            {
                return std::string( resolved );
            }
            if( split == std::string_view::npos )
            {
                break;
            }
            remaining.remove_prefix( split + 1 );
        }
    }
    return {};
}

// popen a shell command, return its trimmed stdout ("" on any failure — never crashes). One shared copy
// (quality.h popenTrimmed) serves this and the quality git one-liners.
inline std::string doctorPopenTrim( const std::string& cmd )
{
    return rw::quality::popenTrimmed( cmd );
}

// §P11 doctor item: --doctor's failing rows used to print raw mtimes/sizes/counts with no conclusion — the
// one verb whose job is diagnosis made the reader do the diagnosis. Each helper below returns the empty
// string on a PASSING check and a ` hint="..."` attribute fragment on a failing one, naming the derived
// verdict (which side is stale, which grammars failed, what to fix) instead of leaving raw facts to
// interpret. Pulled out of runDoctor (rather than inlined per check) so five small conditionals don't add
// their nesting-weighted cognitive-complexity/verbosity cost to a function that dispatches six checks already.

inline std::string doctorBinaryPathVerdictAttr( bool copied, const std::string& selfPath, const std::string& whichPath,
                                                const struct stat& selfSt, const struct stat& whichSt, std::vector<char>& esc )
{
    if( copied )
    {
        return " copied=\"1\"";
    }
    const bool        selfIsOlder = selfSt.st_mtime < whichSt.st_mtime;
    const std::string olderPath   = selfIsOlder ? selfPath : whichPath;
    const std::string newerPath   = selfIsOlder ? whichPath : selfPath;
    return " hint=\"" + std::string( rw::escapeXml( std::string_view(
                  "STALE: " + olderPath + " is older than " + newerPath
                + " — rebuild/reinstall so PATH points at the newer one, or invoke "
                + newerPath + " directly" ), esc ) ) + "\"";
}

inline std::string doctorGrammarsHint( int loaded, int expected, const std::string& failedLabels, std::vector<char>& esc )
{
    if( loaded == expected )
    {
        return "";
    }
    return " hint=\"" + std::string( rw::escapeXml( std::string_view(
                  "failed to compile: " + failedLabels
                + " — a build/embedded-resource mismatch (rebuild with cmake --build build -j; "
                  "if it persists the embedded tags.scm for that language is stale)" ), esc ) ) + "\"";
}

// --doctor check 2's probe, in full: does each compiled-in grammar's tags.scm actually compile
// (ts_query_new — the same operation ingest()'s prewarm performs)? Pulled out of runDoctor (not just the
// hint) so the for-loop + its two ifs (pre-existing) and the label-collecting else (new, for the hint
// above) all land on a new symbol instead of runDoctor's own complexity.
struct DoctorGrammarProbe { int loaded = 0; int expected = 0; std::string failedLabels; };

// The probe for a grammar that ships NO tags.scm (markdown — ingest walks its tree directly): the honest
// health check is the pairing ingest actually uses, set_language + a real parse of a one-line doc.
inline bool doctorParseProbe( const TSLanguage* ( *grammar )( void ) )
{
    bool      ok = false;
    TSParser* p  = ts_parser_new();
    if( p != nullptr )
    {
        if( ts_parser_set_language( p, grammar() ) )
        {
            static constexpr std::string_view kProbeDoc = "# t\n";
            TSTree* t = ts_parser_parse_string( p, nullptr, kProbeDoc.data(), std::uint32_t( kProbeDoc.size() ) );
            if( t != nullptr )
            {
                ok = !ts_node_is_null( ts_tree_root_node( t ) );
                ts_tree_delete( t );
            }
        }
        ts_parser_delete( p );
    }
    return ok;
}

inline DoctorGrammarProbe doctorProbeGrammars()
{
    struct GEntry { const char* querySub; const TSLanguage* (*grammar)( void ); const char* label; };
    static const GEntry kTable[] = {
        { "cpp",        &tree_sitter_cpp,        "cpp"        },
        { "python",     &tree_sitter_python,     "python"     },
        { "go",         &tree_sitter_go,         "go"         },
        { "rust",       &tree_sitter_rust,       "rust"       },
        { "typescript", &tree_sitter_typescript, "typescript" },
        { "typescript", &tree_sitter_tsx,        "tsx"        },
        { "swift",      &tree_sitter_swift,      "swift"      },
        { "objc",       &tree_sitter_objc,       "objc"       },
        { "javascript", &tree_sitter_javascript, "javascript" },
        { "bash",       &tree_sitter_bash,       "bash"       },
        { "java",       &tree_sitter_java,       "java"       },
        { "ruby",       &tree_sitter_ruby,       "ruby"       },
        { "json",       &tree_sitter_json,       "json"       },
        // The four below were MISSING while the binary linked them, so --doctor reported "13 of 13
        // grammars ok" on a build carrying 17 probeable entries: a csharp/c/cuda/toml query that failed
        // to compile was invisible to the one check whose whole job is to say so. Found by the TOML
        // round's sibling sweep (docs/METHODOLOGY.md §3). `cuda` deliberately shares the "cpp" querySub
        // — it is a generated superset of tree-sitter-cpp and rides cpp's tags.scm, exactly as `tsx`
        // shares "typescript" above — so what is probed for it is cpp's query against the CUDA grammar,
        // which is precisely the pairing ingest uses.
        { "toml",       &tree_sitter_toml,       "toml"       },
        { "yaml",       &tree_sitter_yaml,       "yaml"       },
        { "csharp",     &tree_sitter_c_sharp,    "csharp"     },
        { "c",          &tree_sitter_c,          "c"          },
        { "cpp",        &tree_sitter_cuda,       "cuda"       },
        // markdown carries NO tags.scm — ingest extracts sections by a custom tree walk, so the honest
        // probe is the pairing ingest actually uses: set_language + a real parse, not a query compile.
        { nullptr,      &tree_sitter_markdown,   "markdown"   },
    };
    DoctorGrammarProbe out;
    out.expected = int( sizeof( kTable ) / sizeof( kTable[0] ) );
    for( const GEntry& g : kTable )
    {
        bool ok = false;
        if( g.querySub == nullptr )
        {
            ok = doctorParseProbe( g.grammar );
        }
        else
        {
            const std::string_view scm = rw::embedded_queries::queryFor( g.querySub );
            if( !scm.empty() )
            {
                std::uint32_t errOff  = 0;
                TSQueryError  errType = TSQueryErrorNone;
                TSQuery*      q       = ts_query_new( g.grammar(), scm.data(), static_cast<std::uint32_t>( scm.size() ), &errOff, &errType );
                if( q ) { ok = true; ts_query_delete( q ); }
            }
        }
        if( ok )
        {
            ++out.loaded;
        }
        else
        {
            if( !out.failedLabels.empty() )
            {
                out.failedLabels += ",";
            }
            out.failedLabels += g.label;
        }
    }
    return out;
}

struct DoctorCacheStats { std::size_t blobCount = 0; std::uintmax_t totalBytes = 0; bool truncated = false; };

// Count legacy flat blobs plus the current one-level, two-hex shard layout. The 4K cap matches cache
// hygiene's retained-blob cap; truncated= makes an I/O error or over-cap result an honest floor.
inline DoctorCacheStats doctorCacheStats( const std::string& dir )
{
    namespace fs = std::filesystem;
    DoctorCacheStats out;
    const auto account = [ & ]( const fs::directory_entry& entry )
    {
        const std::string name = entry.path().filename().string();
        if( name.rfind( "ripwire-", 0 ) != 0 ) { return; }
        std::error_code ec;
        if( !entry.is_regular_file( ec ) ) { if( ec ) { out.truncated = true; } return; }
        if( out.blobCount >= rw::quality::kMaxCacheBlobCount ) { out.truncated = true; return; }
        ++out.blobCount;
        const auto byteSize = entry.file_size( ec );
        if( ec ) { out.truncated = true; return; }
        out.totalBytes += byteSize;
    };
    const auto scanShard = [ & ]( const fs::path& shard )
    {
        std::error_code ec;
        fs::directory_iterator it( shard, ec ), end;
        if( ec ) { out.truncated = true; return; }
        while( it != end && !out.truncated )
        {
            account( *it );
            it.increment( ec );
            if( ec ) { out.truncated = true; }
        }
    };
    const auto isShardName = []( const std::string& name )
    {
        return name.size() == 2 && std::isxdigit( static_cast<unsigned char>( name[0] ) )
             && std::isxdigit( static_cast<unsigned char>( name[1] ) );
    };

    std::error_code ec;
    fs::directory_iterator it( dir, ec ), end;
    if( ec ) { out.truncated = true; return out; }
    while( it != end && !out.truncated )
    {
        const std::string name = it->path().filename().string();
        if( name.rfind( "ripwire-", 0 ) == 0 )
        {
            account( *it );
        }
        else if( isShardName( name ) )
        {
            std::error_code sec;
            if( it->is_directory( sec ) ) { scanShard( it->path() ); }
            else if( sec ) { out.truncated = true; }
        }
        it.increment( ec );
        if( ec ) { out.truncated = true; }
    }
    return out;
}

inline std::string doctorCacheDirHint( bool writable, const std::string& dir, std::vector<char>& esc )
{
    if( writable )
    {
        return "";
    }
    return " hint=\"" + std::string( rw::escapeXml( std::string_view(
                  "cannot write to " + dir + " (from TMPDIR/XDG_CACHE_HOME/tmp fallback) — fix its "
                  "permissions, or point TMPDIR/XDG_CACHE_HOME at a directory you can write to" ), esc ) ) + "\"";
}

inline std::string doctorGitHint( bool gitAvailable )
{
    if( gitAvailable )
    {
        return "";
    }
    return " hint=\"git not found on PATH — install it (required for --hotspots/--cochange/--owners/"
           "--merge-scout/--quality-delta and every other churn-mining verb) or check PATH\"";
}

inline std::string doctorTrackedBinariesHint( bool ok, std::size_t staleCount )
{
    if( ok )
    {
        return "";
    }
    return " hint=\"" + std::to_string( staleCount ) + " stale tracked binar" + ( staleCount == 1 ? "y" : "ies" )
         + " — the source (src0=, src1=, …) was committed AFTER its binary (p0=, p1=, …); "
           "rebuild the binary from that newer source and recommit it\"";
}

int runDoctor( const rw::Config& cfg, const char* argv0 )
{
    using namespace rw;

    int                checks = 0;
    int                okCount = 0;
    std::string        rows;
    std::vector<char>  esc;

    const auto row = [ & ]( const char* name, bool ok, const std::string& attrs )
    {
        ++checks;
        if( ok )
        {
            ++okCount;
        }
        rows += "<c n=\"";  rows += name;  rows += "\" ok=\"";  rows += ( ok ? "1" : "0" );  rows += "\"";
        if( !attrs.empty() ) { rows += " "; rows += attrs; }
        rows += "/>";
    };

    // ---- check 1: binary-vs-PATH staleness (no --version mechanism exists — checked; compare
    // realpath'd identity via (device,inode), then mtime/size, of argv[0]'s resolved binary vs
    // `which ripwire`'s) ----
    {
        const std::string selfPath  = selfExecutablePath( argv0 );
        const std::string whichPath = doctorPopenTrim( "which ripwire 2>/dev/null" );
        struct stat        selfSt {};
        struct stat         whichSt {};
        const bool haveSelf  = !selfPath.empty()  && ::stat( selfPath.c_str(),  &selfSt )  == 0;
        const bool haveWhich = !whichPath.empty() && ::stat( whichPath.c_str(), &whichSt ) == 0;

        bool        ok    = true;
        std::string attrs = "self=\"" + std::string( escapeXml( selfPath, esc ) ) + "\"";
        attrs += " which=\"" + std::string( escapeXml( whichPath, esc ) ) + "\"";

        if( !haveWhich )
        {
            attrs += " on_path=\"0\"";   // ripwire not found on PATH at all — not itself a failure (may run via absolute path)
        }
        else if( haveSelf )
        {
            const bool sameFile = ( selfSt.st_dev == whichSt.st_dev && selfSt.st_ino == whichSt.st_ino );
            attrs += " on_path=\"1\" same_file=\"" + std::string( sameFile ? "1" : "0" ) + "\"";
            if( !sameFile )
            {
                // install.sh COPIES the binary (dev/ino always differ from the source build) rather than
                // symlinking it, so a raw same_file="0" false-positives on every install that worked fine.
                // Cheap content-equality fallback (degrade, don't crash): equal mtime AND equal size is the
                // sanctioned proxy for "copied but identical" — a genuine stale shadow almost always differs
                // in at least one. Only a real mismatch still flags ok=false.
                const bool copied = ( selfSt.st_mtime == whichSt.st_mtime && selfSt.st_size == whichSt.st_size );
                ok = copied;   // this exact failure bit the LocBench round — stale PATH binary shadows a freshly built one
                attrs += " self_mtime=\""  + std::to_string( (long long)selfSt.st_mtime )  + "\"";
                attrs += " self_size=\""   + std::to_string( (long long)selfSt.st_size )    + "\"";
                attrs += " which_mtime=\"" + std::to_string( (long long)whichSt.st_mtime ) + "\"";
                attrs += " which_size=\""  + std::to_string( (long long)whichSt.st_size )   + "\"";
                // §P11 doctor item: a raw ok="0" with four raw timestamps made the reader do the
                // subtraction themselves — name which of the two IS the stale one (older mtime) and the
                // fix, so the LocBench-round failure this check exists for reads as a VERDICT.
                attrs += doctorBinaryPathVerdictAttr( copied, selfPath, whichPath, selfSt, whichSt, esc );
            }
        }
        else
        {
            attrs += " on_path=\"1\"";   // could stat the PATH copy but not our own argv[0]-derived path — degrade, don't fail
        }
        row( "binary-path", ok, attrs );
    }

    // ---- check 2: grammar availability — probe each compiled-in grammar's tags.scm actually
    // compiles (ts_query_new), the same operation ingest()'s prewarm performs; count vs expected ----
    // gp OUTLIVES this block on purpose: check 5 reports the same grammar count and used to carry it as a
    // hardcoded "13" with a comment promising it matched this table. It did not — the table reached 17
    // while the literal stayed 13. Reading the one probe twice is what makes that promise structural.
    const DoctorGrammarProbe gp = doctorProbeGrammars();
    {
        std::string grammarAttrs = "loaded=\"" + std::to_string( gp.loaded ) + "\" expected=\"" + std::to_string( gp.expected ) + "\"";
        grammarAttrs += doctorGrammarsHint( gp.loaded, gp.expected, gp.failedLabels, esc );
        row( "grammars", gp.loaded == gp.expected, grammarAttrs );
    }

    // ---- check 3: cache-dir health — resolves, writable (create+delete a probe file), report
    // existing ripwire-* blob count + total bytes (eviction sanity: flag >50 blobs, informational) ----
    {
        const std::string dir   = cacheDirLadder();
        const std::string probe = dir + "/.ripwire-doctor-probe-" + std::to_string( ::getpid() );
        bool writable = false;
        if( std::FILE* f = std::fopen( probe.c_str(), "wb" ) )
        {
            std::fputs( "doctor", f );
            std::fclose( f );
            writable = ( ::unlink( probe.c_str() ) == 0 );
        }

        const DoctorCacheStats stats = doctorCacheStats( dir );
        std::string attrs = "dir=\"" + std::string( escapeXml( dir, esc ) ) + "\"";
        attrs += " blobs=\"" + std::to_string( stats.blobCount ) + "\"";
        attrs += " bytes=\"" + std::to_string( stats.totalBytes ) + "\"";
        attrs += " many=\"" + std::string( stats.blobCount > 50 ? "1" : "0" ) + "\"";   // eviction sanity flag, informational (never fails the check)
        attrs += " truncated=\"" + std::string( stats.truncated ? "1" : "0" ) + "\"";
        attrs += doctorCacheDirHint( writable, dir, esc );
        row( "cache-dir", writable, attrs );
    }

    // ---- check 4: git reachability — `git` on PATH + the target dir's repo status; degrades
    // gracefully on non-repos (ok=1, repo="0" — doctor diagnoses, non-repo isn't sickness) ----
    {
        const std::string gitVer       = doctorPopenTrim( "git --version 2>/dev/null" );
        const bool        gitAvailable = !gitVer.empty();
        std::string        attrs        = "git=\"" + std::string( gitAvailable ? "1" : "0" ) + "\"";
        if( gitAvailable )
        {
            const std::string root   = std::string( cfg.rootPath );
            const std::string isRepo = doctorPopenTrim( "git -c core.quotepath=false -C " + shSingleQuote( root )
                                                          + " rev-parse --is-inside-work-tree 2>/dev/null" );
            const bool repo = ( isRepo == "true" );
            attrs += " repo=\"" + std::string( repo ? "1" : "0" ) + "\"";
            if( repo )
            {
                const bool history = gitRepoHasHistory( root );
                attrs += " history=\"" + std::string( history ? "1" : "0" ) + "\"";
                if( history )
                {
                    // §A10.4: 9-hex-char width, matching the at= convention (gitstamp.h) every other
                    // repo-reading verb uses — this was the tool's one remaining 40-char head=.
                    attrs += " head=\"" + std::string( escapeXml( gitHeadSha( root ).substr( 0, 9 ), esc ) ) + "\"";
                }
            }
        }
        attrs += doctorGitHint( gitAvailable );
        row( "git", gitAvailable, attrs );
    }

    // ---- check 5: tree-sitter version + language count (informational, always ok=1) ----
    {
        const std::uint32_t cppAbi = ts_language_abi_version( tree_sitter_cpp() );
        std::string attrs = "core_abi=\"" + std::to_string( TREE_SITTER_LANGUAGE_VERSION ) + "\"";
        attrs += " cpp_grammar_abi=\"" + std::to_string( cppAbi ) + "\"";
        attrs += " languages=\"" + std::to_string( gp.expected ) + "\"";   // distinct compiled-in grammar entries — DERIVED from check 2's kTable, not restated
        row( "tree-sitter", true, attrs );
    }

    // ---- check 6: tracked-binary staleness — a committed binary whose last-touching
    // commit is a STRICT ancestor of a same-directory/same-stem source's last-touching commit: someone edited
    // the source and never recommitted the binary. Git-commit-order only (never mtime — see binstale.h's
    // header for why); "dependent source" is a naming heuristic, not a build-graph fact — see the same header
    // for exactly what this can and cannot see. ok="0" (and doctor's overall exit 1) iff any pair fires; a
    // non-git root or a >kMaxTrackedFiles repo degrades to ok="1" scanned="0" rather than guess.
    {
        const binstale::BinaryStaleResult bs = binstale::computeBinaryStaleness( std::string( cfg.rootPath ) );
        std::string attrs = "tracked=\"" + std::to_string( bs.trackedCount ) + "\"";
        attrs += " binaries=\"" + std::to_string( bs.binariesFound ) + "\"";
        attrs += " non_git=\"" + std::string( bs.nonGitRoot ? "1" : "0" ) + "\"";
        attrs += " truncated=\"" + std::string( bs.truncated ? "1" : "0" ) + "\"";
        attrs += " stale=\"" + std::to_string( bs.stale.size() ) + "\"";
        // cap the inline listing (doctor is a one-screen diagnostic, not a report) — every dropped pair is
        // still counted in stale="N" above, so a capped display never under-reports the finding.
        constexpr std::size_t kShown = 8;
        for( std::size_t i = 0; i < bs.stale.size() && i < kShown; ++i )
        {
            const binstale::StaleBinary& s = bs.stale[i];
            attrs += " p" + std::to_string( i ) + "=\"" + std::string( escapeXml( s.path, esc ) ) + "\"";
            attrs += " src" + std::to_string( i ) + "=\"" + std::string( escapeXml( s.srcPath, esc ) ) + "\"";
        }
        if( bs.stale.size() > kShown )
        {
            attrs += " more=\"" + std::to_string( bs.stale.size() - kShown ) + "\"";
        }
        const bool ok = bs.nonGitRoot || bs.truncated || bs.stale.empty();
        // §P11 doctor item: name the derived verdict, not just p0=/src0='s raw pair — the fix is always the
        // same shape (rebuild + recommit), so state it once instead of leaving the reader to infer it.
        attrs += doctorTrackedBinariesHint( ok, bs.stale.size() );
        row( "tracked-binaries", ok, attrs );
    }

    // r26-stamp Task A: anchor this diagnostic to the commit (+dirty state) it ran against — cheap here
    // (check 4 above already paid for a git rev-parse/status probe on this same root; two more subprocess
    // calls are noise next to that), and omitted entirely on a non-git root rather than printed as a placeholder.
    const std::string doctorAt = gitstamp::atAttr( std::string( cfg.rootPath ) );
    // §P8 collision: this root spelled its COUNT `ok=` while every <c> child directly beneath it spells its
    // BOOL `ok=` — two meanings on adjacent lines of one document. Renamed per the index-vs-count rule;
    // `passed=` pairs with the `checks=` denominator beside it. The count had ZERO parsers (doctorcheck.sh's
    // 8 assertions all read the CHILD bool), so the half with readers keeps its name.
    std::string out = "<doctor checks=\"" + std::to_string( checks ) + "\" passed=\"" + std::to_string( okCount ) + "\"" + doctorAt + ">";
    out += rows;
    out += "</doctor>";
    std::fputs( out.c_str(), stdout );
    std::fputc( '\n', stdout );
    return ( okCount == checks ) ? 0 : 1;
}

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

// Symbol-level lint checks (S6-A), lifted verbatim out of the --lint block so runLint stays under the
// complexity bar. Walks each C-family Function/Method body for large-function / deep-nesting /
// inconsistent-return; returns the findings the caller merges into the combined lint set.
std::vector<rw::AstMatch> lintSymbolLevelChecks( const rw::IngestResult& ing, const std::vector<std::string>* preRead )
{
    using namespace rw;
            // Build per-file byte map (read each file once).
            // preRead: bytes the caller's corpus walk already holds (astQueryGrouped's keptBytesOut). An
            // empty or missing slot falls through to the read below and yields the same bytes, so the two
            // paths cannot disagree; the size guard keeps a vector built for another corpus in bounds.
            std::vector<std::string> fileBytes( ing.files.size() );
            HashMap<std::uint32_t, bool> fileRead;
            const auto getBytes = [ & ]( std::uint32_t fid ) -> const std::string&
            {
                if( preRead != nullptr && fid < preRead->size() && !( *preRead )[fid].empty() )
                {
                    return ( *preRead )[fid];
                }
                if( fileRead.find( fid ) == fileRead.end() )
                {
                    FILE* fp = std::fopen( diskPath( ing, fid ).c_str(), "rb" );
                    if( fp )
                    {
                        std::fseek( fp, 0, SEEK_END );
                        const long sz = std::ftell( fp );
                        std::fseek( fp, 0, SEEK_SET );
                        if( sz > 0 ) { fileBytes[fid].resize( std::size_t( sz ) ); std::fread( fileBytes[fid].data(), 1, std::size_t( sz ), fp ); }
                        std::fclose( fp );
                    }
                    fileRead[fid] = true;
                }
                return fileBytes[fid];
            };

            // Only check C/C++ functions (SymKind::Function or Method) — the nesting/line checks are
            // most meaningful and least noisy for C-family code. Python/Go/Rust have different idioms.
            // Extension guard: check if the file is a C/C++ source.
            const auto isCFamily = [ & ]( std::uint32_t fid ) -> bool
            {
                const std::string& p = ing.files[fid];
                const std::size_t  d = p.rfind( '.' );
                if( d == std::string::npos )
                {
                    return false;
                }
                const std::string_view ext( p.data() + d );
                return ext == ".c" || ext == ".cpp" || ext == ".cc" || ext == ".cxx"
                    || ext == ".h" || ext == ".hpp" || ext == ".hh" || ext == ".hxx";
            };

            std::vector<AstMatch> symHits;
            for( const Symbol& s : ing.symbols )
            {
                if( s.kind != SymKind::Function && s.kind != SymKind::Method )
                {
                    continue;
                }
                if( s.endByte <= s.sigEndByte )
                {
                    continue; // no body (prototype / abstract)
                }
                if( !isCFamily( s.fileId ) )
                {
                    continue;
                }

                const std::string& src = getBytes( s.fileId );
                if( src.empty() )
                {
                    continue;
                }
                const std::uint32_t bodyA = std::min( s.sigEndByte, std::uint32_t( src.size() ) );
                const std::uint32_t bodyB = std::min( s.endByte,    std::uint32_t( src.size() ) );
                if( bodyB <= bodyA )
                {
                    continue;
                }

                // large-function: count newlines in body span
                {
                    std::uint32_t lines = 0;
                    for( std::uint32_t i = bodyA; i < bodyB; ++i )
                    {
                        if( src[i] == '\n' )
                        {
                            ++lines;
                        }
                    }
                    if( lines > 80 )
                    {
                        AstMatch hit;
                        hit.fileId    = s.fileId;
                        hit.startByte = s.sigStartByte;
                        hit.endByte   = s.endByte;
                        hit.line      = s.line;
                        hit.tag       = "large-function";
                        hit.text      = s.name + " (" + std::to_string( lines ) + " lines)";
                        symHits.push_back( std::move( hit ) );
                    }
                }

                // deep-nesting: track curly-brace depth inside the body, ignoring string/char literals
                // and single-line comments. Report when depth exceeds 4 (the outer body `{` counts as 1).
                {
                    std::uint32_t maxDepth = 0, depth = 0;
                    std::uint32_t deepLine = s.line;
                    std::uint32_t curLine  = s.line;
                    bool          inLineComment = false, inBlockComment = false;
                    char          inString = 0;   // '\0' = not in a string, otherwise the quote char
                    for( std::uint32_t i = bodyA; i < bodyB; ++i )
                    {
                        const char c = src[i];
                        if( c == '\n' ) { ++curLine; inLineComment = false; continue; }
                        if( inLineComment )
                        {
                            continue;
                        }
                        if( inBlockComment )
                        {
                            if( c == '*' && i + 1 < bodyB && src[i + 1] == '/' ) { inBlockComment = false; ++i; }
                            continue;
                        }
                        if( inString != 0 )
                        {
                            if( c == '\\' ) { ++i; continue; }
                            if( c == inString )
                            {
                                inString = 0;
                            }
                            continue;
                        }
                        if( c == '/' && i + 1 < bodyB && src[i + 1] == '/' ) { inLineComment = true; continue; }
                        if( c == '/' && i + 1 < bodyB && src[i + 1] == '*' ) { inBlockComment = true; ++i; continue; }
                        if( c == '"' || c == '\'' ) { inString = c; continue; }
                        if( c == '{' )
                        {
                            ++depth;
                            if( depth > maxDepth ) { maxDepth = depth; deepLine = curLine; }
                        }
                        else if( c == '}' && depth > 0 )
                        {
                            --depth;
                        }
                    }
                    // depth=1 is the outer function body `{` — threshold is >4 meaning depth 5+
                    if( maxDepth > 4 )
                    {
                        AstMatch hit;
                        hit.fileId    = s.fileId;
                        hit.startByte = s.sigStartByte;
                        hit.endByte   = s.endByte;
                        hit.line      = deepLine;
                        hit.tag       = "deep-nesting";
                        hit.text      = s.name + " (max depth " + std::to_string( maxDepth ) + ")";
                        symHits.push_back( std::move( hit ) );
                    }
                }

                // inconsistent-return: the scanner owns the lexical callable-boundary rules; this loop
                // only translates its optional bare-return line into the shared lint finding shape.
                {
                    const std::optional<std::uint32_t> bareReturnLine = inconsistentReturnLine( src, bodyA, bodyB );
                    if( bareReturnLine )
                    {
                        AstMatch hit;
                        hit.fileId    = s.fileId;
                        hit.startByte = s.sigStartByte;
                        hit.endByte   = s.endByte;
                        hit.line      = *bareReturnLine;
                        hit.tag       = "inconsistent-return";
                        hit.text      = s.name + " (bare return in a value-returning function)";
                        symHits.push_back( std::move( hit ) );
                    }
                }
            }   // for each symbol

            // Sort by (file, line) for determinism, then merge into ms.
            std::sort( symHits.begin(), symHits.end(), [ & ]( const AstMatch& x, const AstMatch& y )
                       {
                if( ing.files[x.fileId] != ing.files[y.fileId] ) { return ing.files[x.fileId] < ing.files[y.fileId];
}
                if( x.line != y.line ) { return x.line < y.line;
}
                return x.tag < y.tag; } );
            return symHits;
}

// Unified lint finding shape (built-in tags and user rule ids emit identically). sev is empty for
// built-ins (facts, not severities); user findings carry their declared sev=. Lives at file scope
// (not local to runLint) so dedupeLintFindings below can share it.
struct LintOut { std::uint32_t fileId, startByte, line; std::string rule, sev, text; };

// One <rule> tally row. The built-in and user-rule tally loops in runLint differ ONLY in whether sev=
// is present (nullptr ⇒ omitted, a built-in row) — everything else (capped=, and L7's applicable=) is
// identical branching duplicated twice; this is the one copy. Callers pass already-escaped strings
// (name/sev safety differs: built-in names are compile-time-known, user ids/severities are ex()'d at
// the call site) so this stays a pure formatter with no XML-escaping policy of its own.
//
// wave-4 item 12 (the recorded liability from the six-smalls round, docs/EVALS.md): the DEFAULT PAYLOAD
// byte cap (kLintDefaultPayloadBytes above) keeps a sorted PREFIX of `outs`, so a rule whose findings all
// sort past that prefix loses every <f> locator row while its own count= — computed over the full,
// uncapped `outs` — stays a truthful total. Before this, that rule's tally row was indistinguishable from
// one with real locator rows sitting just below the fold; shown_rows= closes the gap by naming exactly how
// many of THIS rule's rows survived the row/byte window the caller actually gets, unconditionally (never
// omitted, so a fully-capped-away rule reads shown_rows="0" instead of silently locator-less) and always
// <= count (== count on an unpaged, uncapped run, or under an explicit --limit/--offset).
//
// NOUN-PREFIXED, not the bare shown=/capped= pair (src/pageview.h, THE TRUNCATION VOCABULARY rule 1's
// exception): this element's bare `capped=` already carries a DIFFERENT fact — this rule's own raw-capture
// stream hit ITS OWN per-rule match budget, so count= itself is a floor — and rule 3 requires the bit
// paired with shown= to describe the SAME truncation event. Conflating the two under one name would make
// capped="1" mean "match-budget floor" on one row and "row-window cut" on the next, indistinguishably;
// shown_rows=/rows_capped= is its own pair (truncvocabcheck.sh rules 1+3) so the two facts stay legible
// side by side rather than colliding under one bit.
void printLintRuleTallyRow( const std::string& name, const std::string* sev, std::uint32_t count, std::uint32_t shown, bool capped, bool applicable )
{
    const char* sevPart        = "";
    std::string sevBuf;
    if( sev != nullptr )
    {
        sevBuf   = " sev=\"" + *sev + "\"";
        sevPart  = sevBuf.c_str();
    }
    std::printf( "<rule name=\"%s\"%s count=\"%u\" shown_rows=\"%u\" rows_capped=\"%u\"%s%s/>", name.c_str(), sevPart, count, shown,
                 shown < count ? 1u : 0u, capped ? " capped=\"1\"" : "", applicable ? "" : " applicable=\"0\"" );
}

// wave-4 item 12: the (count, shown-inside-`lintPage`) pair for ONE rule's rows in the already-sorted
// `outs`. Lifted out of runLint's two per-rule tally loops (built-in and user) for the same reason
// mergeAtomsPack/dedupeLintFindings/lintSymbolLevelChecks above it were — runLint was already the file's
// largest dispatcher, and this is a second full-`outs` scan per rule either way, not new algorithmic
// weight, just a home outside the function whose size this whole file already works to keep down.
// `wantSevEmpty` is the one distinction between the built-in loop (bare rows, sev.empty()) and the user
// loop (every user finding carries sev=); passing it explicitly keeps this one function instead of two.
struct RuleTally { std::uint32_t count = 0, shown = 0; };
RuleTally tallyLintRule( const std::vector<LintOut>& outs, const std::string& ruleId, bool wantSevEmpty, rw::PageWindow lintPage )
{
    RuleTally t;
    for( std::size_t oi = 0; oi < outs.size(); ++oi )
    {
        const LintOut& m = outs[oi];
        if( m.rule == ruleId && m.sev.empty() == wantSevEmpty )
        {
            ++t.count;
            if( oi >= lintPage.begin && oi < lintPage.end )
            {
                ++t.shown;
            }
        }
    }
    return t;
}

// §P0.2: rules whose RAW capture stream spent its whole per-rule budget — their count= is a floor, not
// a total, and must say so (the contract --match already honours with hits_capped="1"). Keyed by
// (name, namespace): a user rule may share a built-in rule's name, and a cap must never leak across
// that boundary — a bare-name lookup painted `capped="1"` onto rules that were never capped (including
// symbol-level built-ins that have no query budget at all). File scope, like LintOut and for the same
// reason: mergeAtomsPack below fills it too.
struct RuleCap { std::string rule; bool isUserRule; };

// --with-profile (the SYZYGY advice-mode pairing: static shape × PMU weight — Hundt et al., CGO 2006,
// already cited in fieldaffinity.h): one parsed row of the #PROF_TSV block a RIPWIRE_PROFILE build's
// report emits (profileScope.h::print_tsv — scope, file, line, then whatever data columns that run's
// counter tier armed). File scope like LintOut, for the same reason: runLint consumes it.
struct ProfScopeRow
{
    std::string file;      // basename, exactly as PROFILE_SCOPE's Site::file records it
    int         line = 0;  // the PROFILE_SCOPE site line
    std::string scope;     // description text, or the trimmed function name
    std::vector<std::pair<std::string, std::string>> cols;   // header name → raw cell, calls onward
};

// Parse FILE's #PROF_TSV block. nullopt = unreadable file, no sentinel pair, or a header that is not
// the block's own (scope/file/line first) — the caller REFUSES loudly rather than joining nothing
// silently, because "annotated zero findings" and "read the wrong file" must never look alike.
std::optional<std::vector<ProfScopeRow>> parseProfTsv( const std::string& path )
{
    std::FILE* fp = std::fopen( path.c_str(), "rb" );
    if( fp == nullptr )
    {
        return std::nullopt;
    }
    std::string all;
    char        buf[ 4096 ];
    std::size_t got = 0;
    while( ( got = std::fread( buf, 1, sizeof( buf ), fp ) ) > 0 )
    {
        all.append( buf, got );
    }
    std::fclose( fp );

    const auto splitTabs = []( std::string_view lineText )
    {
        std::vector<std::string> cells;
        std::size_t              from = 0;
        for( ;; )
        {
            const std::size_t tab = lineText.find( '\t', from );
            if( tab == std::string_view::npos )
            {
                cells.emplace_back( lineText.substr( from ) );
                return cells;
            }
            cells.emplace_back( lineText.substr( from, tab - from ) );
            from = tab + 1;
        }
    };

    std::vector<ProfScopeRow> rows;
    std::vector<std::string>      header;
    bool inBlock = false, sawEnd = false;
    std::size_t from = 0;
    while( from <= all.size() )
    {
        const std::size_t    nl       = all.find( '\n', from );
        const std::string_view lineText( all.data() + from, ( nl == std::string::npos ? all.size() : nl ) - from );
        from = ( nl == std::string::npos ) ? all.size() + 1 : nl + 1;
        if( !inBlock )
        {
            if( lineText.rfind( "#PROF_TSV_BEGIN", 0 ) == 0 )
            {
                inBlock = true;
            }
            continue;
        }
        if( lineText.rfind( "#PROF_TSV_END", 0 ) == 0 )
        {
            sawEnd = true;
            break;
        }
        if( header.empty() )
        {
            header = splitTabs( lineText );
            if( header.size() < 4 || header[0] != "scope" || header[1] != "file" || header[2] != "line" )
            {
                return std::nullopt;   // not print_tsv's own header — wrong file, refuse
            }
            continue;
        }
        const std::vector<std::string> cells = splitTabs( lineText );
        if( cells.size() < 4 )
        {
            continue;   // a short row carries nothing joinable; skip it rather than invent columns
        }
        ProfScopeRow row;
        row.scope = cells[0];
        row.file  = cells[1];
        row.line  = std::atoi( cells[2].c_str() );
        for( std::size_t cellIndex = 3; cellIndex < cells.size() && cellIndex < header.size(); ++cellIndex )
        {
            row.cols.emplace_back( header[cellIndex], cells[cellIndex] );
        }
        rows.push_back( std::move( row ) );
    }
    if( !inBlock || !sawEnd )
    {
        return std::nullopt;
    }
    return rows;
}


// The --with-profile join itself: annotate each finding with the NEAREST-PRECEDING PROFILE_SCOPE site
// inside its own enclosing symbol (same basename, symbol.line <= site.line <= finding.line — scopes
// lead the region they measure, so a later site never annotates an earlier finding). The measured
// columns are whatever counter tier the profiled run armed; an absent column was NOT measured, never
// zero. Returns the per-finding attribute strings (index-aligned with `outs`) plus the root
// heat_joined= attribute — or nullopt AFTER printing the refusal (unreadable FILE, or no #PROF_TSV
// block), so the caller exits 1: "annotated zero findings" and "read the wrong file" never look alike.
template <class EnclosingFn>
std::optional<std::pair<std::vector<std::string>, std::string>>
buildHeatAnnotations( std::string_view withProfile, const rw::IngestResult& ing, const std::vector<LintOut>& outs, EnclosingFn&& enclosing )
{
    using namespace rw;
    const auto profRows = parseProfTsv( std::string( withProfile ) );
    if( !profRows )
    {
        std::fprintf( stderr, "ripwire: --with-profile=%s: no readable #PROF_TSV block there — generate one with a "
                              "RIPWIRE_PROFILE build (ripwire <dir> 2>report.txt), or pass that report verbatim\n",
                      std::string( withProfile ).c_str() );
        return std::nullopt;
    }
    std::vector<char> esc;
    const auto        ex     = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    const auto        baseOf = []( std::string_view p ) -> std::string_view
    {
        const std::size_t slash = p.find_last_of( '/' );
        return slash == std::string_view::npos ? p : p.substr( slash + 1 );
    };
    std::vector<std::string> heatByFinding( outs.size() );
    std::size_t              joined = 0;
    for( std::size_t findingIndex = 0; findingIndex < outs.size(); ++findingIndex )
    {
        const LintOut& m = outs[ findingIndex ];
        const Symbol*  e = enclosing( m.fileId, m.startByte );
        if( e == nullptr )
        {
            continue;
        }
        const std::string_view fileBase = baseOf( ing.files[ m.fileId ] );
        const ProfScopeRow*    best     = nullptr;
        for( const ProfScopeRow& row : *profRows )
        {
            if( row.line <= 0 || fileBase != row.file )
            {
                continue;
            }
            if( std::uint32_t( row.line ) < e->line || std::uint32_t( row.line ) > m.line )
            {
                continue;
            }
            if( best == nullptr || row.line > best->line )
            {
                best = &row;
            }
        }
        if( best == nullptr )
        {
            continue;
        }
        ++joined;
        std::string attrs = " heat_scope=\"" + ex( best->scope ) + "\"";
        for( const auto& [ colName, colValue ] : best->cols )
        {
            std::string attrName;
            for( const char c : colName )
            { // XML-safe attribute name: the TSV's own names are safe, but a hand-edited one must not break well-formedness
                attrName += ( std::isalnum( static_cast<unsigned char>( c ) ) || c == '_' ) ? c : '_';
            }
            attrs += " heat_" + attrName + "=\"" + ex( colValue ) + "\"";
        }
        heatByFinding[ findingIndex ] = std::move( attrs );
    }
    char joinedBuf[ 48 ];
    std::snprintf( joinedBuf, sizeof( joinedBuf ), " heat_joined=\"%zu\"", joined );
    return std::make_pair( std::move( heatByFinding ), std::string( joinedBuf ) );
}

// Fold the atoms-of-confusion pack (src/atoms.h — Gopstein et al., ESEC/FSE 2017) into the built-in
// lint set: its findings, its per-rule floor disclosures, and its rule names for the tally. Three of
// its seven rules are decided by SUBTRACTION ("every update_expression EXCEPT the statement-level and
// for-header ones"), which no tree-sitter query can express, so the pack spends its own astQuery pass
// on a budget far above kLintMaxPerRule — an exclusion stream truncated at 5000 would manufacture
// false positives on this repo alone. kAtomRuleNames is THE list, so the tally cannot drift from what
// ONE parse pass for all four built-in producers, in the order runLint merges them: the [AST] checks it
// was handed, the atoms pack, the cache pack, and the unreachable-code walk. Each of those used to drive
// its OWN corpus pass, and each of those passes re-read and re-parsed every file -- four reads and four
// tree-sitter parses per file to ask four sets of questions about the SAME tree, plus three rounds of
// compiling every spec against every linked grammar. astQueryGrouped walks the corpus once and buckets the
// findings per group; each bucket is then sorted and budget-capped by exactly the code a standalone call
// runs, so the four results are byte-identical to the four passes they replace.
//
// The fourth is not a spec table: unreachable-code is an ORDERED scan of a block's statement siblings
// ("the first non-comment statement after an unconditional exit"), which no tree-sitter pattern can
// express, so it rides the shared walk as an AstWalk group instead (src/ingest.h). What it shares is what
// it was duplicating -- the read, the parse and the newline index -- not the traversal.
// keptBytes receives the corpus text the walk read (astQueryGrouped's keptBytesOut). The two symbol-level
// passes that run after it -- lintSymbolLevelChecks and the naming lens -- each opened the very files this
// walk had just read and closed, one at a time on the main thread, to look at spans of the same text. They
// now read from here and fall back to their own open only for a file the walk skipped.
std::vector<std::vector<rw::AstMatch>> builtInLintCaptures( const rw::IngestResult& ing, const std::vector<rw::AstQuerySpec>& checks,
                                                            std::vector<std::string>& keptBytes )
{
    PROFILE_SCOPE_DESCRIBE( "lint: astQueryGrouped (built-in + atoms + cache + unreachable)" );
    const std::vector<rw::AstQuerySpec> atomChecks  = rw::atoms::atomsSpecs();
    const std::vector<rw::AstQuerySpec> cacheChecks = rw::cachelint::cacheSpecs();
    return rw::astQueryGrouped( ing, { { &checks,      rw::kLintMaxPerRule,              nullptr },
                                       { &atomChecks,  rw::atoms::kAtomsQueryBudget,     nullptr },
                                       { &cacheChecks, rw::cachelint::kCacheQueryBudget, nullptr },
                                       { nullptr,      rw::kUnreachableMaxHits,          nullptr, rw::AstWalk::UnreachableCode } },
                                &keptBytes );
}

// the pack can emit. Lifted out of runLint for the same reason lintSymbolLevelChecks was.
void mergeAtomsPack( const rw::IngestResult& ing, std::vector<rw::AstMatch>& ms,
                     std::vector<RuleCap>& saturatedRules, std::vector<std::string>& allRuleNames,
                     std::vector<rw::AstMatch> captures )
{
    const rw::atoms::AtomsRun pack = rw::atoms::atomsOfConfusionFromCaptures( ing, rw::kLintMaxPerRule, std::move( captures ) );
    for( const rw::AstMatch& hit : pack.findings )      { ms.push_back( hit ); }
    for( const std::string& tag : pack.saturatedTags )  { saturatedRules.push_back( { tag, false } ); }
    for( const std::string_view rule : rw::atoms::kAtomRuleNames ) { allRuleNames.emplace_back( rule ); }
}

// Fold the cache-friendliness pack (src/cachelint.h — the access-pattern half of the locality story;
// the layout half is --field-affinity) into the built-in lint set: its findings, its per-rule floor
// disclosures, and its rule names for the tally. Same shape as mergeAtomsPack for the same reasons.
void mergeCachePack( const rw::IngestResult& ing, std::vector<rw::AstMatch>& ms,
                     std::vector<RuleCap>& saturatedRules, std::vector<std::string>& allRuleNames,
                     std::vector<rw::AstMatch> captures )
{
    const rw::cachelint::CacheRun pack = rw::cachelint::cacheFriendliness( ing, rw::kLintMaxPerRule, std::move( captures ) );
    for( const rw::AstMatch& hit : pack.findings )      { ms.push_back( hit ); }
    for( const std::string& tag : pack.saturatedTags )  { saturatedRules.push_back( { tag, false } ); }
    for( const std::string_view rule : rw::cachelint::kCacheRuleNames ) { allRuleNames.emplace_back( rule ); }
}

// Fold the identifier-naming lens (src/naminglens.h) into the built-in lint set: its findings go straight
// into ms, and a rule that spent its per-rule budget comes back here to be disclosed as a floor. Its rule
// names are NOT appended — unlike the atoms pack they are spelled in runLint's allRuleNames table, because
// the naming rules are symbol-level built-ins that were declared there before the pack existed. Lifted out
// of runLint for the same reason mergeAtomsPack and lintSymbolLevelChecks were.
void mergeNamingLens( const rw::IngestResult& ing, std::vector<rw::AstMatch>& ms, std::vector<RuleCap>& saturatedRules, bool namingLocals,
                      const std::vector<std::string>* preRead )
{
    for( std::string& namingRule : rw::naminglens::appendNamingFindings( ing, rw::kLintMaxPerRule, ms, namingLocals, preRead ) )
    {
        saturatedRules.push_back( { std::move( namingRule ), false } );
    }
}

// --lint-catalog: print the static rule registry (src/lintcatalog.h) and nothing else — needs no
// corpus. Lifted out of runLint for the same reason mergeAtomsPack/mergeNamingLens were: runLint was
// already the file's largest function, and this branch is fully self-contained.
int emitLintCatalog()
{
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( rw::escapeXml( s, esc ) ); };
    std::printf( "<!-- ripwire lint-catalog: the built-in lint rule registry, one row per rule, in the SAME order the plain lint "
                 "run's own tally uses. sev/cat/rationale describe the rule; lang= is the language TOKEN SET (the spelling the "
                 "lint-rules loader's own language: field accepts) whose grammar can ever satisfy this rule's query or scan — a "
                 "STRUCTURAL ceiling, not which languages happen to be in any one corpus (that disclosure is the lint run's own "
                 "applicable=/inert_rules=). since= is the ripwire release the rule first shipped in. -->" );
    std::printf( "<lintcatalog rules=\"%zu\">", rw::lintcatalog::kLintCatalog.size() );
    for( const rw::lintcatalog::LintCatalogRow& row : rw::lintcatalog::kLintCatalog )
    {
        std::printf( "<rule name=\"%s\" sev=\"%s\" cat=\"%s\" lang=\"%s\" since=\"%s\">%s</rule>",
                     ex( row.name ).c_str(), ex( row.severity ).c_str(), ex( row.category ).c_str(),
                     ex( rw::lintcatalog::lintCatalogLangList( row.langMask ) ).c_str(), ex( row.since ).c_str(),
                     ex( row.rationale ).c_str() );
    }
    std::printf( "</lintcatalog>" );
    return 0;
}

// --lint-select=/--lint-ignore=PREFIX[,...]: resolve BOTH into a LintSelection, validating every token
// against the combined rule-name pool (the static catalog ∪ whatever user rule ids --lint-rules=DIR
// just loaded ∪ the family stems) — done HERE, not in validateConfig, because a token can legitimately
// name a user rule id that is only known after --lint-rules=DIR has been read. nullopt ⇒ a refusal
// was already printed to stderr; the caller's job is just to `return 1`. Lifted out of runLint for the
// same reason emitLintCatalog was — this block alone was worth a third of runLint's complexity growth.
std::optional<rw::lintcatalog::LintSelection> resolveLintSelection( const rw::Config& cfg, const std::vector<rw::LintRule>& userRules )
{
    rw::lintcatalog::LintSelection sel;
    if( cfg.lintSelect.empty() && cfg.lintIgnore.empty() )
    {
        return sel;   // inactive — every rule kept, nothing to disclose
    }

    std::vector<std::string_view> pool;
    pool.reserve( rw::lintcatalog::kLintCatalog.size() + userRules.size() + rw::lintcatalog::kLintFamilyStems.size() );
    for( const rw::lintcatalog::LintCatalogRow& row : rw::lintcatalog::kLintCatalog ) { pool.push_back( row.name ); }
    for( const rw::LintRule& r : userRules ) { pool.push_back( r.id ); }
    for( std::string_view stem : rw::lintcatalog::kLintFamilyStems ) { pool.push_back( stem ); }

    const auto resolve = [ & ]( std::string_view raw, std::vector<std::string>& tokens, const char* flagName ) -> bool
    {
        if( !rw::lintcatalog::splitLintPrefixList( raw, tokens ) )
        {
            std::fprintf( stderr, "ripwire: %s: malformed PREFIX list (empty entry) — comma-separate PREFIXes, e.g. %s=cache-,goto\n",
                          flagName, flagName );
            return false;
        }
        for( const std::string& tok : tokens )
        {
            if( tok == "*" )
            {
                continue;   // the reserved "everything" sentinel — never itself a rule-name prefix
            }
            const bool found = std::any_of( pool.begin(), pool.end(),
                                            [ & ]( std::string_view n ) { return rw::lintcatalog::lintPrefixMatches( tok, n ); } );
            if( !found )
            {
                const std::string near = rw::lintcatalog::lintNameNearMiss( pool, tok );
                std::string        msg = "ripwire: " + std::string( flagName ) + ": '" + tok + "' matches no rule or family";
                if( !near.empty() )
                {
                    msg += " (did you mean '" + near + "'?)";
                }
                msg += " — see --lint-catalog for the full registry\n";
                std::fprintf( stderr, "%s", msg.c_str() );
                return false;
            }
        }
        return true;
    };
    if( !resolve( cfg.lintSelect, sel.selectPrefixes, "--lint-select" ) ) { return std::nullopt; }
    if( !resolve( cfg.lintIgnore, sel.ignorePrefixes, "--lint-ignore" ) ) { return std::nullopt; }
    sel.active = true;

    // selected="K of N" counts actual RULES (built-ins + loaded user rules) — the family stems above
    // exist only to widen the near-miss pool and are never rules themselves.
    for( const rw::lintcatalog::LintCatalogRow& row : rw::lintcatalog::kLintCatalog )
    {
        ++sel.totalCount;
        if( rw::lintcatalog::lintSelectionKeeps( sel, row.name ) ) { ++sel.selectedCount; }
    }
    for( const rw::LintRule& r : userRules )
    {
        ++sel.totalCount;
        if( rw::lintcatalog::lintSelectionKeeps( sel, r.id ) ) { ++sel.selectedCount; }
    }
    return sel;
}

// The corpus' own language mask plus how many of the PRINTED <rule> rows (post --lint-select/-ignore
// filtering — a filtered-out rule was never a row, so it cannot be inert either) are structurally
// inert on it: none of the rule's registered languages (lintcatalog.h) are present at all. Lifted out
// of runLint for the same reason resolveLintSelection was.
struct LintApplicability { std::uint32_t corpusLangs = 0; std::size_t inertRuleCount = 0; };

LintApplicability computeLintApplicability( const rw::IngestResult& ing, bool builtinsRan, const std::vector<std::string>& allRuleNames,
                                            const std::vector<rw::LintRule>& userRules, const rw::lintcatalog::LintSelection& sel )
{
    LintApplicability out;
    out.corpusLangs = rw::lintcatalog::corpusLangMask( ing );
    const auto kept  = [ & ]( std::string_view name ) { return !sel.active || rw::lintcatalog::lintSelectionKeeps( sel, name ); };
    if( builtinsRan )
    {
        for( const std::string& rn : allRuleNames )
        {
            if( !kept( rn ) ) { continue; }
            const rw::lintcatalog::LintCatalogRow* row = rw::lintcatalog::lintCatalogFind( rn );
            if( row != nullptr && ( row->langMask & out.corpusLangs ) == 0 ) { ++out.inertRuleCount; }
        }
    }
    for( const rw::LintRule& r : userRules )
    {
        if( !kept( r.id ) ) { continue; }
        if( ( rw::langBit( r.lang ) & out.corpusLangs ) == 0 ) { ++out.inertRuleCount; }
    }
    return out;
}

// THE emitted order of --lint's rows: (file path, startByte, rule, sev, text). sev and text are part of
// the KEY, not decoration. (file, startByte, rule) alone is NOT a total order — one rule can emit two
// findings at the same byte (naming-confusable pairs `rbegin` with both `begin` and `cbegin`, both
// anchored at the symbol's own offset) — and std::sort is unstable, so tied rows came out in whatever
// order the producers happened to have appended them. That made a VISIBLE part of the output depend on
// the order the checks run in rather than on the data: a determinism contract held by accident, and it
// flipped the moment the two built-in packs were merged from one call site instead of two. Everything a
// reader can SEE is now in the key, so rows that still tie are byte-identical and dedupeLintFindings
// collapses them. Lifted out of runLint for the same reason dedupeLintFindings was.
void sortLintRows( const rw::IngestResult& ing, std::vector<LintOut>& outs )
{
    std::sort( outs.begin(), outs.end(), [ & ]( const LintOut& x, const LintOut& y )
    {
        if( ing.files[x.fileId] != ing.files[y.fileId] ) { return ing.files[x.fileId] < ing.files[y.fileId]; }
        if( x.startByte != y.startByte )                 { return x.startByte < y.startByte; }
        if( x.rule != y.rule )                           { return x.rule < y.rule; }
        if( x.sev != y.sev )                             { return x.sev < y.sev; }
        return x.text < y.text;
    } );
}

// §P6.1: two DIFFERENT AST captures (different startByte — e.g. the same magic-number value
// spelled twice on one line, `h >> 33` appearing twice in the same expression) can still render
// as a byte-identical <f> row, because the row carries only file:line — no column — so a reader
// cannot tell them apart. A second identical row adds no information a reader can act on
// differently from the first, so collapse on the row's own visible identity (rule, sev,
// file:line, enclosing symbol, text) — keep the first occurrence in the caller's already-
// deterministic sort order. This also keeps findings= and each rule's count= truthful: they
// count distinct VISIBLE findings, not raw captures. Lifted out of the --lint block (same reason
// as lintSymbolLevelChecks above) so runLint stays under the complexity/verbosity bar.
std::vector<LintOut> dedupeLintFindings( const rw::IngestResult& ing, std::vector<LintOut> outs )
{
    using namespace rw;
    // model.h::symbolsByFile — same scan order, same comparator as the hand-written loop it replaces.
    const SymbolsByFile fileSyms = symbolsByFile( ing,
                                                  []( const Symbol& ) { return true; },
                                                  [ & ]( NodeId a, NodeId b ) { return ing.symbols[a].sigStartByte < ing.symbols[b].sigStartByte; } );
    const auto enclosing = [ & ]( std::uint32_t f, std::uint32_t off ) -> const Symbol*
    {
        const Symbol* best = nullptr;
        for( NodeId id : fileSyms[f] )
        {
            const Symbol& s = ing.symbols[id];
            if( s.sigStartByte > off )
            {
                break;
            }
            if( off < s.endByte && ( !best || s.sigStartByte > best->sigStartByte ) )
            {
                best = &s;
            }
        }
        return best;
    };

    HashMap<std::string, char> seenRow;
    std::vector<LintOut>       deduped;  deduped.reserve( outs.size() );
    for( const LintOut& o : outs )
    {
        const Symbol* e = enclosing( o.fileId, o.startByte );
        std::string   key;
        key.reserve( o.rule.size() + o.sev.size() + ing.files[ o.fileId ].size() + o.text.size() + 32 );
        key += o.rule;                                key += '\x1f';
        key += o.sev;                                 key += '\x1f';
        key += ing.files[ o.fileId ];                 key += '\x1f';
        key += std::to_string( o.line );              key += '\x1f';
        key += e ? e->name : std::string();           key += '\x1f';
        key += o.text;
        if( seenRow.find( key ) != seenRow.end() )
        {
            continue; // same visible row already kept
        }
        seenRow.emplace( std::move( key ), 0 );
        deduped.push_back( o );
    }
    return deduped;
}

// The routed → anchored → mention-anchored → (opt-in) co-change-boosted lens rank for a task, plus the header
// note fragments each stage contributes. This is THE ranking the --for lens consumes; extracted so runForLens
// and runPackTask (L4) share ONE ranking implementation (the plan's "do not reimplement ranking" mandate).
// rw::LensRanking itself now lives in packtask.h (L4) — shared with the MCP explore/pack_task verb's own
// routed-ranking path (mcpverbs.h), which populates the SAME struct via the same low-level ranking calls.

// Compute the lens rank for `task` exactly as the --for path does (all existing boosts: routing, --anchor,
// the B8 mention anchor, the B3 opt-in co-change prior). Pure function of (d, task): reads d.cfg for the same
// flags --for reads, so both callers get identical rankings for the same query + flags.
rw::LensRanking computeLensRanking( const MainDispatch& d, std::string_view task )
{
    using namespace rw;
    const Config&                     cfg       = d.cfg;
    const IngestResult&               ing       = d.ing;
    const Graph&                      g         = d.g;
    const std::string&                root      = d.root;
    const bool                        multiRoot = d.multiRoot;
    const std::vector<WorkspaceRoot>& ws        = d.ws;

    // H2 (B0 r2): --for's consumers only read the top-K of this rank, so lexicalScores may skip symbols that
    // provably cannot enter that top-K (exact MaxScore pruning — emitted bytes identical). --adaptive/--anchor
    // are full-distribution consumers and force exhaustive scoring.
    std::size_t       forPruneK = 0;
    std::vector<char> ifaceExact;
    if( !cfg.adaptive && !cfg.anchor )
    {
        forPruneK = cfg.candidates ? ( cfg.topK > 0 ? std::size_t( cfg.topK ) : 0 )
                                   : std::size_t( cfg.packTopN > 0 ? cfg.packTopN : 40 );
        if( forPruneK > 0 && !cfg.candidates )     // candidates bypasses the lens bundle → no lego set
        {
            ifaceExact.assign( ing.symbols.size(), 0 );
            for( std::size_t i = 0; i < g.implementors.size() && i < ifaceExact.size(); ++i )
            {
                if( !g.implementors[i].empty() )
                {
                    ifaceExact[i] = 1;
                }
            }
        }
    }
    const std::vector<char>* ifaceExactPtr = ifaceExact.empty() ? nullptr : &ifaceExact;

    // §P4 tier de-prioritization (filter.h): fixtures / present/ decks / generated captures score down,
    // folded INTO BM25 scoring (pruning-bound-safe) and BEFORE the B8 mention anchor — a fixture the task
    // literally NAMES is still lifted near the top.
    const std::vector<float> tierMul = rankTierSymbolMultipliers( ing );

    LensRanking out;
    std::vector<float>& lensRank = out.rank;
    if( !cfg.noRoute )
    {
        const RouteChoice rc = chooseForRanker( ing, task );
        lensRank      = ( rc.which == LexMode::NameExact ) ? lexicalScoresNameExactTiered( ing, task, &tierMul )
                                                           : lexicalScoresTiered( ing, g.outOff, g.outTargets, task, forPruneK, ifaceExactPtr, &tierMul );
        out.routeNote = " [routed: " + rc.reason + "]";
        out.routeTag  = ( rc.which == LexMode::NameExact ) ? "name-exact" : "subtoken+body";   // §A4f: the machine form of the same fact
    }
    else
    {
        lensRank = lexicalScoresTiered( ing, g.outOff, g.outTargets, task, forPruneK, ifaceExactPtr, &tierMul );
    }

    // R4: capture the RAW routed lexical score's max BEFORE --anchor/mention/cochange reshape lensRank — the
    // honesty signal reads the actual textual evidence, not a graph-expanded or query-mention-boosted number
    // (those can promote a symbol the query's words never touched, which would mask a genuinely weak query).
    // The §P4 tier factor is divided back out for the same reason (maxScoreUndoingTier, filter.h).
    if( !lensRank.empty() )
    {
        out.maxLexicalScore = maxScoreUndoingTier( lensRank, tierMul );
    }

    // --anchor (EXPERIMENTAL): lexically-anchored graph expansion (byte-identical without the flag).
    if( cfg.anchor )
    {
        lensRank = anchoredLexicalRank( g, lensRank );
    }

    // B8 query-mention anchoring: lift a file / dotted module / Scope.symbol the task literally NAMES near the
    // top (inert — byte-identical — when the text names nothing indexed). Routed path only.
    if( !cfg.noRoute && !cfg.noMentionBoost && !std::getenv( "RIPWIRE_NO_MENTION" ) )
    {
        MentionBoostInfo mentionInfo;
        if( applyMentionBoost( ing, task, lensRank, &mentionInfo ) )
        {
            char nb[ 160 ];
            std::snprintf( nb, sizeof( nb ), " [mention anchor: %u file%s + %u symbols named in the task lifted near the top]",
                           mentionInfo.fileCount, mentionInfo.fileCount == 1 ? "" : "s", mentionInfo.symbolCount );
            out.mentionNote  = nb;
            out.anchorLifts  = mentionInfo.fileCount + mentionInfo.symbolCount;   // §A4f: the count the candidates root emits
        }
    }

    // r4 sibling lift (EXPERIMENTAL, pre-registered — bench/locbench/results/r4_siblift/PREREG.md): lift the
    // strongest query-relevant same-directory siblings of the top-ranked files into the slot ladder. INERT
    // (byte-identical) unless RIPWIRE_SIBLIFT="<seed>,<sib>" parses in range. Routed path only.
    if( !cfg.noRoute )
    {
        if( const auto [ sibSeed, sibPer ] = sibliftParams(); sibSeed > 0 )
        {
            applySiblingLift( ing, lensRank, sibSeed, sibPer );
        }
    }

    // r5 file-level evidence pooling (EXPERIMENTAL, pre-registered —
    // bench/locbench/results/r5_pooling/PREREG.md): rank files by POOLED symbol evidence instead of
    // their single best symbol, so a file with five moderate hits can outrank one with a single sharp
    // one. Chooses no neighbour, which is the axis siblift failed on. INERT (byte-identical) unless
    // RIPWIRE_POOL="<K>,<blend*100>" parses in range. Routed path only.
    if( !cfg.noRoute )
    {
        if( const auto [ poolK, poolBlend ] = filePoolParams(); poolK > 0 )
        {
            applyFilePooling( ing, lensRank, poolK, poolBlend );
        }
    }

    // r6 structural expansion (EXPERIMENTAL, pre-registered —
    // bench/locbench/results/r6_expansion/PREREG.md): lift the RESOLVED import/reference neighbours of
    // the top-ranked files. siblift had this seed with a same-directory edge; anchorhop had this edge
    // seeded from mention anchors; both were rejected. This is the untried diagonal, and the first
    // candidate that adds evidence the QUERY did not supply. INERT unless RIPWIRE_EXPAND="<S>,<N>".
    if( !cfg.noRoute )
    {
        if( const auto [ expSeeds, expPer ] = expandParams(); expSeeds > 0 )
        {
            applyStructuralExpansion( ing, lensRank, expSeeds, expPer );
        }
    }

    // B3 co-change prior boost (OPT-IN, EXPERIMENTAL): files that historically change WITH the top seeds get a
    // bounded secondary boost. Inert (byte-identical) without usable git history. Routed path only.
    if( !cfg.noRoute && ( cfg.cochangeBoost || std::getenv( "RIPWIRE_COCHANGE" ) ) )
    {
        PROFILE_SCOPE_DESCRIBE( "main: co-change prior boost (mine + apply)" );
        std::vector<std::vector<std::uint32_t>> coSets;
        if( multiRoot )
        {
            for( std::uint32_t r = 0; r < ws.size(); ++r )
            {
                if( !hasEnclosingGitRepo( ws[r].arg ) )
                {
                    continue;
                }
                auto part = gitRecentCommitFileSets( ws[r].arg, ing, kCoBoostCommitWindow, kCoBoostMaxFilesPerCommit, r );
                for( std::vector<std::uint32_t>& c : part )
                {
                    coSets.push_back( std::move( c ) );
                }
            }
        }
        else if( hasEnclosingGitRepo( root ) )
        {
            coSets = gitRecentCommitFileSets( root, ing, kCoBoostCommitWindow, kCoBoostMaxFilesPerCommit );
        }

        CoBoostInfo boostInfo;
        if( !coSets.empty() && applyCoChangeBoost( ing, coSets, lensRank, &boostInfo ) )
        {
            char nb[ 200 ];
            std::snprintf( nb, sizeof( nb ), " [cochange boost: promoted %u symbols in %u files that historically change with the top seeds (last %u commits)]",
                           boostInfo.boostedSymbolCount, boostInfo.boostedFileCount, kCoBoostCommitWindow );
            out.boostNote = nb;
        }
    }

    // R5 — doc-mention surfacing (default-on, route-agnostic; see mention.h applyDocMentionBoost):
    // reuses g.mentions (the same doc<->code backtick edges `--mentions=SYM` already exposes) to lift docs
    // that discuss the query's top-resolved symbols, strictly below those symbols' own scores. Runs LAST
    // (after route/anchor/query-mention/co-change) so it reads the fully-resolved rank.
    if( !cfg.noDocMention && !std::getenv( "RIPWIRE_NO_DOC_MENTION" ) )
    {
        DocMentionBoostInfo docMentionInfo;
        if( applyDocMentionBoost( g, lensRank, &docMentionInfo ) )
        {
            char nb[ 160 ];
            std::snprintf( nb, sizeof( nb ), " [doc mentions: %u doc%s discussing %u top-ranked symbol%s surfaced]",
                           docMentionInfo.docCount, docMentionInfo.docCount == 1 ? "" : "s",
                           docMentionInfo.anchorCount, docMentionInfo.anchorCount == 1 ? "" : "s" );
            out.docMentionNote = nb;
        }
    }
    return out;
}

// §P8/§P12.2 — --adaptive used to silently no-op under --format=candidates: both candidates dispatch sites
// (the --for one below and --query's in runDefaultMap) returned before the cliff-cut logic ever ran, so the
// flag was accepted and produced byte-identical output. It now cuts the SAME scored list candidates already
// exports — one leading XML comment (candidates owns its own document root, so this mirrors how --query's
// own default-map adaptive note is emitted: a comment ahead of the root, never inline inside it) plus the
// clamped row cap. `ceiling` is the verb's own natural cap (--top-k, not the 40-row --for lens cap).
// `scanFullDistribution` mirrors each CALLER's own default-map --adaptive behavior (true for --for, whose
// 40-row cap can hide the true cliff; false for --query, whose ceiling already covers the full top-k).
// One function (not inlined at each call site) so the two PRE-EXISTING dispatch functions this composes
// into (runForLens/runDefaultMap) each gain a single call instead of the whole cut-and-print sequence.
inline void emitCandidates( std::FILE* out, const rw::IngestResult& ing, const std::vector<float>& rank,
                             int topK, bool adaptive, bool scanFullDistribution,
                             rw::CandidateProvenance prov,   // §A4f: route/anchored/weak — the caller owns which ranker ran
                             rw::RedactCounts* redact )      // §B0/W3-N1: REQUIRED — <sig> is emitted text
{
    int capN = topK;
    if( adaptive )
    {
        const rw::AdaptiveCut ac = rw::adaptiveCut( rank, 5, std::size_t( topK ), scanFullDistribution );
        char nb[ 208 ];
        if( !ac.hitCeiling && ac.cliffRank < ac.kept )
        {
            std::snprintf( nb, sizeof( nb ), "<!-- adaptive: kept %zu of %d - sharp cliff at rank %zu (%d%% drop), clamped up to the floor of %zu -->",
                           ac.kept, topK, ac.cliffRank, ac.dropPct, ac.kept );
        }
        else if( !ac.hitCeiling )
        {
            std::snprintf( nb, sizeof( nb ), "<!-- adaptive: kept %zu of %d - cliff at rank %zu, %d%% drop -->",
                           ac.kept, topK, ac.cliffRank, ac.dropPct );
        }
        else if( ac.positiveHits <= ac.kept )
        {
            std::snprintf( nb, sizeof( nb ), "<!-- adaptive: kept %zu of %d - only %zu symbols matched this query (sharp query, short tail) -->",
                           ac.kept, topK, ac.positiveHits );
        }
        else
        {
            std::snprintf( nb, sizeof( nb ), "<!-- adaptive: kept %zu of %d - no relevance cliff (broad query saturates the score); capped at the ceiling -->",
                           ac.kept, topK );
        }
        std::fputs( nb, out );
        capN = int( ac.kept );
    }
    packCandidates( out, ing, rank, capN, redact, prov );
}

// ── §A4a — the --for --json bundle, budgeted ────────────────────────────────────────────────────────────
// The JSON lens used to run NO size control at all: byte-identical at --token-budget=1000 and 20000 while
// the XML sibling shrank 4.7x, so the JSON/MCP audience — the one that most needs a budget — had none. It
// runs the same H1 ladder against the same budget the XML path computes, and SAYS what it did: "capped" is
// the ladder's own verdict (never inferred by the caller) and "est_tokens" is the delivered size, mirroring
// the XML `<sigs capped="1">` / header `est_tokens="N"` attributes.
//
// The sigs array is rendered into memory first for exactly the reason the XML path buffers it: the TRUE
// delivered byte count must be known before the header that reports it is written. Its own function (not a
// branch inside runForLens) because it is a whole second serialization of the bundle — inlined, it made the
// XML path harder to read for a reader who only cares about XML.
struct ForLensJsonInputs
{
    const rw::IngestResult&          ing;
    const std::vector<float>&         rank;
    int                               topN;
    const std::vector<std::uint32_t>* fanIn;
    const std::vector<char>*          impure;
    const std::vector<std::uint32_t>* churnPerFile;
    const std::vector<std::uint8_t>*  cloneMember;
    const std::vector<std::uint8_t>*  tested;
    const std::vector<std::uint32_t>* amp;
    rw::RedactCounts*                redact;            // §B0: the run's redaction tally — nullptr under --no-redact
    std::size_t                       packBudgetBytes;   // per-entry streaming budget (--pack-budget-bytes)
    std::size_t                       tokenBudget;       // --token-budget=N, 0 ⇒ the kForPayloadBudgetBytes default
    const rw::notes::NoteIndex*      noteIndex;         // §B1.3: L3 field notes, as the XML bundle already
                                                         // receives them. nullptr ⇒ no notes keys at all.
    // §B1.4 (capture-audit-4): existence counts for the three sections that stay XML-only under --json —
    // the notes_total convention verbatim: "what the tree matched" BEFORE any display-side cap/dedup, not a
    // promise of exactly how many rows the XML sibling would print. legoTotal in particular can exceed the
    // XML's own row count (packLego dedups same-named interfaces and caps at topN=12) — that is by design,
    // not drift: the point is telling 0 (genuinely nothing on this surface) from N>0 (dropped, ask for XML),
    // not mirroring packLego's display-only collapsing. Always present (never conditional), because a key
    // that is sometimes ABSENT reintroduces the exact ambiguity this fix exists to remove.
    std::size_t                       legoTotal;
    std::size_t                       composeTotal;
    std::size_t                       routesTotal;
};

// The lens bundle's opening keys. Every note is absent-unless-present — the same silence-means-nothing-
// happened convention the XML header comment uses, so a reader never has to tell an empty string from a
// missing stage. §A4e: `weak` is the one that used to be XML-only (string-spliced into a comment, hence
// structurally unreachable from JSON); it is a real key here.
struct ForLensNotes
{
    const std::string& route;
    const std::string& mention;
    const std::string& boost;
    const std::string& docMention;
    const std::string& adaptive;
    bool               weak;
};

// W3FIX H2 — the pieces --for's header comment is made of, so the header can be REBUILT in three shapes (as
// built / task echo dropped / that plus route=) for serialize.h's climbCeilingLadder to price. A free function
// over a parts struct rather than a lambda inside runForLens: the ladder calls it up to three times, and
// runForLens is already one of the largest functions in this file. Mirrors packtask.h PackTaskHeaderParts.
struct ForLensHeaderParts
{
    std::string_view task;             // §B1.7's subject — the VERBATIM query, for the root attribute
    std::string_view rootOpenStr;      // ctxRootOpen( task, routeNoteRaw ), pre-built (its size is charged)
    std::string_view taskNote;         // the comment's scrubbed echo of `task` (xmlCommentText)
    std::string_view adaptiveNote, mentionNote, boostNote, docMentionNote;
    bool             anchor     = false;   // --anchor's EXPERIMENTAL caveat paragraph
    bool             autoBundle = false;   // T3: auto mode is on (cfg.detail==0, no --signatures-only) — appends the bundle=auto legend
    std::string_view rootArg;              // R-E (2026-08-17): the single-root run's own root= — the ladder's
                                            // route-dropped rebuild below calls ctxRootOpen a second time and
                                            // must carry the SAME root as the pre-built rootOpenStr did.
};

// T3 — the legend sentence for the terminal-by-default bundle, a named constant so the sigs-budget
// exemption below (the D2 adaptiveNote precedent) subtracts EXACTLY the bytes the legend adds. No "--"
// anywhere in it: it rides inside an XML comment, where "--" is ill-formed (G4). It also defines the
// <bodies>/<calls> disclosure trio, because those attributes now appear on --for's first screen and the
// legend-coverage contract is that every first-screen attribute is defined in the emitting verb's legend.
inline constexpr std::string_view kForAutoBundleLegend =
    "; bundle=auto: the top-ranked FULL bodies ride inline after the signatures in a bodies section "
    "(bodies=N on this root counts them; bodies=0 reason=budget when none fit the remaining budget "
    "whole; the signatures-only flag (no-bodies mode) opts out) — read them here instead of opening the files. The "
    "bodies element discloses the house way: total=requested, shown=printed, capped=1 when they "
    "differ; each body's calls child lists its callee signatures, total= always, shown=/capped= only "
    "when that list is cut";

// One spelling of --for's header, three shapes of it. `withTaskEcho=false` replaces the comment's echo with a
// note pointing at the task= attribute that still holds the verbatim copy — the duplicate goes, nothing else.
// Byte-identical to the pre-ladder header when both flags are true and extraNotes is empty (golden-neutral).
inline std::string forLensHeaderText( const ForLensHeaderParts& p, bool withRouteAttr, bool withTaskEcho,
                                      std::string_view extraNotes )
{
    std::string h;
    h.reserve( 640 + kForAutoBundleLegend.size() + p.rootOpenStr.size() + p.taskNote.size() + p.adaptiveNote.size()
               + p.mentionNote.size() + p.boostNote.size() + p.docMentionNote.size() + extraNotes.size() );
    h += withRouteAttr ? std::string( p.rootOpenStr ) : rw::ctxRootOpen( p.task, {}, p.rootArg );
    h += "<!-- ripwire lens for ";
    if( withTaskEcho ) { h += "\"";  h.append( p.taskNote );  h += "\""; }
    else
    {
        h += "[task_echo: dropped (ceiling) - the verbatim copy is the task= attribute above]";
    }
    // L1 (density audit 2026-08-08): the comment used to append a SCRUBBED copy of the route note here —
    // ~230-260 B saying, on every routed call, exactly what the verbatim route= attribute above already says.
    // The attribute is the surviving copy (verbatim + machine-addressable); the ceiling ladder's rung (c)
    // now truly is "the first rung that costs unique information" (serialize.h climbCeilingLadder).
    h.append( p.adaptiveNote );
    h.append( p.mentionNote );      // B8: present only when the task named something indexed (else "")
    h.append( p.boostNote );        // B3: present only when the co-change prior actually promoted something
    h.append( p.docMentionNote );   // R5: present only when a resolved symbol's mentioning docs surfaced
    if( p.anchor )
    {
        h += " [anchored, EXPERIMENTAL: lexical + graph-expanded rank; honest numbers: on the 80-commit co-change "
             "eval it MATCHES lexical-alone (within 0.3pt) and stays below whole-name BM25 - it adds lexically-"
             "invisible neighbours without hurting, no measured recall lift; see bench/ANSWERQUALITY.md]";
    }
    h += ": reusable building blocks + quality facts for what you're about to touch "
         "(cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) "
         "— prefer composing/reusing these; watch the high-churn/high-amp/cloned ones";
    if( p.autoBundle )
    {
        h.append( kForAutoBundleLegend );   // T3: present whenever auto mode is on, whatever the fit outcome — it explains bodies="0" too
    }
    h.append( extraNotes );
    h += " -->";
    // W3-S item 5 (2026-08-19): the --for lens carries root= on its <ctx> with nothing defining it — the
    // same "an attribute the document never explains" gap the root-relative round closed on eighteen other
    // legends via the shared rw::kRootRelPathsLegend clause (graphlegend.h), missed here because this
    // header is built in main.cpp rather than through a shared emitter. Pasting THAT clause verbatim was
    // tried and reverted: at 159 B it took a --token-budget=800 bundle's est_tokens from inside the ceiling
    // to 811 (+1.4%) and red test/fornotesbudgetcheck.sh — a real "a disclosure has BYTES" trap, on a
    // contract that says est_tokens <= the stated budget in both dialects.
    //
    // Trade-off chosen: a SHORTER spelling for this one call site, not a floor recalibration. Recalibrating
    // the shared budget constants (kMinBytesPerToken / kBudgetHeadroom / kCeilingFirstEntryTolerance,
    // serialize.h) would move every OTHER --for/--pack-task gate pinned against them
    // (bundleidcheck.sh/partitioncheck.sh/estchargecheck.sh among others) for one verb's 21-byte gap — a
    // blast radius wildly out of proportion to the fix. A second wording is normally exactly the kind of
    // echo-site drift kRootRelPathsLegend's own header warns against (it was hoisted OUT of eighteen
    // per-verb copies for that reason) — but --for is the one call site with a MEASURED, hard byte
    // constraint the other eighteen do not carry, and the two dialects (CLI --for, MCP `for`) share this
    // ONE short form, so there are still only two spellings in the whole tool, not nineteen.
    // Measured: 159 B (kRootRelPathsLegend) -> 126 B (kForRootRelPathsLegendShort), saving 33 B. On the
    // --token-budget=800 fixture fornotesbudgetcheck.sh builds: WITHOUT any root= clause, est_tokens=799
    // (1 B of headroom under the 800 ceiling); WITH kRootRelPathsLegend appended, est_tokens=811 (RED, the
    // regression this comment records); WITH the short form below, est_tokens=800 (fits exactly — the
    // clause is now the FIRST byte of headroom this bundle had left, not eleven tokens past it).
    // `on` is p.rootArg's OWN presence, the same convention rootRelPathsLegend(bool) itself uses elsewhere
    // (never re-derived from withRouteAttr or anything else the ceiling ladder decided above).
    h += rw::forRootRelPathsLegendShort( !p.rootArg.empty() );
    return h;
}

inline std::string forLensJsonHeader( std::string_view task, const ForLensNotes& notes )
{
    using rw::jsonStr;
    std::string h = "{\"task\":\"" + jsonStr( task ) + "\"";
    if( !notes.route.empty() )
    {
        h += ",\"route\":\"" + jsonStr( notes.route ) + "\"";
    }
    // the XML twin of these two fields carries task_scrubbed=/route_scrubbed= when the scrub lost bytes; this
    // dialect is the faithful one and says so from its own side (serialize.h ctxRootJsonScrubKeys). Absent on
    // clean input, so no ordinary document moves a byte.
    h += rw::ctxRootJsonScrubKeys( task, notes.route );
    if( !notes.mention.empty() )
    {
        h += ",\"mention\":\"" + jsonStr( notes.mention ) + "\"";
    }
    if( !notes.boost.empty() )
    {
        h += ",\"boost\":\"" + jsonStr( notes.boost ) + "\"";
    }
    if( !notes.docMention.empty() )
    {
        h += ",\"doc_mention\":\"" + jsonStr( notes.docMention ) + "\"";
    }
    if( !notes.adaptive.empty() )
    {
        h += ",\"adaptive\":\"" + jsonStr( notes.adaptive ) + "\"";
    }
    if( notes.weak )
    {
        h += ",\"weak\":true";
    }
    return h;
}

// §B1.3: the auto-surfaced field notes ride the rows inside the sigs array; this stanza is their DISCLOSURE
// — `notes_total` counts what the tree matched, `notes_kept` what survived the byte ladder, the same pair
// --pack-task --json reports. Empty unless a NoteIndex exists, so a tree with no .ripwire_notes keeps its
// pre-feature bytes exactly (the L3 inertness contract).
inline std::string forLensNotesStanza( const rw::JsonSigNoteCounts& counts, bool active )
{
    if( !active )
    {
        return {};
    }
    return ",\"notes_total\":" + std::to_string( counts.total ) + ",\"notes_kept\":" + std::to_string( counts.kept );
}

inline int emitForLensJson( std::FILE* out, const std::string& header, const ForLensJsonInputs& in )
{
    using namespace rw;

    // the SAME budget arithmetic the XML bundle runs: default kForPayloadBudgetBytes, an explicit
    // --token-budget wins, and the envelope's own bytes are charged before the sigs budget.
    //
    // §C1 (capture-audit-4) — this was 40, and the text it covers is `,"capped":false` (15) +
    // `,"est_tokens":` (14) + the digits + `,"sigs":` (8) + `}` (1) = 38 fixed. So 40 reserved room for a
    // TWO-digit est_tokens and under-reserved from five digits up — which is every real bundle. The two
    // halves are now named separately because they are two different jobs: the RESERVATION below must be an
    // upper bound (it is subtracted from the budget before the sigs are built), while the CHARGE further
    // down is measured exactly from the bytes that get written. Conflating them is what let a single
    // constant be wrong for one job while looking right for the other.
    //
    // Ten digits is 9 999 999 999 tokens — a ~36 GB bundle. The bound is stated rather than computed so the
    // reservation stays a compile-time constant, as its two sibling stanzas below already are.
    constexpr std::size_t kJsonEnvelopeFixedBytes = 38;
    constexpr std::size_t kJsonEnvelopeDigitsMax  = 10;
    constexpr std::size_t kJsonEnvelopeBytes      = kJsonEnvelopeFixedBytes + kJsonEnvelopeDigitsMax;   // 48, the RESERVATION
    // §B1.3: the notes stanza `,"notes_total":N,"notes_kept":M` is charged too — but ONLY when a NoteIndex
    // exists, so a tree with no .ripwire_notes keeps its budget arithmetic (and therefore its bytes) exactly
    // as before. That is the L3 inertness contract, not a rounding convenience.
    constexpr std::size_t kJsonNotesStanzaBytes = 40;
    // §B1.4: `,"lego_total":N,"compose_total":N,"routes_total":N` — UNLIKE the notes stanza, these three keys
    // are always present (never conditional), because the whole point is that 0 must mean "genuinely none
    // on this surface", not "not computed this run" — reserved generously (each count is realistically
    // 0..a few hundred, well under 7 digits) rather than measured exactly at charge time.
    constexpr std::size_t kJsonSurfaceCountsBytes = 96;
    const std::size_t bundleBudget = in.tokenBudget > 0
        ? std::size_t( double( in.tokenBudget ) * kMinBytesPerToken * kBudgetHeadroom )
        : kForPayloadBudgetBytes;
    const std::size_t fixedBytes = header.size() + kJsonEnvelopeBytes + kJsonSurfaceCountsBytes
                                  + ( in.noteIndex ? kJsonNotesStanzaBytes : 0 );
    const std::size_t sigsBudget = bundleBudget > fixedBytes ? bundleBudget - fixedBytes : 1;

    const JsonSigLens lens{ /*metrics=*/true, in.fanIn, in.impure, in.churnPerFile, in.cloneMember,
                            in.tested, in.amp, /*rankAdaptivePayload=*/true, in.noteIndex };
    JsonSigNoteCounts noteCounts;
    const auto packSigs = [ & ]( std::FILE* dst, std::size_t budget, bool* outCapped )
    { packSignaturesJson( dst, in.ing, in.rank, in.topN, lens, in.redact, in.packBudgetBytes, budget, outCapped, &noteCounts ); };

    // §B1.4: built once, used on both the degrade path below and the normal return — these three are plain
    // size_t values already computed by the caller (no rendering, no redaction seam), so unlike est_tokens
    // there is no "cannot compute it here" case that would justify omitting them on the degrade path too.
    const std::string surfaceCountsStanza = ",\"lego_total\":" + std::to_string( in.legoTotal )
                                           + ",\"compose_total\":" + std::to_string( in.composeTotal )
                                           + ",\"routes_total\":" + std::to_string( in.routesTotal );

    bool        sigsCapped = false;
    std::string sigsJson;
    {
        char*       jbuf = nullptr;
        std::size_t jsz  = 0;
        std::FILE*  jm   = rw::openChargeBuffer( &jbuf, &jsz );
        if( !jm )
        {
            // ENOMEM-class: emit unbudgeted rather than nothing, and report no est_tokens/capped at all —
            // a number this path cannot compute must never be fabricated.
            DEGRADED_PATH_ALERT( "main: open_memstream failed for the --for --json sigs block — emitting unbudgeted, est_tokens omitted" );
            std::fputs( header.c_str(), out );
            std::fwrite( surfaceCountsStanza.data(), 1, surfaceCountsStanza.size(), out );
            std::fputs( ",\"sigs\":", out );
            packSigs( out, 0, nullptr );
            std::fputs( "}", out );
            return 0;
        }
        packSigs( jm, sigsBudget, &sigsCapped );
        std::fflush( jm );  std::fclose( jm );
        if( jbuf ) { sigsJson.assign( jbuf, jsz );  std::free( jbuf ); }
    }

    const std::string notesStanza = forLensNotesStanza( noteCounts, in.noteIndex != nullptr );

    // §C1 + §C2 — the CHARGE, measured from the bytes this function is about to write rather than from the
    // reservation's upper bound. Two members were wrong:
    //   • the envelope was charged at the flat reservation (40) instead of its real width, which depends on
    //     `capped`'s spelling (`false` is one byte wider than `true`) and on est_tokens' own digit count;
    //   • `,"over_ceiling":true` was WRITTEN to `out` and left OUT of bundleBytes, so est_tokens did not
    //     charge the key describing the fact that est_tokens had blown its ceiling. That is §H7's
    //     self-reference shape at the one place it is most misleading.
    //
    // est_tokens counting its own digits is a fixed point, so it is SOLVED rather than approximated: start
    // with no digits, re-measure, repeat. Each pass can only widen the document, and a wider document can
    // only keep or grow the digit count, so the iteration is monotone and terminates — three passes cover
    // every value below 10^10 (a 10-digit est_tokens would need a ~36 GB bundle). The over_ceiling decision
    // rides the same fixed point in the safe direction: the key is emitted only when the document is already
    // over, and adding its 20 bytes can only keep it over, never bring it back under.
    const std::size_t cappedClauseBytes = sigsCapped ? 14u : 15u;      // ,"capped":true / ,"capped":false
    const std::size_t envelopeTextBytes = cappedClauseBytes + 14u + 8u + 1u;   // + ,"est_tokens": + ,"sigs": + }
    const std::size_t bundleBytesBase   = header.size() + sigsJson.size() + notesStanza.size()
                                        + surfaceCountsStanza.size() + envelopeTextBytes;
    const std::size_t ceilingAllowance  = in.tokenBudget > 0 ? ceilingAllowanceBytes( in.tokenBudget ) : 0;

    std::size_t estTokens   = 0;
    std::size_t bundleBytes = bundleBytesBase;
    for( int solvePass = 0; solvePass < 4; ++solvePass )
    {
        const std::size_t digits    = std::to_string( estTokens ).size() - ( estTokens == 0 ? 1 : 0 );
        const bool        isOver    = in.tokenBudget > 0 && ( bundleBytesBase + digits ) > ceilingAllowance;
        const std::size_t withKey   = bundleBytesBase + digits + ( isOver ? 20u : 0u );   // ,"over_ceiling":true
        const std::size_t nextTokens = std::size_t( double( withKey ) / kBytesPerTokenDefault + 0.5 );
        bundleBytes = withKey;
        if( nextTokens == estTokens )
        {
            break;
        }
        estTokens = nextTokens;
    }
    VERIFY( bundleBytes >= bundleBytesBase );
    // W3FIX H2 — the JSON sibling of the XML header's over_ceiling note. The two dialects charge the SAME
    // header bytes to the SAME budget, so they must also agree about the case where that charge cannot make the
    // document fit: the envelope's own verbatim task echo is user-length, and past some task length no sigs
    // trim can bring the bundle under an explicit --token-budget's stated ceiling. Absent ⇒ within the ceiling
    // (the silence-means-nothing-happened convention every other key here uses), never "not measured".
    // §C2: the SAME verdict the charge above solved for — read from the solved bundleBytes so the key that is
    // written and the bytes that were charged can never disagree (they used to be two separate comparisons,
    // one of which did not count the key it was deciding to emit).
    std::string overCeiling;
    if( in.tokenBudget > 0 && bundleBytes > ceilingAllowance )
    {
        overCeiling = ",\"over_ceiling\":true";
    }
    VERIFY( overCeiling.size() == 0 || overCeiling.size() == 20 );   // the 20 the charge above reserved for it
    std::fputs( header.c_str(), out );
    std::fwrite( surfaceCountsStanza.data(), 1, surfaceCountsStanza.size(), out );
    std::fwrite( notesStanza.data(), 1, notesStanza.size(), out );
    std::fwrite( overCeiling.data(), 1, overCeiling.size(), out );
    std::fprintf( out, ",\"capped\":%s,\"est_tokens\":%zu,\"sigs\":", sigsCapped ? "true" : "false", estTokens );
    std::fwrite( sigsJson.data(), 1, sigsJson.size(), out );
    std::fputs( "}", out );
    return 0;
}

// ── T3: the terminal-by-default auto <bodies> section (pre-registered: docs/EVALS.md §4) ─────────────────
// The single biggest measured non-terminal chain is map-then-read: the agent runs --for, then opens the
// file the map named. The terminal bundle that already served bodies (--pack-task) went uncalled for a
// month, so the DEFAULT gets richer instead: the top-ranked symbols' FULL bodies ride inline after the
// signatures, assembled by the SAME packBodies walk --pack-task uses (rank-first, skip-whole with a visible
// marker, disclosed shown=/total=/capped=), candidates capped at the pack-task cap so the shapes converge.
// Whole-body-or-not-at-all: truncateOversizedFirst=false, so a rank-1 def larger than the whole body budget
// is DROPPED and disclosed, never cut mid-def.
//
// BUDGET: an explicit --token-budget is a hard ceiling — the bodies get only what the rendered bundle
// genuinely left under it (`committedBytes`; the sigs/lego/compose/routes/graph bytes are computed exactly
// as before — auto mode never shrinks them), and a ceiling too tight for even the disclosure turns the
// whole surface off (`surfaceOff`): the output is then the pre-T3 bundle exactly, so the stated ceiling
// holds exactly as it did before this feature (D10) and nothing present goes undisclosed. WITHOUT an
// explicit budget, the default bundle gains the fixed kForAutoBodyBudgetBytes allowance on top of
// kForPayloadBudgetBytes — the per-call cost the T3 registration's guard covers, disclosed through
// est_tokens, which charges these bytes at the body rate. Every input is deterministic (ranked surface,
// rendered byte counts, constants), so body inclusion is a pure function of (corpus, query, budget).
//
// DEGRADE: a chargeSection memstream failure keeps the OLD behavior — surfaceOff, no bundle= attribute for
// that run (an est_tokens that cannot see the section must not describe it), with the alert on stderr.
// A free function over runForLens' locals (the ForLensHeaderParts precedent) — runForLens is already one of
// the largest functions in this file, and the decision reads better as one value than as inline branches.
struct ForAutoBodiesResult
{
    rw::ChargedSection section;             // rendered auto <bodies> bytes; empty when nothing is emitted
    std::string        attr;                // the <ctx> root disclosure; empty ⇒ no attribute (surface off / degrade)
    bool               surfaceOff = false;  // true ⇒ the caller rebuilds the header WITHOUT the bundle=auto legend
};

ForAutoBodiesResult buildForAutoBodies( const rw::Config& cfg, const rw::IngestResult& ing, const rw::Graph& g,
                                        const std::vector<rw::NodeId>& lensSurfaceIds, const std::vector<float>& lensRank,
                                        std::size_t committedBytes, std::size_t bundleBudget, rw::RedactCounts* redactPtr )
{
    ForAutoBodiesResult out;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool             fabSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view fabRootArg    = fabSingleRoot ? cfg.roots[0] : std::string_view();

    // candidates: the positive-score head of the ranked surface — the same "top heads with a positive
    // score" rule packTaskBundleText applies, on the same (score desc, id asc) order sigs selected with
    std::vector<rw::NodeId> autoBodyIds;
    for( rw::NodeId sid : lensSurfaceIds )
    {
        if( autoBodyIds.size() >= rw::kPackTaskBodyCandidates || lensRank[sid] <= 0.0f )
        {
            break;
        }
        autoBodyIds.push_back( sid );
    }

    std::size_t leftBytes = bundleBudget > committedBytes ? bundleBudget - committedBytes : 0;
    if( cfg.tokenBudget == 0 )
    {
        leftBytes += rw::kForAutoBodyBudgetBytes;   // the default bundle's body allowance (see serialize.h)
    }

    if( cfg.tokenBudget > 0 && leftBytes == 0 )
    {
        out.surfaceOff = true;                      // explicit ceiling too tight for even the disclosure
        return out;
    }
    if( autoBodyIds.empty() )
    {
        // R9 fix (W3-S, 2026-08-19): this used to return with `out.section` untouched (default-constructed,
        // isRendered=false), so the caller's `autoSection.isRendered && !autoSection.xml.empty()` guard
        // dropped the WHOLE <bodies> element — only the <ctx bundle="auto" bodies="0" reason="no_candidates">
        // attribute below spoke to it. "A zero means none found, never none exists" (CONTRIBUTING #3)
        // applies to elements too. packBodies handles an empty id list natively (requestedCount=0,
        // shownCount=0), so this renders the same honest "<bodies shown="0" total="0" capped="0"></bodies>"
        // shell the "budget" branch below already gets for free, rather than a second hand-rolled tag.
        out.attr    = " bundle=\"auto\" bodies=\"0\" reason=\"no_candidates\"";
        out.section = rw::chargeSection( [ & ]( std::FILE* f )
            { rw::packBodies( f, ing, autoBodyIds, /*budgetBytes=*/1, g.outOff, g.outTargets, cfg.compress, redactPtr,
                               /*ranges=*/nullptr, /*noteIndex=*/nullptr, nullptr, /*truncateOversizedFirst=*/false,
                               /*withFileContext=*/false, fabRootArg ); },
            rw::kBytesPerTokenBody );
        if( !out.section.isRendered )
        {
            out.surfaceOff = true;                      // degrade: pre-T3 output exactly (alert already on stderr)
            out.section    = rw::ChargedSection{};
        }
        return out;
    }

    // noteIndex=nullptr, deliberately: every auto-body symbol is by construction in the <sigs> head, whose
    // <d> row ALREADY surfaces its field notes — repeating them on the body would spend allowance bytes on
    // duplicates AND desync the --json dialect's notes_kept from the XML sibling's note count
    // (fornotesjsoncheck), since the JSON bundle renders no bodies.
    const std::size_t  autoBodyBudget = std::min( leftBytes, cfg.packBudgetBytes );
    rw::EmittedBodies autoEmitted;
    out.section = rw::chargeSection( [ & ]( std::FILE* f )
        { rw::packBodies( f, ing, autoBodyIds, autoBodyBudget, g.outOff, g.outTargets, cfg.compress, redactPtr,
                           /*ranges=*/nullptr, /*noteIndex=*/nullptr, &autoEmitted, /*truncateOversizedFirst=*/false,
                           /*withFileContext=*/false, fabRootArg ); },
        rw::kBytesPerTokenBody );

    if( !out.section.isRendered )
    {
        out.surfaceOff = true;                      // degrade: pre-T3 output exactly (alert already on stderr)
        out.section    = rw::ChargedSection{};
    }
    else if( autoEmitted.kept.empty() )
    {
        // R9 fix (W3-S, 2026-08-19): `out.section` ALREADY holds packBodies' own honest
        // "<bodies shown="0" total="N" capped="1"></bodies>" render from the chargeSection() call just
        // above — this branch used to overwrite it with an empty section ("drop the empty section
        // whole"), so the element vanished from the document even though the bytes to say so honestly
        // had already been paid for and charged. Keep it; only the attr= reason below is new
        // information (WHY zero: the budget, not the candidate set).
        out.attr = " bundle=\"auto\" bodies=\"0\" reason=\"budget\"";
    }
    else
    {
        out.attr = " bundle=\"auto\" bodies=\"" + std::to_string( autoEmitted.kept.size() ) + "\"";
    }
    return out;
}

std::optional<int> runForLens( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::string&                root         = d.root;
    const bool                        multiRoot    = d.multiRoot;
    const std::vector<WorkspaceRoot>& ws           = d.ws;
    const std::vector<std::uint32_t>* fanInPtr     = d.fanInPtr;
    const std::vector<char>*          impurePtr    = d.impurePtr;
    const std::vector<std::uint8_t>*  testedPtr    = d.testedPtr;
    const std::vector<std::uint32_t>* ampPtr       = d.ampPtr;
    std::vector<std::uint32_t>&       forChurn     = d.forChurn;
    RedactCounts&                     redactCounts = d.redactCounts;
    RedactCounts*                     redactPtr    = d.redactPtr;
    const rw::notes::NoteIndex*      notesPtr     = d.notesPtr;   // L3: surfaces <note> children on the emitted symbols/files
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool             flSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view flRootArg    = flSingleRoot ? cfg.roots[0] : std::string_view();

    // --for=TASK: the task lens — a ranked, signatures-only inventory of the building blocks relevant
    // to the task (with descriptive cx/in metrics), framed for reuse. The evidence-optimal bundle
    // (signatures > bodies, ranked best-first, "compose from these" — CrossCodeEval/eWASH/De-Hallucinator).
    // Emits multiple sibling blocks (sigs, lego, compose) — wrapped in <ctx> so the output is a single
    // valid XML document (G4). The default map (plain ripwire <dir>) never reaches this path.
    if( !cfg.forTask.empty() )
    {
        // ROUTING (now the DEFAULT): a deterministic, confidence-gated query-shape classifier picks the BASE
        // ranker for THIS query — name-exact BM25 when the query NAMES a symbol (identifier syntax, or every
        // content word is a symbol name), else the subtoken+body default (lexical.h chooseForRanker). The
        // confidence gate makes routing SAFE on both query shapes (--eval-retrieval: routed tracks the better
        // ranker on identifier AND conceptual queries), so it defaults ON. --no-route forces subtoken+body (the
        // pre-default behavior). Compose order with --anchor: ROUTE picks the base lens rank, then ANCHOR
        // expands that base via the graph walk. Under --no-route lensRank is the subtoken+body default exactly
        // as before → byte-identical output (golden neutrality preserved for the un-routed path).
        // H2 (B0 r2): --for's consumers only read the top-K of this rank (K = the bundle's self-limit:
        // forTopN, or --top-k for the candidates export) PLUS every interface (packLego ranks all
        // implementor-bearing symbols by this vector), so lexicalScores may safely skip symbols that
        // provably cannot enter that top-K (exact MaxScore pruning — emitted bytes are identical).
        // Full-distribution consumers force exhaustive scoring: --adaptive scans the whole positive
        // score distribution for the cliff, --anchor seeds PPR personalization from it.
        // ROUTING + anchoring + the B8 mention anchor + the opt-in B3 co-change prior all live in
        // computeLensRanking (shared with runPackTask so the ranking is defined once). Compose order with
        // --anchor: ROUTE picks the base lens rank, then ANCHOR expands it; mention/co-change run after.
        LensRanking        lr        = computeLensRanking( d, cfg.forTask );
        std::vector<float> lensRank  = std::move( lr.rank );
        const std::string  routeNoteRaw = std::move( lr.routeNote ); // verbatim; lands ONLY in route= (attribute-escaped) + the JSON twin — L1: the comment no longer echoes it
        const std::string  mentionNote( std::move( lr.mentionNote ) );
        const std::string  boostNote( std::move( lr.boostNote ) );
        const std::string  docMentionNote( std::move( lr.docMentionNote ) );
        // R4: weak-result honesty signal — the top match's RAW lexical score (pre-anchor/mention/cochange,
        // see computeLensRanking) falls below kWeakLexicalScoreThreshold, so the ranking below this header
        // rests on thin-to-no textual evidence. Read below (with est_tokens) into the header comment.
        const bool         forWeak = lr.maxLexicalScore < kWeakLexicalScoreThreshold;

        // R6 (A4-R6) — --format=candidates: a FLAT top-K export of THIS ranked set for an external reranker
        // (identity + score + signature, no lens extras). A single <candidates> root (G4-clean), so it bypasses
        // the whole <ctx> lens bundle below. Capped by --top-k. Deterministic (score desc, id asc).
        //
        // §P12.2 fix: --adaptive used to no-op here (this block returned before the cliff-cut logic below ever
        // ran). emitCandidates() now cuts BEFORE the bypass, full-distribution scan like --for's own
        // default-map cut (the ceiling is --top-k, not the 40-row lens cap).
        if( cfg.candidates )
        {
            // §A4e/§A4f: the export carries the ranking's provenance — which ranker ran, how many mention
            // anchors moved it, and (the signal that used to be XML-comment-only) whether the whole ranking
            // rests on evidence too thin to trust.
            emitCandidates( stdout, ing, lensRank, cfg.topK, cfg.adaptive, /*scanFullDistribution=*/true,
                            CandidateProvenance{ lr.routeTag, lr.anchorLifts, forWeak }, redactPtr );
            reportRedactions( stderr, redactCounts );    // W3-N1: <sig> is now a redacting seam — this export must disclose its own tally
            return 0;
        }

        // G4: the task text is echoed into an XML comment, where "--" is ill-formed (and "-->" would terminate
        // the comment early). W3FIX M3: the hand-rolled '--' collapse scrubbed dashes and NOTHING else, so a C0
        // byte or invalid UTF-8 in the task made xmllint reject the document and a '\n' put a raw newline outside
        // CDATA — xmlCommentText (serialize.h) is the ONE scrub for all three, shared with --pack-task / MCP
        // `for` / --exemplar / --from-trace. Byte-identical on control-free input. (L1: the route note no
        // longer rides in the comment — route= carries it verbatim, attribute-escaped by ctxRootOpen, and
        // the JSON sibling keeps the same RAW text.)
        const std::string taskNote = xmlCommentText( cfg.forTask );
        int forTopN = cfg.packTopN > 0 ? cfg.packTopN : 40;

        // --adaptive (lever 2): cut the returned set at the relevance CLIFF — the largest
        // relative score gap in [floor, ceiling] (Adaptive-k). A sharp query keeps few; a flat/broad query
        // (no knee) hits the ceiling and is kept as-is (cap-and-note). floor=5, ceiling=forTopN. The cut
        // narrows forTopN BEFORE packSignatures selects, so the emitted set is exactly the kept head. The
        // note is legible in the header so the reader knows WHY the set is the size it is. Without --adaptive,
        // forTopN is untouched → byte-identical output (golden neutral).
        std::string adaptiveNote;
        if( cfg.adaptive )
        {
            const int         ceil = cfg.packTopN > 0 ? cfg.packTopN : 40;
            // scanFullDistribution=true: --for caps at 40, so a sharp query's real cliff often sits BELOW the
            // cap while the top-40 head is flat — a scan bounded at the cap finds no knee and keeps 40/40
            // (the recorded "inert on --for"). Scan the RAW lexical (BM25) distribution BEFORE the cap so the
            // true cliff is seen, then clamp kept into [floor, ceiling]. lensRank IS the raw lexical score here
            // (subtoken+body or name-exact; --anchor's blend is opt-in and handled by keeping this the same call).
            const AdaptiveCut ac   = adaptiveCut( lensRank, 5, std::size_t( forTopN ), /*scanFullDistribution=*/true );
            forTopN = int( ac.kept );
            char nb[ 200 ];
            if( !ac.hitCeiling && ac.cliffRank < ac.kept )
            {
                std::snprintf( nb, sizeof( nb ), " [adaptive: kept %zu of %d - sharp cliff at rank %zu (%d%% drop), clamped up to the floor of %zu]",
                               ac.kept, ceil, ac.cliffRank, ac.dropPct, ac.kept );
            }
            else if( !ac.hitCeiling )
            {
                std::snprintf( nb, sizeof( nb ), " [adaptive: kept %zu of %d - cliff at rank %zu, %d%% drop]",
                               ac.kept, ceil, ac.cliffRank, ac.dropPct );
            }
            else if( ac.positiveHits <= ac.kept )
            {
                std::snprintf( nb, sizeof( nb ), " [adaptive: kept %zu of %d - only %zu symbols matched this query (sharp query, short tail)]",
                               ac.kept, ceil, ac.positiveHits );
            }
            else
            {
                std::snprintf( nb, sizeof( nb ), " [adaptive: kept %zu of %d - no relevance cliff (broad query saturates the score); capped at the ceiling]",
                               ac.kept, ceil );
            }
            adaptiveNote = nb;
        }

        // H1 (B0 r2): the bundle is emitted under a GLOBAL payload budget (serialize.h kForPayloadBudgetBytes; an
        // EXPLICIT --token-budget=N overrides it at the same conservative byte rate the --max-tokens fitter uses).
        // Trimming happens inside <sigs> only, so the header is built as a string and the sibling blocks (lego,
        // compose) are rendered FIRST — their exact byte cost is subtracted from the bundle budget before
        // packSignatures enforces the remainder. Emission ORDER is unchanged (header, sigs, lego, compose, bodies,
        // </ctx>): when nothing trims, the output is byte-identical to the pre-H1 path. W3FIX H2: the header goes
        // through forLensHeaderText (above) rather than being appended once, because the ceiling ladder below has
        // to PRICE a header without the comment's task echo or without route= and then emit that exact shape.
        const std::string        rootOpenStr = ctxRootOpen( cfg.forTask, routeNoteRaw, flRootArg );
        // T3 (pre-registered: docs/EVALS.md §4, T3 round): terminal-by-default — the auto <bodies> mode is on
        // unless the caller took an explicit body posture (--detail=N) or opted out (--signatures-only). The
        // --json and --format=candidates dialects never reach the auto machinery (candidates returned above;
        // --json returns before it below), so this mode is an XML-bundle fact only.
        const bool         autoBundleMode = cfg.detail == 0 && !cfg.signaturesOnly;
        // NOT const: the tight-explicit-budget path in the auto block below may turn the auto surface off
        // (autoBundle=false) and rebuild the header without the legend — the ladder's later rebuilds read
        // this struct through buildForHeader and must honor that decision.
        ForLensHeaderParts headerParts{ cfg.forTask, rootOpenStr, taskNote, adaptiveNote,
                                        mentionNote, boostNote, docMentionNote, cfg.anchor, autoBundleMode, flRootArg };
        const auto buildForHeader = [ & ]( bool withRouteAttr, bool withTaskEcho, std::string_view extraNotes )
        { return forLensHeaderText( headerParts, withRouteAttr, withTaskEcho, extraNotes ); };
        std::string headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );

        // Q3 quality lens: fold churn (per-file) + clone-membership (per-symbol) onto the --for bundle, next
        // to the ccx/tested/amp already computed above. A4-P6: churn (12-month) was already computed above in
        // the SAME 18-month co-change popen (gitCoChangeAndChurn), so there is no second git subprocess here.
        // git-less ⇒ forChurn stays all-0 → churn= omitted. Guard sizing defensively (always sized above).
        if( forChurn.size() != ing.files.size() )
        {
            forChurn.assign( ing.files.size(), 0u );
        }
        // clone membership: 1 if the symbol is in any duplicate-clone group (same threshold as --clones default).
        std::vector<std::uint8_t> forClone( ing.symbols.size(), 0u );
        for( const CloneGroup& cg : findClones( ing, 40 ) )
        {
            for( NodeId m : cg.members )
            {
                if( m < forClone.size() )
                {
                    forClone[m] = 1u;
                }
            }
        }

        // THE BUNDLE'S RESOLVED SURFACE: the top-N ids by lensRank — the exact set <sigs> selects. Three
        // consumers now: the S5-E HAS-A compose view, the B6.3 route view, and (§P3) the <lego> scope
        // filter, which keeps only interfaces this surface actually reaches. §B1.4 (capture-audit-4):
        // HOISTED above the --json branch — both dialects need it now, XML to RENDER lego/compose/routes,
        // JSON to COUNT them without rendering (see below). Computed once, kept alive for the
        // direct-emission degrade paths further down too.
        std::vector<NodeId> lensSurfaceIds;
        {
            const std::size_t S = ing.symbols.size();
            lensSurfaceIds.resize( S );
            for( NodeId i = 0; i < S; ++i )
            {
                lensSurfaceIds[i] = i;
            }
            // A4-F23c: score-only sort left ties straddling the cut stdlib-dependent. Use the (score desc, id
            // asc) total order (same key packSignatures selects with) so the surface set is deterministic.
            rw::sortutil::radixSortByScoreDescId( lensSurfaceIds, lensRank );
            const std::size_t cap = std::min<std::size_t>( std::size_t( forTopN ), S );
            lensSurfaceIds.resize( cap );
        }
        // IS-A: socket → bricks — for the interfaces THIS task actually reaches (§P3: the implementors map is
        // pre-scoped to lensSurfaceIds; withPaths keeps two same-named impls apart, exactly as --lego=TYPE
        // spells them). No interface reached ⇒ no <lego> element. Kept alive for the §P3×§P4 narrowing below
        // (XML render) and the §B1.4 count (JSON) — this is pure membership bookkeeping, never a redacting
        // seam, so hoisting it above the --json branch changes no dialect's redaction tally.
        std::vector<std::vector<NodeId>> legoScoped = legoImplementorsOnSurface( ing, g.implementors, lensSurfaceIds );

        // L2: --json — the ranking ("sigs") bundle, plus (§B1.4) a COUNT of what <lego>/<compose>/<routes>
        // would have held on this same surface. They still stay XML-only — rendering them for real would
        // mean a second redaction pass over interface method bodies the JSON dialect otherwise never takes —
        // but a reader can now tell "0, genuinely nothing here" from "dropped, ask for the XML dialect",
        // the notes_total precedent applied verbatim. jsonUnsupportedVerb already refused
        // --format=candidates/columnar/--detail, so reaching here with cfg.json means the plain lens bundle.
        if( cfg.json )
        {
            // §B1.3: --with-graph has no JSON dialect yet (the mermaid block is XML-only) — warn once and
            // continue without it, the same warn-and-continue shape --partition's --with-graph note (below,
            // runPackTask) already uses, rather than silently dropping the flag's effect with no tell at all.
            if( cfg.withGraph )
            {
                std::fprintf( stderr, "ripwire: --with-graph is not applied under --json (the mermaid graph block is XML-only for now) — emitted without it\n" );
            }

            std::size_t legoTotal = 0;
            for( const std::vector<NodeId>& impls : legoScoped )
            {
                if( !impls.empty() )
                {
                    ++legoTotal;
                }
            }

            std::vector<char> onSurfaceFlags( ing.symbols.size(), 0 );
            for( NodeId sid : lensSurfaceIds )
            {
                if( sid < onSurfaceFlags.size() )
                {
                    onSurfaceFlags[sid] = 1;
                }
            }
            const auto isOnSurface = [ & ]( NodeId sid ) noexcept -> bool
            { return sid < onSurfaceFlags.size() && onSurfaceFlags[sid] != 0; };

            // mirrors packCompose/packRoutes' own inSet membership test (serialize.h) verbatim, minus the
            // escaping/redaction/XmlWriter machinery — a COUNT, never a render, so it never touches redactCounts.
            std::size_t composeTotal = 0;
            for( const ComposeEdge& ce : g.composeEdges )
            {
                if( ce.ownerSym < ing.symbols.size() && ( isOnSurface( ce.ownerSym ) || isOnSurface( ce.typeSym ) ) )
                {
                    ++composeTotal;
                }
            }
            std::size_t routesTotal = 0;
            for( const RouteEdge& re : g.routeEdges )
            {
                if( isOnSurface( re.fromSym ) || isOnSurface( re.toSym ) )
                {
                    ++routesTotal;
                }
            }

            const int jsonRc = emitForLensJson( stdout,
                                                forLensJsonHeader( cfg.forTask, ForLensNotes{ routeNoteRaw, mentionNote, boostNote,
                                                                                              docMentionNote, adaptiveNote, forWeak } ),
                                                ForLensJsonInputs{ ing, lensRank, forTopN, fanInPtr, impurePtr, &forChurn,
                                                                   &forClone, testedPtr, ampPtr, redactPtr,
                                                                   cfg.packBudgetBytes, cfg.tokenBudget, notesPtr,
                                                                   legoTotal, composeTotal, routesTotal } );
            // §B0: this early return skipped the end-of-function tally below, so a --for --json run redacted
            // SILENTLY — the one stderr line that tells the user a secret was in their tree never appeared.
            reportRedactions( stderr, redactCounts );
            return jsonRc;
        }

        // H1: render lego + compose into memory first (they are independent of <sigs>), so the sigs
        // budget below is EXACT. open_memstream failure (ENOMEM-class) degrades to direct emission
        // after the sigs — same bytes, the budget just can't see the sibling blocks' size then.
        std::string legoStr, composeStr, routeStr, sigsStr;
        bool        legoPreRendered = false, composePreRendered = false, routePreRendered = false, sigsPreRendered = false;

        {
            char*       lbuf = nullptr;
            std::size_t lsz  = 0;
            if( std::FILE* lm = rw::openChargeBuffer( &lbuf, &lsz ) )
            {
                packLego( lm, ing, legoScoped, lensRank, 12, redactPtr, impurePtr, kNoNode, /*withPaths=*/true, flRootArg );
                std::fflush( lm );  std::fclose( lm );
                if( lbuf ) { legoStr.assign( lbuf, lsz );  std::free( lbuf ); }
                legoPreRendered = true;
            }
            else
            {
                DEGRADED_PATH_ALERT( "main: open_memstream failed for the lego block — budget will not see its size" );
            }
        }
        if( !g.composeEdges.empty() )
        {
            char*       cbuf = nullptr;
            std::size_t csz  = 0;
            if( std::FILE* cm = rw::openChargeBuffer( &cbuf, &csz ) )
            {
                packCompose( cm, ing, g.composeEdges, lensSurfaceIds );
                std::fflush( cm );  std::fclose( cm );
                if( cbuf ) { composeStr.assign( cbuf, csz );  std::free( cbuf ); }
                composePreRendered = true;
            }
            else
            {
                DEGRADED_PATH_ALERT( "main: open_memstream failed for the compose block — budget will not see its size" );
            }
        }
        else
        {
            composePreRendered = true;                                // nothing to emit
        }
        if( !g.routeEdges.empty() )
        {
            // B6.3: route view for the same relevant symbol set (top-N by lensRank)
            char*       rbuf = nullptr;
            std::size_t rsz  = 0;
            if( std::FILE* rm = rw::openChargeBuffer( &rbuf, &rsz ) )
            {
                packRoutes( rm, ing, g.routeEdges, lensSurfaceIds );
                std::fflush( rm );  std::fclose( rm );
                if( rbuf ) { routeStr.assign( rbuf, rsz );  std::free( rbuf ); }
                routePreRendered = true;
            }
            else
            {
                DEGRADED_PATH_ALERT( "main: open_memstream failed for the routes block — budget will not see its size" );
            }
        }
        else
        {
            routePreRendered = true;                                  // nothing to emit
        }

        // the bundle budget: default kForPayloadBudgetBytes; an explicit --token-budget beats it
        const std::size_t bundleBudget = cfg.tokenBudget > 0
            ? std::size_t( double( cfg.tokenBudget ) * rw::kMinBytesPerToken * rw::kBudgetHeadroom )
            : rw::kForPayloadBudgetBytes;
        // D2 (audit regressions, 2026-08-08): the adaptive note's own bytes are EXEMPT from the <sigs> trim
        // charge (headerStr contains adaptiveNote verbatim, so subtracting its size prices the header as the
        // plain run's). --adaptive's contract is that only its CUT changes the emitted set ("without it,
        // output is byte-identical"); charging the note made a NO-CUT (flat) query drop one <d> whenever the
        // corpus path length landed the trim boundary inside the note's ~110 B — adaptivecheck PHASE3's
        // "kept 40 of 40" header over a set one row short of the plain run's, i.e. a disclosed-inert mode
        // that was not inert. The note is still real bytes everywhere it matters downstream: est_tokens and
        // the ceiling ladder measure the emitted header, so nothing under-reports; only the global default
        // budget can overshoot, by at most the note (~0.5% of kForPayloadBudgetBytes), disclosed here.
        // T3: the bundle=auto legend's bytes are EXEMPT from the <sigs> trim charge, exactly like the
        // adaptive note above (the D2 precedent): the contract is that auto mode changes NOTHING about the
        // signatures — the same corpus/query/budget produces byte-identical <sigs> with and without
        // --signatures-only, in BOTH budget regimes. The legend is still real bytes downstream: under an
        // explicit --token-budget the whole auto surface (legend + root attribute + bodies) must fit the
        // leftover under the stated ceiling or is turned off entirely (see the auto block below), and
        // est_tokens always measures the emitted header.
        constexpr std::size_t kAutoAttrReserve = 48;   // ' bundle="auto" bodies="0" reason="no_candidates"' — the widest spelling
        const std::size_t autoLegendBytes = autoBundleMode ? kForAutoBundleLegend.size() : 0u;
        const std::size_t fixedBytes = headerStr.size() - adaptiveNote.size() - autoLegendBytes
                                     + legoStr.size() + composeStr.size() + routeStr.size() + 6;   // + "</ctx>"
        const std::size_t sigsBudget = bundleBudget > fixedBytes ? bundleBudget - fixedBytes : 1;   // ≥1: 0 would mean "no budget"

        // The two attributes SPLICED into the header AFTER the ceiling ladder has chosen a rung — est_tokens
        // (" est_tokens=\"NNNNNNNN\"", bounded well under 24 B: 8 digits covers ~100M tokens) and, when the
        // query scored weak, weak="1" (exactly 9 B). Neither exists yet at ladder time, so the ladder cannot
        // measure them and reserves them instead; both are EXACT-counted into est_tokens itself further down.
        // Seam-verifier LOW (2026-07-29) found the est_tokens half unpriced (a 3-budget-point window landed
        // ~15.5% past the bare ceiling with no over_ceiling label); CA4 verifier L2 found the weak="1" half the
        // same way, 9 bytes spliced in after the number that is supposed to describe them.
        constexpr std::size_t kEstTokensAttrReserve = 24;
        constexpr std::size_t kWeakAttrBytes        = 9;   // exactly ` weak="1"`
        const std::size_t     headerSpliceReserve   = kEstTokensAttrReserve + ( forWeak ? kWeakAttrBytes : 0u );

        // D10: --token-budget SHAPES this bundle (exit-0 trim) rather than gating it (exit-3 like the
        // default map/--query) — but the shaped result must still be checkable against the budget it shaped
        // against. <sigs> is now buffered too (same open_memstream pattern as lego/compose/routes above) so the
        // TRUE delivered byte count is known before the header is finalized; est_tokens="N" uses the same
        // mid-band content rate estimateTokens() uses for the default map (kBytesPerTokenDefault), not the
        // conservative kMinBytesPerToken the budget CEILING is sized with — this reports what was actually
        // produced, not the worst-case bound. open_memstream failure degrades to direct emission (no est_tokens
        // attribute — same as before this change; never a fabricated number).
        {
            char*       sbuf = nullptr;
            std::size_t ssz  = 0;
            if( std::FILE* sm = rw::openChargeBuffer( &sbuf, &ssz ) )
            {
                packSignatures( sm, ing, lensRank, forTopN, cfg.packBudgetBytes, true, fanInPtr, impurePtr, redactPtr,
                                &forChurn, &forClone, testedPtr, ampPtr,     // Q3: churn/clone/tested/amp folded onto the <d> blocks
                                /*rankAdaptivePayload=*/true,                // B0.3: tail entries excerpt-trimmed by global rank (serialize.h kForDoc*)
                                sigsBudget,                                  // H1: global payload budget (trim ladder; payload="capped" marker)
                                notesPtr,                                    // L3: field-notes surfacing (inert when null)
                                flRootArg );                                 // R-E: root-relative p=
                std::fflush( sm );  std::fclose( sm );
                if( sbuf ) { sigsStr.assign( sbuf, ssz );  std::free( sbuf ); }
                sigsPreRendered = true;
            }
            else
            {
                DEGRADED_PATH_ALERT( "main: open_memstream failed for the sigs block — est_tokens omitted from the header" );
            }
        }

        // §P3 × §P4: the budget trim above can drop files the lego scope still references — narrow the lego
        // block to the RENDERED sigs' files and re-render (a byte-subset of what the budget already charged
        // for, so the bundle only shrinks; before est_tokens so the header reports the delivered size).
        if( sigsPreRendered && legoPreRendered && !legoStr.empty()
            && narrowLegoToRenderedSigs( ing, legoScoped, sigsStr, flRootArg.empty() ? std::string_view() : rw::sarif::rootPrefixOf( flRootArg ) ) )
        {
            legoStr = captureXml( [ & ]( std::FILE* f ) { packLego( f, ing, legoScoped, lensRank, 12, redactPtr, impurePtr, kNoNode, /*withPaths=*/true, flRootArg ); } );
        }

        // ── §F1 (CA4 wave-1 verifier): the lens's LAST TWO payload sections, rendered and CHARGED here ──────
        // §H7 gave the default map the structural property "a section cannot be APPENDED without being
        // charged" — and this lens kept two sections outside it, emitted straight to stdout AFTER est_tokens
        // was already written: --detail=N bodies and --with-graph's mermaid block. MEASURED at the pause:
        // `--for --token-budget=2000 --detail=20` streamed 68 035 B against a 4 248 B allowance (16x) with
        // est_tokens="1674" unmoved and stderr empty, while the self-check that concluded "no bypass found"
        // was taken on the BARE --for — the one shape where both sections are absent. Both now go through
        // rw::chargeSection for the reason the map's four do: a section that renders through the funnel is
        // charged by construction, not by a second piece of code remembering to add it.
        //
        // ORDER HERE (not the emission order, which is unchanged: detail, then graph): the graph block has no
        // budget knob, so its size is a FIXED cost; the bodies are the one section with a byte budget, so they
        // are the section that absorbs whatever the ceiling has left. Pricing the fixed cost first is what lets
        // the bodies' budget be exact.
        rw::ChargedSection graphSection, detailSection;
        if( cfg.withGraph )
        {
            graphSection = rw::chargeSection( [ & ]( std::FILE* f ) { packGraphBlock( f, ing, lensRank, g.outOff, g.outTargets ); },
                                               rw::kBytesPerTokenDefault );
        }

        // both kept alive past the render so the isRendered=false degrade path below re-emits the SAME set at
        // the SAME budget (the map path's emitSection lambda has the identical contract)
        std::vector<NodeId> detailIds;
        std::size_t         detailBodyBudget = 0;

        // --detail=N (lever 3): importance-weighted detail — spend FULL bodies on only
        // the top-N ranked symbols (the head the rank identifies), leaving the rest as the signatures emitted
        // above. Measured +63% tokens for the 3 relevant heads vs +355% for all-bodies. N is clamped to the
        // emitted head (forTopN, already narrowed by --adaptive) so a body never references a symbol outside
        // the lens. N=0 emits nothing → byte-identical to a run without --detail.
        if( cfg.detail > 0 )
        {
            const std::size_t S = ing.symbols.size();
            detailIds.resize( S );
            for( NodeId i = 0; i < S; ++i )
            {
                detailIds[i] = i;
            }
            rw::sortutil::radixSortByScoreDescId( detailIds, lensRank );   // (score desc, id asc) — same order as the sigs
            const std::size_t detN = std::min<std::size_t>( { std::size_t( cfg.detail ), std::size_t( forTopN ), S } );
            detailIds.resize( detN );
            // Composes with --max-tokens: when set, it bounds the body byte budget (same conservative rate the
            // map path uses). §F1: --token-budget SHAPES this lens (D10 — trims to fit, always exit 0), so it
            // has to bound the bodies as well; before this it bounded <sigs> ONLY and the bodies rode along on
            // --pack-budget-bytes, which is how a 2 000-token budget delivered 68 KB. The bodies get whatever
            // the ceiling has left after the header, <sigs>, the sibling blocks, the graph block, the closing
            // tag and the two header attributes spliced in below — and never MORE than the budget they already
            // had, so a run WITHOUT --token-budget is byte-identical.
            detailBodyBudget = cfg.maxTokens > 0
                ? std::size_t( double( cfg.maxTokens ) * rw::kMinBytesPerToken * rw::kBudgetHeadroom )
                : cfg.packBudgetBytes;
            if( cfg.tokenBudget > 0 )
            {
                const std::size_t spentBytes = headerStr.size() + sigsStr.size() + legoStr.size() + composeStr.size()
                                             + routeStr.size() + graphSection.xml.size() + 6 + headerSpliceReserve;
                const std::size_t leftBytes  = bundleBudget > spentBytes ? bundleBudget - spentBytes : 1;
                detailBodyBudget = std::min( detailBodyBudget, leftBytes );
            }
            detailSection = rw::chargeSection( [ & ]( std::FILE* f )
                { packBodies( f, ing, detailIds, detailBodyBudget, g.outOff, g.outTargets, cfg.compress, redactPtr,
                              /*ranges=*/nullptr, notesPtr, /*outEmitted=*/nullptr, /*truncateOversizedFirst=*/true,
                              /*withFileContext=*/false, flRootArg ); },   // L3: --detail bodies surface notes too (part of the --for bundle)
                rw::kBytesPerTokenBody );
        }

        // ── T3: the terminal-by-default auto <bodies> section (pre-registered: docs/EVALS.md §4) ────────────
        // The decision + render live in buildForAutoBodies (above runForLens — this function is already one
        // of the largest in the file); this site only wires its verdict in: keep the section + attribute, or
        // rebuild the header WITHOUT the legend when the surface turned off (tight explicit ceiling, or the
        // chargeSection degrade), so the ladder's later rebuilds honor the decision too.
        rw::ChargedSection autoSection;
        std::string        autoAttr;   // spliced onto the <ctx> root after the ladder; its exact bytes are priced there
        if( autoBundleMode && sigsPreRendered )
        {
            // committed so far: the real header (legend included), the rendered sections, "</ctx>", and the
            // post-ladder splices (est_tokens/weak reserves + the root attribute's worst case, kAutoAttrReserve)
            const std::size_t committedBytes = headerStr.size() + sigsStr.size() + legoStr.size() + composeStr.size()
                                             + routeStr.size() + graphSection.xml.size() + 6 + headerSpliceReserve + kAutoAttrReserve;
            ForAutoBodiesResult autoBodies = buildForAutoBodies( cfg, ing, g, lensSurfaceIds, lensRank,
                                                                 committedBytes, bundleBudget, redactPtr );
            autoSection = std::move( autoBodies.section );
            autoAttr    = std::move( autoBodies.attr );
            if( autoBodies.surfaceOff )
            {
                headerParts.autoBundle = false;
                headerStr = buildForHeader( /*withRouteAttr=*/true, /*withTaskEcho=*/true, {} );
            }
        }

        // W3FIX H2 — the ceiling ladder (rungs + rationale: serialize.h climbCeilingLadder), same rungs in the
        // same order --pack-task climbs. The header IS charged to the budget above, but charging is not FITTING: at
        // an explicit --token-budget the header floor (fixed legend + the task echoed twice) can exceed the stated
        // ceiling by itself, sigsBudget then clamps to 1, and packSignatures' first-entry-whole floor still emits
        // ~1.5 KB — a silent 5.3x overrun on a 900-char task, against a --help that promises "trims to fit". Runs
        // BEFORE est_tokens so the estimate covers the disclosure; inert without an explicit --token-budget.
        if( cfg.tokenBudget > 0 && sigsPreRendered )
        {
            static constexpr rw::CeilingLadderNotes kNotes{
                " [task_echo: dropped (ceiling)]", " [task_echo + route_attr: dropped (ceiling)]",
                " [over_ceiling: the header floor (verbatim task echo + fixed legend) exceeds this budget"
                " - no payload left to trim]" };
            // §F1: the ladder prices what will actually be EMITTED, so the two sections charged above are in
            // this sum. headerSpliceReserve covers the est_tokens (and weak="1") attributes spliced in below —
            // see its definition for why a reserve rather than a measurement.
            headerStr = rw::climbCeilingLadder( buildForHeader, headerStr,
                                                 sigsStr.size() + legoStr.size() + composeStr.size() + routeStr.size()
                                                     + detailSection.xml.size() + autoSection.xml.size() + graphSection.xml.size()
                                                     + autoAttr.size() + 6 + headerSpliceReserve,   // + "</ctx>" + the header splices below (autoAttr exact-counted)
                                                 rw::ceilingAllowanceBytes( cfg.tokenBudget ),
                                                 /*hasRouteAttr=*/!routeNoteRaw.empty(), kNotes );
        }

        // T3: the bundle=auto disclosure attributes, spliced onto the <ctx> root AFTER the ladder (a rung
        // rebuild would lose an earlier splice — the same reason weak=/est_tokens= splice late). The literal
        // "><!--" boundary is unambiguous: escapeXml entity-escapes '<' inside attribute values, so the first
        // occurrence is the root element's own close. Spliced BEFORE est_tokens is computed, so the number
        // measures a header that already carries these bytes exactly.
        if( !autoAttr.empty() )
        {
            const std::size_t rootCloseAt = headerStr.find( "><!--" );
            if( rootCloseAt != std::string::npos )
            {
                headerStr.insert( rootCloseAt, autoAttr ); // else: unexpected shape, header left as-is (attr dropped, section still disclosed by its own element)
            }
        }

        // R4 + §L2: weak="1" — same insert-before-"-->" mechanism as est_tokens below, but unconditional on
        // sigsPreRendered (forWeak is known from lr.maxLexicalScore regardless of the sigs render path).
        // Absent entirely when the query cleared the threshold (never a fabricated "weak=0" — same
        // silence-means-fine convention as the other opt-in header notes above). It is spliced in AHEAD of
        // est_tokens now: it used to go in afterwards, i.e. 9 bytes of the document that the number describing
        // that document had not measured (CA4 verifier L2). Doing it first makes those 9 bytes part of
        // headerStr.size() below — an exact count, not a reserve.
        if( forWeak )
        {
            const std::size_t closeAt = headerStr.rfind( " -->" );
            if( closeAt != std::string::npos )
            {
                headerStr.insert( closeAt, " weak=\"1\"" ); // else: unexpected shape, header left as-is
            }
        }

        if( sigsPreRendered )
        {
            // §F1: every section this lens emits is in this sum — <sigs>, <lego>, <compose>, <routes>, the
            // --detail bodies and the --with-graph block — each from its own RENDERED bytes.
            //
            // SELF-REFERENCE (the §L2 mechanism generalized): the est_tokens attribute is part of the document
            // est_tokens measures, so its own digit string belongs inside the byte total. The previous form
            // summed the bundle WITHOUT it and reported ~8 tokens under, which is why the measured rate read
            // 2.51 B/tok where this emitter's rate is 2.50. Bounded 4-pass fixpoint, same shape and same bound
            // as serialize()'s and buildRecall's; the attribute BUILT last is the attribute inserted. WHAT THE
            // LOOP GUARANTEES: on convergence (the `break`, reached in <=2 passes on every shape measured) the
            // number stated is exactly the number the document's own bytes were measured against; on the bound
            // it is the number measured against a header whose est_tokens field differed by at most a digit or
            // two, i.e. a residual under one token — never a fabricated number.
            // EACH KIND OF BYTE AT ITS OWN RATE, summed exactly the way the map path sums
            // mapEstTokens + extraPayloadTokens: markup (header, <sigs>, <lego>, <compose>, <routes>, the
            // mermaid graph block) at the mid-band kBytesPerTokenDefault, and the --detail bodies at the
            // kBytesPerTokenBody rate chargeSection already charged them at, because def-body text BPE-merges
            // far more aggressively than signature markup. Converting the WHOLE bundle at the markup rate
            // would over-read the bodies by ~1.5x — the same "one number for two kinds of bytes" defect §H7
            // is about, aimed the other way, and it would report a --for --detail bundle at 2.50 B/tok when
            // its real shape is ~3.6.
            const std::size_t markupBytes = headerStr.size() + sigsStr.size() + legoStr.size() + composeStr.size()
                                          + routeStr.size() + graphSection.xml.size() + 6;   // + "</ctx>"
            const std::size_t bodyTokens  = detailSection.tokens + autoSection.tokens;   // T3: the auto bodies are charged at the body rate too
            std::size_t estTokens = rw::tokensForEmittedBytes( markupBytes, kBytesPerTokenDefault ) + bodyTokens;
            std::string attr      = " est_tokens=\"" + std::to_string( estTokens ) + "\"";
            for( int pass = 0; pass < 4; ++pass )
            {
                const std::size_t next = rw::tokensForEmittedBytes( markupBytes + attr.size(), kBytesPerTokenDefault ) + bodyTokens;
                if( next == estTokens )
                {
                    break;
                }
                estTokens = next;
                attr      = " est_tokens=\"" + std::to_string( estTokens ) + "\"";
            }
            const std::size_t closeAt = headerStr.rfind( " -->" );
            if( closeAt != std::string::npos )
            {
                headerStr.insert( closeAt, attr ); // else: unexpected shape, header left as-is
            }
        }

        std::fwrite( headerStr.data(), 1, headerStr.size(), stdout );
        if( sigsPreRendered )
        {
            std::fwrite( sigsStr.data(), 1, sigsStr.size(), stdout );
        }
        else
        {
            packSignatures( stdout, ing, lensRank, forTopN, cfg.packBudgetBytes, true, fanInPtr, impurePtr, redactPtr,
                            &forChurn, &forClone, testedPtr, ampPtr, /*rankAdaptivePayload=*/true, sigsBudget, notesPtr, flRootArg );
        }
        if( legoPreRendered )
        {
            std::fwrite( legoStr.data(), 1, legoStr.size(), stdout );
        }
        else
        {
            packLego( stdout, ing, legoScoped, lensRank, 12, redactPtr, impurePtr, kNoNode, /*withPaths=*/true, flRootArg ); // same scope+identity on the degrade path (§P3; un-narrowed — sigs bytes unknown here)
        }
        if( composePreRendered )
        {
            std::fwrite( composeStr.data(), 1, composeStr.size(), stdout );
        }
        else if( !g.composeEdges.empty() )
        {
            packCompose( stdout, ing, g.composeEdges, lensSurfaceIds );
        }
        if( routePreRendered )
        {
            std::fwrite( routeStr.data(), 1, routeStr.size(), stdout );
        }
        else if( !g.routeEdges.empty() )
        {
            packRoutes( stdout, ing, g.routeEdges, lensSurfaceIds );
        }

        // §F1: the last two sections, from the bytes already RENDERED and CHARGED above — so what the header
        // priced and what stdout receives are the same bytes by construction, not by two pieces of code
        // agreeing. The --detail bodies are ADDED after <sigs>/<lego>/<compose>/<routes>, so the rest of the
        // bundle keeps signatures-only. A section whose pre-render degraded (isRendered=false) is emitted here
        // directly at the SAME budget — uncharged for that one run, with an alert, never a fabricated number.
        if( cfg.detail > 0 )
        {
            rw::emitChargedSection( stdout, detailSection, [ & ]{ packBodies( stdout, ing, detailIds, detailBodyBudget, g.outOff, g.outTargets,
                                                                              cfg.compress, redactPtr, /*ranges=*/nullptr, notesPtr,
                                                                              /*outEmitted=*/nullptr, /*truncateOversizedFirst=*/true,
                                                                              /*withFileContext=*/false, flRootArg ); } );
        }
        else if( autoSection.isRendered && !autoSection.xml.empty() )
        {
            // T3: the auto <bodies> section — same slot as --detail's (after the signature-shaped sections, so
            // the rest of the bundle keeps its shape). Emitted from the exact bytes est_tokens charged; the
            // degrade path (isRendered=false) deliberately emits NOTHING — the pre-T3 bundle is the fallback
            // contract for this optional enrichment, unlike --detail's explicit request (see the block above).
            std::fwrite( autoSection.xml.data(), 1, autoSection.xml.size(), stdout );
        }

        // R8: --with-graph — a compact mermaid flowchart of the ranked bundle's anchor neighborhood,
        // right before </ctx>. Off by default (G5): omitted, this is a no-op and output is byte-identical.
        if( cfg.withGraph )
        {
            rw::emitChargedSection( stdout, graphSection, [ & ]{ packGraphBlock( stdout, ing, lensRank, g.outOff, g.outTargets ); } );
        }

        std::printf( "</ctx>" );
        reportRedactions( stderr, redactCounts );
        return 0;
    }
    return std::nullopt;
}

std::optional<int> runTargetedViews( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::vector<std::uint32_t>& fanIn        = d.fanIn;
    const QMetrics&                   qmetrics     = d.qmetrics;
    RedactCounts&                     redactCounts = d.redactCounts;
    RedactCounts*                     redactPtr    = d.redactPtr;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — shared
    // by --lego and --exemplar, both dispatched from this function.
    const bool             tvSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view tvRootArg    = tvSingleRoot ? cfg.roots[0] : std::string_view();
    const std::string      tvRootPrefix = tvSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();

    // --lego=TYPE: the TARGETED Lego view — resolve ONE named interface/base and emit its signature, full
    // method contract (where sound), and EVERY implementor (own-language only, via the langCompatible guard
    // in buildGraph) with p= file paths so the agent can open them. Same <lego> schema as --for; mirrors the
    // single-symbol verbs (--around/--expand). file:name disambiguates a same-named type across languages.
    if( !cfg.legoType.empty() )
    {
        const NodeId focus = resolveFocus( ing, cfg.legoType );
        if( focus == kNoNode )
        {
            // §B4.2: one shared refusal — a non-defining `file:name` says WHICH files define the type and
            // hands back a runnable retry; a genuinely unknown name still gets the near-miss it always had.
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --lego type not found: ",
                                                                   cfg.legoType, "--lego=" ).c_str() );
            return 1;
        }
        const std::vector<char> legoImpure = computeImpure( ing, g );
        const std::vector<float> flat( ing.symbols.size(), 0.f );   // single iface → rank is irrelevant (id tie-break)
        // R-E fix (2026-08-19): the document root DISCLOSES the root its p= are now relative to. The first
        // R-E landing made packLego's p= root-relative and left the root undisclosed, so a --lego bundle
        // carried relative paths against a root the reader could not name — the honesty rule this tool sells.
        std::printf( "%s", rw::ctxRootOpen( {}, {}, tvRootArg ).c_str() );
        packLego( stdout, ing, g.implementors, flat, 1, d.redactPtr, &legoImpure, focus, /*withPaths=*/true, tvRootArg );
        std::printf( "</ctx>" );
        reportRedactions( stderr, d.redactCounts );      // W3-N1: a contract <m> sig is a redacting seam — disclose the tally
        return 0;
    }

    // --exemplar=KIND|TASK (Q7): return the repo's BEST-IN-CLASS instance of what the agent is about to write
    // — same KIND, high fan-in, low cognitive complexity, tested — as an imitation target (signature + body).
    // Selection is by ROLE (kind + those metrics), a DETERMINISTIC composite sort with an id tie-break; it is
    // NEVER ranked by textual similarity to the query (similar-snippet retrieval measurably hurts).
    // The argument is either a kind token (fn|method|cls|class|struct|iface|var) or a TASK string whose top
    // lexical match's kind is used — one flag, two natural inputs, both resolving to a target kind by ROLE.
    // A3-F5: selection now enforces a hard ccx ceiling, a fixture-path penalty, and a task→kind confidence
    // floor — see exemplar.h for the three invariants; this block only RESOLVES the input and EMITS the pick.
    if( !cfg.exemplar.empty() )
    {
        const ExemplarPick pick = selectExemplar( ing, g, fanIn, qmetrics.tested, cfg.exemplar );

        if( pick.winner == kNoNode )
        {
            if( pick.targetKind == SymKind::Other )
            { // task string matched nothing lexical at all
                std::fprintf( stderr, "ripwire: --exemplar: no symbol matches '%.*s'\n", int( cfg.exemplar.size() ), cfg.exemplar.data() );
            }
            else
            {
                std::fprintf( stderr, "ripwire: --exemplar: no %s in the corpus to exemplify\n", symTag( pick.targetKind ) );
            }
            return 1;   // no-candidate case degrades cleanly (clear message, nonzero exit, no crash)
        }

        // emit: a self-describing header (why THIS one), the winner's signature+body via packBodies. Extra
        // attributes surface the A3-F5 degrade paths honestly: low_confidence (weak task→kind fell back to fn)
        // and over_ccx_bar (nothing was under the complexity ceiling — the pick is the least-bad, not clean).
        const auto fin = [ & ]( NodeId i ) -> std::uint32_t { return ( i < fanIn.size() ) ? fanIn[i] : 0u; };
        const auto ts  = [ & ]( NodeId i ) -> std::uint8_t  { return ( i < qmetrics.tested.size() ) ? qmetrics.tested[i] : std::uint8_t( 0 ); };
        const Symbol&     wsym = ing.symbols[ pick.winner ];
        std::vector<char> esc;
        const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // G4: collapse '--' runs so the comment can't terminate early. W3FIX M3: escapeXml below already kept
        // C0/invalid-UTF-8 out, but a '\n' in the task is a LEGAL XML char that escapeXml passed through, so
        // `--exemplar=$'a\nb'` emitted a raw newline outside CDATA. xmlCommentText is the shared scrub (it runs
        // BEFORE ex(), so entity escaping is unchanged and control-free input stays byte-identical).
        const std::string reqNote = xmlCommentText( cfg.exemplar );
        const std::string kindNote = pick.fromTask ? ( " (task -> kind=" + std::string( symTag( pick.targetKind ) )
                                                       + ( pick.lowConfidence ? ", low-confidence: weak match, fell back to fn" : "" ) + ")" )
                                                    : std::string();   // stable storage for %s
        // §B6 M13: the rule is exemplar.h's kExemplarSelectionRule, RENDERED — this legend used to lead with
        // complexity while the composite leads with the fixture penalty, and the MCP twin said a third thing.
        // §B7.9 (CA4): the root element carries in=, ccx= and (conditionally) tested=, and this legend
        // defined candidates=, low_confidence= and over_ccx_bar= but not those three — the three that are
        // the SELECTION EVIDENCE the sentence above claims to be showing ("tested before untested, higher
        // fan-in, lower complexity" is the rule; in=/ccx=/tested= are its inputs, unreadable without a gloss).
        // tested= is absence-meaningful and says so, per the house rule for an omitted-not-zero attribute.
        // The truncation-trio clause closes the four baseline lines this verb held (bodies@shown/total/capped
        // + calls@total, the "cheapest bulk win" shape the baseline header names) — packBodies emits both
        // children, and calls@total only surfaces when the winner has callees, so the gap was tree-dependent.
        std::printf( "<!-- ripwire exemplar for \"%s\"%s: the repo's best-in-class %s to imitate — %s. "
                     "On the root, the three attributes that ARE that ordering's evidence: in=reuse-count "
                     "(callers), ccx=cognitive complexity, tested=1 when a test reaches it (OMITTED, never 0, "
                     "when none does). The body follows in a bodies section, its callee signatures in a calls "
                     "child; both disclose truncation the house way: total= is how many qualified, shown= how "
                     "many are printed, capped=1 when the two differ (calls omits shown= and capped= when its "
                     "list is complete). Copy its shape, not its text. -->",
                     ex( reqNote ).c_str(), kindNote.c_str(), symTag( pick.targetKind ), rw::kExemplarSelectionRule );
        // R-E fix (2026-08-19): root= — same reason as --lego above. p= went root-relative in the first R-E
        // landing with no attribute naming the root, on the one verb whose whole job is "open this file".
        const std::string exemplarRootAttr = tvSingleRoot ? ( " root=\"" + ex( tvRootArg ) + "\"" ) : std::string();
        std::printf( "<exemplar kind=\"%s\" candidates=\"%zu\" n=\"%s\" p=\"%s:%u\" in=\"%u\" ccx=\"%u\"%s%s%s%s>",
                     symTag( pick.targetKind ), pick.candidateCount, ex( wsym.name ).c_str(),
                     ex( tvSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ wsym.fileId ], tvRootPrefix ) : std::string_view( ing.files[ wsym.fileId ] ) ).c_str(), wsym.line,
                     fin( pick.winner ), wsym.ccx, exemplarRootAttr.c_str(), ts( pick.winner ) ? " tested=\"1\"" : "",
                     pick.lowConfidence ? " low_confidence=\"1\"" : "",
                     pick.overCcxBar    ? " over_ccx_bar=\"1\"" : "" );
        packBodies( stdout, ing, { pick.winner }, cfg.packBudgetBytes, g.outOff, g.outTargets, cfg.compress, redactPtr,
                   /*ranges=*/nullptr, /*noteIndex=*/nullptr, /*outEmitted=*/nullptr, /*truncateOversizedFirst=*/true,
                   /*withFileContext=*/false, tvRootArg );
        std::printf( "</exemplar>" );
        reportRedactions( stderr, redactCounts );
        return 0;
    }

    // --recall=TASK: retrieve the most relevant DOCUMENTS (memory notes / design docs) for a task and emit
    // their FULL bodies, token-budgeted — the memory-as-graph recall verb (pull the relevant few, not the
    // whole corpus). Same deterministic lexical ranking as --for; relatedness is lexical, not graph (eval).
    if( !cfg.recall.empty() )
    {
        // §P2 — the two budget flags obey the documented two-personality rule (D10): --max-tokens SHAPES (byte
        // ceiling at the map family's densest rate × headroom — the old ×4 B/tok overshot ~85×), --token-budget
        // GATES inside emitRecallBudgeted (exit 3, header line only — never the artifact it rejected).
        // pathFieldDefaultW=1: the recall lens ranks DOCS, where the filename often IS the answer's name
        // ("readme", "report", "paired_table") — measured by bench/recalleval (gate: recallevalcheck.sh).
        const std::vector<float> rscore = lexicalScores( ing, g.outOff, g.outTargets, cfg.recall, 0, nullptr, 1 );
        const std::size_t        budget = cfg.maxTokens > 0 ? std::size_t( double( cfg.maxTokens ) * rw::kMinBytesPerToken * rw::kBudgetHeadroom ) : 0;
        // §B2: --top-k=N now actually SHAPES how many docs recall emits (was accept-and-ignore — --help and
        // the --limit refusal both already promised this). Default stays 8 when the user never passed the flag.
        const int                 recallK = cfg.topKExplicit ? cfg.topK : 8;
        const RecallBundle       bundle = buildRecall( ing, rscore, cfg.recall, recallK, budget, true, redactPtr );   // docs (markdown) only — notes/plans/designs, not code
        const int                rc     = emitRecallBudgeted( stdout, bundle, cfg.tokenBudget );
        reportRedactions( stderr, redactCounts );
        return rc;
    }
    return std::nullopt;
}

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

// THE per-file churn mining every churn-consuming verb shares: one window, one multi-root merge rule, one
// definition of "git could not be mined at all" (false ⇒ every caller must report UNAVAILABLE rather than
// treat an all-zero vector as "nothing changed"). Extracted from the --hotspots block when --ensemble became
// its second caller — a second copy of a 20-line per-root merge loop is exactly the clone --quality-delta
// flags, and it is also how the two verbs' windows would silently diverge one round from now.
// `since`/`rootScope`: the single-root path uses the caller's ALREADY-RESOLVED scope (so --hotspots does not
// resolve it twice); the multi-root path resolves per root, because a revision is only meaningful inside the
// repository that contains it. An empty `since` means "the default window", exactly as before.
bool mineChurnPerFile( const rw::IngestResult& ing, const std::string& root, bool multiRoot,
                       const std::vector<rw::WorkspaceRoot>& ws, std::string_view since,
                       const rw::SinceScope& rootScope, const char* defaultWindow, std::vector<std::uint32_t>& churn )
{
    if( !multiRoot )
    {
        return gitChurnCounts( root, ing, churn, defaultWindow, since.empty() ? nullptr : &rootScope );
    }
    // §5: churn mined per root against that root's files only; merged into one labeled list below.
    bool churnOk = false;
    for( std::uint32_t r = 0; r < ws.size(); ++r )
    {
        const rw::SinceScope       perRootScope = rw::resolveSinceScope( ws[r].arg, since );
        std::vector<std::uint32_t> rootChurn( ing.files.size(), 0 );
        if( !gitChurnCounts( ws[r].arg, ing, rootChurn, defaultWindow, since.empty() ? nullptr : &perRootScope, r ) )
        {
            continue;
        }
        churnOk = true;
        for( std::size_t f = 0; f < churn.size(); ++f )
        {
            churn[f] += rootChurn[f];
        }
    }
    return churnOk;
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

// The exit-1 "nothing to compare against" wording for --quality-delta, in one place. Three cases, and the
// distinction is what the w1 verifier caught: saying "no <file>" is TRUE only in the third. A stale sidecar DID
// exist — either it was just dropped by the self-heal, or the unlink failed and it is sitting there right now —
// and `sel.isStaleFileOnDisk()` (the seam's DISK fact, never the removeStaleFile intent) picks which. The
// stale halves mirror the MCP twin's errMsg in mcpverbs.h::computeQualityDelta, per-arm verbs aside; keeping
// this out of runQualityDelta keeps three branches out of a body that is already the file's largest.
std::string noBaselineFatalMessage( const std::string& baselineFile, const rw::quality::BaselineSelection& sel )
{
    // §B12.4 (CA4): the non-stale arm named only the missing sidecar and left out the OTHER half of the
    // condition it is reporting — this message is reached only when the git-HEAD fallback was attempted and
    // ALSO came back empty. Its MCP twin (mcpverbs.h::computeQualityDelta, the "and no git HEAD to
    // auto-compare against" errMsg) has always carried both halves for the identical state, so a CLI reader
    // could not tell the fallback had even been tried and would look for a bug in the sidecar. Same two
    // clauses, same order, same verb-name spelling convention as the stale arms below.
    if( !sel.isSidecarStale() )
    {
        return "ripwire: no " + baselineFile + " and no git HEAD to auto-compare against — run `ripwire <dir> --quality-baseline` BEFORE the change you want to measure\n";
    }

    return "ripwire: " + baselineFile + " was STALE (pinned at a different HEAD) and there is no current HEAD tree to fall back to — "
         + ( sel.isStaleFileOnDisk() ? "it is still on disk (could not be removed): delete it, or re-run `ripwire <dir> --quality-baseline` to re-pin it\n"
                                     : "it has been removed: re-run `ripwire <dir> --quality-baseline` BEFORE the change you want to measure\n" );
}

// ── R-I: --quality-delta=A..B, the WAVE-level form ───────────────────────────────────────────────────────
//
// The state two COMMITTED trees need, with the temp-dir teardown bound to the caller's scope. Both trees stay
// alive together on purpose: computeSnapshot reads A while computeDelta reads B, and both read file bytes
// through their materialized tree, so neither guard may fire early (quality::loadRefTree's header states the
// same contract from the other side).
//
// `sameRef` is the A==B case. It is a legal question with an empty answer, and it is answered by materializing
// ONE tree and comparing it with itself rather than by a special-cased early return: the empty delta then
// falls out of the ordinary machinery instead of being asserted by a branch nobody re-tests.
struct RefPairDelta
{
    rw::quality::TmpTreeGuard baseGuard;             // declared BEFORE the trees so teardown outlives their use
    rw::quality::TmpTreeGuard targetGuard;
    rw::quality::RefTree      baseTree;
    rw::quality::RefTree      targetTree;
    bool                  sameRef = false;
    std::string           attrs;                     // XML:  ` base_ref="…" target_ref="…" churn="unavailable"`
    std::string           jsonAttrs;                 // JSON: the SAME three facts — built beside attrs so the
                                                     // two emitters cannot disclose different things

    const rw::quality::RefTree& target() const noexcept { return sameRef ? baseTree : targetTree; }
};

// Resolve the spec and materialize both sides. Returns an EXIT CODE on any refusal or environment failure
// (already reported on stderr), or nullopt when `out` is ready to compare. Splitting user error from
// environment failure is the same line --dmm's handler draws: a revision that does not resolve is a typo the
// caller can fix, everything else is the machine.
std::optional<int> loadRefPairDelta( const std::string& root, std::string_view spec, const rw::Config& cfg, RefPairDelta& out )
{
    using namespace rw;

    const quality::RefSpec ref = quality::resolveRefSpec( root, spec );
    switch( ref.status )
    {
        case quality::RefSpecStatus::BadRev:
            // The did-you-mean here cannot be a spelling neighbourhood — git already owns the ref namespace and
            // has no cheap enumeration of it — so the adjacent help names the PROBE and the three causes that
            // actually produce this on an agent's machine, which is more use than a guessed nearest ref.
            std::fprintf( stderr, "ripwire: --quality-delta: '%s' does not resolve to a commit in %s\n"
                                  "  check it with `git -C %s rev-parse --verify %s^{commit}`; the usual causes are a typo, a ref that\n"
                                  "  lives only on a remote you have not fetched, or a shallow clone whose history stops before it\n",
                          ref.badToken.c_str(), root.c_str(), root.c_str(), ref.badToken.c_str() );
            return 1;
        case quality::RefSpecStatus::BadRange:
            std::fprintf( stderr, "ripwire: --quality-delta: '%s' uses the three-dot form; this compares two TREES, so spell it A..B "
                                  "(or --quality-delta=$(git merge-base A B)..B if the merge base is what you meant)\n", ref.badToken.c_str() );
            return 1;
        case quality::RefSpecStatus::NoGit:
        case quality::RefSpecStatus::NoParent:
            // Environment, not a typo — and unlike --dmm (a measurement that reports UNAVAILABLE and exits 0)
            // this verb has nothing to report at all, so it takes the same exit 1 the bare form's
            // "nothing to compare against" path takes.
            std::fprintf( stderr, "ripwire: --quality-delta=%.*s: %s\n", int( spec.size() ), spec.data(), ref.reason.c_str() );
            return 1;
        case quality::RefSpecStatus::Ok:
            break;
    }
    // resolveRefSpec only reports Ok for the working-tree form on an EMPTY spec, which the flag table refuses
    // before it reaches here; the guard is belt-and-braces so a future grammar change cannot silently compare
    // a materialized tree against a working tree whose keys are spelled against a different root.
    if( ref.targetIsWorkingTree || ref.baseSha.empty() || ref.targetSha.empty() )
    {
        std::fprintf( stderr, "ripwire: --quality-delta needs TWO commits (A..B); use the bare --quality-delta for the working tree\n" );
        return 1;
    }

    // DISTINCT tags — see quality::loadRefTree's header. Sharing one would make the target's extraction
    // delete the base tree out from under the clone detector, which reads file bytes off disk.
    out.sameRef = ( ref.baseSha == ref.targetSha );
    if( !quality::loadRefTree( root, ref.baseSha, cfg.excludes, cfg.maxFileBytes, "qdpair-base", out.baseGuard, out.baseTree ) )
    {
        std::fprintf( stderr, "ripwire: --quality-delta: could not materialize or parse the tree at %s\n", ref.baseSha.c_str() );
        return 1;
    }
    if( !out.sameRef && !quality::loadRefTree( root, ref.targetSha, cfg.excludes, cfg.maxFileBytes, "qdpair-target", out.targetGuard, out.targetTree ) )
    {
        std::fprintf( stderr, "ripwire: --quality-delta: could not materialize or parse the tree at %s\n", ref.targetSha.c_str() );
        return 1;
    }

    // Both values are bare 40-char object names straight out of `rev-parse --verify` (resolveRefSpec accepts
    // nothing else), so they carry no XML-significant byte and are spliced rather than escaped — the same
    // reasoning gitstamp::atAttr states for its own hex value.
    out.attrs     = " base_ref=\"" + ref.baseSha + "\" target_ref=\"" + ref.targetSha + "\" churn=\"unavailable\"";
    out.jsonAttrs = ",\"base_ref\":\"" + ref.baseSha + "\",\"target_ref\":\"" + ref.targetSha + "\",\"churn\":\"unavailable\"";
    return std::nullopt;
}

// WHAT this delta is measured AGAINST, and on WHICH tree — the one place --quality-delta decides that.
// Extracted from runQualityDelta when the ref-pair form landed: floor selection was previously a single
// straight-line arm inside that body, and adding a second, differently-shaped floor turned it into the kind
// of branch pile the verb itself measures (runQualityDelta's own complexity crossed the bar on this lane's
// --quality-delta before this extraction). Everything downstream — acks, counters, both emitters, the exit
// code — reads these three fields and does not care which floor produced them.
//
// `deltaRoot` is WHICH SIDE was judged, and every root-relative key and displayed symbol downstream is
// spelled against it rather than against the repo root. In the ref-pair form the judged tree is a
// materialized temp dir: its keys must match the floor tree's key-for-key (S2), and its PID-suffixed path
// must never reach stdout — a temp path in the output would make two runs of the same comparison differ
// byte for byte, which is a determinism bug even when every finding is correct.
struct DeltaBasis
{
    rw::quality::BaselineSelection       baseSel;
    std::vector<rw::quality::Regression> regs;
    std::string                          deltaRoot;   // see above — NOT interchangeable with the repo root
};

// Returns an EXIT CODE when there is nothing to compare against (already reported), nullopt when `out` holds
// a usable comparison. `refs` is the CALLER's because it owns the materialized trees' teardown, and those
// trees must outlive every read of `out.regs`.
std::optional<int> resolveDeltaBasis( const MainDispatch& d, const std::string& baselineFile,
                                      RefPairDelta& refs, DeltaBasis& out )
{
    using namespace rw;
    const Config&       cfg  = d.cfg;
    const std::string&  root = d.root;

    // ── the REF-PAIR floor: two COMMITTED trees, neither of them the working tree ─────────────────────────
    if( !cfg.qualityDeltaRange.empty() )
    {
        if( const std::optional<int> refused = loadRefPairDelta( root, cfg.qualityDeltaRange, cfg, refs ) )
        {
            return refused;
        }
        // No sidecar is read, written or DELETED by this form. Deliberate, and disclosed in --help: the
        // sidecar's whole contract is "pinned at the current HEAD", which says nothing about a pair of
        // arbitrary commits — and the bare form's self-heal deleting a user's pinned floor as a side effect
        // of a wave-level measurement would be a side effect nobody asked for.
        out.baseSel.snapshot = quality::computeSnapshot( refs.baseTree.ing, refs.baseTree.g, refs.baseTree.root );
        out.baseSel.marker   = "ref-pair";
        out.deltaRoot        = refs.target().root;
        out.regs             = quality::computeDelta( refs.target().ing, refs.target().g, out.baseSel.snapshot,
                                                      out.deltaRoot, cfg.excludes, cfg.maxFileBytes );
        return std::nullopt;
    }

    // ── the WORKING-TREE floors, unchanged ───────────────────────────────────────────────────────────────
    // Precedence: (1) an explicit `.ripwire_quality_baseline` sidecar (from --quality-baseline) wins whenever
    // it is pinned at the CURRENT HEAD — the mid-task convergence loop (baseline once, edit, re-check) is
    // unchanged; (2) else — no sidecar, or a STALE one (see R3 below) — if the root is a git repo with a HEAD
    // tree, auto-baseline against HEAD so the "before I push" loop works with no start-of-task ritual (T0.1);
    // (3) else degrade to the exit-1 "run --quality-baseline first" guidance (non-git / unborn /
    // detached-no-tree — unchanged).
    //
    // STALENESS + the self-heal live in ONE place, quality::selectBaseline — R3 owner ruling (2026-07-29): a
    // sidecar whose pinned sha != the CURRENT HEAD sha is STALE, full stop. The B10.1b "reachable ancestor is
    // a deliberately-pinned floor" carve-out this arm used to apply (gitIsAncestor) is REVOKED: a parallel
    // session's sidecar pinned at a commit that merely happened to be an ancestor of this session's HEAD made
    // THIS arm report 31 phantom regressions while the MCP quality_delta verb — same binary, same repo, same
    // second — correctly reported zero. That divergence was only possible because each arm carried its own
    // copy of the test; there is now exactly one, in quality.h.
    //
    // What remains this arm's own POLICY is the `removeStaleFile=true` argument: the stale sidecar is silently
    // UNLINKED (best-effort) so the NEXT run sees no file at all rather than rediscovering the same dead pin,
    // and the ONLY record is the `baseline=` XML attribute ("git-HEAD (stale sidecar removed)") — no stderr
    // spam, which is the B10.1b noise fix that survives the ruling intact. The read-only MCP arm passes false
    // and reports "…ignored" instead. When the unlink FAILS (read-only parent dir) this arm degrades to the
    // read-only story — marker "…ignored", one DEGRADED_PATH_ALERT from the seam — because the pin is still
    // on disk; `isStaleFileOnDisk()` is the fact, and the fatal message words itself from it, not the intent.
    out.deltaRoot = std::string( cfg.rootPath );
    out.baseSel   = quality::selectBaseline( root, baselineFile, /*removeStaleFile=*/true );
    if( !out.baseSel.isSidecarHonored() )
    {
        auto [ headSnap, ok ] = computeHeadSnapshot( root, nullptr, cfg.maxFileBytes, cfg.excludes );
        if( !ok )
        {
            // w1 MED: this used to say "no <file>" in BOTH cases — factually false when the file is a STALE
            // sidecar that was just dropped, and doubly so when the self-heal unlink FAILED and the thing is
            // still sitting on disk. The stale-aware wording (and the MCP twin it mirrors) lives in
            // noBaselineFatalMessage above. Exit code is unchanged (1) in every branch.
            std::fputs( noBaselineFatalMessage( baselineFile, out.baseSel ).c_str(), stderr );
            return 1;
        }
        out.baseSel.snapshot = std::move( headSnap );
        if( !out.baseSel.isSidecarStale() )
        { // the stale/healed case is silent by design — only the true "never baselined" case is informative
            std::fprintf( stderr, "ripwire: no %s — auto-comparing the working tree vs git HEAD (commit the baseline with --quality-baseline to pin it)\n",
                          baselineFile.c_str() );
        }
    }
    out.regs = quality::computeDelta( d.ing, d.g, out.baseSel.snapshot, cfg.rootPath, cfg.excludes, cfg.maxFileBytes );
    return std::nullopt;
}

// runQualityViews was NOT a dispatch chain — it held two
// branches, one of which was 298 lines. That one body is now runQualityDelta below; the residual
// runQualityViews keeps only --dead-code. ONE extraction, verbatim: the 298-line body is unsplit, because
// its interior is a sequential pipeline over shared locals, not independent arms.
std::optional<int> runQualityDelta( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::string&                root         = d.root;

    // --quality-baseline / --quality-delta (the convergence-loop oracle): snapshot ccx + clone groups + dead
    // candidates to .ripwire_quality_baseline; then report ONLY what a change made WORSE vs it. The "delta not
    // absolute" discipline — a refine loop targets the regression it introduced, not absolute numbers (the
    // defense against metric-gaming). exit 2 if any new debt, like --arch.
    if( cfg.qualityBaseline || cfg.qualityDelta )
    {
        // D1 fix (HIGH): resolve BOTH sidecars against the analyzed ROOT, not the process CWD —
        // see quality::rootQualifiedSidecar's comment for why a bare relative filename is unsafe here
        // (a foreign cwd's sidecar could be silently rewritten, or even deleted by the stale-baseline
        // self-heal below). Computed once; every read/write/remove site in this block uses it.
        const std::string baselineFile = quality::baselinePath( root );
        const std::string acksFile     = quality::acksPath( root );

        if( cfg.qualityBaseline )
        {
            const bool wrote = quality::writeBaseline( quality::computeSnapshot( ing, g, cfg.rootPath ), baselineFile, gitHeadSha( root ) );
            std::fprintf( stderr, wrote ? "ripwire: wrote %s (snapshot of %zu symbols)\n" : "ripwire: could not write %s\n",
                          baselineFile.c_str(), ing.symbols.size() );
            return wrote ? 0 : 1;
        }

        // Precedence for the baseline: (1) an explicit `.ripwire_quality_baseline` sidecar (from
        // --quality-baseline) wins whenever it is pinned at the CURRENT HEAD — the mid-task convergence loop
        // (baseline once, edit, re-check) is unchanged; (2) else — no sidecar, or a STALE one (see R3 below) —
        // if the root is a git repo with a HEAD tree, auto-baseline against HEAD so the "before I push" loop
        // works with no start-of-task ritual (T0.1); (3) else degrade to the exit-1 "run --quality-baseline
        // first" guidance (non-git / unborn / detached-no-tree — unchanged).
        //
        // STALENESS + the self-heal now live in ONE place, quality::selectBaseline — R3 owner ruling
        // (2026-07-29): a sidecar whose pinned sha != the CURRENT HEAD sha is STALE, full stop. The B10.1b
        // "reachable ancestor is a deliberately-pinned floor" carve-out this arm used to apply (gitIsAncestor)
        // is REVOKED: a parallel session's sidecar pinned at a commit that merely happened to be an ancestor of
        // this session's HEAD made THIS arm report 31 phantom regressions while the MCP quality_delta verb —
        // same binary, same repo, same second — correctly reported zero. That divergence was only possible
        // because each arm carried its own copy of the test; there is now exactly one, in quality.h.
        //
        // What remains this arm's own POLICY is the `removeStaleFile=true` argument: the stale sidecar is
        // silently UNLINKED (best-effort) so the NEXT run sees no file at all rather than rediscovering the
        // same dead pin, and the ONLY record is the `baseline=` XML attribute ("git-HEAD (stale sidecar
        // removed)") — no stderr spam, which is the B10.1b noise fix that survives the ruling intact. The
        // read-only MCP arm passes false and reports "…ignored" instead. When the unlink FAILS (read-only
        // parent dir) this arm degrades to the read-only story — marker "…ignored", one DEGRADED_PATH_ALERT
        // from the seam — because the pin is still on disk; `baseSel.isStaleFileOnDisk()` is the fact, and the
        // fatal message below words itself from it rather than from the intent.
        // `refs` is declared HERE because it owns both materialized trees' teardown and they must outlive
        // every read of `regs` (DeltaBasis's header states that rule, and why the emitters below spell every
        // path and symbol against basis.deltaRoot rather than against `root`).
        const bool   refPair = !cfg.qualityDeltaRange.empty();
        RefPairDelta refs;
        DeltaBasis   basis;
        if( const std::optional<int> refused = resolveDeltaBasis( d, baselineFile, refs, basis ) )
        {
            return *refused;
        }
        const quality::BaselineSelection& baseSel   = basis.baseSel;
        const std::string&                deltaRoot = basis.deltaRoot;
        std::vector<quality::Regression>&  regs     = basis.regs;

        // Signal-to-noise round — the per-finding ACK RATCHET. Suppress findings already accepted (with a
        // reason) in .ripwire_quality_acks, honestly (acked="N"); a finding that WORSENED past its acked
        // magnitude survives the filter and reappears. --quality-ack merges the currently-VISIBLE findings
        // into that file instead of printing the report (accepting what previous acks already hid would be
        // a silent blanket ack — only what the agent can see right now is what it can accept).
        gtl::btree_map<std::string, quality::AckRecord> acks = quality::readAckRecords( acksFile );
        const std::size_t ackedCount = quality::applyAckRatchet( regs, acks );
        if( cfg.qualityAck )
        {
            // --ack-only=SUBSTR[,SUBSTR]: ack a SUBSET instead of everything on screen. Without it, the only
            // way to accept one deliberate contract change was to accept the whole report — which is how a
            // ratchet quietly becomes a rubber stamp. A finding matches if a substring occurs in its kind or
            // in its canonical id (so "api-surface", "src/quality.h", or one exact id all work).
            const auto ackSelected = [ & ]( const quality::Regression& r ) -> bool
            {
                if( cfg.qualityAckOnly.empty() )
                {
                    return true;
                }
                std::string_view rest = cfg.qualityAckOnly;
                while( !rest.empty() )
                {
                    const std::size_t     comma = rest.find( ',' );
                    const std::string_view pat  = rest.substr( 0, comma );
                    // kind, canonical id, or FACET. The facet is what makes this precise enough to be honest:
                    // "api-surface" also covers the never-gating new-symbol rows, so acking by kind would
                    // sweep in 59 findings to accept 8. --ack-only=contract-change accepts exactly the
                    // deliberate ones. The pseudo-token "gating" selects whatever would actually exit 2.
                    const bool gates = !r.isMinor && !r.isNewSymbol;
                    if( !pat.empty() && ( r.kind.find( pat ) != std::string::npos || r.sym.find( pat ) != std::string::npos || ( !r.facet.empty() && r.facet.find( pat ) != std::string::npos ) || ( pat == "gating" && gates ) ) )
                    {
                        return true;
                    }
                    if( comma == std::string_view::npos )
                    {
                        break;
                    }
                    rest = rest.substr( comma + 1 );
                }
                return false;
            };

            std::size_t ackWritten = 0, ackSkipped = 0;
            for( const quality::Regression& r : regs )
            {
                if( !ackSelected( r ) ) { ++ackSkipped;  continue; }
                ++ackWritten;
                // P0.3: the ack IDENTITY is ackKindToken, not the bare kind — a zero-magnitude finding
                // (was==now==0: dead-code, api-surface tier A) acks per ORIGIN, so acking the never-gating
                // new-symbol row can no longer blank-check the gating contract-change row on the same symbol.
                const std::string   ackKind = quality::ackKindToken( r );
                quality::AckRecord& rec     = acks[ quality::ackMapKey( ackKind, r.key ) ];
                rec = quality::AckRecord{ ackKind, r.key, std::max( rec.ackNow, r.now ),
                                          cfg.qualityAckReason.empty() ? rec.reason : std::string( cfg.qualityAckReason ) };
            }
            if( ackWritten == 0 && !cfg.qualityAckOnly.empty() )
            {
                std::fprintf( stderr, "ripwire: --ack-only=%.*s matched none of the %zu finding(s) — nothing written\n",
                              int( cfg.qualityAckOnly.size() ), cfg.qualityAckOnly.data(), regs.size() );
                return 1;
            }
            const bool wroteAcks = quality::writeAckRecords( acksFile, acks );
            if( wroteAcks && !cfg.qualityAckOnly.empty() )
            {
                std::fprintf( stderr, "ripwire: acknowledged %zu of %zu finding(s) (%zu left UNACKED by --ack-only, %zu already acked) → %s\n",
                              ackWritten, regs.size(), ackSkipped, ackedCount, acksFile.c_str() );
            }
            else if( wroteAcks )
            {
                std::fprintf( stderr, "ripwire: acknowledged %zu finding(s) (%zu already acked) → %s\n",
                              regs.size(), ackedCount, acksFile.c_str() );
            }
            else
            {
                std::fprintf( stderr, "ripwire: could not write %s\n", acksFile.c_str() );
            }
            return wroteAcks ? 0 : 1;
        }

        // L2 — stale-ack disclosure (rationale: quality.h's computeStaleAcks). Checked against the CURRENT
        // tree, not the baseline above, so it costs one more computeSnapshot; skipped when the ledger is
        // empty. Reported, never gated — the exit code below reads `regs` alone.
        // R-I: "the CURRENT tree" is the JUDGED tree, which in the ref-pair form is tree B — checking the
        // ledger against the working tree there would report acks as stale because of edits that have nothing
        // to do with the comparison being made.
        const std::vector<quality::StaleAck> staleAcks = acks.empty() ? std::vector<quality::StaleAck>{}
                                                         : quality::computeStaleAcks( acks, refPair
                                                             ? quality::computeSnapshot( refs.target().ing, refs.target().g, refs.target().root )
                                                             : quality::computeSnapshot( ing, g, cfg.rootPath ) );

        // r26 ORIGIN SPLIT — three counts over the VISIBLE (post-ack) findings, one pass:
        //   minorCount      — the materiality tier (unchanged axis).
        //   newSymbolCount  — findings that exist only because the code is NEW (quality.h's origin axis).
        //   gatingCount     — the EXIT PREDICATE: preexisting-worse AND major. Emitted as gating= so the
        //                     header alone tells you the exit code (it used to be "regressions > minor").
        // preexisting-worse = regressions − new-symbol by construction (the axis is a partition), so the two
        // header counters always sum to regressions= — an invariant the gate asserts.
        std::size_t minorCount = 0, newSymbolCount = 0, gatingCount = 0;
        for( const quality::Regression& r : regs )
        {
            if( r.isMinor )
            {
                ++minorCount;
            }
            if( r.isNewSymbol )
            {
                ++newSymbolCount;
            }
            else if( !r.isMinor )
            {
                ++gatingCount;
            }
        }
        const std::size_t preexistingCount = regs.size() - newSymbolCount;

        // P2.5 — one stderr line NAMING the gating finding, in --token-budget's style ("ripwire: --token-budget
        // exceeded: est_tokens=… > budget=…"). stdout is the machine artifact and a caller that only checks
        // `$?` gets a number with no subject; this puts the WHICH on the channel a human reads, without
        // touching the XML contract. Names the first gating row in the already-sorted list (deterministic).
        //
        // §A4 (minor): emitted BEFORE the format fork, not after the XML tail — under --json the fork returned
        // first, so exactly the caller most likely to be a script reading `$?` got the bare exit=2 with no
        // subject. The line is about the EXIT CODE, which both formats share, so it belongs to neither.
        if( gatingCount > 0 )
        {
            const quality::Regression* first = nullptr;
            for( const quality::Regression& r : regs )
            {
                if( !r.isNewSymbol && !r.isMinor ) { first = &r; break; }
            }
            if( first )
            {
                const std::string at = first->path.empty() ? std::string{}
                                                           : " at " + first->path + ":" + std::to_string( first->line );
                std::fprintf( stderr, "ripwire: --quality-delta gating: %zu preexisting-worse major finding(s); first: %s %s%s (was=%u now=%u)\n",
                              gatingCount, first->kind.c_str(), first->sym.c_str(), at.c_str(), first->was, first->now );
            }
        }

        // L2: --json — same regressions, keys mirror the XML attr names (kind/sym/members/tokens/was/now/
        // sev/churn/surface). jsonUnsupportedVerb already refused --quality-baseline/--quality-ack, so
        // reaching here with cfg.json means the plain --quality-delta report.
        if( cfg.json )
        {
            const char* baseMarkerJ = baseSel.marker;   // R3: the one spelling table lives in quality::selectBaseline — the XML/JSON twins cannot drift apart
            // The JSON sibling of the XML at= anchor — "at":null (never a fake sha) on a non-git root, and
            // null in the ref-pair form too: the list was not computed "at" any working-tree state, and the
            // two refs below ARE its anchor.
            const std::string atValJ  = refPair ? std::string{} : gitstamp::stampAt( root );
            const std::string atJsonJ = atValJ.empty() ? std::string( "null" ) : ( "\"" + atValJ + "\"" );
            // R-I: the same two shas + the same unmeasurable-kind disclosure the XML root carries, spelled in
            // JSON. Empty for the bare form, so that object stays byte-identical to before.
            std::printf( "{\"baseline\":\"%s\",\"regressions\":%zu,\"minor\":%zu,\"acked\":%zu,\"stale\":%zu,"
                         "\"preexisting-worse\":%zu,\"new-symbol\":%zu,\"gating\":%zu,\"at\":%s%s,\"r\":[",
                         jsonStr( baseMarkerJ ).c_str(), regs.size(), minorCount, ackedCount, staleAcks.size(),
                         preexistingCount, newSymbolCount, gatingCount, atJsonJ.c_str(), refs.jsonAttrs.c_str() );
            bool firstR = true;
            for( const quality::Regression& r : regs )
            {
                if( !firstR )
                {
                    std::printf( "," );
                }
                firstR = false;
                std::printf( "{\"kind\":\"%s\"", jsonStr( r.kind ).c_str() );
                if( r.kind == "duplication" )
                {
                    std::printf( ",\"members\":\"%s\",\"tokens\":%u", jsonStr( quality::displaySym( r.sym, deltaRoot ) ).c_str(), r.now );
                }
                else
                {
                    std::printf( ",\"sym\":\"%s\"", jsonStr( quality::displaySym( r.sym, deltaRoot ) ).c_str() );
                    if( !( r.kind == "dead-code" ) && !( r.kind == "api-surface" && r.was == r.now ) )
                    {
                        std::printf( ",\"was\":%u,\"now\":%u", r.was, r.now );
                    }
                }
                if( !r.path.empty() )
                {
                    std::printf( ",\"p\":\"%s:%u\"", jsonStr( r.path ).c_str(), r.line ); // P2.5 locator
                }
                if( !r.isNewSymbol && !r.isMinor )
                {
                    std::printf( ",\"gating\":true" ); // P2.5 — the exit predicate, stated per row
                }
                if( r.isMinor )
                {
                    std::printf( ",\"sev\":\"minor\"" );
                }
                if( !r.facet.empty() )
                {
                    const char* facetName = ( r.kind == "short-horizon-churn" ) ? "churn"
                                           : ( r.kind == "api-surface" )        ? "surface"
                                           : nullptr;
                    if( facetName )
                    {
                        std::printf( ",\"%s\":\"%s\"", facetName, jsonStr( r.facet ).c_str() );
                    }
                }
                if( r.isNewSymbol )
                {
                    std::printf( ",\"origin\":\"new-symbol\"" ); // absent = preexisting-worse (mirrors the XML)
                }
                std::printf( "}" );
            }
            std::printf( "]," );
            std::fputs( quality::staleAcksJsonArray( staleAcks ).c_str(), stdout );   // L2 — "sa":[...], same taxonomy as the XML sa= rows below
            std::printf( "}" );
            return gatingCount > 0 ? 2 : 0;
        }

        std::vector<char> esc;
        const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // §B7.1 (CA4) — the heading used to open "only what changed for the WORSE vs
        // .ripwire_quality_baseline", which is FALSE in every state but one: three of the four floors this
        // verb can use are not that file, and in one of them the file was judged stale and DELETED from the
        // user's tree during this very run. The floor actually used is named by baseline= on the element
        // below, so the heading now points at that attribute instead of asserting a floor, and the four
        // marker states (plus at=) are defined HERE — the first screen is the only place a reader meets
        // them, and a marker string that is only legible to whoever wrote it is not a disclosure.
        // G4: no "--" anywhere inside an XML comment ⇒ flag names are written bare ("quality-baseline"),
        // the same convention kMaxTokensFitLegend follows. No "%" either: this is a one-argument printf.
        std::printf( "<!-- ripwire quality-delta: only what a change made WORSE against the floor named by "
                     "baseline= below. FOUR floors, and they are not interchangeable: sidecar = the pinned "
                     ".ripwire_quality_baseline snapshot, honored only because it was pinned at the CURRENT "
                     "git HEAD; git-HEAD = no sidecar existed, so the working tree was auto-compared against "
                     "the HEAD tree; git-HEAD (stale sidecar removed) = a sidecar existed, was pinned at a "
                     "DIFFERENT sha, and this run DELETED it from your working tree before falling back to "
                     "HEAD (re-pin with quality-baseline); git-HEAD (stale sidecar ignored) = same staleness "
                     "verdict, but the file was left on disk (the read-only MCP arm, or an unlink that "
                     "failed). Only the first is a floor YOU chose; the other three compare against HEAD, so "
                     "anything already committed cannot appear. A FIFTH marker, ref-pair, means none of those: "
                     "the verb was given a RANGE, so it compared two COMMITTED trees and no sidecar was read, "
                     "written or deleted. Those reports carry base_ref= and target_ref= (the two RESOLVED "
                     "shas, at full length, because a wave number gets quoted into handoffs) and OMIT at=, "
                     "since the pair is the anchor. They also carry churn set to unavailable, which is the "
                     "honest statement that one of the ten kinds, short-horizon-churn, cannot be measured "
                     "there at all: it needs git history at the tree being judged, and both trees are "
                     "materialized OUT of the repo into temp dirs. Its silence in such a report is therefore "
                     "not evidence that nothing churned. at= is the git commit (plus a dirty marker "
                     "when the working tree differs) this list was computed at. Findings: "
                     "complexity over the ccx bar, verbosity (LOC)/nesting/params regressions, new duplication, "
                     "newly-dead, new public api-surface (contract drift), error-masking, short-horizon churn, "
                     "new clone of a reused helper. THREE independent axes, applied in this order: (1) acked "
                     "findings are suppressed entirely (acked= counts them, honestly); (2) ORIGIN — a finding on "
                     "a symbol that EXISTED at the baseline is preexisting-worse (no origin= attribute), one that "
                     "exists only because the code is NEW carries origin=\"new-symbol\"; (3) MATERIALITY — a small "
                     "numeric delta is sev=\"minor\". EXIT 2 fires only on preexisting-worse AND major, i.e. "
                     "gating=\"N\" above; new-symbol rows never gate. Clone kinds classify by their member set (a "
                     "group is new-symbol only if EVERY member is new); short-horizon-churn is preexisting by "
                     "construction. exit 0 is NOT a verdict on the new-symbol rows — nothing that existed got "
                     "worse, but the new debt is yours: read them. LIMIT: origin is canonId identity "
                     "(path::scope::name), so a RENAMED or MOVED symbol reads as new — a regression carried in "
                     "with a move classifies new-symbol and will not gate. Descriptive: weigh + fix the real "
                     "ones, do not game the number (a wrong abstraction beats a low score). "
                     "stale=\"N\" is a SEPARATE axis, never gating, over the .ripwire_quality_acks ledger: an "
                     "ack whose target no longer applies. Each sa row's why is target-gone (the key names no "
                     "symbol/group any more) or finding-gone (the target survived, this kind just does not "
                     "fire on it) — hygiene disclosure only, the ledger file is never auto-edited. "
                     "Each row carries "
                     // Found by this lane's own legend-coverage sweep, not by the brief: the two attributes
                     // that IDENTIFY a row — which axis regressed, and on what — were the only ones the
                     // dictionary below never named, while it defines p=, sev=, origin= and gating=.
                     "kind= (which of the measured axes regressed) and sym= (the canonical id it regressed on) — "
                     // The duplication pair is a DIRTY-TREE-ONLY first screen: a clean tree emits no rows at
                     // all, so the legendcoverage ratchet only meets members=/tokens= when the working tree
                     // holds a fresh duplicate, and a gap here reds the suite exactly when an agent has
                     // uncommitted edits open. Defined here so that encounter is green; the baseline stays a
                     // downward-only ratchet with no line added for it.
                     "except duplication rows, which name the whole clone group rather than one symbol: members= "
                     "is the group's member list and tokens= its shared normalized-token count (the same per-group "
                     "pair the clones verb reports) — plus "
                     "p=\"path:line\" (root-relative; the first-sorting member for the clone kinds; omitted, "
                     "never faked, when no locator resolves), and every row the header's gating= counter "
                     "counts also carries a gating attribute set to 1 — those are the rows the exit code fires "
                     "on, and they are now marked positively rather than by the ABSENCE of sev/origin. "
                     "(This sentence deliberately spells no attribute=value literal: the header counters are "
                     "parsed by grep in several gates, and a quoted numeric example here would be matched "
                     "first.) -->" );
        const char* baseMarker = baseSel.marker;    // R3: ditto — one seam decides staleness AND names it
        // at= anchors this regression list to the commit (+dirty state) it was computed against.
        std::printf( "<quality-delta baseline=\"%s\" regressions=\"%zu\" minor=\"%zu\" acked=\"%zu\" stale=\"%zu\" preexisting-worse=\"%zu\" new-symbol=\"%zu\" gating=\"%zu\"%s%s>",
                     baseMarker, regs.size(), minorCount, ackedCount, staleAcks.size(), preexistingCount, newSymbolCount, gatingCount,
                     // R-I: at= is OMITTED for the ref-pair form rather than stamped with the working tree's
                     // sha, which would anchor the list to a commit it was not computed from. base_ref= and
                     // target_ref= are the anchor there, and they carry FULL shas because a wave measurement
                     // gets quoted into handoffs where a 9-char prefix is one collision from unverifiable.
                     refPair ? "" : gitstamp::atAttr( root ).c_str(), refs.attrs.c_str() );
        for( const quality::Regression& r : regs )
        {
            // duplication carries a member LIST (members=) + token count; the per-symbol was/now kinds
            // (complexity/verbosity/nesting/params) carry was/now; api-surface + dead-code are sym-only.
            // sev="minor" marks a below-materiality delta (never gates); absent = major.
            const char* sev = r.isMinor ? " sev=\"minor\"" : "";
            // B10.2 — the optional classification facet: attribute NAME is chosen by kind (churn=
            // short-horizon-churn's self/ambient split; surface= api-surface's new-symbol/contract-change
            // tier); r.facet carries only the VALUE, so main.cpp is the one place that maps kind → attr name.
            std::string facetAttr;
            if( !r.facet.empty() )
            {
                const char* facetName = ( r.kind == "short-horizon-churn" ) ? "churn"
                                       : ( r.kind == "api-surface" )        ? "surface"
                                       : nullptr;
                if( facetName )
                {
                    facetAttr = std::string( " " ) + facetName + "=\"" + r.facet + "\"";
                }
            }
            // r26 — the ORIGIN axis, emitted LAST so the existing attribute order is untouched. Present only
            // on new-symbol rows (absent = preexisting-worse), the same "mark the exception" convention sev=
            // uses. api-surface's own surface="new-symbol" facet is the same fact narrowed to that kind; it
            // stays for shape compatibility, and origin= is what the exit gate reads.
            const char* origin = r.isNewSymbol ? " origin=\"new-symbol\"" : "";
            // P2.5 — the two attributes that make a row ACTIONABLE, appended last so every pre-r27 attribute
            // keeps its position:
            //   p="path:line" — sym= is a canonical id whose display tail is often a bare one-letter local
            //     (`sym="cc"`), i.e. ungreppable. Omitted, never faked, when no locator was resolvable.
            //   gating="1"    — marks exactly the rows the header's gating= counts and the exit code fires on.
            //     Until now a gating row was identifiable ONLY by the ABSENCE of sev="minor" (and of
            //     origin="new-symbol") — absence-as-signal is the least machine-friendly encoding available.
            std::string locAttr;
            if( !r.path.empty() )
            {
                locAttr = " p=\"" + ex( r.path ) + ":" + std::to_string( r.line ) + "\"";
            }
            const char* gatingAttr = ( !r.isNewSymbol && !r.isMinor ) ? " gating=\"1\"" : "";
            if( r.kind == "duplication" )
            {
                std::printf( "<r kind=\"duplication\" members=\"%s\" tokens=\"%u\"%s%s%s%s%s/>", ex( quality::displaySym( r.sym, deltaRoot ) ).c_str(), r.now, sev, facetAttr.c_str(), origin, locAttr.c_str(), gatingAttr );
            }
            else if( r.kind == "dead-code" )
            {
                std::printf( "<r kind=\"%s\" sym=\"%s\"%s%s%s%s%s/>", r.kind.c_str(), ex( quality::displaySym( r.sym, deltaRoot ) ).c_str(), sev, facetAttr.c_str(), origin, locAttr.c_str(), gatingAttr );
            // B10.2e: api-surface now carries two shapes — a brand-new/newly-public symbol (was=now=0, no
            // param comparison to show) and a param-count contract-change (was/now = the real counts). Print
            // was/now whenever they differ from each other so the contract-change case's was=/now= is visible
            // while the new-symbol case's meaningless was="0" now="0" is omitted, matching its old sym-only shape.
            }
            else if( r.kind == "api-surface" && r.was == r.now )
            {
                std::printf( "<r kind=\"%s\" sym=\"%s\"%s%s%s%s%s/>", r.kind.c_str(), ex( quality::displaySym( r.sym, deltaRoot ) ).c_str(), sev, facetAttr.c_str(), origin, locAttr.c_str(), gatingAttr );
            }
            else
            {
                std::printf( "<r kind=\"%s\" sym=\"%s\" was=\"%u\" now=\"%u\"%s%s%s%s%s/>", r.kind.c_str(), ex( quality::displaySym( r.sym, deltaRoot ) ).c_str(), r.was, r.now, sev, facetAttr.c_str(), origin, locAttr.c_str(), gatingAttr );
            }
        }
        std::fputs( quality::staleAcksXml( staleAcks ).c_str(), stdout );   // L2 — one <sa> row per stale ack (quality::staleAcksXml)
        std::printf( "</quality-delta>" );
        return gatingCount > 0 ? 2 : 0;   // r26: only a PREEXISTING-worse AND major regression gates (== gating=)
    }
    return std::nullopt;
}

// ── --dmm ────────────────────────────────────────────────────────────────────────────────────────────────
// The Delta Maintainability Model scalar — the TRENDABLE complement to --quality-delta above, and it sits
// here because the two answer the same question at different resolutions ("which kinds got worse" vs "how
// did this change score, on one scale"). dmm.h owns the whole computation and the emission; this handler
// resolves the flag, splits the ONE user-error case (a revision that does not resolve → a refusal that
// names the offending token, exit 1) from every environment case (no git, a root commit, an archive that
// failed → an UNAVAILABLE report, exit 0), and never gates: a maintainability score with a threshold on it
// is a score people write code to.
std::optional<int> runDmm( const MainDispatch& d )
{
    using namespace rw;
    const Config& cfg = d.cfg;

    if( !cfg.dmm )
    {
        return std::nullopt;
    }

    const dmm::Result r = dmm::computeDmm( d.root, cfg.dmmRange, d.ing, cfg.excludes, cfg.maxFileBytes );
    if( r.status == dmm::Status::BadRev )
    {
        std::fprintf( stderr, "ripwire: --dmm: '%s' does not resolve to a commit in %s\n", r.badToken.c_str(), d.root.c_str() );
        return 1;
    }
    if( r.status == dmm::Status::BadRange )
    {
        std::fprintf( stderr, "ripwire: --dmm: '%s' uses the three-dot form; --dmm compares two TREES, so spell it A..B "
                              "(or --dmm=$(git merge-base A B)..B if the merge base is what you meant)\n", r.badToken.c_str() );
        return 1;
    }
    return dmm::writeDmmReport( r );
}

// §A10.6: strips a REPEATED leading "./" so `./src`, `././src`, and `src` all compare on the same text —
// used to normalize both the user's --dead-code=DIR filter and every indexed path it is matched against.
inline std::string_view deadCodeStripDotSlash( std::string_view p ) noexcept
{
    while( p.size() >= 2 && p[0] == '.' && p[1] == '/' )
    {
        p.remove_prefix( 2 );
    }
    return p;
}

// §A10.6: the --dead-code=DIR path filter, hoisted out of runQualityViews so the branch lives on its own
// symbol instead of inflating that function's complexity. `anchoredAtRoot` (a LEADING ./ on the RAW arg,
// decided by the caller before dirFilter is normalized) restricts the match to path position 0 — the
// repo ROOT — instead of the default component-anywhere match (leading dir, trailing filename, or an
// interior directory, all at '/' boundaries so `sr` never matches `src/`). Allocation-free: called once
// per indexed file and once per candidate symbol.
//
// W3FIX: position 0 is only the repo root when the indexed path is ROOT-RELATIVE, which it is for
// `ripwire .` (paths read "./src/x.h") and is NOT for `ripwire /abs/repo` (paths read "/abs/repo/src/x.h").
// So the anchored arm matched nothing at all under an absolute root spelling, and --dead-code=./src refused
// with "matches no indexed path" on a tree that plainly has one — the same root-spelling class arch.h's
// relForHash header comment describes for baseline hashes. The fix is that same normalization, reused rather
// than re-derived: strip the ingest root LEXICALLY first, then compare. `root` empty ⇒ the leading-./ strip
// alone, i.e. byte-identical to the pre-fix relative-root behavior.
inline bool deadCodeFilterMatchesPath( std::string_view path, std::string_view dirFilter, bool anchoredAtRoot,
                                       std::string_view root = {} ) noexcept
{
    const std::string_view p = anchoredAtRoot ? rw::relForHash( path, root ) : deadCodeStripDotSlash( path );
    if( anchoredAtRoot )
    {
        if( dirFilter.size() > p.size() || p.substr( 0, dirFilter.size() ) != dirFilter )
        {
            return false;
        }
        const std::size_t afterEnd = dirFilter.size();
        return afterEnd == p.size() || p[ afterEnd ] == '/';
    }
    for( std::size_t at = p.find( dirFilter ); at != std::string_view::npos; at = p.find( dirFilter, at + 1 ) )
    {
        const std::size_t afterEnd = at + dirFilter.size();
        const bool leftOnBoundary  = at == 0 || p[ at - 1 ] == '/';
        const bool rightOnBoundary = afterEnd == p.size() || p[ afterEnd ] == '/';
        if( leftOnBoundary && rightOnBoundary )
        {
            return true;
        }
    }
    return false;
}

// --quality-panel[=PRESET]: THE SINGLE COMMAND (qualitypanel.h owns the join, the preset selection AND its
// emission, the way --ensemble owns its own). Its own function rather than a block inside runQualityViews:
// that dispatcher is already the tree's third-most complex symbol, and this verb needs three statements the
// other branches there do not (a preset parse, a refusal, a churn mining pass).
//
// It is dispatched from runQualityViews rather than from runMaintenanceViews beside --ensemble because two of
// its six families need what that dispatcher has and this one does not: the call graph (the state family's
// closure) and the value-use references (both new families) — see needsValueUses below.
//
// THE PRESET REFUSAL LIVES HERE, not in validateModifierGuards, and that is deliberate: the preset vocabulary
// belongs to the verb (qualitypanel.h), and cli.h is a leaf that includes only ingest.h. Pulling the whole
// lens stack into the argument parser to spell three names would be a worse trade than refusing one step
// later. Refusing at all is the point — silently substituting `default` for a preset the caller did not name
// answers a different question under the label they typed.
//
// GIT IS OPTIONAL, exactly as it is for --ensemble: five of the six families need no history, so a failed
// mining pass hands the join a nullptr and the historical family is reported UNAVAILABLE rather than as
// "did not fire". --since is deliberately not plumbed in — the churn window is part of the disclosed
// threshold set and one fixed 12-month window keeps hrank= comparable between runs.
int runQualityPanel( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;

    qpanel::Preset preset = qpanel::Preset::Default;
    if( !cfg.qualityPanelPreset.empty() && !qpanel::parsePreset( cfg.qualityPanelPreset, preset ) )
    {
        std::fprintf( stderr, "ripwire: --quality-panel: unknown preset '%.*s' (supported: strict|default|lenient; "
                              "bare --quality-panel is default)\n",
                      int( cfg.qualityPanelPreset.size() ), cfg.qualityPanelPreset.data() );
        return 1;
    }

    std::vector<std::uint32_t> churn( ing.files.size(), 0 );
    const rw::SinceScope       noScope;
    const bool                 churnOk = mineChurnPerFile( ing, d.root, d.multiRoot, d.ws, std::string_view(), noScope,
                                                           rw::ensemble::kEnsembleChurnSince, churn );
    return qpanel::writePanelReport( ing, d.g, churnOk ? &churn : nullptr, d.root, preset, cfg.pageLimit, cfg.pageOffset );
}

// The residual of §6.3's extraction: --dead-code, the only branch left in runQualityViews. main() calls it
// immediately after runQualityDelta, i.e. in the position the old two-branch chain evaluated it.
std::optional<int> runQualityViews( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — shared
    // across every lens dispatched from this function.
    const bool         qvSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  qvRootPrefix = qvSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  qvRootEsc;
    const std::string  qvRootAttr   = qvSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], qvRootEsc ) ) + "\"" ) : std::string();

    // --readability: the Posnett/Hindle/Devanbu (MSR 2011) closed-form lens, per function, LEAST readable
    // first (readability.h owns the measurement AND its emission, the way --handoff owns its packet). It
    // reads only the symbol table and the files on disk, so it needs neither the graph nor git — and it is
    // a LENS: exit 0 always, no verdict, no threshold.
    if( cfg.readability )
    {
        return writeReadabilityReport( ing, cfg.pageLimit, cfg.pageOffset, qvRootPrefix, qvRootAttr );
    }

    // --comment-coherence: two published content measures per documented function/method (Steidl c_coeff
    // + Scalabrino CIC) — commentcoherence.h owns the measurement AND its emission, the same shape as
    // --readability. Symbol table + files on disk only; no graph, no git; a LENS: exit 0 always.
    if( cfg.commentCoherence )
    {
        return writeCommentCoherenceReport( ing, cfg.pageLimit, cfg.pageOffset, qvRootPrefix, qvRootAttr );
    }

    // --nonlocal-state: per function, the non-local MUTABLE state it or its transitive callees reach, reads
    // and writes kept apart (nonlocalstate.h owns the discovery, the closure AND its emission, the way
    // --readability does). It needs the symbol table, the value-use references and the call graph — but no
    // git — and it is a LENS: exit 0 always, no verdict, no threshold, every count a disclosed floor.
    if( cfg.nonlocalState )
    {
        return nonlocal::writeNonLocalStateReport( ing, g, cfg.pageLimit, cfg.pageOffset, qvRootPrefix, qvRootAttr );
    }

    if( cfg.qualityPanel )
    {
        return runQualityPanel( d );
    }

    // --naming-calibration: §9.5 — the naming-* lint rules judged against the repo's OWN rename history
    // (renamemine.h owns the mining, the join, the scoring AND the emission, the way --readability does).
    // It walks git and reads the symbol table; it needs no graph. Exit 0 always — a measurement, not a
    // verdict: test/namingcalibrationcheck.sh is where the per-rule floor lives.
    if( cfg.namingCalibration )
    {
        return renamemine::writeNamingCalibrationReport( ing, d.root );
    }

    // --naming-consistency: §9.2 TIER A convention normalization — the corpus's own case-convention vote,
    // read-only, graph-free (namingconsistency.h owns the scan, the decision and the emission). Exit 0
    // always — a lens, not a gate.
    if( cfg.namingConsistency )
    {
        return namingconsistency::writeNamingConsistencyReport( ing, cfg.pageLimit, cfg.pageOffset, qvRootPrefix, qvRootAttr );
    }

    // --dead-code[=DIR]: HIGH-CONFIDENCE candidates only. Zero callers is incomplete whole-program evidence,
    // so the default reports source-defined free functions with explicit internal (`static`) linkage. External
    // entry points, methods, header definitions and declarations are excluded. There is no broad product mode,
    // so do not overload the directory filter with lower-confidence behavior.
    // Output: deterministic (sorted by file path then line), terse XML consistent with other report verbs.
    if( cfg.deadCode )
    {
        const auto* inRo = g.inEdges.rowOffsets();    // in-edge CSR row offsets: inDeg(i) = inRo[i+1]-inRo[i]
        std::vector<std::string> sourceByFile( ing.files.size() );
        std::vector<char>        sourceLoaded( ing.files.size(), 0 );
        const auto sourceFor = [ & ]( std::uint32_t fileId ) -> const std::string&
        {
            if( sourceLoaded[fileId] )
            {
                return sourceByFile[fileId];
            }
            sourceLoaded[fileId] = 1;
            std::FILE* file = std::fopen( diskPath( ing, fileId ).c_str(), "rb" );
            if( !file )
            {
                return sourceByFile[fileId];
            }
            std::fseek( file, 0, SEEK_END );
            const long byteCount = std::ftell( file );
            std::fseek( file, 0, SEEK_SET );
            if( byteCount > 0 )
            {
                sourceByFile[fileId].resize( std::size_t( byteCount ) );
                const std::size_t bytesRead = std::fread( sourceByFile[fileId].data(), 1, std::size_t( byteCount ), file );
                sourceByFile[fileId].resize( bytesRead );
            }
            std::fclose( file );
            return sourceByFile[fileId];
        };
        const auto hasStaticToken = [ & ]( const Symbol& symbol ) -> bool
        {
            const std::string& source = sourceFor( symbol.fileId );
            const std::size_t begin = std::min<std::size_t>( symbol.sigStartByte, source.size() );
            const std::size_t end   = std::min<std::size_t>( symbol.sigEndByte, source.size() );
            if( begin >= end )
            {
                return false;
            }
            constexpr std::string_view token = "static";
            std::size_t position = begin;
            while( ( position = source.find( token, position ) ) != std::string::npos && position + token.size() <= end )
            {
                const auto isIdentifier = []( char c ) noexcept { return std::isalnum( static_cast<unsigned char>( c ) ) || c == '_'; };
                const bool leftBoundary  = position == begin || !isIdentifier( source[ position - 1 ] );
                const bool rightBoundary = position + token.size() == end || !isIdentifier( source[ position + token.size() ] );
                if( leftBoundary && rightBoundary )
                {
                    return true;
                }
                position += token.size();
            }
            return false;
        };

        // Optional path filter (--dead-code=DIR). §P0.3: this was a bare SUFFIX test, so it could only ever
        // match a FILENAME — every directory argument produced count="0" with confidence="high", and a typo'd
        // directory was byte-identical to a real one. It now matches a directory PREFIX, a trailing path
        // component, or the whole path, all at directory boundaries so `src` never matches `srcmut/` —
        // UNLESS the filter carries a leading ./, which anchors it at the repo root instead (§A10.6,
        // deadCodeFilterMatchesPath above: `./src` matches only the top-level src/ subtree, never an
        // interior `*/src/*` component that the bare `src` spelling also, correctly, matches).
        //
        // W3FIX: `root` is handed to the anchored arm so "position 0" means the repo root under EVERY root
        // spelling. Without it the anchored match compared the filter against an ABSOLUTE indexed path and
        // could never hit, so `ripwire /abs/repo --dead-code=./src` refused where `ripwire . --dead-code=./src`
        // answered. The unanchored (component-anywhere) arm never read the root and is untouched.
        const std::string_view dirFilterRaw = cfg.deadCodeDir;
        std::string_view       dirFilter = deadCodeStripDotSlash( dirFilterRaw );
        while( !dirFilter.empty() && dirFilter.back() == '/' )
        {
            dirFilter.remove_suffix( 1 ); // `test/` ≡ `test`
        }
        const bool anchoredAtRoot = dirFilterRaw.size() >= 2 && dirFilterRaw[ 0 ] == '.' && dirFilterRaw[ 1 ] == '/';
        const auto filterMatchesPath = [ & ]( std::string_view path ) noexcept -> bool
        {
            return deadCodeFilterMatchesPath( path, dirFilter, anchoredAtRoot, d.root );
        };

        // A filter that names nothing in the indexed tree is a user error, not a measurement: refuse loudly
        // rather than ship `count="0" confidence="high"` about a directory that was never crawled.
        if( !dirFilter.empty() )
        {
            bool filterHitsIndex = false;
            for( const std::string& indexedPath : ing.files )
            {
                if( filterMatchesPath( indexedPath ) ) { filterHitsIndex = true; break; }
            }
            if( !filterHitsIndex )
            {
                std::fprintf( stderr, "ripwire: --dead-code=%.*s matches no indexed path — a zero here would be a failure, not a measurement "
                                      "(pass a directory or file that exists in the tree, e.g. ripwire <dir> --dead-code=src)\n",
                              int( dirFilterRaw.size() ), dirFilterRaw.data() );
                return 1;
            }
        }

        // collect candidates: in-degree == 0, not exported, sorted for determinism
        std::vector<NodeId> candidates;
        candidates.reserve( 64 );
        for( const Symbol& s : ing.symbols )
        {
            if( s.kind != SymKind::Function )
            {
                continue; // methods and non-callable nodes are out of scope
            }
            if( s.sigEndByte >= s.endByte )
            {
                continue; // declarations have no deletion evidence
            }
            if( isHeaderPath( ing.files[s.fileId] ) )
            {
                continue; // may be instantiated by external TUs
            }
            if( !hasStaticToken( s ) )
            {
                continue; // external linkage may be an entry point/API
            }

            // optional path filter: directory prefix, trailing component, or the whole path
            if( !dirFilter.empty() && !filterMatchesPath( ing.files[s.fileId] ) )
            {
                continue;
            }

            // in-degree == 0 → no call in the indexed tree reaches this symbol
            const std::uint32_t inDeg = inRo[ s.id + 1 ] - inRo[ s.id ];
            if( inDeg == 0 )
            {
                candidates.push_back( s.id );
            }
        }

        // deterministic order: file path asc, then line asc, then name asc (stable across runs)
        std::sort( candidates.begin(), candidates.end(), [ & ]( NodeId a, NodeId b )
        {
            const Symbol& sa = ing.symbols[a];  const Symbol& sb = ing.symbols[b];
            const std::string& pa = ing.files[ sa.fileId ];  const std::string& pb = ing.files[ sb.fileId ];
            if( pa != pb )
            {
                return pa < pb;
            }
            if( sa.line != sb.line )
            {
                return sa.line < sb.line;
            }
            return sa.name < sb.name;
        } );

        std::printf( "<!-- ripwire dead-code: high-confidence source functions with internal linkage and no caller in the indexed tree. "
                     "A bare-name filter matches by path COMPONENT: filter=\"src\" keeps any path with a src segment at any depth "
                     "(test/x/src/y.cpp included); anchor with ./ (filter=\"./src\") to pin the root-level directory only. "
                     "Graph evidence is local to the indexed tree; verify before deleting -->" );
        // §P15/§P16: candidates is already deterministically sorted (path asc, line asc, name asc) and used to
        // print every candidate unconditionally — completeness was the whole contract, matching --uses' shape,
        // so it pages the same way: no historic display cap, discloseCap=false (un-paginated tag byte-identical).
        const PageWindow  dcPw = pageWindow( candidates.size(), cfg.pageLimit, cfg.pageOffset );
        char              dcAb[ kPageDisclosureCap ];
        // V2-7: a FILTERED zero must not be byte-identical to an unfiltered clean tree — with the ./-anchor
        // and component spellings now giving different answers for the same word, the root says which
        // filter produced this count. Absent = no filter, whole tree (never an empty filter="").
        std::string dcFilterAttr;
        if( !cfg.deadCodeDir.empty() )
        {
            std::vector<char> dcFiltEsc;
            dcFilterAttr = " filter=\"" + std::string( escapeXml( cfg.deadCodeDir, dcFiltEsc ) ) + "\"";
        }
        std::printf( "<dead-code count=\"%zu\" confidence=\"high\" evidence=\"internal-linkage+zero-callers\"%s%s%s>", candidates.size(),
                     dcFilterAttr.c_str(),
                     pageDisclosure( dcAb, sizeof( dcAb ), dcPw.end - dcPw.begin, candidates.size(), dcPw.end,
                                     cfg.pageLimit, cfg.pageOffset, false ),
                     qvRootAttr.c_str() );
        std::vector<char> dcEsc;
        for( std::size_t candidateIndex = dcPw.begin; candidateIndex < dcPw.end; ++candidateIndex )
        {
            const NodeId candidateId = candidates[ candidateIndex ];
            const Symbol& s = ing.symbols[ candidateId ];
            // name and path may contain & < > " — escape both so output is valid XML.
            const auto en = rw::escapeXml( s.name, dcEsc );
            std::printf( "<d n=\"%.*s\" t=\"%s\"", int( en.size() ), en.data(), symTag( s.kind ) );
            const std::string_view rp = qvSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], qvRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            const auto ep = rw::escapeXml( rp, dcEsc );
            std::printf( " p=\"%.*s\" l=\"%u\"/>", int( ep.size() ), ep.data(), s.line );
        }
        std::printf( "</dead-code>" );
        return 0;
    }
    return std::nullopt;
}

// --edit-check=SYM (B11/L5): "did MY edit change a contract someone depends on", at edit time, for ONE
// symbol — --quality-delta answers the same question per-DIFF at commit time; this is the fast targeted
// entry point. Resolves SYM exactly like --around/--lego
// (resolveFocus — file:name disambiguates), then compares the WORKING-TREE symbol against the git-HEAD
// baseline (computeHeadSnapshot — the SAME qheadsnap/qsnap cache family --quality-delta's T0.1 auto-baseline
// uses, so a warm run is a cache-blob read, never a fresh git-archive/ingest/clone-detection pass — that is
// what keeps this under the ≤100ms warm budget the gate asserts, unlike --quality-delta's own ~250ms+
// per-call clone recompute over the whole tree). Reuses B10.2's per-canonId MAX-aggregation over the overload
// set (same file+scope+name share one g.canonId) for the was/now params + publicness comparison — NOT a
// single arbitrarily-iterated overload — so a low-param overload can never manufacture a phantom
// contract-change (the exact trap B10 fixed in quality.h; re-implementing it single-overload here would
// reintroduce it). status is exactly one of unchanged / new-symbol / contract-change, and it is the JOIN of
// three facts, not of the was/now pair alone (editcheck.h's editCheckVerdict owns the derivation and its
// reasoning; change= names which fact carried a contract-change):
//   new-symbol       — SYM's canonical id has no baseline record at all (absent from base.locBySym, the same
//                       "existed at baseline in ANY form" test quality.h's api-surface kind uses). Never
//                       escalated: there was no contract to change.
//   contract-change   — SYM existed at baseline AND at least one of THREE was-vs-now facts moved: the params
//                       MAX, publicness, or the definition COUNT (defs_was= vs the root's defs=). The third
//                       exists because the MAX fold is blind to an overload REMOVED below it — both sides keep
//                       the same max while a call site stops binding, and answering "unchanged" there is a
//                       false reassurance from the one verb whose value is the headline word. change= names
//                       which fact carried it; it adds broken-callers as corroboration but never as the sole
//                       cause, because incompatible= describes the CURRENT tree rather than the edit.
//   unchanged         — SYM existed at baseline and none of the three moved (a body-only edit is unchanged by
//                       design: this checks the CONTRACT, not the body — that is --quality-delta's
//                       short-horizon-churn kind's job).
// A non-git root / no HEAD degrades to new-symbol (nothing to compare against) with a DEGRADED_PATH_ALERT —
// never a crash; only an unresolvable SYM refuses loudly (below).
//
// 1-hop callers (reuse the --callers 1-hop in-edge walk, unioned over the whole overload set) are listed with
// any call-site flagged INCOMPATIBLE when its argument count is reliably counted (argCountKnown) AND no
// surviving overload could accept it — every overload with a FIXED arity (arityExact!=0) disagrees, and none
// is a variadic/default-arg/implicit-receiver wildcard that an argument count could never disprove
// (editcheck.h::editCheckImplicitReceiver adds the Python/Ruby half that arityExact cannot express), evaluated
// against the CURRENT (post-edit) overload set.
//
// One-sided IN THE ARITY, not a proof of BINDING — and the emitted legend says so rather than promising
// "provably … never a guess". Call edges are name-based, so a receiver-qualified call to a same-named callee
// this tool does not index is measured against the one definition it does index; an untouched, compiling tree
// therefore carries a nonzero incompatible= on a handful of shared names. See editcheck.h's measurement note
// for the swept numbers and why no cheap sound filter exists.
//
// The contract-comparison core (EditCheckContract / editCheckOverloadSet / editCheckContractVsHead /
// editCheckIncompatibleFlags / editCheckCallers / the whole <edit-check> XML assembler) now lives in
// editcheck.h (L4) as editCheckBundleText() — shared verbatim with the MCP edit_check verb (mcpverbs.h's
// editCheckText()). This handler only resolves the CLI's symbol spec (the shared resolver + the did-you-mean
// refusal message + the §A6a ambiguity refusal) and hands the resolved node to that ONE assembler.
//
// §A6a — an AMBIGUOUS bare name is REFUSED, not silently narrowed. resolveFocus() answers "the lowest-id
// definition with this name", which is the right answer for --around's ego graph and the WRONG one here: this
// verb's whole value is "did I break a contract?", and answered about a definition the agent never edited it
// returns status="unchanged" — reassurance for the wrong symbol. Its siblings can union (--callers reports
// defs="3" and lists the union); a CONTRACT cannot be unioned, so the only honest answers are one definition
// or a refusal that says how to name one. The resolver moves to resolveAllByNameQualified (every match, not
// the lowest id) — byte-identical on any selector that matched exactly one definition site, and it accepts a
// canonical id too, which is the spelling the refusal has to offer when a file alone cannot separate two
// scopes in one file.
std::optional<int> runEditCheck( const MainDispatch& d )
{
    using namespace rw;
    const Config&        cfg = d.cfg;
    const IngestResult&  ing = d.ing;

    if( cfg.editCheckSym.empty() )
    {
        return std::nullopt;
    }

    const std::vector<NodeId> matches = resolveAllByNameQualified( ing, cfg.editCheckSym );
    if( matches.empty() )
    {
        // §B4.2: the shared refusal — see selectorrefuse.h. A `file:name` whose FILE half is the fault used
        // to read as "that symbol does not exist", which sends an agent hunting for a rename that never was.
        std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --edit-check symbol not found: ",
                                                               cfg.editCheckSym, "--edit-check=" ).c_str() );
        return 1;
    }

    const std::vector<EditCheckGroup> groups = editCheckGroups( ing, d.g, matches );
    if( groups.size() > 1 )
    {
        std::fprintf( stderr, "ripwire: --edit-check: %s\n",
                      editCheckAmbiguousMessage( cfg.editCheckSym, groups, "--edit-check=", matches.size() ).c_str() );
        return 1;
    }
    const NodeId focus = groups[0].lowestNode;

    const std::string xml = editCheckBundleText( ing, d.g, d.root, cfg.maxFileBytes, cfg.excludes, focus );
    std::fwrite( xml.data(), 1, xml.size(), stdout );
    return 0;
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

// The nine navigate verbs — --callers/--callees, --graph-query, --uses, --external-surface, --path,
// --connect, --impact, --mentions, --affected — were nine independent top-level branches of a single
// 478-line runNavigateVerbs. Each is now its own handler with the `std::optional<int>( const MainDispatch& )`
// shape the file's other 23 handlers already use; the bodies are cut VERBATIM and main() calls them in the
// SAME order the chain evaluated them. That order is observable (passing two verb flags picks exactly one
// answer) and nothing pinned it before — test/dispatchordercheck.sh does now.

// macro-edges round: the role attribute a callers/callees XML row carries iff the neighbour is an indexed
// function-like #define — the edge crosses a macro expansion, not a plain call (rows carry no role=
// otherwise, and NEVER role="call"). Kind-derived, so the columnar/JSON dialects disclose the same fact
// through their t="macro"; kept out of runCallHierarchy's row loop as a call, not another branch.
inline const char* macroRoleAttr( rw::SymKind k ) noexcept
{
    return k == rw::SymKind::Macro ? " role=\"macro\"" : "";
}

std::optional<int> runCallHierarchy( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         chSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  chRootPrefix = chSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  chEsc;
    const std::string  chRootAttr   = chSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], chEsc ) ) + "\"" ) : std::string();

    // --callers=SYM / --callees=SYM: sharp 1-hop call hierarchy from the graph (in-edges = callers,
    // out-edges = callees). LSP's incomingCalls/outgoingCalls — crisper than the --around neighbourhood.
    if( !cfg.callers.empty() || !cfg.callees.empty() )
    {
        const bool             wantCallers = !cfg.callers.empty();
        const std::string_view sym         = wantCallers ? cfg.callers : cfg.callees;
        // X9(b): "file:name" now disambiguates here too (same rule as --around/--lego/--edit-check via
        // resolveFocus) — a same-named symbol living in more than one file previously had no way to pick
        // one side on --callers/--callees.
        const std::vector<NodeId> matches  = resolveAllByNameQualified( ing, sym );
        if( matches.empty() )
        {
            const std::string verb = std::string( wantCallers ? "--callers" : "--callees" );   // one arm, two spellings
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: " + verb + " symbol not found: ",
                                                                   sym, verb + "=" ).c_str() );   // §B4.2 shared refusal
            return 1;
        }
        std::vector<char>   seen( ing.symbols.size(), 0 );
        std::vector<NodeId> result;
        for( NodeId x : matches )
        {
            if( wantCallers )
            {
                const auto* ro = g.inEdges.rowOffsets();
                const auto* ci = g.inEdges.colIndices();
                for( std::uint32_t k = ro[x]; k < ro[x + 1]; ++k )
                {
                    if( NodeId c = ci[k]; c < seen.size() && !seen[c] ) { seen[c] = 1; result.push_back( c ); }
                }
            }
            else
            {
                for( std::uint32_t k = g.outOff[x]; k < g.outOff[x + 1]; ++k )
                {
                    if( NodeId c = g.outTargets[k]; c < seen.size() && !seen[c] ) { seen[c] = 1; result.push_back( c ); }
                }
            }
        }
        std::sort( result.begin(), result.end(), [ & ]( NodeId a, NodeId b )
        {
            const Symbol& sa = ing.symbols[a];  const Symbol& sb = ing.symbols[b];
            if( sa.fileId != sb.fileId )
            {
                return ing.files[sa.fileId] < ing.files[sb.fileId];
            }
            return sa.line != sb.line ? sa.line < sb.line : sa.name < sb.name;
        } );
        const char*       tag = wantCallers ? "callers" : "callees";
        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

        // Count bodyless definitions (declarations with no body): sigEndByte == endByte means no body
        std::size_t bodylessDefsCount = 0;
        if( !wantCallers )  // Only relevant for callees; callers don't have this concern
        {
            for( NodeId x : matches )
            {
                const Symbol& sym = ing.symbols[x];
                if( sym.sigEndByte == sym.endByte )
                {
                    ++bodylessDefsCount;
                }
            }
        }
        // T2 + §P8 G1: paginate the sorted result. count= stays the un-windowed total (V3 L-4: "TRUE" is the
        // word this comment used, and it contradicts the counts_floor= marker the emitter ten lines below now
        // prints — the total is true of the PAGE, never of the world); the disclosure appears only
        // when paging is active — discloseCap=false because these two verbs have NO display cap of their own
        // (an un-paginated --callers always emitted every caller), so the un-paged opening tag stays
        // byte-identical. See src/pageview.h, THE TRUNCATION VOCABULARY.
        const PageWindow  pw = pageWindow( result.size(), cfg.pageLimit, cfg.pageOffset );
        char              pab[ kPageDisclosureCap ];

        // §H4 §3.4: the FIRST legend these two verbs have ever shipped (0 bytes before — which is why every
        // one of their root attributes sits in test/legendcoverage_baseline.txt), and the floor marker that
        // is the round's honest half. ONE opener for both forms, printed BEFORE the format branches so the
        // columnar and default shapes carry the identical disclosure. JSON has no comment-node analogue, so
        // there the marker travels as the counts_floor key on the root object instead.
        // V1 fix (verifier finding 3): bodyless_defs= is callees-only (main.cpp gates the attribute itself
        // behind !wantCallers a few lines up), so its defining sentence rides along only on the callees
        // form — a --callers call no longer pays for vocabulary it can never emit. The wantCallers branch
        // lives in rw::callHierarchyLegendOpen (graphlegend.h), not here, so it does not add to this
        // already-large dispatcher's own complexity.
        if( !cfg.json )
        {
            std::printf( "%s%s-->%s", rw::callHierarchyLegendOpen( wantCallers ).c_str(), rw::graphCountDisclosure().c_str(), rw::rootRelPathsLegend( chSingleRoot ) );
        }

        // --format=columnar (RESEARCH lever 1): the same page window, re-encoded as a path-table + parallel
        // arrays (dedups the repeated per-row markup + paths). Default --format=xml is byte-identical below.
        if( cfg.columnar )
        {
            std::vector<NodeId> page( result.begin() + pw.begin, result.begin() + pw.end );
            // §B1.1: composed into a std::string, NEVER a fixed `char attrbuf[]`. `of=` echoes a
            // caller-supplied symbol NAME, which is unbounded (a markdown SECTION heading routinely runs
            // 200-600 chars), so the old 288-byte buffer truncated it mid-attribute at exit 0 — invalid
            // XML past ~185 chars once paging flags widened the string, and at a boundary length a
            // well-formed tag whose next_offset=/offset=/limit= had been silently amputated. Same
            // composition runImpact already used; the columnar-capable family is exactly
            // {callers, callees, uses, impact} and this is the last shared site of the first two.
            const std::string attr = "of=\"" + ex( sym ) + "\" defs=\"" + std::to_string( matches.size() )
                                   + "\" count=\"" + std::to_string( result.size() ) + "\""
                                   + ( !wantCallers && bodylessDefsCount > 0 ? " bodyless_defs=\"" + std::to_string( bodylessDefsCount ) + "\"" : "" )
                                   + chRootAttr   // R-E: same root= the XML/JSON branches carry
                                   + pageDisclosure( pab, sizeof( pab ), pw.end - pw.begin, result.size(), pw.end,
                                                     cfg.pageLimit, cfg.pageOffset, false )
                                   + rw::kGraphCountFloorAttrXml;   // §H4 §3.4 — every dialect carries the marker
            emitColumnarSymbolRows( stdout, ing, tag, attr, page, chRootPrefix );
            return 0;
        }

        // L2: --json — same rows, keys mirror the XML attr names (of/count/offset/limit/t/n/p).
        // §A4c: the page disclosure is pageDisclosure()'s JSON row of the syntax table now, not a hand-rolled
        // `offset`+`limit` pair — the SAME seven fields the XML tag two lines below carries (discloseCap=false
        // for the same reason: these two verbs have no display cap of their own, so un-paged discloses nothing).
        if( cfg.json )
        {
            std::printf( "{\"of\":\"%s\",\"defs\":%zu,\"count\":%zu", jsonStr( sym ).c_str(), matches.size(), result.size() );
            if( !wantCallers && bodylessDefsCount > 0 )
            {
                std::printf( ",\"bodyless_defs\":%zu", bodylessDefsCount );
            }
            // R-E: the JSON twin of the XML root= below — right after the leading identifying fields.
            if( chSingleRoot ) { std::printf( ",\"root\":\"%s\"", jsonStr( cfg.roots[0] ).c_str() ); }
            std::printf( "%s%s", pageDisclosure( pab, sizeof( pab ), pw.end - pw.begin, result.size(), pw.end,
                                        cfg.pageLimit, cfg.pageOffset, false, kJsonPageSyntax ),
                         rw::kGraphCountFloorAttrJson );   // §H4 §3.4 — the JSON dialect's spelling of the same marker
            std::printf( ",\"%s\":[", tag );
            printJsonSymbolRows( ing, result, pw.begin, pw.end, chRootPrefix );
            std::printf( "]}" );
            return 0;
        }

        // §P10.6: defs= = resolved definitions this name matched (matches.size()) — the rows below UNION the
        // neighbors of every def, which --uses/--impact already disclose and these two verbs silently hid.
        std::printf( "<%s of=\"%s\" defs=\"%zu\" count=\"%zu\"%s", tag, ex( sym ).c_str(), matches.size(), result.size(), chRootAttr.c_str() );
        if( !wantCallers && bodylessDefsCount > 0 )
        {
            std::printf( " bodyless_defs=\"%zu\"", bodylessDefsCount );
        }
        std::printf( "%s%s>", pageDisclosure( pab, sizeof( pab ), pw.end - pw.begin, result.size(), pw.end,
                                    cfg.pageLimit, cfg.pageOffset, false ),
                     rw::kGraphCountFloorAttrXml );
        for( std::size_t i = pw.begin; i < pw.end; ++i )
        {
            const Symbol&           s  = ing.symbols[ result[i] ];
            const std::string_view  rp = chSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], chRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            std::printf( "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"%s/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line,
                         macroRoleAttr( s.kind ) );
        }
        std::printf( "</%s>", tag );
        return 0;
    }
    return std::nullopt;
}

std::optional<int> runGraphQuery( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         gqSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  gqRootPrefix = gqSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();

    // --graph-query=EXPR (ABS-5): composable node-set operators over the call graph — a FIXED, closed set
    // (sources name()/all; filters kind/cx/fanin/file/layer; bounded transitive-closure callers()/callees(); set
    // joins and/or/not). NOT a Datalog engine. Evaluates to a deterministic sorted node-set, serialized like
    // --callers so the agent can compose questions the fixed verbs did not pre-anticipate.
    if( !cfg.graphQuery.empty() )
    {
        query::Eval         ev( ing, g, cfg.graphQuery );
        std::vector<NodeId> result = ev.run();
        if( !ev.ok )
        {
            std::fprintf( stderr, "ripwire: --graph-query: %s\n", ev.err.c_str() );
            return 1;
        }
        // §P0.5b: a name() literal matching NO indexed symbol is a typo — refuse it the way the eleven other
        // symbol-taking verbs do, with the shared did-you-mean. Only the literal is judged: a name that does
        // resolve while the composed query legitimately selects nothing still reports count="0" below.
        if( !ev.unresolvedNames.empty() )
        {
            const std::string& missingName = ev.unresolvedNames.front();
            std::fprintf( stderr, "%s\n", withDidYouMean( ing, missingName,
                          "ripwire: --graph-query: name(\"" + missingName + "\") matches no symbol in the indexed tree" ).c_str() );
            return 1;
        }
        // Rank the matched set by importance (PageRank) so a BROAD query leads with what matters, and cap it
        // to --top-k (default 200). A node-set query like kind(all,fn) can match the whole graph; emitting all
        // of it is a token bomb, so we never dump more than --top-k and report the true total. Order is
        // (rank desc, id asc) — the id tie-break makes the top-K deterministic, exactly as the default map.
        const auto [ rank, prIters, prConverged ] = rankGraph( g );
        const rw::RankDisclosure prD{ prIters, prConverged, true };   // W2-F: this listing IS PageRank-ordered
        const std::size_t        total = result.size();
        std::sort( result.begin(), result.end(), [ & ]( NodeId a, NodeId b )
                   {
            if( rank[a] != rank[b] ) { return rank[a] > rank[b];
}
            return a < b; } );
        // §P15/§P16: result is now a real, deterministically-ordered (rank desc, id asc) row list — --limit
        // overrides the --top-k display cap exactly like --graph-query's siblings' packTopN/effectiveRowCap
        // composition, and --offset finally pages past it. count= stays the un-windowed total, unaffected by
        // either — a floor over the modelled graph, never an exhaustive one (counts_floor=, V3 L-4).
        const int         gqHistCap = cfg.topK > 0 ? cfg.topK : int( total );
        const PageWindow  gqPw      = pageWindow( total, effectiveRowCap( cfg.pageLimit, gqHistCap ), cfg.pageOffset );
        const std::size_t keep      = gqPw.end - gqPw.begin;

        std::vector<char> esc;
        const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // §H4 §3.4 / V3 M-1: --graph-query is the SIXTH surface that counts off this same call graph — its
        // `callers(name("X"),1)` reports the identical number --callers does — and it shipped the marker on
        // neither. That is the §B4 echo-site shape src/graphlegend.h's own header indicts, so the shared
        // constants land here too rather than a sixth wording.
        std::printf( "<!-- ripwire graph-query: a fixed-operator node-set query over the call graph (sources "
                     "name/all; filters kind/cx/fanin/file/layer; bounded closure callers/callees; joins and/or/not), "
                     "ranked by importance + capped at the top-k limit (default 200); narrow the query or raise top-k for more. NOT Datalog. "
                     "%s%s-->", rw::graphCountDisclosure().c_str(), rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str() );
        // §P8 vocabulary (see src/pageview.h, THE TRUNCATION VOCABULARY): count= is the true total and
        // shown= the --top-k slice, but capped= was missing — so a caller reading a 200-row answer had to
        // know the default top-k to tell a complete result from a truncated one. Rule 3: the bit is always
        // emitted alongside shown=, so "no capped attribute" is never something a parser must interpret.
        char gqAb[ kPageDisclosureCap ];
        const std::string gqRootAttr = gqSingleRoot ? ( " root=\"" + ex( cfg.roots[0] ) + "\"" ) : std::string();
        std::printf( "<query expr=\"%s\" count=\"%zu\"%s%s%s%s>",
                     ex( cfg.graphQuery ).c_str(), total,
                     pageDisclosure( gqAb, sizeof( gqAb ), keep, total, gqPw.end, cfg.pageLimit, cfg.pageOffset, true ),
                     rw::kGraphCountFloorAttrXml, gqRootAttr.c_str(), rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ).c_str() );
        for( std::size_t ri = gqPw.begin; ri < gqPw.end; ++ri )
        {
            const NodeId            c  = result[ ri ];
            const Symbol&           s  = ing.symbols[c];
            const std::string_view  rp = gqSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], gqRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            std::printf( "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"/>",
                         symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line );
        }
        std::printf( "</query>" );
        return 0;
    }
    return std::nullopt;
}

// §P10.2: --uses' selector-parsing seam, factored out so the file:name fix adds a new small symbol
// instead of growing the already-hot runUses. fileQualified excludes a canonical id ("::") — that was
// never a use-site match key and stays byte-identical. siteMatchName filters sites (name-only, can't
// split per-def); suggestName is the NAME half for did-you-mean (--expand/--outline's Lane H rule), so a
// "file:" prefix never again poisons the suggester (the constant "srcmut_sigchange" bug). defsOfName is the
// un-narrowed def count for the disclosure attribute — meaningful only when fileQualified.
struct UsesSelector { bool fileQualified; std::string_view siteMatchName; std::string_view suggestName; std::size_t defsOfName; };
inline UsesSelector resolveUsesSelector( const rw::IngestResult& ing, std::string_view sym, std::size_t defsCount )
{
    UsesSelector u;
    u.fileQualified = sym.find( "::" ) == std::string_view::npos && sym.find( ':' ) != std::string_view::npos;
    std::string_view file;
    if( u.fileQualified )
    {
        rw::splitQualifiedSpec( sym, file, u.siteMatchName );
    }
    else
    {
        u.siteMatchName = sym;
    }
    rw::splitQualifiedSpec( sym, file, u.suggestName );
    u.defsOfName = u.fileQualified ? rw::resolveAllByName( ing, u.siteMatchName ).size() : defsCount;
    return u;
}

// §A6b: the file:name qualifier must narrow the ANSWER, not just the label. Pre-fix it narrowed defs= alone,
// so --uses=src/notes.h:empty and --uses=src/scipoverlay.h:empty returned byte-identical 1211-row sets — the
// selector looked honoured and was not. What CAN be narrowed soundly is the CALL role: a call site's resolved
// target is exactly what the call graph already records, so "keep the call sites whose enclosing symbol has a
// resolved edge to one of the chosen defs" is --callers' own narrowing read in the other direction — same
// relation, same evidence, no new guess. read/write/import/extends carry no resolution at all (a Reference
// holds a NAME), so they stay name-matched and the header says so.
//
// Returns a per-enclosing-symbol flag array (indexed by NodeId), never a set of sites: the ONE pass over
// ing.references that collects sites then tests membership in O(1), instead of re-walking the graph per site.
inline std::vector<char> usesChosenCallers( const rw::IngestResult& ing, const rw::Graph& g, std::span<const rw::NodeId> defs )
{
    using namespace rw;
    std::vector<char> isChosenCaller( ing.symbols.size(), 0 );
    const auto*       ro = g.inEdges.rowOffsets();
    const auto*       ci = g.inEdges.colIndices();
    for( NodeId def : defs )
    {
        if( def >= ing.symbols.size() )
        {
            continue;
        }
        for( std::uint32_t k = ro[def]; k < ro[def + 1]; ++k )
        {
            if( NodeId c = ci[k]; c < isChosenCaller.size() )
            {
                isChosenCaller[c] = 1;
            }
        }
    }
    return isChosenCaller;
}

// ONE use-site row: (file, line, role, enclosing canonical id). File scope ⇒ `in` empty.
struct UseSite { std::uint32_t fileId; std::uint32_t line; rw::RefRole role; std::string in; };

// The use-site scan: references whose NAME matches the selector and that carry a real use-site role. Markdown
// doc-mentions / wikilinks and HAS-A compose edges are NOT name use-sites (excluded). Returns the rows in the
// deterministic emission order (file path, line, role, enclosing-id) plus `callSitesOfName` — the call-role
// total BEFORE the §A6b narrowing, which is what the disclosure attribute reports.
inline std::pair<std::vector<UseSite>, std::size_t>
collectUseSites( const rw::IngestResult& ing, const UsesSelector& sel, std::span<const char> isChosenCaller )
{
    using namespace rw;
    std::vector<UseSite> sites;
    std::size_t          callSitesOfName = 0;
    for( const Reference& r : ing.references )
    {
        if( r.calleeName != sel.siteMatchName )
        {
            continue;
        }
        if( r.isCompose || r.isDocLink )
        {
            continue; // type edge / doc mention — not a use-site
        }
        if( r.lang == Lang::Markdown )
        {
            continue; // markdown [[wikilink]] — not a code use-site
        }
        if( r.role == RefRole::Call )
        {
            ++callSitesOfName;
        }
        // the file: qualifier's call-role narrowing. A file-scope call site (fromSymbol==kNoNode) carries no
        // resolved edge to test, so it cannot be SHOWN to reach the chosen def and is dropped with the rest —
        // call_sites_of_name= keeps the size of what was dropped visible.
        if( sel.fileQualified && r.role == RefRole::Call && ( r.fromSymbol >= isChosenCaller.size() || !isChosenCaller[r.fromSymbol] ) )
        {
            continue;
        }
        std::string in;
        if( r.fromSymbol != kNoNode && r.fromSymbol < ing.symbols.size() )
        {
            const Symbol& fs = ing.symbols[ r.fromSymbol ];
            in = canonicalId( ing.files[ fs.fileId ], fs.scope, fs.name );
        }
        sites.push_back( { r.fileId, r.line, r.role, std::move( in ) } );
    }

    std::sort( sites.begin(), sites.end(), [ & ]( const UseSite& a, const UseSite& b )
               {
        if( a.fileId != b.fileId ) { return ing.files[ a.fileId ] < ing.files[ b.fileId ];
}
        if( a.line   != b.line ) {   return a.line < b.line;
}
        if( a.role   != b.role ) {   return std::uint8_t( a.role ) < std::uint8_t( b.role );
}
        return a.in < b.in; } );
    return { std::move( sites ), callSitesOfName };
}

// §A6b(ii): the refusal for a file: qualifier that names a file defining nothing of that name. Pre-fix --uses
// ANSWERED such a selector — with the name-wide site set and external="1" — so the one spelling that is
// certainly a mistake got the most confident-looking answer, while --callers/--impact/--edit-check all
// refused it. The sibling prefix ("symbol not found:") is kept verbatim because that is what an agent greps
// for; what is added is the list of files that DO define the name, so the retry is one paste away.
//
// §B4.2: that MESSAGE now lives in selectorrefuse.h and every SYM-taking verb speaks it — this arm is what
// it was generalized FROM, so what stays here is only the exit code. The wording is unchanged (a file-list
// cap with an explicit remainder is the one addition, shared by all six arms).
inline int refuseUsesFileQualifier( const rw::IngestResult& ing, std::string_view sym, const UsesSelector& )
{
    std::fprintf( stderr, "%s\n", rw::selectorNotFoundMessage( ing, "ripwire: --uses symbol not found: ",
                                                                sym, "--uses=" ).c_str() );
    return 1;
}

// §P8 G1 — --uses was the one verb that disclosed NOTHING: it accepted --limit/--offset, ignored both, and
// carried no shown=/capped= either, so a 118-site listing looked the same as a 3-site one to a parser. It
// pages now, with NO display cap: completeness is this verb's whole contract, so a bare --uses must keep
// printing every site (discloseCap=false, byte-identical un-paginated) and only an explicit --limit windows.
std::optional<int> runUses( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         usSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  usRootPrefix = usSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  usEsc;
    const std::string  usRootAttr   = usSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], usEsc ) ) + "\"" ) : std::string();

    // --uses=SYM (ABS-3): the use-site index for SYM — the resolvable places its name is referenced, with a
    // §H4 note: NOT "complete". The index is a FLOOR (counts_floor=, src/graphlegend.h), and the word this
    // comment used to carry is the same absolutism the legend shipped for eight rounds.
    // ROLE (call/read/write/import/extends) and p="file:line", plus the enclosing symbol. Reference-name-based
    // (same heuristic level as the call edges), so a BARE name shared by several symbols reports the union of
    // all their use-sites. external="1" when SYM has NO in-corpus definition at all. §P10.2/§A6b: SYM also
    // accepts "file:name" (resolveUsesSelector) — that narrows defs= AND the call-role sites (usesChosenCallers);
    // the other roles stay name-matched, and defs_of_name=/call_sites_of_name= disclose both gaps.
    // Deterministic: use-sites sorted by (file path, line, role, enclosing-id); every value XML-escaped.
    if( !cfg.usesSym.empty() )
    {
        const std::string_view sym = cfg.usesSym;

        // resolveAllByNameQualified — the SAME resolver --callers/--impact/--expand/--path use — so --uses
        // finally accepts "file:name" too; byte-identical to the old resolveAllByName on a bare name/id.
        const std::vector<NodeId> defs = resolveAllByNameQualified( ing, sym );
        const UsesSelector        sel  = resolveUsesSelector( ing, sym, defs.size() );

        // §A6b(iii): external="1" is the claim "this name has NO definition in the indexed tree" — it may only
        // be made when that is what was measured. With a file: qualifier defs= is a NARROWED count, so the
        // un-narrowed defs_of_name= is the one that can license the claim; pre-fix a non-defining qualifier
        // printed external="1" beside defs_of_name="3", which says the opposite in the same element.
        const bool external = defs.empty() && sel.defsOfName == 0;
        VERIFY( !( external && sel.defsOfName > 0 ) );

        // §A6b(i): the call sites that resolve to the CHOSEN defs (empty ⇒ nothing narrows, every role stays
        // name-matched, and the un-qualified output is byte-identical).
        const std::vector<char> isChosenCaller = sel.fileQualified ? usesChosenCallers( ing, g, defs ) : std::vector<char>{};

        // the sorted use-sites, plus the un-narrowed call-role total the disclosure reports.
        const auto [ sites, callSitesOfName ] = collectUseSites( ing, sel, isChosenCaller );

        // §A6b(ii): a file: qualifier naming a file with NO definition of the name is a WRONG SELECTOR — its
        // three siblings all refuse it, and so does this one now.
        if( defs.empty() && sel.fileQualified )
        {
            return refuseUsesFileQualifier( ing, sym, sel );
        }

        // r27-emitters T3 / §P10.2: external="1" is a real answer, a typo is not — distinguished by the
        // sites, not the defs. The message states only what defs.empty() proves (no indexed definition),
        // never "no reference site" (sites ignores any file: qualifier, so its emptiness isn't a property
        // of the typed selector — the old wording was also false whenever the file:name bug this fixes
        // made defs wrongly empty for a selector that DID resolve).
        if( defs.empty() && sites.empty() )
        {
            std::fprintf( stderr, "%s\n", withDidYouMean( ing, sel.suggestName,
                          "ripwire: --uses selector matched no indexed definition: " + std::string( sym ) ).c_str() );
            return 1;
        }

        // §A6b: the qualifier disclosure, built once for both emitters. defs_of_name= is the un-narrowed DEF
        // count; narrowed_roles="call" names which roles the qualifier actually narrowed and call_sites_of_name=
        // is that role's un-narrowed total, so "how much did the qualifier drop" is arithmetic, not a guess.
        const std::string selectorAttrs = sel.fileQualified
            ? " defs_of_name=\"" + std::to_string( sel.defsOfName ) + "\" narrowed_roles=\"call\" call_sites_of_name=\"" + std::to_string( callSitesOfName ) + "\""
            : std::string{};

        std::vector<char> esc;
        const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        // §H4 §3.4 item 2: the opener is shared with the MCP twin (src/graphlegend.h) — the two were
        // byte-identical copies of a sentence that promised "every use-site of SYM", which the qualified-call
        // round proved false and which a name-based static reference index cannot make true.
        std::printf( "%s"
                     "Reference-name-based (same heuristic level as call edges) — verify in source if a name is overloaded. "
                     "external=\"1\" ⇒ SYM has no definition in the indexed tree under ANY spelling (stdlib/third-party) — "
                     "never merely none in the file you qualified with (that spelling refuses instead). "
                     "A \"file:name\" SYM narrows defs= AND the role=\"call\" sites, which are kept only where the call RESOLVES to a "
                     "chosen def (the callers verb's own narrowing, read the other way, so the two agree); read/write/import/extends carry no "
                     "resolution and stay name-matched across every def sharing the name. narrowed_roles= names what narrowed, and "
                     "defs_of_name=/call_sites_of_name= (file: qualifier only) are the un-narrowed totals. "
                     "%s-->%s", rw::kUsesLegendOpen, rw::graphCountDisclosure().c_str(), rw::rootRelPathsLegend( usSingleRoot ) );
        // §P8 G1: the page window over the sorted sites; count= stays the un-windowed total (note above
        // runUses) — of the sites the extractor RESOLVED, which counts_floor= is there to say (V3 L-4).
        const PageWindow  upw      = pageWindow( sites.size(), cfg.pageLimit, cfg.pageOffset );
        const std::size_t pageRows = upw.end - upw.begin;
        char              upab[ kPageDisclosureCap ];
        const char* const upage    = pageDisclosure( upab, sizeof( upab ), pageRows, sites.size(), upw.end, cfg.pageLimit, cfg.pageOffset, false );

        // --format=columnar (RESEARCH lever 1): the use-site rows as a path-table + parallel arrays.
        if( cfg.columnar )
        {
            std::vector<std::uint32_t> ufiles, ulines;
            std::vector<RefRole>       uroles;
            std::vector<std::string>   uins;
            ufiles.reserve( pageRows ); ulines.reserve( pageRows ); uroles.reserve( pageRows ); uins.reserve( pageRows );
            for( std::size_t i = upw.begin; i < upw.end; ++i )
            { const UseSite& u = sites[i];  ufiles.push_back( u.fileId ); ulines.push_back( u.line ); uroles.push_back( u.role ); uins.push_back( u.in ); }
            // §B1.1: std::string composition, not a fixed `char attrbuf[]` — the 512-byte buffer here cut
            // `of=` mid-value (invalid XML at exit 0) once the echoed symbol name passed ~480 chars, which
            // a markdown SECTION heading reaches routinely. Same shape as runImpact / the callers arm.
            const std::string attr = "of=\"" + ex( sym ) + "\" defs=\"" + std::to_string( defs.size() )
                                   + "\" external=\"" + ( external ? "1" : "0" ) + "\" count=\"" + std::to_string( sites.size() ) + "\""
                                   + selectorAttrs + usRootAttr + upage + rw::kGraphCountFloorAttrXml;   // §H4 §3.4
            emitColumnarUseSites( stdout, ing, attr, ufiles, ulines, uroles, uins, usRootPrefix );
            return 0;
        }

        std::printf( "<uses of=\"%s\" defs=\"%zu\" external=\"%d\" count=\"%zu\"%s%s%s%s>",
                     ex( sym ).c_str(), defs.size(), external ? 1 : 0, sites.size(), selectorAttrs.c_str(), usRootAttr.c_str(), upage,
                     rw::kGraphCountFloorAttrXml );
        for( std::size_t siteIndex = upw.begin; siteIndex < upw.end; ++siteIndex )
        {
            const UseSite&          u  = sites[ siteIndex ];
            const std::string_view  rp = usSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ u.fileId ], usRootPrefix ) : std::string_view( ing.files[ u.fileId ] );
            std::printf( "<u role=\"%s\" p=\"%s:%u\"", refRoleTag( u.role ), ex( rp ).c_str(), u.line );
            // §P8 collision: `in=` means three things tool-wide — enclosing NAME (--grep/--match/--lint),
            // fan-in COUNT (--for/--pack-task/--exemplar), and here the enclosing symbol's canonical ID. The
            // first two are load-bearing and stay; this one had ZERO consumers, so it is the one that moves.
            // `in_id=` keeps the "enclosing" sense while saying it is an ID, per the index-vs-count rule.
            if( !u.in.empty() )
            {
                std::printf( " in_id=\"%s\"", ex( u.in ).c_str() );
            }
            std::printf( "/>" );
        }
        std::printf( "</uses>" );
        return 0;
    }
    return std::nullopt;
}

// ── G4 VERIFY-A-CLAIM: --verify="CLAIM" — one structured claim, a three-valued verdict, evidence inline ──
//
// The claim grammar and the verdict/limit vocabularies live in src/verify.h; test/verifycheck.sh pins the
// whole contract. This handler REUSES the sibling machinery verb-for-verb — shortestPathAny (--path),
// collectUseSites (--uses), grepCollect/grepEnrich (--grep), transitiveCallers (--impact) — because the gap
// the usage mine measured was never the data: it was that verification took a multi-call chain plus manual
// reading. The honesty split is the heart: a witness CONFIRMS; only a complete literal scan (or a printed
// witness against an absence-claim) REFUTES; every model-bounded absence is NOT-ESTABLISHED with limit=
// naming the bound. complete= is computed from the scan's own honesty bits (T1) and never co-occurs with
// counts_floor= — a false completeness claim is the worst bug this tool can ship.
std::optional<int> runVerify( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;
    const Graph&        g   = d.g;

    if( cfg.verifyClaim.empty() )
    {
        return std::nullopt;
    }

    const verify::Claim claim = verify::parseClaim( cfg.verifyClaim );
    if( !claim.ok )
    {
        std::fprintf( stderr, "%s\n", claim.err.c_str() );
        return 1;
    }

    // bounded evidence SAMPLE — verdicts are always computed on the FULL sets, only the printed rows
    // window; the root's disclosure pair says so per the truncation vocabulary (src/pageview.h rules 1-3).
    constexpr int kEvidenceCap = 20;

    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    // the sibling verbs' own row grammar for symbol evidence (--path/--graph-query rows)
    const auto emitSymRow = [ & ]( NodeId n )
    {
        const Symbol& s = ing.symbols[n];
        std::printf( "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( ing.files[ s.fileId ] ).c_str(), s.line );
    };

    // the FILE argument: a path substring over the indexed tree (filePathContains — the file: qualifier's
    // own rule). A claim about a file the index never saw REFUSES: no verdict about it could be a
    // measurement, and the skipped verb is where "why is it not indexed" lives.
    std::vector<char> fileFlags;
    const auto        matchFiles = [ & ]( std::string_view filePat ) -> bool
    {
        fileFlags.assign( ing.files.size(), 0 );
        bool any = false;
        for( std::size_t fileIndex = 0; fileIndex < ing.files.size(); ++fileIndex )
        {
            if( filePathContains( ing.files[ fileIndex ], filePat ) )
            {
                fileFlags[ fileIndex ] = 1;
                any = true;
            }
        }
        return any;
    };
    const auto refuseFile = [ & ]( std::string_view filePat ) -> int
    {
        std::fprintf( stderr, "ripwire: --verify file matched nothing indexed: %.*s — FILE is a path substring over the indexed tree; "
                              "files the ingest skipped are not searchable (the --skipped verb lists exactly which, with reasons)\n",
                      int( filePat.size() ), filePat.data() );
        return 1;
    };

    // the root opener, shared by every shape so the attribute ORDER is fixed: claim, shape, verdict,
    // shape-specific facts, limit=, then the honesty attribute (complete= XOR counts_floor=), then the
    // disclosure pair. `honesty` is exactly one of kGraphCountFloorAttrXml / " complete=\"1\"" / "".
    const auto openRoot = [ & ]( const char* verdict, const std::string& facts, const char* limit, const char* honesty, const char* pageTail )
    {
        VERIFY( std::size_t( claim.shape ) < std::size( verify::kShapeTags ) );   // the parser is the only producer, every value in range
        std::printf( "%s<verify claim=\"%s\" shape=\"%s\" verdict=\"%s\"%s", verify::kVerifyLegend,
                     ex( cfg.verifyClaim ).c_str(), verify::kShapeTags[ std::size_t( claim.shape ) ], verdict, facts.c_str() );
        if( limit[0] != '\0' )
        {
            std::printf( " limit=\"%s\"", limit );
        }
        std::printf( "%s%s>", honesty, pageTail );
    };

    char              pab[ kPageDisclosureCap ];
    const auto        pageTailOf = [ & ]( std::size_t shownRows, std::size_t total, std::size_t windowEnd ) -> const char*
    { return pageDisclosure( pab, sizeof( pab ), shownRows, total, windowEnd, 0, 0, true ); };

    // ── calls( A , B ) — does A transitively call B (directed, name-based call graph) ────────────────
    if( claim.shape == verify::ClaimShape::Calls )
    {
        const std::vector<NodeId> srcDefs = resolveAllByNameQualified( ing, claim.arg1 );
        const std::vector<NodeId> dstDefs = resolveAllByNameQualified( ing, claim.arg2 );
        if( srcDefs.empty() || dstDefs.empty() )
        {
            const std::string_view missing = srcDefs.empty() ? claim.arg1 : claim.arg2;
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --verify symbol not found: ", missing, "--verify=" ).c_str() );
            return 1;
        }
        const std::vector<NodeId> path = rw::shortestPathAny( g, srcDefs, dstDefs );
        const std::string         facts = " from_defs=\"" + std::to_string( srcDefs.size() ) + "\" to_defs=\"" + std::to_string( dstDefs.size() ) + "\""
                                        + ( path.empty() ? std::string{} : " hops=\"" + std::to_string( path.size() - 1 ) + "\"" );
        if( !path.empty() )
        {
            openRoot( "confirmed", facts, "", rw::kGraphCountFloorAttrXml, pageTailOf( path.size(), path.size(), path.size() ) );
            for( NodeId n : path )
            {
                emitSymRow( n );
            }
        }
        else
        {
            openRoot( "not-established", facts, verify::kLimitCallGraphFloor, rw::kGraphCountFloorAttrXml, pageTailOf( 0, 0, 0 ) );
        }
        std::printf( "</verify>" );
        return 0;
    }

    // ── uses( SYM ) / unused( SYM ) — rides the --uses reference index (a FLOOR, and the verdicts obey it) ─
    if( claim.shape == verify::ClaimShape::Uses || claim.shape == verify::ClaimShape::Unused )
    {
        const std::string_view    sym  = claim.arg1;
        const std::vector<NodeId> defs = resolveAllByNameQualified( ing, sym );
        const UsesSelector        sel  = resolveUsesSelector( ing, sym, defs.size() );
        const std::vector<char>   isChosenCaller = sel.fileQualified ? usesChosenCallers( ing, g, defs ) : std::vector<char>{};
        const auto [ sites, callSitesOfName ]    = collectUseSites( ing, sel, isChosenCaller );
        (void) callSitesOfName;
        if( defs.empty() && sites.empty() )
        {
            std::fprintf( stderr, "%s\n", withDidYouMean( ing, sel.suggestName,
                          "ripwire: --verify symbol not found: " + std::string( sym ) ).c_str() );
            return 1;
        }
        const bool        external = defs.empty() && sel.defsOfName == 0;
        const std::size_t total    = sites.size();
        const PageWindow  w        = pageWindow( total, kEvidenceCap, 0 );
        const std::string facts    = " defs=\"" + std::to_string( defs.size() ) + "\" external=\"" + ( external ? "1" : "0" )
                                   + "\" count=\"" + std::to_string( total ) + "\"";
        const bool        anySites = total > 0;
        const char*       verdict  = claim.shape == verify::ClaimShape::Uses ? ( anySites ? "confirmed" : "not-established" )
                                                                        : ( anySites ? "refuted"   : "not-established" );
        openRoot( verdict, facts, anySites ? "" : verify::kLimitReferenceFloor, rw::kGraphCountFloorAttrXml,
                  pageTailOf( w.end - w.begin, total, w.end ) );
        for( std::size_t siteIndex = w.begin; siteIndex < w.end; ++siteIndex )
        {
            const UseSite& u = sites[ siteIndex ];
            std::printf( "<u role=\"%s\" p=\"%s:%u\"", refRoleTag( u.role ), ex( ing.files[ u.fileId ] ).c_str(), u.line );
            if( !u.in.empty() )
            {
                std::printf( " in_id=\"%s\"", ex( u.in ).c_str() );
            }
            std::printf( "/>" );
        }
        std::printf( "</verify>" );
        return 0;
    }

    // ── contains( FILE , "LIT" ) — the literal-scan shape, and the one that can serve a TRUE complete no ─
    if( claim.shape == verify::ClaimShape::Contains )
    {
        if( !matchFiles( claim.arg1 ) )
        {
            return refuseFile( claim.arg1 );
        }
        const GrepCollection    found = grepCollect( ing, std::string( claim.arg2 ) );
        std::vector<GrepRawHit> inFile;
        for( const GrepRawHit& r : found.raw )
        {
            if( fileFlags[ r.fileId ] )
            {
                inFile.push_back( r );
            }
        }
        const std::size_t total       = inFile.size();
        const bool        clean       = found.cleanScan();
        const PageWindow  w           = pageWindow( total, kEvidenceCap, 0 );
        const bool        windowWhole = w.begin == 0 && w.end == total;
        const bool        complete    = clean && windowWhole;   // T1: the scan's own honesty bits decide, never the verdict
        const char*       verdict     = total > 0 ? "confirmed" : ( clean ? "refuted" : "not-established" );
        const char*       limit       = ( total == 0 && !clean ) ? ( found.isBudgetReached ? verify::kLimitCollectionCeiling : verify::kLimitScanDegraded ) : "";
        const char*       honesty     = complete ? " complete=\"1\"" : ( !clean ? rw::kGraphCountFloorAttrXml : "" );
        openRoot( verdict, " hits=\"" + std::to_string( total ) + "\"", limit, honesty, pageTailOf( w.end - w.begin, total, w.end ) );
        const std::vector<GrepHit> hits = grepEnrich( ing, std::span<const GrepRawHit>( inFile ).subspan( w.begin, w.end - w.begin ) );
        for( const GrepHit& h : hits )
        {
            std::printf( "<hit p=\"%s:%u\" in=\"%s\"><m><![CDATA[", ex( ing.files[ h.fileId ] ).c_str(), h.line, ex( h.enclosing ).c_str() );
            std::string safe;
            appendCdataSafe( h.text, safe );
            std::fwrite( safe.data(), 1, safe.size(), stdout );
            std::printf( "]]></m></hit>" );
        }
        std::printf( "</verify>" );
        return 0;
    }

    // ── defines( FILE , SYM ) — symbol-table witness first, then the literal check that can refute ────
    if( claim.shape == verify::ClaimShape::Defines )
    {
        if( !matchFiles( claim.arg1 ) )
        {
            return refuseFile( claim.arg1 );
        }
        // deliberately NO unknown-symbol refusal here: the claim is about the FILE, and "no file defines
        // this name anywhere" is a legitimate answer an agent asks for — the legend says so.
        const std::vector<NodeId> defsOfName = resolveAllByName( ing, claim.arg2 );
        std::vector<NodeId>       defsInFile;
        for( NodeId n : defsOfName )
        {
            if( fileFlags[ ing.symbols[n].fileId ] )
            {
                defsInFile.push_back( n );
            }
        }
        if( !defsInFile.empty() )
        {
            const PageWindow  w     = pageWindow( defsInFile.size(), kEvidenceCap, 0 );
            const std::string facts = " defs=\"" + std::to_string( defsInFile.size() ) + "\" defs_of_name=\"" + std::to_string( defsOfName.size() ) + "\"";
            openRoot( "confirmed", facts, "", rw::kGraphCountFloorAttrXml, pageTailOf( w.end - w.begin, defsInFile.size(), w.end ) );
            for( std::size_t defIndex = w.begin; defIndex < w.end; ++defIndex )
            {
                emitSymRow( defsInFile[ defIndex ] );
            }
            std::printf( "</verify>" );
            return 0;
        }
        // no extracted definition — the literal check: does the name token occur in the file's bytes at
        // all? Absent under a clean scan ⇒ a COMPLETE no (the file cannot define what it never spells;
        // preprocessor token-pasting is outside the claim, like every literal claim is index-scoped).
        // Present ⇒ the extraction floor, never a refutation.
        const GrepCollection    found = grepCollect( ing, std::string( claim.arg2 ) );
        std::vector<GrepRawHit> inFile;
        for( const GrepRawHit& r : found.raw )
        {
            if( fileFlags[ r.fileId ] )
            {
                inFile.push_back( r );
            }
        }
        const std::size_t occ   = inFile.size();
        const bool        clean = found.cleanScan();
        const std::string facts = " defs=\"0\" defs_of_name=\"" + std::to_string( defsOfName.size() ) + "\" occurrences=\"" + std::to_string( occ ) + "\"";
        if( occ > 0 )
        {
            const PageWindow w = pageWindow( occ, kEvidenceCap, 0 );
            openRoot( "not-established", facts, verify::kLimitExtractionFloor, rw::kGraphCountFloorAttrXml, pageTailOf( w.end - w.begin, occ, w.end ) );
            const std::vector<GrepHit> hits = grepEnrich( ing, std::span<const GrepRawHit>( inFile ).subspan( w.begin, w.end - w.begin ) );
            for( const GrepHit& h : hits )
            {
                std::printf( "<hit p=\"%s:%u\" in=\"%s\"><m><![CDATA[", ex( ing.files[ h.fileId ] ).c_str(), h.line, ex( h.enclosing ).c_str() );
                std::string safe;
                appendCdataSafe( h.text, safe );
                std::fwrite( safe.data(), 1, safe.size(), stdout );
                std::printf( "]]></m></hit>" );
            }
        }
        else if( clean )
        {
            openRoot( "refuted", facts, "", " complete=\"1\"", pageTailOf( 0, 0, 0 ) );
        }
        else
        {
            openRoot( "not-established", facts, found.isBudgetReached ? verify::kLimitCollectionCeiling : verify::kLimitScanDegraded,
                      rw::kGraphCountFloorAttrXml, pageTailOf( 0, 0, 0 ) );
        }
        std::printf( "</verify>" );
        return 0;
    }

    // ── reaches( SYM , "FILE" | LAYER ) — does code there transitively CALL the target (impact-based) ─
    VERIFY( claim.shape == verify::ClaimShape::Reaches );
    const std::vector<NodeId> targetDefs = resolveAllByNameQualified( ing, claim.arg1 );
    if( targetDefs.empty() )
    {
        std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --verify symbol not found: ", claim.arg1, "--verify=" ).c_str() );
        return 1;
    }
    if( claim.arg2Quoted )
    {
        if( !matchFiles( claim.arg2 ) )
        {
            return refuseFile( claim.arg2 );
        }
    }
    else if( !query::isKnownLayerWord( claim.arg2 ) )
    {
        std::fprintf( stderr, "ripwire: --verify reaches: '%.*s' is not a built-in layer (%.*s) — quote it (\"%.*s\") to mean a FILE path substring\n",
                      int( claim.arg2.size() ), claim.arg2.data(),
                      int( std::string_view( query::kLayerVocabulary ).size() ), std::string_view( query::kLayerVocabulary ).data(),
                      int( claim.arg2.size() ), claim.arg2.data() );
        return 1;
    }
    const std::vector<NodeId> reach = rw::transitiveCallers( g, targetDefs );
    std::vector<NodeId>       witnesses;
    for( NodeId n : reach )
    {
        const std::uint32_t fileId = ing.symbols[n].fileId;
        if( claim.arg2Quoted ? bool( fileFlags[ fileId ] ) : ( builtinLayer( ing.files[ fileId ] ) != nullptr && claim.arg2 == builtinLayer( ing.files[ fileId ] ) ) )
        {
            witnesses.push_back( n );
        }
    }
    const std::string facts = " target_defs=\"" + std::to_string( targetDefs.size() ) + "\" witnesses=\"" + std::to_string( witnesses.size() ) + "\"";
    if( !witnesses.empty() )
    {
        const std::vector<NodeId> path = rw::shortestPathAny( g, witnesses, targetDefs );
        openRoot( "confirmed", facts + ( path.empty() ? std::string{} : " hops=\"" + std::to_string( path.size() - 1 ) + "\"" ),
                  "", rw::kGraphCountFloorAttrXml, pageTailOf( path.size(), path.size(), path.size() ) );
        for( NodeId n : path )
        {
            emitSymRow( n );
        }
    }
    else
    {
        openRoot( "not-established", facts, verify::kLimitCallGraphFloor, rw::kGraphCountFloorAttrXml, pageTailOf( 0, 0, 0 ) );
    }
    std::printf( "</verify>" );
    return 0;
}

// §P11.9: --external-surface's accumulation + row-building, pulled out of runExternalSurface so the extra
// per-REFERENCING-LANGUAGE bookkeeping (a name called from several languages, e.g. `printf` — C's stdio
// call AND Bash's builtin, used to merge into one row, summing unrelated surfaces and burying the smaller
// one) lands as a function CALL in the verb body, not another decision point inside it. Slot array indexed
// by the Lang enum (model.h; 16 values, small and POD) rather than a hashable composite key or nested map.
struct ExtSurfaceAcc  { std::uint32_t refs = 0; std::uint32_t calls = 0; };
struct ExtSurfaceName { std::string name; rw::Lang lang; std::uint32_t refs; std::uint32_t calls; };
constexpr std::size_t kExtSurfaceLangSlots = 16;   // cardinality of enum class rw::Lang (model.h)

inline rw::HashMap<std::string, std::array<ExtSurfaceAcc, kExtSurfaceLangSlots>>
accumulateExternalSurface( const rw::IngestResult& ing, const rw::HashMap<std::string, char>& defined )
{
    using namespace rw;
    // count references to names that have NO in-corpus def. We count only CALL / IMPORT / EXTENDS sites: an
    // undefined name we INVOKE / #include / derive-from is a genuine external dependency, whereas a bare
    // read/write of an undefined identifier is overwhelmingly a LOCAL variable (no symbol node), which would
    // otherwise swamp the surface with single-letter noise. `calls` is the call subset of `refs`.
    rw::HashMap<std::string, std::array<ExtSurfaceAcc, kExtSurfaceLangSlots>> ext;
    for( const Reference& r : ing.references )
    {
        if( r.isCompose || r.isDocLink )
        {
            continue; // type edge / doc mention — not a code reference
        }
        if( r.lang == Lang::Markdown )
        {
            continue; // markdown link — not a code reference
        }
        if( r.calleeName.empty() )
        {
            continue;
        }
        if( r.role == RefRole::Read || r.role == RefRole::Write )
        {
            continue; // a bare read/write ⇒ a local, not a dependency
        }
        if( defined.contains( r.calleeName ) )
        {
            continue; // DEFINED in-corpus → not external (set-difference)
        }
        const std::size_t langSlot = std::size_t( r.lang ) < kExtSurfaceLangSlots ? std::size_t( r.lang ) : 0;
        ExtSurfaceAcc& e = ext[ r.calleeName ][ langSlot ];
        ++e.refs;
        if( r.role == RefRole::Call )
        {
            ++e.calls;
        }
    }
    return ext;
}

inline std::vector<ExtSurfaceName>
buildExternalSurfaceRows( const rw::HashMap<std::string, std::array<ExtSurfaceAcc, kExtSurfaceLangSlots>>& ext )
{
    std::vector<ExtSurfaceName> names;
    names.reserve( ext.size() );
    for( const auto& [ nm, slots ] : ext )
    {
        for( std::size_t li = 0; li < kExtSurfaceLangSlots; ++li )
        {
            if( slots[li].refs )
            {
                names.push_back( { nm, rw::Lang( li ), slots[li].refs, slots[li].calls } );
            }
        }
    }
    std::sort( names.begin(), names.end(), []( const ExtSurfaceName& a, const ExtSurfaceName& b )
               {
                   if( a.refs != b.refs )
                   {
                       return a.refs > b.refs; // most-leaned-on first
                   }
                   if( a.name != b.name )
                   {
                       return a.name < b.name; // then name asc
                   }
                   return a.lang < b.lang;                          // then lang (deterministic tie-break for a split name)
               } );
    return names;
}

std::optional<int> runExternalSurface( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;

    // --external-surface (ABS-3): the set-difference DEPENDENCY SURFACE — names REFERENCED in the corpus but
    // never DEFINED in it (the stdlib / third-party the code leans on). Counts only real use-sites (call/read/
    // write/import/extends), excludes doc-mentions/compose/markdown. Deterministic: sorted by (refCount desc,
    // name asc). Every in-corpus-defined name is, by construction, excluded (that is the set-difference).
    if( cfg.externalSurface )
    {
        // in-corpus definition names (final segment), for the set-difference membership test.
        HashMap<std::string, char> defined;
        defined.reserve( ing.symbols.size() );
        for( const Symbol& s : ing.symbols )
        {
            if( s.kind != SymKind::Section )
            { // markdown headings are doc structure, not code defs
                defined.emplace( s.name, char( 1 ) );
            }
        }

        const auto ext   = accumulateExternalSurface( ing, defined );
        const auto names = buildExternalSurfaceRows( ext );

        // §P15/§P16: names is deterministically sorted (refs desc, name asc, lang asc — buildExternalSurfaceRows
        // above). --pack-top-n was the only cap and had no --offset partner; --limit now overrides it exactly
        // like --deps' packTopN/pageLimit composition (src/serialize.h::packDeps), and --offset finally pages.
        const int         histCap = cfg.packTopN > 0 ? cfg.packTopN : int( names.size() );
        const PageWindow  extPw   = pageWindow( names.size(), effectiveRowCap( cfg.pageLimit, histCap ), cfg.pageOffset );
        std::vector<char> esc;
        const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        std::printf( "<!-- ripwire external-surface: names CALLED/IMPORTED/EXTENDED but never defined in the indexed "
                     "tree = the stdlib/third-party surface the code depends on (refs=use-sites, calls=of-which-calls) -->" );
        // P2.1: --pack-top-n caps the listing; names= is the true total, shown=/capped= the printed slice.
        const std::size_t extShown = extPw.end - extPw.begin;
        char              extAb[ kPageDisclosureCap ];
        std::printf( "<external-surface names=\"%zu\"%s>", names.size(),
                     pageDisclosure( extAb, sizeof( extAb ), extShown, names.size(), extPw.end,
                                     cfg.pageLimit, cfg.pageOffset, true ) );
        for( std::size_t i = extPw.begin; i < extPw.end; ++i )
        {
            std::printf( "<x n=\"%s\" lang=\"%s\" refs=\"%u\" calls=\"%u\"/>",
                         ex( names[i].name ).c_str(), langTag( names[i].lang ), names[i].refs, names[i].calls );
        }
        std::printf( "</external-surface>" );
        return 0;
    }
    return std::nullopt;
}

std::optional<int> runPath( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         pthSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  pthRootPrefix = pthSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  pthRootEsc;
    const std::string  pthRootAttr   = pthSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], pthRootEsc ) ) + "\"" ) : std::string();

    // --path=SRC,DST: shortest directed call-path (how does SRC reach DST through calls?)
    if( !cfg.pathSpec.empty() )
    {
        const std::string_view spec  = cfg.pathSpec;
        const std::size_t       comma = spec.find( ',' );
        // §B8.2: the bare-arg-count refusal goes through the same helper as every other value refusal —
        // it used to answer `--path=zzq` with a bare "needs SRC,DST", naming neither what it got nor what
        // to type, while the flag's own kViewFlags row already carries both for the EMPTY case.
        if( comma == std::string_view::npos )
        { rw::refuseFlagValue( "--path", "two symbol names, FROM,TO", spec, "--path=main,rankGraph" );  return 1; }
        const std::string_view srcN = spec.substr( 0, comma ), dstN = spec.substr( comma + 1 );

        // r27-emitters T4: resolve EVERY def of each endpoint, not just the lowest-id one. `--path=main,X` used
        // to bind `main` to whichever def happened to hold the lowest NodeId (a bench script, a CMake stub, a
        // fixture) and then report reachable="0" for a path that plainly exists from the real `main` — a WRONG
        // answer with no way to see why. The search below is one multi-source BFS over all src defs, so the
        // cost is unchanged (a single O(E) pass, not one BFS per def pair). `file:name` still disambiguates,
        // exactly as on --around/--lego/--callers, and the resolved endpoints are now echoed so the ambiguity
        // that remains is VISIBLE.
        const std::vector<NodeId> srcDefs = resolveAllByNameQualified( ing, srcN );
        const std::vector<NodeId> dstDefs = resolveAllByNameQualified( ing, dstN );
        if( srcDefs.empty() || dstDefs.empty() )
        {
            // §M7 (W3FIX): both endpoints resolve through resolveAllByNameQualified, i.e. the shared file:name
            // grammar, so the endpoint that missed gets the shared diagnosis (unindexed path vs wrong file half
            // vs unknown name) instead of a near-miss on the name half alone.
            const std::string_view missing = srcDefs.empty() ? srcN : dstN;
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --path endpoint not found: ",
                                                                  missing, "--path=" ).c_str() );
            return 1;
        }

        const std::vector<NodeId> path    = rw::shortestPathAny( g, srcDefs, dstDefs );   // ONE BFS over every def pair
        const NodeId              srcUsed = path.empty() ? srcDefs.front() : path.front();
        const NodeId              dstUsed = path.empty() ? dstDefs.front() : path.back();

        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        const auto        loc = [ & ]( NodeId n ) -> std::string
        { const Symbol& s = ing.symbols[n];
          const std::string_view rp = pthSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], pthRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
          return ex( rp ) + ":" + std::to_string( s.line ); };

        // from_p/to_p = the def this run actually bound the name to; from_defs/to_defs = how many it could have
        // bound it to (>1 ⇒ qualify with file:name if this is not the one you meant).
        // R-E fix (2026-08-19): --path ships no legend of its own, so the shared root-relative clause IS its
        // whole first-screen legend here — root= would otherwise be the one attribute on this document with
        // nothing anywhere saying what it means. Same text, same helper, as every other verb's.
        std::printf( "%s", rw::rootRelPathsLegend( pthSingleRoot ) );
        std::printf( "<path from=\"%s\" to=\"%s\" from_p=\"%s\" to_p=\"%s\" from_defs=\"%zu\" to_defs=\"%zu\" reachable=\"%d\" hops=\"%zu\"%s",
                     ex( srcN ).c_str(), ex( dstN ).c_str(), loc( srcUsed ).c_str(), loc( dstUsed ).c_str(),
                     srcDefs.size(), dstDefs.size(),
                     path.empty() ? 0 : 1, path.empty() ? std::size_t( 0 ) : path.size() - 1, pthRootAttr.c_str() );
        // P2.10: a dead end is exactly the moment to name the next verb. --path is DIRECTED; --connect searches
        // undirected and finds the shared-caller join a directed walk can never see.
        if( path.empty() )
        {
            std::printf( " hint=\"no directed call path — try --connect=%s,%s (undirected: finds a shared caller), or --uses/--impact for non-call references%s\"",
                         ex( srcN ).c_str(), ex( dstN ).c_str(),
                         ( srcDefs.size() > 1 || dstDefs.size() > 1 ) ? "; several defs share these names — qualify as file:name to pick one" : "" );
        }
        std::printf( ">" );
        for( NodeId n : path )
        {
            const Symbol&           s  = ing.symbols[n];
            const std::string_view  rp = pthSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], pthRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            std::printf( "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line );
        }
        std::printf( "</path>" );
        return 0;
    }
    return std::nullopt;
}

std::optional<int> runConnect( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool             cnSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view cnRootArg    = cnSingleRoot ? cfg.roots[0] : std::string_view();

    // --connect=A,B,C: the minimal connecting subgraph over 2..16 task symbols — how do they RELATE, and
    // which intermediaries join them? Search is UNDIRECTED (finds the shared-caller join a directed --path
    // can't), every reported edge keeps its true caller→callee direction. packConnect (mcp.h) is the ONE
    // shared emitter, so this and the MCP `connect` verb write identical bytes.
    if( !cfg.connectSpec.empty() )
    {
        std::vector<std::string_view> specs;
        {
            std::string_view s = cfg.connectSpec;
            for( ;; )
            {
                const std::size_t comma = s.find( ',' );
                const std::string_view tok = s.substr( 0, comma );
                if( !tok.empty() )
                {
                    specs.push_back( tok );
                }
                if( comma == std::string_view::npos )
                {
                    break;
                }
                s.remove_prefix( comma + 1 );
            }
        }
        if( specs.size() < 2 || specs.size() > rw::connectcfg::kMaxTerminals )
        {
            std::fprintf( stderr, "ripwire: --connect needs 2..%zu comma-separated symbols (got %zu) — for a broader ranked set use --for\n",
                          rw::connectcfg::kMaxTerminals, specs.size() );
            return 1;
        }
        std::vector<NodeId> terminals;
        for( const std::string_view spec : specs )
        {
            const NodeId id = resolveFocus( ing, spec );                 // "name" or "file:name" — exactly --around/--lego
            if( id == kNoNode )
            {
                // §M7 (W3FIX): resolveFocus is the SAME file:name resolver --around/--lego use, so this arm
                // gets the same shared diagnosis rather than a bare near-miss about the name half.
                std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --connect symbol not found: ",
                                                                       spec, "--connect=" ).c_str() );
                return 1;
            }
            terminals.push_back( id );
        }
        // §B8.1: the parser now REFUSES a radius outside the band instead of letting the core clamp it
        // silently, so cli.h's domain ceiling and connectcfg's clamp band must be the same number. This is
        // the one seam where both headers are visible — the core keeps clamping (the MCP `connect` verb and
        // any other caller still hand it an unvalidated radius; a core that VERIFYs on hostile input is a
        // crash, not a guard).
        static_assert( rw::kConnectRadiusMax == int( rw::connectcfg::kMaxRadius ),
                       "--connect-radius' refusal band drifted from the core's clamp band — the refusal would name a range the core does not honor" );
        const rw::ConnectResult res = rw::connectSubgraph( g, terminals, std::uint32_t( cfg.connectRadius ) );
        rw::packConnect( stdout, ing, res, d.redactPtr, cfg.maxTokens, cnRootArg );
        return 0;
    }
    return std::nullopt;
}

// §P10.3 / §P8 G1 — why --impact's 40-row cap is now a DEFAULT and not a ceiling. The verb answers "is it
// safe to change X?", and it answered it with a fixed 40 rows of a radius that is routinely 100+, while
// accepting --limit/--offset and ignoring both: the one question in the tool where a silent 3%-of-the-truth
// answer is most expensive was also the one with no flag to widen it. effectiveRowCap( --limit, 40 ) keeps
// the no-flag output byte-identical and makes --limit=200 finally emit up to 200 of reaches=.
std::optional<int> runImpact( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         imSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  imRootPrefix = imSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  imEsc;
    const std::string  imRootAttr   = imSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], imEsc ) ) + "\"" ) : std::string();

    // --impact=SYM: transitive blast radius — every symbol that (transitively) reaches SYM via calls
    if( !cfg.impactSym.empty() )
    {
        // X9(b): "file:name" disambiguates here too (same rule as --around/--lego/--edit-check).
        const std::vector<NodeId> seeds = resolveAllByNameQualified( ing, cfg.impactSym );
        if( seeds.empty() )
        {
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --impact symbol not found: ",
                                                                   cfg.impactSym, "--impact=" ).c_str() );   // §B4.2
            return 1;
        }
        const std::vector<NodeId> reach = rw::transitiveCallers( g, seeds );
        const auto [ rank, prIters, prConverged ] = rankGraph( g );
        const rw::RankDisclosure  prD{ prIters, prConverged, true };   // W2-F: the listing is PageRank-ordered
        std::vector<NodeId>       show  = reach;
        std::sort( show.begin(), show.end(), [ & ]( NodeId a, NodeId b ) { return rank[a] != rank[b] ? rank[a] > rank[b] : a < b; } );
        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        if( !cfg.json )
        { // L2: JSON has no comment-node analogue; the XML-only leading doc comment
            // §B12.4 in-band (W3FIX): the paging clause comes from pageview.h::kPageRaiseCapClause, which
            // carries the limit="0" definition too — rule 7 existed only in --help and that header before.
            // §H4 §3.4: opener + the shared floor/counting-unit tail, both from src/graphlegend.h so the MCP
            // twin cannot drift from this wording (the §B4 echo-site class).
            std::printf( "%s%s. %s%s-->", rw::kImpactLegendOpen, rw::kPageRaiseCapClause,
                         rw::graphCountDisclosure().c_str(), rw::renderDisclosure( prD, rw::DiscloseAs::LegendClause ).c_str() );
        }
        // P2.1 + §P8 G1: the rank-ordered listing's 40 is a DEFAULT now, not a ceiling — see the §P10.3 note
        // above runImpact. reaches= stays the un-windowed reach-set size — the blast radius the INDEXED graph
        // can see, which counts_floor= discloses is a floor (V3 L-4); pageDisclosure emits the same ` shown=
        // capped=` bytes this tag used to hand-roll (src/pageview.h, THE TRUNCATION VOCABULARY, rules 1-3).
        const PageWindow  ipw       = pageWindow( show.size(), effectiveRowCap( cfg.pageLimit, 40 ), cfg.pageOffset );
        const std::size_t shownRows = ipw.end - ipw.begin;
        char              ipab[ kPageDisclosureCap ];

        // --format=columnar (RESEARCH lever 1): same page window, path-table + parallel arrays.
        // V1-1: a fixed 160-byte buffer truncated mid-attribute on long escaped symbol
        // names (invalid XML, the F6 class), and this branch hand-rolled shown=/capped= without the paging
        // half — the one pageDisclosure() sibling the §A4c rollout missed. std::string kills the truncation
        // class outright; the disclosure comes from the same call the XML branch below makes.
        if( cfg.columnar )
        {
            std::vector<NodeId> page( show.begin() + ipw.begin, show.begin() + ipw.end );
            const std::string attr = "of=\"" + ex( cfg.impactSym ) + "\" defs=\"" + std::to_string( seeds.size() )
                                   + "\" reaches=\"" + std::to_string( reach.size() ) + "\""
                                   + imRootAttr
                                   + pageDisclosure( ipab, sizeof( ipab ), shownRows, show.size(), ipw.end,
                                                     cfg.pageLimit, cfg.pageOffset, true )
                                   + rw::kGraphCountFloorAttrXml            // §H4 §3.4
                                   + rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs );          // W2-F
            emitColumnarSymbolRows( stdout, ing, "impact", attr.c_str(), page, imRootPrefix );
            return 0;
        }

        // L2: --json — same set, keys mirror the XML attr names (of/defs/reaches/shown/capped/t/n/p).
        // §A4c: shown/capped came from a hand-rolled pair that never grew the paging half, so a JSON caller
        // walking --offset had no has_more/next_offset to terminate on. The JSON row of pageDisclosure()'s
        // syntax table emits the same seven fields the XML tag below emits (discloseCap=true — this verb DOES
        // have a 40-row display cap of its own).
        if( cfg.json )
        {
            std::printf( "{\"of\":\"%s\",\"defs\":%zu,\"reaches\":%zu",
                         jsonStr( cfg.impactSym ).c_str(), seeds.size(), reach.size() );
            if( imSingleRoot ) { std::printf( ",\"root\":\"%s\"", jsonStr( cfg.roots[0] ).c_str() ); }   // R-E
            std::printf( "%s%s%s,\"impact\":[",
                         pageDisclosure( ipab, sizeof( ipab ), shownRows, show.size(), ipw.end,
                                         cfg.pageLimit, cfg.pageOffset, true, kJsonPageSyntax ),
                         rw::kGraphCountFloorAttrJson,             // §H4 §3.4
                         rw::renderDisclosure( prD, rw::DiscloseAs::JsonKeys ).c_str() );  // W2-F: the dialects keep ONE keyset
            printJsonSymbolRows( ing, show, ipw.begin, ipw.end, imRootPrefix );
            std::printf( "]}" );
            return 0;
        }

        std::printf( "<impact of=\"%s\" defs=\"%zu\" reaches=\"%zu\"%s%s%s%s>",
                     ex( cfg.impactSym ).c_str(), seeds.size(), reach.size(), imRootAttr.c_str(),
                     pageDisclosure( ipab, sizeof( ipab ), shownRows, show.size(), ipw.end,
                                     cfg.pageLimit, cfg.pageOffset, true ),
                     rw::kGraphCountFloorAttrXml, rw::renderDisclosure( prD, rw::DiscloseAs::XmlAttrs ).c_str() );
        for( std::size_t i = ipw.begin; i < ipw.end; ++i )
        {
            const Symbol&           s  = ing.symbols[ show[i] ];
            const std::string_view  rp = imSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ s.fileId ], imRootPrefix ) : std::string_view( ing.files[ s.fileId ] );
            std::printf( "<s t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( s.kind ), ex( s.name ).c_str(), ex( rp ).c_str(), s.line );
        }
        std::printf( "</impact>" );
        return 0;
    }
    return std::nullopt;
}

// §A8.4: collapseMentionsToFileRows moved to src/mention.h — the MCP `mentions` verb shares it now
// (the same section-vs-file overcount lived there; two collapses would be the §A4c clone class).

std::optional<int> runMentions( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    const bool         mnSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  mnRootPrefix = mnSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();

    // --mentions=SYM: which DOCS (markdown plans/designs) name this code symbol in a `backtick` — the doc↔code
    // link (the reverse of "what code a doc touches"). From g.mentions, built OUT of the call graph so a doc
    // mentioning a symbol never inflated its PageRank/blast-radius. Rows now collapse to one per FILE (see
    // collapseMentionsToFileRows, above): mentions= is that file's own section-mention count, l= its first
    // (lowest-line) mention; the root's docs= names the row count (distinct files), sections= the old
    // pre-collapse tally, so nothing measured is lost, just renamed honestly.
    if( !cfg.mentionsSym.empty() )
    {
        // §B11.1 — the --owners twin, same defect, same fix: the shared file:name grammar and the shared
        // refusal that names which half is at fault. A qualified spelling now NARROWS the mention scan to the
        // definitions in that file instead of being refused as an unknown symbol.
        const std::vector<NodeId> defs = resolveAllByNameQualified( ing, cfg.mentionsSym );
        if( defs.empty() )
        {
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --mentions symbol not found: ",
                                                                   cfg.mentionsSym, "--mentions=" ).c_str() );
            return 1;
        }
        std::vector<NodeId> docs;
        for( NodeId d : defs )
        {
            if( d < g.mentions.size() )
            {
                for( NodeId dn : g.mentions[d] )
                {
                    docs.push_back( dn );
                }
            }
        }
        std::sort( docs.begin(), docs.end() );  docs.erase( std::unique( docs.begin(), docs.end() ), docs.end() );
        const std::size_t           sectionCount = docs.size();
        std::vector<MentionFileRow> fileRows     = collapseMentionsToFileRows( ing, docs );

        std::vector<char> esc;
        const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        std::printf( "<!-- ripwire mentions: markdown FILES that name this symbol in a `backtick` (doc<->code; NOT a call edge). "
                     "docs= is the row count (distinct files); sections= counts the underlying markdown-section mentions "
                     "before file-collapse (docs <= sections). Each row's mentions= is its own section-mention count. "
                     "No line locator: the doc edge is stored at file granularity — a fabricated always-1 l= was removed; absent beats fake -->%s", rw::rootRelPathsLegend( mnSingleRoot ) );
        // §P15/§P16: fileRows is deterministic (file path order) and printed unconditionally, no historic
        // display cap — pageWindow directly on cfg.pageLimit/cfg.pageOffset, discloseCap=false so the
        // un-paginated tag stays byte-identical.
        const PageWindow  mentionsPw = pageWindow( fileRows.size(), cfg.pageLimit, cfg.pageOffset );
        char              mentionsAb[ kPageDisclosureCap ];
        const std::string mnRootAttr = mnSingleRoot ? ( " root=\"" + ex( cfg.roots[0] ) + "\"" ) : std::string();
        std::printf( "<mentions of=\"%s\" defs=\"%zu\" docs=\"%zu\" sections=\"%zu\"%s%s>", ex( cfg.mentionsSym ).c_str(), defs.size(),
                     fileRows.size(), sectionCount,
                     pageDisclosure( mentionsAb, sizeof( mentionsAb ), mentionsPw.end - mentionsPw.begin, fileRows.size(), mentionsPw.end,
                                     cfg.pageLimit, cfg.pageOffset, false ),
                     mnRootAttr.c_str() );
        for( std::size_t rowIndex = mentionsPw.begin; rowIndex < mentionsPw.end; ++rowIndex )
        {
            const MentionFileRow&  row = fileRows[ rowIndex ];
            const std::string_view rp  = mnSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ row.fileId ], mnRootPrefix ) : std::string_view( ing.files[ row.fileId ] );
            std::printf( "<doc p=\"%s\" mentions=\"%zu\"/>", ex( rp ).c_str(), row.mentions );
        }
        std::printf( "</mentions>" );
        return 0;
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
            changed = rw::changedMaskFromList( ing, cfg.testGateFiles );
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
            char hdr[ 320 ];
            std::snprintf( hdr, sizeof( hdr ),
                           "<ctx><!-- ripwire field notes: notes=%zu targets=%zu dangling=%zu (a target with no matching indexed symbol/file — legal: listed here, surfaced nowhere) -->",
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
    std::array<std::uint64_t, std::size_t( Lang::Yaml ) + 1> symbolTally {};
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
    std::array<std::uint64_t, std::size_t( Lang::Yaml ) + 1> fileTally {};
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

// L4 — --pack-task="TASK": the budget-shared task bundle. ONE call assembling
// the whole 3-5 call orientation dance under ONE deterministic byte budget (default 6K tokens; --token-budget
// overrides), in a FIXED section order with a header that reports EVERY truncation (the overbudgetcheck "no
// silent caps" precedent). Reuses: the shared lens ranking (computeLensRanking — all --for boosts apply), the
// --detail body machinery (packBodies), the --callers in-edge walk, L3 field notes (notesPtr), and the
// --affected test-mining (transitiveCallers + isTestPath). Existing verbs stay byte-identical (this path is
// only reached when --pack-task is given). Section budgets are consumed in the fixed ALLOCATION order
// ranking > bodies > callers > notes > tests: each section gets whatever the higher-priority sections left, so
// a tiny budget naturally degrades to ranking-only (each dropped section is named in the header — no silent cap).
//
// BUDGET CONTRACT (the gate asserts it): the internal target is `budgetTokens × kMinBytesPerToken ×
// kBudgetHeadroom` bytes; the emitted bundle never exceeds the token CEILING `budgetTokens × kMinBytesPerToken`
// except by at most one section's trailing entry (packBodies always emits its first body whole), so a small
// documented tolerance covers the overshoot.
// The section assembler itself (PackTaskSection / packTaskListSection / the 5-section budget-share machinery /
// kPackTask* constants) now lives in packtask.h (L4) as packTaskBundleText() — shared verbatim with the MCP
// explore/pack_task verb (mcpverbs.h's packTaskText()). This handler only resolves CLI-specific inputs
// (flags, MainDispatch pointers) and hands them to that ONE assembler.
std::optional<int> runPackTask( const MainDispatch& d )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;
    const Graph&        g   = d.g;

    if( !cfg.packTaskFlag )
    {
        return std::nullopt;
    }
    if( cfg.packTask.empty() )   // refuse loudly without a task string (never fall through to the default map)
    {
        std::fprintf( stderr, "ripwire: --pack-task: a task string is required — e.g. --pack-task=\"add retry to the http client\"\n" );
        return 1;
    }
    const std::string task( cfg.packTask );

    // ── the routed+anchored lens ranking, shared verbatim with --for (all existing boosts apply) ───────────
    LensRanking lr = computeLensRanking( d, task );

    // Q3 per-file churn (mirror --for): only mined on the --for git pass, so here it stays empty/zero when
    // --for wasn't also given → the churn= attr is simply omitted by packSignatures (nullptr-safe).
    std::vector<std::uint32_t> forChurn = d.forChurn;
    if( forChurn.size() != ing.files.size() )
    {
        forChurn.assign( ing.files.size(), 0u );
    }

    PackTaskInputs in;
    in.budgetTokens         = cfg.tokenBudget;        // F5: stays std::size_t end-to-end (0 ⇒ the shared default)
    in.sigLadderBudgetBytes = cfg.packBudgetBytes;
    in.compress             = cfg.compress;
    in.fanIn                = d.fanInPtr;
    in.impure               = d.impurePtr;
    in.churn                = &forChurn;
    in.tested               = d.testedPtr;
    in.amp                  = d.ampPtr;
    in.redact               = d.redactPtr;
    in.notes                = d.notesPtr;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h).
    in.rootArg = ( ing.realPaths.empty() && cfg.roots.size() == 1 ) ? cfg.roots[0] : std::string_view();

    // --partition=N: the FAN-OUT form. Same lens ranking, same PackTaskInputs, same
    // assembler; partition.h only decides WHICH slice each of the N+1 bundles is masked to and how the
    // per-agent budget divides. Handled before the single-bundle emission below because it replaces the
    // document, not a section of it. cli.h has already bounded N to 2..16 and refused a bare --partition.
    if( cfg.partitionCount > 0 )
    {
        const std::uint32_t partitionCount = std::uint32_t( cfg.partitionCount );
        // --with-graph splices its mermaid block into ONE bundle's </ctx>; there are N+1 here and no single
        // place it belongs. Say so on stderr rather than dropping it silently (it is not worth failing the
        // whole run over — the bundles themselves are unaffected).
        if( cfg.withGraph )
        {
            std::fprintf( stderr, "ripwire: --with-graph is not applied in --partition mode (N+1 bundles, no single graph) — bundles emitted without it\n" );
        }
        if( cfg.json )
        {
            std::string js;
            packpartition::packTaskPartitionText( ing, g, task, lr, in, partitionCount, &js );
            std::fwrite( js.data(), 1, js.size(), stdout );
        }
        else
        {
            const std::string doc = packpartition::packTaskPartitionText( ing, g, task, lr, in, partitionCount );
            std::fwrite( doc.data(), 1, doc.size(), stdout );
        }
        reportRedactions( stderr, d.redactCounts );
        return 0;
    }

    // L2: --json — same section decisions, JSON shape, computed by the SAME packTaskBundleText call the XML
    // path uses (its optional jsonOut tail), so truncation reporting can never drift between the two shapes.
    if( cfg.json )
    {
        // §B1.3 (capture-audit-4): --with-graph has no JSON dialect yet (the mermaid block is XML-only,
        // spliced in only on the plain-text path below) — warn once and continue without it, the same
        // warn-and-continue shape the --partition branch above already uses, rather than silently dropping
        // the flag's effect with no tell at all.
        if( cfg.withGraph )
        {
            std::fprintf( stderr, "ripwire: --with-graph is not applied under --json (the mermaid graph block is XML-only for now) — emitted without it\n" );
        }
        std::string js;
        packTaskBundleText( ing, g, task, lr, in, &js );
        std::fwrite( js.data(), 1, js.size(), stdout );
        reportRedactions( stderr, d.redactCounts );
        return 0;
    }

    // R8: --with-graph — a compact mermaid flowchart of the ranked bundle's anchor neighborhood, spliced
    // in right before the bundle's closing </ctx> (the extracted packTaskBundleText owns the tag; splitting
    // here keeps the MCP explore/pack_task path graph-free, which has no --with-graph surface). Off by
    // default (G5): omitted, this is a no-op and output is byte-identical.
    //
    // §F1: RENDERED AND CHARGED FIRST. Spliced in after the assembler had already divided the budget and
    // priced its ceiling ladder, its ~399 B rode in uncharged — MEASURED `--pack-task --token-budget=800
    // --with-graph` = 2 445 B against a 2 171 B allowance, 12.6% over with no over_ceiling, where the bare form
    // at the same budget was conformant. in.trailingSectionBytes hands the assembler the size BEFORE it spends
    // the budget (PackTaskInputs documents both places it lands). The degrade path (isRendered=false) splices
    // nothing and streams the block directly, so the bytes are identical and only the charge is lost.
    rw::ChargedSection graphSection;
    if( cfg.withGraph )
    {
        graphSection        = rw::chargeSection( [ & ]( std::FILE* f ) { packGraphBlock( f, ing, lr.rank, g.outOff, g.outTargets ); },
                                                  rw::kBytesPerTokenDefault );
        in.trailingSectionBytes = graphSection.xml.size();   // 0 on the degrade path — the pre-§F1 accounting for that one run
    }

    std::string bundle = packTaskBundleText( ing, g, task, lr, in );
    if( cfg.withGraph && bundle.size() >= 6 && bundle.compare( bundle.size() - 6, 6, "</ctx>" ) == 0 )
    {
        std::fwrite( bundle.data(), 1, bundle.size() - 6, stdout );
        rw::emitChargedSection( stdout, graphSection, [ & ]{ packGraphBlock( stdout, ing, lr.rank, g.outOff, g.outTargets ); } );
        std::printf( "</ctx>" );
    }
    else
    {
        std::fwrite( bundle.data(), 1, bundle.size(), stdout );
    }
    reportRedactions( stderr, d.redactCounts );
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
void emitGrepEncRows( const rw::IngestResult& ing, const rw::Graph& g, std::span<const rw::GrepHit> hits,
                      const std::vector<std::uint32_t>* amp, const std::vector<std::uint8_t>* tested,
                      std::vector<char>& esc )
{
    using namespace rw;
    for( const GrepEncRow& row : grepEnclosingRows( ing, g, hits ) )
    {
        const auto en = rw::escapeXml( row.chain, esc );
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
            if( amp && id < amp->size() )
            {
                ampMax = std::max( ampMax, (*amp)[id] );
            }
            if( tested && id < tested->size() && (*tested)[id] )
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
    std::vector<GrepTerm> grepTerms;
    grepTerms.reserve( cfg.grepAnd.size() + cfg.grepNot.size() );
    for( const std::string_view t : cfg.grepAnd ) { grepTerms.push_back( GrepTerm{ std::string( t ), false } ); }
    for( const std::string_view t : cfg.grepNot ) { grepTerms.push_back( GrepTerm{ std::string( t ), true } ); }
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
    // G3: terms=/scope=/suppressed= — only when AND/NOT was actually given, so a plain --grep answer
    // stays byte-identical to before G3 landed (the "purely additive" rule every ripwire flag follows).
    std::string termsAttr;
    if( !grepTerms.empty() )
    {
        std::string termsList = ex( pat );
        for( const GrepTerm& t : grepTerms )
        {
            termsList += t.negated ? " -" : " +";
            termsList += ex( t.term );
        }
        termsAttr = " terms=\"" + termsList + "\" scope=\"" + ( grepScopeVal == GrepScope::File ? "file" : "line" ) + "\""
                  + " terms_suppressed=\"" + std::to_string( termsSuppressed ) + "\"";
    }
    // G4 (2026-08-15 harvest, report-ugrep §F6): corpus_excluded=/corpus_oversize= — so hits="0" can
    // distinguish "not in this repo" from "in a file the crawl never scanned" (an --exclude= match, or a
    // file past --max-file-size). Absent when zero, matching skippedOversize's own "absent means nothing
    // was skipped" convention (model.h) — never a re-run hint (--skipped already itemizes the rows).
    std::string corpusAttr;
    if( ing.crawlSkips.excludedFiles > 0 )
    {
        corpusAttr += " corpus_excluded=\"" + std::to_string( ing.crawlSkips.excludedFiles ) + "\"";
    }
    if( !ing.skippedOversize.empty() )
    {
        corpusAttr += " corpus_oversize=\"" + std::to_string( ing.skippedOversize.size() ) + "\"";
    }
    // R-H: the tier disclosure (helper above) — empty when nothing was held back.
    const std::string tierAttr = grepTierAttrs( tierReport );
    // §R-J: unindexed_files_scanned=/unindexed_files_skipped=/unindexed_candidates_capped= (helper above).
    const std::string auxAttr = grepUnindexedAttrs( aux );
    std::printf( "<grep pattern=\"%s\"%s%s files=\"%d\" hits=\"%zu\"%s hits_capped=\"%d\"%s%s%s%s>",
                 ex( pat ).c_str(), rootAttr.c_str(), termsAttr.c_str(), filesMatched, hitCount,
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
    emitGrepEncRows( ing, g, std::span<const GrepHit>( hits ), amp, tested, esc );

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

// --sarif: build the SARIF rule catalogue + finding list from the SAME `outs` / `allRuleNames` /
// `userRules` / `saturatedRules` runLint's XML path already computed, and emit it (src/sarif.h).
// Lifted out of runLint for the same reason lintSymbolLevelChecks / dedupeLintFindings /
// buildHeatAnnotations above were — pure re-serialization, zero new analysis, and runLint was already
// the file's largest verb. `capOf` is redefined locally (a small linear scan over `saturatedRules`,
// mirroring runLint's own) rather than shared by reference, so this stays a self-contained call.
// The two per-rule DISCLOSURES the XML path states and this one has to state differently. Both are read
// off the SAME inputs the XML arm below uses (lintSelectionKeeps for the row it would have dropped,
// lintCatalogFind ∧ corpusLangs for its applicable="0"), never recomputed from a second source of truth —
// see sarif.h's own header for why SARIF spells them as defaultConfiguration.enabled / properties.applicable
// instead of "omit the row" / "omit the attribute".
// `d` replaces the ing/root/cfg trio this used to take one by one — the same MainDispatch every other verb
// handler in this file is already given, and the reason the two new disclosures below cost no signature
// growth: the run's flags (builtinsActive, the raw select=/ignore=) are fields of d.cfg, so the next fact
// the XML root grows will not widen this signature either.
template <class EnclosingFn>
void emitRunLintSarif( const MainDispatch& d,
                       const std::vector<std::string>& allRuleNames, const std::vector<rw::LintRule>& userRules,
                       const std::vector<RuleCap>& saturatedRules, const std::vector<LintOut>& outs,
                       const rw::lintcatalog::LintSelection& lintSel, std::uint32_t corpusLangs,
                       EnclosingFn&& enclosing )
{
    using namespace rw;
    const Config&       cfg = d.cfg;
    const IngestResult& ing = d.ing;
    const auto capOf = [ & ]( const std::string& ruleName, bool isUserRule ) -> const RuleCap*
    {
        for( const RuleCap& rc : saturatedRules )
        {
            if( rc.rule == ruleName && rc.isUserRule == isUserRule )
            {
                return &rc;
            }
        }
        return nullptr;
    };
    const auto keptBySelection = [ & ]( std::string_view name ) noexcept
    {
        return !lintSel.active || rw::lintcatalog::lintSelectionKeeps( lintSel, name );
    };

    std::vector<rw::sarif::SarifRuleDecl> sarifRules;
    sarifRules.reserve( allRuleNames.size() + userRules.size() );
    if( cfg.lint )   // built-in rule catalogue only enters the tally under --lint (mirrors the XML arm)
    {
        for( const std::string& rn : allRuleNames )
        {
            const rw::lintcatalog::LintCatalogRow* catRow = rw::lintcatalog::lintCatalogFind( rn );
            const bool applicable = catRow == nullptr || ( catRow->langMask & corpusLangs ) != 0;
            sarifRules.push_back( { rn, false, capOf( rn, false ) != nullptr, keptBySelection( rn ), applicable } );
        }
    }
    for( const LintRule& r : userRules )
    {
        const bool applicable = ( rw::langBit( r.lang ) & corpusLangs ) != 0;
        sarifRules.push_back( { r.id, true, capOf( r.id, true ) != nullptr, keptBySelection( r.id ), applicable } );
    }

    std::vector<rw::sarif::SarifFinding> sarifFindings;
    sarifFindings.reserve( outs.size() );
    for( const LintOut& m : outs )
    {
        const Symbol* e = enclosing( m.fileId, m.startByte );
        sarifFindings.push_back( { m.rule, m.sev, ing.files[ m.fileId ], m.line, e ? e->name : std::string(), m.text } );
    }

    rw::sarif::SarifRunProperties props;
    props.anyRuleCapped   = !saturatedRules.empty();
    props.selectionActive = lintSel.active;
    props.selectedCount   = lintSel.selectedCount;
    props.totalCount      = lintSel.totalCount;
    props.select.assign( cfg.lintSelect );
    props.ignore.assign( cfg.lintIgnore );
    rw::sarif::emitLintSarif( stdout, sarifRules, sarifFindings, props, d.root );
}

// §L3 / octocode F3: everything one --match run answers with, as ONE structured-binding-friendly return
// (CONTRIBUTING.md §3 Interfaces) instead of a growing out-param list — matches/uncompiled/grammarsAttr/
// eligibleFiles/nearestKind/nearestGrammar are all facts about the SAME query, so a caller reading five
// separate by-ref writes was already the wrong shape before this fix added a sixth.
struct MatchQueryOutcome
{
    std::vector<rw::AstMatch> matches;
    std::vector<std::string>  uncompiled;      // non-empty ⇒ the query compiled for NO grammar, refuse
    std::string                grammarsAttr;    // §L3: pre-joined, see AstQueryGroup::grammarsOut
    std::size_t                eligibleFiles = 0;
    std::string                nearestKind;     // octocode F3: "" when no candidate was close enough
    std::string                nearestGrammar;  // "" alongside a "" nearestKind
};

// Runs a --match query and reports the grammar-applicability disclosure (see AstQueryGroup::grammarsOut/
// eligibleFilesOut in ingest.h and mcprefusal.h's joinClauses), so a query that compiles for SOME grammars
// but none are present in the corpus can say so instead of reporting a bare hits="0" indistinguishable from
// "this pattern does not occur" (§P0.1's gap, one level up the stack). Standalone so runLint's own
// dispatcher body, already one of the largest in this file, doesn't grow by the plumbing.
static MatchQueryOutcome runMatchQuery( const rw::IngestResult& ing, const std::string& matchQuery, std::size_t maxHits )
{
    const std::vector<rw::AstQuerySpec> specs{ { matchQuery, std::string() } };
    MatchQueryOutcome                   out;
    std::vector<std::string>            grammarsOut, nearestKinds, nearestGrammars;
    rw::AstQueryGroup                   grp;
    grp.specs             = &specs;
    grp.maxMatches        = maxHits;
    grp.uncompiledOut     = &out.uncompiled;
    grp.grammarsOut       = &grammarsOut;
    grp.eligibleFilesOut  = &out.eligibleFiles;
    grp.nearestKindOut    = &nearestKinds;      // octocode F3: parallel to uncompiledOut — a one-spec caller
    grp.nearestGrammarOut = &nearestGrammars;   // ever gets at most one entry in either
    out.matches = std::move( rw::astQueryGrouped( ing, { grp } )[0] );
    out.grammarsAttr = rw::mcprefuse::joinClauses( std::vector<std::string_view>( grammarsOut.begin(), grammarsOut.end() ), "," );
    if( !nearestKinds.empty() )    { out.nearestKind    = std::move( nearestKinds[0] ); }
    if( !nearestGrammars.empty() ) { out.nearestGrammar = std::move( nearestGrammars[0] ); }
    return out;
}

// Join owned strings through the ONE joiner the refusal surfaces already use, so a list this file prints
// and a list an MCP refusal prints cannot drift in spelling. (joinClauses takes views; every caller here
// holds owned strings, and hand-rolling the conversion at each call site is how they drift.)
static std::string joinOwned( const std::vector<std::string>& parts, const char* sep )
{
    return rw::mcprefuse::joinClauses( std::vector<std::string_view>( parts.begin(), parts.end() ), sep );
}

// The pattern verb's schema legend, named and hoisted out of runLint: a fifteen-line string literal inside
// an already-large dispatcher body is verbosity the reader pays for at every OTHER verb in that function,
// and a legend nobody can grep for by name is one nobody audits. No literal flag spelling in it — a `-`
// pair is illegal inside an XML comment.
inline constexpr std::string_view kPatternLegend =
    "<!-- ripwire pattern: structural search written in CODE, not in tree-sitter node kinds; each hit = a matching "
                         "node + its enclosing symbol. q= is the pattern as received. grammars= names every served grammar the pattern "
                         "resolved for and shapes= the node KIND it became in each, so what was actually searched for is auditable; "
                         "unsupported= names the families this verb does not serve at all (a zero there would be a lie, so it never "
                         "reports one). Every grammar name here is per grammar OBJECT, so a dialect that borrows another's templates "
                         "is spelled apart from it (cpp/cu = the CUDA grammar, typescript/tsx = the TSX one); a bare cpp NEVER stands "
                         "for its dialects. eligible_files= = corpus files whose grammar the pattern resolved for, i.e. the files "
                         "actually SCANNED; skipped_files= = files in a served language it did NOT resolve for, which were never read "
                         "at all; of_files= = total indexed files. $NAME binds one node and the same $NAME twice must match "
                         "structurally; $_ binds nothing; the ellipsis is matched by a single first-match-wins probe (never an "
                         "exhaustive search) under the disclosed ellipsis_bound sibling cap. Comments are transparent on both sides; "
                         "everything else is kind- and text-exact. unresolved_in= names the served grammars the pattern did not "
                         "resolve for, and appears whenever that could mislead - on a zero result (the zero may be theirs, not the "
                         "code's) or on any run with skipped_files above zero. shown=/capped= = rows printed vs found. hits= is a "
                         "FLOOR, not a total, when EITHER hits_capped=\"1\" (engine match limit reached) or ellipsis_capped=\"1\"; "
                         "the latter means an ellipsis probe gave up on ellipsis_skipped= candidate nodes whose sibling run exceeded "
                         "ellipsis_bound, so a node that would have matched can be missing (ellipsis_skipped= counts ABANDONS and is "
                         "itself a floor on those nodes). raise the default cap with limit=N (offset=M pages) -->";

// R2 — everything ONE pattern run answers with before a byte is emitted, as one structured return (the
// same shape, and the same reason, as MatchQueryOutcome above). A non-empty `refusal` is the whole result:
// the caller prints it and exits 1, and no <pattern> element is ever opened.
struct PatternSearchOutcome
{
    std::vector<rw::AstMatch> matches;
    std::string               refusal;         // non-empty ⇒ refuse; already ends in a newline
    std::string               grammarsAttr;    // resolved grammar names, joined
    std::string               shapesAttr;      // "name:node_kind" per resolved grammar, joined
    std::string               ellipsisAttr;    // "" unless the pattern uses an ellipsis
    std::string               unresolvedAttr;  // "" unless some served grammar did not resolve
    std::size_t               eligibleFiles = 0;
    std::size_t               skippedFiles  = 0;   // served-language files this pattern never scanned (V-3)
    bool                      ellipsisCapped = false;   // an ellipsis probe abandoned a node at the bound (V-2)
    std::uint64_t             ellipsisSkipped = 0;      // how many times — a floor on the nodes left unevaluated
};

// Compile the pattern for every served grammar, decide refusal-or-proceed, run the walk, and assemble the
// disclosures. The refusal path is the load-bearing half: §P0.1's rule one level out — a pattern nothing
// could ask is not a zero, it is a refusal — and the served / not-served lists ride the message so the fix
// arrives in the same breath as the fault.
static PatternSearchOutcome runPatternSearch( const rw::IngestResult& ing, std::string_view rawPattern )
{
    PatternSearchOutcome                      out;
    const std::vector<rw::pattern::GrammarRow> rows     = rw::supportedPatternGrammars();
    const rw::pattern::CompileOutcome          compiled = rw::pattern::compileAll( rawPattern, rows );
    if( !compiled.ok )
    {
        out.refusal = "ripwire: --pattern: " + compiled.err + " (pattern as received: " + std::string( rawPattern ) + ")"
                      + " — served grammars: " + joinOwned( rw::pattern::servedNames( rows ), "," )
                      + "; not served: " + std::string( rw::pattern::kUnsupportedGrammars ) + "\n";
        return out;
    }
    const rw::pattern::PatternProgramSet& progs = compiled.set;

    std::atomic<std::uint64_t> ellipsisCapped{ 0 };

    rw::AstQueryGroup grp;
    grp.walk              = rw::AstWalk::Pattern;
    grp.patternPrograms   = &progs;
    grp.maxMatches        = rw::pattern::kMaxHits;
    grp.ellipsisCappedOut = &ellipsisCapped;
    out.matches           = std::move( rw::astQueryGrouped( ing, { grp } )[0] );

    out.ellipsisSkipped = ellipsisCapped.load( std::memory_order_relaxed );
    out.ellipsisCapped  = out.ellipsisSkipped != 0;

    out.grammarsAttr                 = joinOwned( rw::pattern::resolvedNames( progs ), "," );
    out.shapesAttr                   = joinOwned( rw::pattern::resolvedShapes( progs ), "," );
    const rw::PatternFileCensus cens = rw::eligiblePatternFiles( ing, progs );
    out.eligibleFiles                = cens.eligibleCount;
    out.skippedFiles                 = cens.skippedCount;
    // Both attributes below are emitted ONLY when they are facts about THIS pattern: an ellipsis fact on a
    // pattern with no ellipsis, or a partial-resolution note on a run that found plenty, is decoration —
    // and decoration is how a reader learns to stop reading attributes. unresolved_in= in particular is
    // ast-grep's PatternHasError posture: a partial resolution only MISLEADS when the answer is zero, so
    // the caller withholds it unless the row list is empty.
    if( progs.usesEllipsis )
    {
        // ellipsis_capped=/ellipsis_skipped= ride the same condition as ellipsis_bound= — they are facts
        // about an ellipsis run and decoration on anything else — but unlike the bound they are facts about
        // THIS run. ellipsis_capped= is always spelled, 0 or 1, exactly like hits_capped=/capped=: a
        // disclosure that only appears when it is bad teaches the reader to skim past it.
        out.ellipsisAttr = " ellipsis=\"first-match\" ellipsis_bound=\"" + std::to_string( rw::pattern::kEllipsisBound ) + "\""
                           + " ellipsis_capped=\"" + ( out.ellipsisCapped ? "1" : "0" ) + "\""
                           + " ellipsis_skipped=\"" + std::to_string( out.ellipsisSkipped ) + "\"";
    }
    if( !progs.unresolved.empty() )
    {
        out.unresolvedAttr = " unresolved_in=\"" + joinOwned( progs.unresolved, "," ) + "\"";
    }
    return out;
}

// octocode F3: the "compiled for no grammar" refusal's optional trailer — "" when nearestKind is empty (no
// candidate node-kind token in the query landed within the edit-distance cutoff of any linked grammar's
// vocabulary), which reads exactly as the refusal did before this fix (an honest "no plausible near-miss",
// never a guess). Extracted so the refusal call site stays a single fprintf, not a nested if beside it.
static std::string matchNearestKindClause( const std::string& kind, const std::string& grammar )
{
    if( kind.empty() )
    {
        return std::string();
    }
    std::string clause = " — nearest_kind=\"" + kind + "\"";
    if( !grammar.empty() )
    {
        clause += " grammar=\"" + grammar + "\"";
    }
    return clause;
}

std::optional<int> runLint( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses (sarif.h) — --lint's
    // OWN --sarif re-serialization (writeSarifResult) already applies it; this brings the native --match/
    // --lint XML forms into parity rather than leaving them the only two still absolute per row.
    const bool         lintSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string  lintRootPrefix = lintSingleRoot ? rw::sarif::rootPrefixOf( cfg.roots[0] ) : std::string();
    std::vector<char>  lintRootEsc;
    const std::string  lintRootAttr   = lintSingleRoot ? ( " root=\"" + std::string( escapeXml( cfg.roots[0], lintRootEsc ) ) + "\"" ) : std::string();

    // --lint-catalog: the built-in rule registry, standalone — needs no corpus at all (lintcatalog.h's
    // table is static), so it is handled before the match/lint/lint-rules setup below even starts.
    if( cfg.lintCatalog )
    {
        return emitLintCatalog();
    }

    // --match=QUERY (structural search) and --lint (built-in checks) both ride the shared AST-query pass and
    // annotate each hit with its enclosing symbol — so they share this setup.
    if( !cfg.match.empty() || !cfg.pattern.empty() || cfg.lint || !cfg.lintRulesDir.empty() )
    {
        // model.h::symbolsByFile — same scan order, same comparator as the hand-written loop it replaces.
        const SymbolsByFile fileSyms = symbolsByFile( ing,
                                                      []( const Symbol& ) { return true; },
                                                      [ & ]( NodeId a, NodeId b ) { return ing.symbols[a].sigStartByte < ing.symbols[b].sigStartByte; } );
        const auto enclosing = [ & ]( std::uint32_t f, std::uint32_t off ) -> const Symbol*
        {
            const Symbol* best = nullptr;
            for( NodeId id : fileSyms[f] )
            {
                const Symbol& s = ing.symbols[id];
                if( s.sigStartByte > off )
                {
                    break;
                }
                if( off < s.endByte && ( !best || s.sigStartByte > best->sigStartByte ) )
                {
                    best = &s;
                }
            }
            return best;
        };
        const auto emitEscaped = []( const std::string& s )
        {
            for( char ch : s )
            {
                if( ch == '<' )
                {
                    std::fputs( "&lt;", stdout );
                }
                else if( ch == '>' )
                {
                    std::fputs( "&gt;", stdout );
                }
                else if( ch == '&' )
                {
                    std::fputs( "&amp;", stdout );
                }
                else
                {
                    std::fputc( ch, stdout );
                }
            }
        };
        std::vector<char> esc;
        const auto        ex  = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
        const int         cap = cfg.packTopN > 0 ? cfg.packTopN : 100;

        if( !cfg.match.empty() )   // structural search: the user's tree-sitter query (≥1 @capture)
        {
            // P2.1: the listing stops at `cap` (--pack-top-n, default 100) while hits= counted everything the
            // engine collected — a `hits="5000"` header over 100 rows said nothing about the other 4900.
            // And hits= is itself bounded by astQuery's own maxMatches, so `hits="5000"` is a FLOOR, not a
            // total; hits_capped= says which of the two it is (same contract as --grep's).
            // §P0.1: astQuery reports CAPTURES, so a query binding none matches nothing it can report —
            // `--match='(if_statement)'` produced a clean, confident hits="0" next to 5000 for the same
            // query with `@i`. A capture-less bare zero must be unreachable: auto-capture the query when
            // appending a capture is provably what the user would have typed (exactly one top-level
            // pattern), and refuse loudly otherwise. Never scan a query we did not understand.
            std::string matchQuery( cfg.match );
            bool        autoCaptured = false;
            {
                const AstQueryShape shape = astQueryShape( matchQuery );
                if( !shape.hasCapture )
                {
                    // A `;` comment makes appending unsafe (` @m` on the end of a comment line is itself
                    // commented out), so a capture-less query that carries one is refused, not guessed at.
                    if( !shape.isSingleTopLevel || shape.hasComment )
                    {
                        // Deliberately does NOT assert a cause: this branch catches several top-level
                        // patterns, zero patterns, and a mis-quoted query alike, and naming the wrong one
                        // would be its own small fabrication. Show the query as received and let the
                        // reader see the stray quote / second pattern for themselves.
                        std::fprintf( stderr, "ripwire: --match: this query captures nothing — add @name, e.g. '(if_statement) @m'. "
                                              "ripwire auto-captures only a query that is exactly ONE top-level pattern, and will not guess for this one "
                                              "(query as received: %s)\n",
                                      matchQuery.c_str() );
                        return 1;
                    }
                    matchQuery  += " @m";
                    autoCaptured = true;
                }
            }
            constexpr std::size_t        kMatchMaxHits = 5000;   // astQuery's per-spec budget, named not implied
            const MatchQueryOutcome      mq = runMatchQuery( ing, matchQuery, kMatchMaxHits );
            const std::vector<AstMatch>& ms            = mq.matches;
            const std::string&           grammarsAttr  = mq.grammarsAttr;   // §L3: which grammars the query compiled against
            const std::size_t&           eligibleFiles = mq.eligibleFiles;
            // §P0.4's rule, applied to --match's own engine: a query no grammar compiled measured NOTHING,
            // so a hits="0" here would be a failure wearing a result. Refuse, exactly like an invalid --regex.
            if( !mq.uncompiled.empty() )
            {
                std::fprintf( stderr, "ripwire: --match: the query compiled for no grammar — refusing rather than reporting a zero it did not measure "
                                      "(query as received: %s)%s\n",
                              std::string( cfg.match ).c_str(), matchNearestKindClause( mq.nearestKind, mq.nearestGrammar ).c_str() );
                return 1;
            }
            // §P8 G3: --match was missed when its sibling --grep got paging — `--limit=5` still emitted the
            // full 100-row cap, so the two structurally identical search verbs disagreed about whether
            // --limit meant anything. Same window, same disclosure, same default cap (--pack-top-n, else
            // 100): pageDisclosure emits exactly the ` shown= capped=` bytes this tag used to hand-roll, so
            // an un-paginated --match is byte-identical. See src/pageview.h, THE TRUNCATION VOCABULARY.
            const PageWindow  matchPage  = pageWindow( ms.size(), effectiveRowCap( cfg.pageLimit, cap ), cfg.pageOffset );
            const std::size_t matchShown = matchPage.end - matchPage.begin;
            char              mpab[ kPageDisclosureCap ];
            // §L3: no `attr="value"` spelled out below for grammars=/eligible_files=/of_files= — a naive
            // whole-line grep (matchcapturecheck.sh's own idiom) would match the WORDED example first.
            std::printf( "<!-- ripwire match: tree-sitter structural query; each hit = a captured node + its enclosing symbol. "
                         "shown=/capped= = rows printed vs found; hits_capped=\"1\" ⇒ hits= is a FLOOR (engine match limit reached). "
                         "auto_captured=\"1\" ⇒ the query bound no @capture and ripwire appended `@m` to its single top-level pattern. "
                         "grammars= names every grammar the query compiled against; eligible_files=/of_files= are corpus files in that "
                         "language set vs total indexed files. raise the default cap with limit=N (offset=M pages) -->" );
            std::printf( "<match hits=\"%zu\"%s hits_capped=\"%d\"%s grammars=\"%s\" eligible_files=\"%zu\" of_files=\"%zu\"%s>",
                         ms.size(),
                         pageDisclosure( mpab, sizeof( mpab ), matchShown, ms.size(), matchPage.end,
                                         cfg.pageLimit, cfg.pageOffset, true ),
                         ms.size() >= kMatchMaxHits ? 1 : 0,
                         autoCaptured ? " auto_captured=\"1\"" : "",
                         ex( grammarsAttr ).c_str(),
                         eligibleFiles,
                         ing.files.size(),
                         lintRootAttr.c_str() );
            for( std::size_t hitIndex = matchPage.begin; hitIndex < matchPage.end; ++hitIndex )
            {
                const AstMatch&         m  = ms[ hitIndex ];
                const Symbol*           e  = enclosing( m.fileId, m.startByte );
                const std::string_view  rp = lintSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ m.fileId ], lintRootPrefix ) : std::string_view( ing.files[ m.fileId ] );
                std::printf( "<m p=\"%s:%u\" in=\"%s\">", ex( rp ).c_str(), m.line, e ? ex( e->name ).c_str() : "" );
                emitEscaped( m.text );
                std::printf( "</m>" );
            }
            std::printf( "</match>" );
            return 0;
        }

        // R2 — the PATTERN surface: structural search written in CODE instead of in node kinds.
        // Sits here, beside --match, because it answers the same question through the same walk and must
        // emit through the same conventions (enclosing symbol, page window, grammar applicability). The
        // work BEFORE the walk — compile per grammar, refuse or proceed, assemble the disclosures — is
        // runPatternSearch, extracted for exactly the reason runMatchQuery was: runLint's dispatcher body
        // is already one of the largest in this file and must not grow a verb's worth of plumbing.
        if( !cfg.pattern.empty() )
        {
            const PatternSearchOutcome ps = runPatternSearch( ing, cfg.pattern );
            if( !ps.refusal.empty() )
            {
                std::fprintf( stderr, "%s", ps.refusal.c_str() );
                return 1;
            }
            const PageWindow  patPage  = pageWindow( ps.matches.size(), effectiveRowCap( cfg.pageLimit, cap ), cfg.pageOffset );
            const std::size_t patShown = patPage.end - patPage.begin;
            char              ppab[ kPageDisclosureCap ];
            std::printf( "%.*s", int( kPatternLegend.size() ), kPatternLegend.data() );
            // unresolved_in= is withheld only when it could not mislead: a run that found matches AND read
            // every file it serves. The moment a served-language file went unscanned (skipped_files>0), the
            // partial resolution is exactly what explains it, hits>0 or not — V-3's second case, where a
            // matched .tsx sat beside a silently unread .ts.
            const bool tellUnresolved = ps.matches.empty() || ps.skippedFiles > 0;
            std::printf( "<pattern hits=\"%zu\"%s hits_capped=\"%d\" q=\"%s\" grammars=\"%s\" shapes=\"%s\" unsupported=\"%.*s\"%s%s eligible_files=\"%zu\" skipped_files=\"%zu\" of_files=\"%zu\"%s>",
                         ps.matches.size(),
                         pageDisclosure( ppab, sizeof( ppab ), patShown, ps.matches.size(), patPage.end, cfg.pageLimit, cfg.pageOffset, true ),
                         ps.matches.size() >= rw::pattern::kMaxHits ? 1 : 0,
                         ex( cfg.pattern ).c_str(),
                         ex( ps.grammarsAttr ).c_str(),
                         ex( ps.shapesAttr ).c_str(),
                         int( rw::pattern::kUnsupportedGrammars.size() ), rw::pattern::kUnsupportedGrammars.data(),
                         ps.ellipsisAttr.c_str(),
                         tellUnresolved ? ps.unresolvedAttr.c_str() : "",
                         ps.eligibleFiles,
                         ps.skippedFiles,
                         ing.files.size(),
                         lintRootAttr.c_str() );
            for( std::size_t hitIndex = patPage.begin; hitIndex < patPage.end; ++hitIndex )
            {
                const rw::AstMatch&    m  = ps.matches[ hitIndex ];
                const Symbol*          e  = enclosing( m.fileId, m.startByte );
                const std::string_view rp = lintSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ m.fileId ], lintRootPrefix ) : std::string_view( ing.files[ m.fileId ] );
                std::printf( "<m p=\"%s:%u\" in=\"%s\">", ex( rp ).c_str(), m.line, e ? ex( e->name ).c_str() : "" );
                emitEscaped( m.text );
                std::printf( "</m>" );
            }
            std::printf( "</pattern>" );
            return 0;
        }

        // --lint: built-in single-capture [AST]-only checks (C-family). Descriptive — facts, not gates;
        // never the [FLOW]/[TYPE] checks ripwire can't see soundly.
        //
        // S6-A: added 4 new AST-query checks + 3 symbol-level checks (large-function, deep-nesting,
        // inconsistent-return) that require body-text analysis beyond what a single tree-sitter capture gives.
        // Checks skipped (too noisy / require real semantics):
        //   missing-const — needs type inference + mutation analysis ([TYPE]) — false positives on out-params
        //   non-virtual-dtor — needs inheritance graph ([TYPE]) — not reliably detectable from the AST alone
        //   implicit-bool-conv — `if(ptr)` is idiomatic C++; flagging it produces near-universal noise
        std::vector<AstMatch> ms;   // combined findings (built-in tags + user rule ids); shared by both sources

        std::vector<RuleCap> saturatedRules;   // see the RuleCap declaration at file scope for why the key is a PAIR

        // All BUILT-IN rule names in declaration order — drives the per-rule tally in the XML header.
        // Symbol-level checks are appended after the query-based checks; order matches the conceptual list.
        // Declared BEFORE the --lint block so the atoms pack can append its own names from inside it (one
        // guarded region instead of two, which is also what keeps runLint's branch count from growing per pack).
        std::vector<std::string> allRuleNames = {
            "c-style-cast", "goto", "do-while", "unsafe-c-fn", "weak-crypto", "redundant-parens",
            "suspicious-semicolon", "typedef-over-using", "magic-number", "empty-catch", "self-assign",
            "large-function", "deep-nesting", "inconsistent-return", "unreachable-code",
            "naming-short", "naming-wordy", "naming-series", "naming-underscore", "naming-case",
            "naming-predicate", "naming-setter", "naming-confusable", "naming-uninformative",
        };

        if( cfg.lint )   // built-in [AST] checks only run with --lint; --lint-rules alone emits user findings only
        {
        const std::vector<AstQuerySpec> checks = {
            { "(cast_expression) @c",                                                                       "c-style-cast" },         // cppcoreguidelines-pro-type-cstyle-cast
            { "(goto_statement) @c",                                                                        "goto" },                  // cppcoreguidelines-avoid-goto
            { "(do_statement) @c",                                                                          "do-while" },              // cppcoreguidelines-avoid-do-while
            { "(call_expression function: (identifier) @c (#match? @c \"^(strcpy|strcat|sprintf|gets)$\"))","unsafe-c-fn" },           // bugprone unbounded C string fns
            { "(call_expression function: (identifier) @c (#match? @c \"^(MD5|md5|SHA1|sha1|MD4|md4|RC4|rc4)$\"))","weak-crypto" },   // broken hash/cipher (the one [AST] security item; insecure rand() excluded — too noisy)
            { "(parenthesized_expression (parenthesized_expression) @c)",                                   "redundant-parens" },      // clang-tidy readability-redundant-parentheses
            { "(if_statement consequence: (expression_statement) @c)",                                      "suspicious-semicolon" },  // clang-tidy bugprone-suspicious-semicolon (post-filtered below)
            // S6-A new checks:
            { "(type_definition declarator: (type_identifier) @c)",                                         "typedef-over-using" },    // C-style typedef struct/union in C++ — prefer using T = ...
            { "(number_literal) @c",                                                                        "magic-number" },          // numeric literal outside const/constexpr init (post-filtered below)
            { "(catch_clause body: (compound_statement) @c)",                                               "empty-catch" },           // catch block with empty/comment-only body (post-filtered below)
            { "(assignment_expression left: (_) @lhs right: (_) @rhs (#eq? @lhs @rhs))",                   "self-assign" },           // x = x — predicate rejects unequal pairs before post-filtering
        };
        // §P0.2: kLintMaxPerRule (lintrules.h) is spent PER RULE, not pooled — a rule can only ever be capped
        // by its own matches. A rule that lands exactly on the budget has a count= that is a FLOOR, disclosed below.
        // The corpus text the one grouped walk read, kept alive for the symbol-level passes below so they
        // do not re-open the same files a second and third time. Lives exactly as long as this lint block.
        std::vector<std::string>           corpusBytes;
        std::vector<std::vector<AstMatch>> grouped = builtInLintCaptures( ing, checks, corpusBytes );
        ms = std::move( grouped[0] );
        for( const AstQuerySpec& check : checks )       // saturation is measured on the RAW captures, before the post-filters below thin them
        {
            std::size_t rawForRule = 0;
            for( const AstMatch& m : ms )
            {
                if( m.tag == check.tag )
                {
                    ++rawForRule;
                }
            }
            if( rawForRule >= kLintMaxPerRule )
            {
                saturatedRules.push_back( { check.tag, false } );
            }
        }

        // suspicious-semicolon: the query also matches a normal `if(x) foo();` (the grammar gives both an
        // expression_statement consequence). Keep ONLY an empty body — matched text trims to just ";" — the real bug.
        ms.erase( std::remove_if( ms.begin(), ms.end(), []( const AstMatch& m )
                                  {
                                      if( m.tag != "suspicious-semicolon" )
                                      {
                                          return false;
                                      }
                                      const auto ws = []( char c )
                                      { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; };
                                      std::string_view t  = m.text;
                                      while( !t.empty() && ws( t.front() ) )
                                      {
                                          t.remove_prefix( 1 );
                                      }
                                      while( !t.empty() && ws( t.back() ) )
                                      {
                                          t.remove_suffix( 1 );
                                      }
                                      return t != ";";   // non-empty body → not the bug → drop
                                  } ),
                  ms.end() );

        // empty-catch: keep ONLY catch bodies whose trimmed text is empty (nothing but whitespace/braces).
        // The captured node is the compound_statement — its text is "{...}"; trim and check for "{}".
        ms.erase( std::remove_if( ms.begin(), ms.end(), []( const AstMatch& m )
                                  {
                                      if( m.tag != "empty-catch" )
                                      {
                                          return false;
                                      }
                                      const auto ws = []( char c )
                                      { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; };
                                      std::string_view t = m.text;
                                      while( !t.empty() && ws( t.front() ) )
                                      {
                                          t.remove_prefix( 1 );
                                      }
                                      while( !t.empty() && ws( t.back() ) )
                                      {
                                          t.remove_suffix( 1 );
                                      }
                                      // After trimming, an empty body is "{}" or "{ }" (only whitespace between braces).
                                      if( t.size() < 2 || t.front() != '{' || t.back() != '}' )
                                      {
                                          return true; // malformed — drop
                                      }
                                      std::string_view inner = t.substr( 1, t.size() - 2 );
                                      for( char c : inner )
                                      {
                                          if( !ws( c ) )
                                          {
                                              return true; // non-whitespace inside → not empty → drop
                                          }
                                      }
                                      return false;   // truly empty catch body → keep the finding
                                  } ),
                  ms.end() );

        std::vector<std::string> magicFileBytes( ing.files.size() );
        std::vector<char>        magicFileRead( ing.files.size(), 0 );
        const auto magicBytes = [ & ]( std::uint32_t fileId ) -> const std::string&
        {
            if( !magicFileRead[fileId] )
            {
                darkflags::readWhole( diskPath( ing, fileId ), magicFileBytes[fileId] );
                magicFileRead[fileId] = 1;
            }
            return magicFileBytes[fileId];
        };

        // magic-number: drop literals that are:
        //   (a) semantic -2..2 forms (universal idioms) or base-prefixed masks/protocol constants
        //   (b) inside a const/constexpr variable initializer (that's exactly the right place for numbers)
        //   (c) inside an enum body (enumerator values are naturally numeric)
        // Keep only literals inside function/method bodies to limit noise.
        // The enclosing symbol check (Function/Method) is the main guard.
        ms.erase( std::remove_if( ms.begin(), ms.end(), [ & ]( const AstMatch& m )
                                  {
                                      if( m.tag != "magic-number" )
                                      {
                                          return false;
                                      }
                                      if( isUniversalOrAllowlistedNumber( m.text ) )
                                      {
                                          return true;
                                      }
                                      const std::string& src = magicBytes( m.fileId );
                                      if( !src.empty() && isConstantInitializerNumber( src, m.startByte ) )
                                      {
                                          return true;
                                      }
                                      // must be inside a function/method body to be a magic-number finding
                                      const Symbol* e = enclosing( m.fileId, m.startByte );
                                      if( !e || ( e->kind != SymKind::Function && e->kind != SymKind::Method ) )
                                      {
                                          return true;
                                      }
                                      return false;   // non-trivial literal in a function body → flag it
                                  } ),
                  ms.end() );

        // #eq? rejected unequal assignment pairs inside tree-sitter, so the remaining captures arrive as
        // lhs/rhs twins in byte order. Collapse every complete twin pair into one finding; unlike the old
        // (file,line) bucket this cannot cross-wire two independent assignments sharing a source line.
        {
            std::vector<AstMatch> saKeep;
            std::vector<AstMatch> saCaptured;
            for( const AstMatch& m : ms )
            {
                if( m.tag == "self-assign" )
                {
                    saCaptured.push_back( m );
                }
            }
            ms.erase( std::remove_if( ms.begin(), ms.end(), []( const AstMatch& m ) { return m.tag == "self-assign"; } ), ms.end() );
            for( std::size_t i = 0; i + 1 < saCaptured.size(); i += 2 )
            {
                const AstMatch& lhs = saCaptured[i];
                const AstMatch& rhs = saCaptured[i + 1];
                if( lhs.fileId != rhs.fileId || lhs.text != rhs.text )
                {
                    continue; // defensive: an incomplete/crossed capture pair is never evidence
                }
                const auto trim = []( std::string_view t ) -> std::string
                {
                    const auto ws = []( char c ) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; };
                    while( !t.empty() && ws( t.front() ) )
                    {
                        t.remove_prefix( 1 );
                    }
                    while( !t.empty() && ws( t.back() ) )
                    {
                        t.remove_suffix( 1 );
                    }
                    return std::string( t );
                };
                const std::string expression = trim( lhs.text );
                AstMatch hit;
                hit.fileId    = lhs.fileId;
                hit.startByte = lhs.startByte;
                hit.endByte   = lhs.endByte;
                hit.line      = lhs.line;
                hit.tag       = "self-assign";
                hit.text      = expression + " = " + expression;
                saKeep.push_back( std::move( hit ) );
            }
            // Sort saKeep for determinism before appending.
            std::sort( saKeep.begin(), saKeep.end(), [ & ]( const AstMatch& x, const AstMatch& y )
                       {
                if( ing.files[x.fileId] != ing.files[y.fileId] ) { return ing.files[x.fileId] < ing.files[y.fileId];
}
                return x.line < y.line; } );
            for( auto& hit : saKeep )
            {
                ms.push_back( std::move( hit ) );
            }
        }

        // Symbol-level checks (S6-A): walk each Function/Method body — checks that need line-counting or
        // control-flow nesting depth, which a single tree-sitter @capture can't give without reparsing.
        // These produce AstMatch entries (same format) so they flow into the same XML tally/listing.
        //
        //   large-function    — body line-span (newlines in [sigEndByte, endByte)) > 80
        //   deep-nesting      — curly-brace nesting depth inside [sigEndByte, endByte) > 4
        //   inconsistent-return — mix of `return;` and `return <expr>;` in the same body
        //
        // Note: deep-nesting uses curly-brace depth as a proxy for control-flow depth (fast, no full reparse).
        // This correctly catches deeply nested if/for/while blocks because each adds a `{` in Allman/K&R style.
        // It can over-report on struct-initialiser nesting — acceptable, as those are also a complexity signal.
        { PROFILE_SCOPE_DESCRIBE( "lint: lintSymbolLevelChecks" );
        for( AstMatch& symHit : lintSymbolLevelChecks( ing, &corpusBytes ) )
        {
            ms.push_back( std::move( symHit ) );
        }
        }

        // unreachable-code (joern-lite CFG sketch): pure-syntactic intra-block dead-code — a statement
        // after an unconditional exit (return/break/continue/throw, +Python raise) in the SAME block.
        // Conservative: no dataflow, goto excluded, jump-target siblings stop the scan (no false positives
        // on code reached via a label or on `if(x) return; foo();` where foo() is a reachable sibling).
        // Already collected, sorted and capped: it rode the one grouped walk above as grouped[3] instead of
        // spending a fourth read + parse of the whole corpus on its own pool.
        {
            PROFILE_SCOPE_DESCRIBE( "lint: mergeUnreachable" );
            for( auto& h : grouped[3] )
            {
                ms.push_back( std::move( h ) );
            }
        }

        // The packs that live outside this function: the atoms-of-confusion pack (src/atoms.h), the
        // identifier-naming lens (src/naminglens.h) and the cache-friendliness pack (src/cachelint.h).
        // Each merges its own findings, its own floor disclosures and — for the packs whose rule list is
        // owned by the pack — its own rule names. All run here, inside the one --lint guard, so the sort
        // below covers every built-in finding regardless of its source.
        { PROFILE_SCOPE_DESCRIBE( "lint: mergeAtomsPack" ); mergeAtomsPack( ing, ms, saturatedRules, allRuleNames, std::move( grouped[1] ) ); }
        { PROFILE_SCOPE_DESCRIBE( "lint: mergeNamingLens" ); mergeNamingLens( ing, ms, saturatedRules, cfg.namingLocals, &corpusBytes ); }
        { PROFILE_SCOPE_DESCRIBE( "lint: mergeCachePack" ); mergeCachePack( ing, ms, saturatedRules, allRuleNames, std::move( grouped[2] ) ); }

        // Re-sort the combined findings (AST + symbol-level) for deterministic output.
        std::sort( ms.begin(), ms.end(), [ & ]( const AstMatch& x, const AstMatch& y )
                   {
            if( ing.files[x.fileId] != ing.files[y.fileId] ) { return ing.files[x.fileId] < ing.files[y.fileId];
}
            if( x.startByte != y.startByte ) { return x.startByte < y.startByte;
}
            return x.tag < y.tag; } );
        }   // if( cfg.lint ) — built-in checks

        // LintOut = the unified finding shape so built-in tags and user rule ids emit identically (defined
        // at file scope, above lintSymbolLevelChecks — dedupeLintFindings shares it). sev is empty for
        // built-ins (facts, not severities); user findings carry their declared sev=.
        std::vector<LintOut> outs;  outs.reserve( ms.size() );
        for( const AstMatch& m : ms )
        {
            outs.push_back( { m.fileId, m.startByte, m.line, m.tag, std::string(), m.text } );
        }

        // --lint-rules=DIR: load user YAML rules and run them through the SAME astQuery engine. Malformed
        // files alert+skip inside the loader; a bad ts query alert+skips inside astQuery. Exit 1 ONLY if the
        // flag was given but zero rules loaded (nothing to run = a user mistake worth surfacing).
        std::vector<LintRule> userRules;
        if( !cfg.lintRulesDir.empty() )
        {
            userRules = loadLintRules( std::string( cfg.lintRulesDir ) );
            if( userRules.empty() )
            {
                std::fprintf( stderr, "ripwire: --lint-rules=%.*s: no rules loaded\n", int( cfg.lintRulesDir.size() ), cfg.lintRulesDir.data() );
                return 1;
            }
            const auto [ userFindings, saturatedUserRuleIds ] = runLintRules( ing, userRules );
            for( const LintFinding& f : userFindings )
            {
                outs.push_back( { f.fileId, f.startByte, f.line, f.id, f.severity, f.message } );
            }
            for( const std::string& id : saturatedUserRuleIds )
            {
                saturatedRules.push_back( { id, true } );
            }
        }

        // --lint-select=PREFIX[,...] / --lint-ignore=PREFIX[,...]: resolved HERE, not in validateConfig,
        // because a PREFIX can legitimately name a user rule id that --lint-rules=DIR has only just
        // loaded above. See resolveLintSelection's own header for the pool it validates against.
        const std::optional<rw::lintcatalog::LintSelection> lintSelOpt = resolveLintSelection( cfg, userRules );
        if( !lintSelOpt )
        {
            return 1;   // refusal already printed
        }
        const rw::lintcatalog::LintSelection& lintSel = *lintSelOpt;
        if( lintSel.active )
        {
            outs.erase( std::remove_if( outs.begin(), outs.end(),
                                        [ & ]( const LintOut& o ) { return !rw::lintcatalog::lintSelectionKeeps( lintSel, o.rule ); } ),
                       outs.end() );
        }

        // Final deterministic order over the COMBINED set — see sortLintRows for why the key runs all the
        // way out to the row's own text.
        sortLintRows( ing, outs );

        // §P6.1: collapse rows that would render byte-identically (see dedupeLintFindings above for why —
        // two genuinely different AST captures, e.g. the same magic-number value spelled twice on one line,
        // can share the same rule/file:line/enclosing-symbol/text because the row carries no column).
        outs = dedupeLintFindings( ing, std::move( outs ) );

        // W3-S (2026-08-19): E6 found --lint emitting an UNCAPPED payload on a large corpus — 2,037,645 B /
        // 6,169 findings (~330 B/finding, driven by long single-line minified text=) with no --help promise
        // ("trims to fit") kept and no way for a caller to see it coming; every other verb in the catalog has
        // a display default (--hotspots 40, --grep 100, …), --lint alone had none. Measured HERE before
        // choosing the cap: this repo prints 367,924 B / 3,213 findings (~114 B/finding); a second, larger
        // polyglot fixture (ctxpack, 1,033 tracked files) prints 254,445 B / 2,312 findings (~110 B/finding).
        // kLintDefaultPayloadBytes=100,000 lands an order of magnitude under E6's pathological case while
        // staying multiples of every other capped verb's default payload on this repo (--hotspots ~5.5 KB,
        // --clones ~17 KB, --grep(100 hits) ~57 KB) — --lint's own facts are individually smaller so it earns
        // a bigger budget. An explicit --limit=N always beats it (effectiveRowCap's existing rule), so a
        // caller who already knew to page past a cap sees no change.
        static constexpr std::size_t kLintDefaultPayloadBytes = 100000;
        const bool paging = cfg.pageLimit > 0 || cfg.pageOffset > 0;
        std::size_t lintDefaultShown = outs.size();
        if( !paging )
        {
            // Byte-budget the default (unpaged) run. Rows are already in final sorted order, so this keeps
            // the same sorted PREFIX pageWindow() would keep by row count; the stopping rule is bytes here
            // because a corpus with long text= rows (E6's vendored-bundle case) needs far FEWER rows to reach
            // the same budget than a corpus of short rows does. text= dominates real row size and is summed
            // exactly; the flat +80 covers the <f> tag markup, path, rule name and enclosing symbol name,
            // which are all short in practice — an estimate, not a second full render (that would mean
            // rendering the very tail this exists to avoid paying for), and one that can only ever be
            // conservative in the wrong direction (undercounting an unusually long path/rule name by a few
            // dozen bytes), never by the orders of magnitude that would silently readmit the 2 MB case.
            std::size_t bytesUsed = 0;
            lintDefaultShown = 0;
            for( std::size_t i = 0; i < outs.size(); ++i )
            {
                const LintOut& m = outs[i];
                const Symbol*  e = enclosing( m.fileId, m.startByte );
                const std::size_t rowBytes = m.text.size() + m.rule.size() + m.sev.size()
                                            + ing.files[ m.fileId ].size()
                                            + ( e ? e->name.size() : 0 ) + 80;
                if( lintDefaultShown > 0 && bytesUsed + rowBytes > kLintDefaultPayloadBytes )
                {
                    break;   // the sorted prefix already kept at least one row — stop BEFORE the overflow row
                }
                bytesUsed += rowBytes;
                ++lintDefaultShown;
            }
        }
        const PageWindow lintPage = paging
                                  ? pageWindow( outs.size(), cfg.pageLimit, cfg.pageOffset )
                                  : PageWindow{ 0, lintDefaultShown };
        const std::size_t shownCount = lintPage.end - lintPage.begin;

        // §P0.2 disclosure: which rules (if any) spent their whole per-rule budget, so their count= is a floor.
        const auto capOf = [ & ]( const std::string& ruleName, bool isUserRule ) -> const RuleCap*
        {
            for( const RuleCap& rc : saturatedRules )
            {
                if( rc.rule == ruleName && rc.isUserRule == isUserRule )
                {
                    return &rc;
                }
            }
            return nullptr;
        };
        const bool anyRuleCapped = !saturatedRules.empty();

        // §L7: per-rule LANGUAGE applicability — a rule whose registered languages (lintcatalog.h) never
        // intersect the corpus' own languages is not "measured zero", it is structurally inert here.
        // Applicability is per-LANGUAGE granularity (does the corpus contain ANY file of a language this
        // rule's grammar could ever satisfy), never per-file-content — a rule can be "applicable" and
        // still find nothing. See computeLintApplicability's own header for why it lives outside this function.
        const LintApplicability lintApplicability = computeLintApplicability( ing, cfg.lint, allRuleNames, userRules, lintSel );
        const std::uint32_t     corpusLangs        = lintApplicability.corpusLangs;
        const std::size_t       inertRuleCount      = lintApplicability.inertRuleCount;

        // --sarif: `outs` re-serialized as SARIF instead of the native XML below (emitRunLintSarif above).
        // validateConfig already refused this alongside --match / --with-profile / paging.
        if( cfg.sarif )
        {
            emitRunLintSarif( d, allRuleNames, userRules, saturatedRules, outs, lintSel, corpusLangs, enclosing );
            return 0;
        }

        // --with-profile join, lifted into buildHeatAnnotations (runLint was already the file's largest
        // verb): per-finding heat_* attribute strings index-aligned with `outs`, + the root attribute.
        std::vector<std::string> heatByFinding;
        std::string              heatJoinedAttr;
        if( !cfg.withProfile.empty() )
        {
            auto heat = buildHeatAnnotations( cfg.withProfile, ing, outs, enclosing );
            if( !heat )
            {
                return 1;   // refusal already printed — never join nothing silently
            }
            heatByFinding  = std::move( heat->first );
            heatJoinedAttr = std::move( heat->second );
        }

        // §L7 root disclosure: inert_rules= (only when >0 — same "absent = nothing to say" convention as
        // findings_capped=) and, only when --lint-select/--lint-ignore were given, selected="K of N" plus
        // the raw select=/ignore= you passed, so a filtered zero is never confusable with an unfiltered one.
        std::string lintRootExtra;
        if( inertRuleCount > 0 )
        {
            char buf[ 48 ];
            std::snprintf( buf, sizeof( buf ), " inert_rules=\"%zu\"", inertRuleCount );
            lintRootExtra += buf;
        }
        if( lintSel.active )
        {
            char buf[ 64 ];
            std::snprintf( buf, sizeof( buf ), " selected=\"%zu of %zu\"", lintSel.selectedCount, lintSel.totalCount );
            lintRootExtra += buf;
            if( !cfg.lintSelect.empty() )
            {
                lintRootExtra += " select=\"" + ex( cfg.lintSelect ) + "\"";
            }
            if( !cfg.lintIgnore.empty() )
            {
                lintRootExtra += " ignore=\"" + ex( cfg.lintIgnore ) + "\"";
            }
        }

        // §P8 collision, documented not renamed — see the --grep legend above for the full reasoning.
        std::printf( "<!-- ripwire lint: [AST]-only checks (descriptive facts, not gates). rule=the check; sev=user-rule severity; "
                     "in=enclosing symbol NAME (the same spelling is a fan-in COUNT in for/pack-task/exemplar). "
                     "A rule named atom-X is an atom of confusion (Gopstein, FSE 2017): a C-family shape that misleads READERS, C/C++/ObjC/CUDA only. "
                     "Each rule is scanned under its OWN match budget, so no rule is ever starved by a noisier one. "
                     "A rule that spends its whole budget carries capped=\"1\" — its count= is then a FLOOR (that rule's raw captures reached the "
                     "per-rule budget; only its own matches can cap it); findings_capped=\"1\" on the root ⇒ at least one rule is a floor. "
                     "Absent = nothing was capped and every count= is a total. raise the default cap with limit=N (offset=M pages). "
                     "On the root, shown=/capped= are the ROW-COUNT pair (rows printed vs whether the DEFAULT payload byte-cap trimmed "
                     "them, absent an explicit limit=) — a different fact from the per-rule capped=\"1\" above, which is a MATCH-BUDGET "
                     "floor on one rule's own count=; findings= is always the true total either way. "
                     "A rule row's applicable=\"0\" ⇒ NONE of its registered languages (the lint-catalog listing) are present in this "
                     "corpus at all — its count=\"0\" is structural inertness, never a measurement; the root's inert_rules=N tallies "
                     "how many printed rows that is true for. lint-select=/lint-ignore=PREFIX[,...] narrow the printed rows to a "
                     "family (e.g. cache-); the root then carries selected=\"K of N\" plus the raw select=/ignore= you passed. "
                     "Each rule row's own shown_rows=/rows_capped= is how many of THAT rule's rows fall inside the printed <f> window "
                     "(the root's shown=/capped= trims a SORTED PREFIX of the combined findings, so a rule whose rows all sort past the "
                     "cut carries shown_rows=\"0\" rows_capped=\"1\" while its count= stays the true total — never confuse a capped-away "
                     "rule with one that measured zero); this is a DIFFERENT fact from the row's own bare capped=\"1\" above (that rule's "
                     "own raw-capture stream hit its per-rule match budget) — the two can disagree on the same row. -->" );
        if( !cfg.withProfile.empty() )
        {
            std::printf( "<!-- with-profile: heat_* on a finding = MEASURED inclusive totals of the joined #PROF_TSV scope — the nearest "
                         "PROFILE_SCOPE site at/above the finding inside its own enclosing symbol. Columns are whatever counter tier the "
                         "profiled run armed; an ABSENT heat column was not measured, never zero. heat_joined= on the root counts annotated "
                         "findings; 0 is honest (no finding sits inside a profiled scope), never an error. -->" );
        }
        {
            // §P8 vocabulary (see src/pageview.h, THE TRUNCATION VOCABULARY, rule 3): --lint ESTABLISHED the
            // six-attribute paging block that pageDisclosure() now serves to every other paging verb, but its
            // own hand-rolled copy never grew the capped= bit pageDisclosure emits, so the verb that defined
            // the shape was the one verb that did not spell it — fixed here by calling the shared helper
            // instead of hand-rolling a second copy (W3-S: this is also what lets the new default byte cap
            // above disclose shown=/capped= on the UNPAGED path, which the old hand-rolled `else` branch could
            // not do at all). discloseCap=true unconditionally, same as every other default-capped verb
            // (--impact, --hotspots, …): pageDisclosure only adds the paging half (total=/has_more=/
            // next_offset=/offset=/limit=) when --limit/--offset was actually given, so an un-paged, un-capped
            // run (a small corpus under kLintDefaultPayloadBytes) is byte-identical to before this change.
            // Distinct from findings_capped= below, which is rule 4's FLOOR marker on the total itself.
            char lintPageBuf[ kPageDisclosureCap ];
            std::printf( "<lint findings=\"%zu\"%s%s%s%s%s>", outs.size(),
                         pageDisclosure( lintPageBuf, sizeof( lintPageBuf ), shownCount, outs.size(), lintPage.end,
                                        cfg.pageLimit, cfg.pageOffset, /*discloseCap=*/true ),
                         anyRuleCapped ? " findings_capped=\"1\"" : "", heatJoinedAttr.c_str(), lintRootExtra.c_str(), lintRootAttr.c_str() );
        }
        if( cfg.lint )
        { // built-in per-rule tally (order → deterministic)
            for( const std::string& rn : allRuleNames )
            {
                if( lintSel.active && !rw::lintcatalog::lintSelectionKeeps( lintSel, rn ) )
                { // deselected — no row at all, so it can never look like a checked-and-empty rule
                    continue;
                }
                const RuleTally rt = tallyLintRule( outs, rn, /*wantSevEmpty=*/true, lintPage );
                const rw::lintcatalog::LintCatalogRow* catRow = rw::lintcatalog::lintCatalogFind( rn );
                const bool applicable = catRow == nullptr || ( catRow->langMask & corpusLangs ) != 0;
                printLintRuleTallyRow( rn, nullptr, rt.count, rt.shown, capOf( rn, false ) != nullptr, applicable );
            }
        }
        for( const LintRule& r : userRules )                          // user per-rule tally (declaration order → deterministic)
        {
            if( lintSel.active && !rw::lintcatalog::lintSelectionKeeps( lintSel, r.id ) )
            {
                continue;
            }
            const RuleTally rt = tallyLintRule( outs, r.id, /*wantSevEmpty=*/false, lintPage );
            const bool  applicable = ( rw::langBit( r.lang ) & corpusLangs ) != 0;
            const std::string sevEx = ex( r.severity );
            printLintRuleTallyRow( ex( r.id ), &sevEx, rt.count, rt.shown, capOf( r.id, true ) != nullptr, applicable );
        }
        for( std::size_t findingIndex = lintPage.begin; findingIndex < lintPage.end; ++findingIndex )
        {
            const LintOut&          m  = outs[ findingIndex ];
            const Symbol*           e  = enclosing( m.fileId, m.startByte );
            const std::string_view  rp = lintSingleRoot ? rw::sarif::rootRelativeUri( ing.files[ m.fileId ], lintRootPrefix ) : std::string_view( ing.files[ m.fileId ] );
            if( m.sev.empty() )
            { // built-in finding — unchanged shape (no sev=)
                std::printf( "<f rule=\"%s\" p=\"%s:%u\" in=\"%s\"%s>", ex( m.rule ).c_str(), ex( rp ).c_str(), m.line, e ? ex( e->name ).c_str() : "",
                             heatByFinding.empty() ? "" : heatByFinding[ findingIndex ].c_str() );
            }
            else
            { // user finding — carries sev=
                std::printf( "<f rule=\"%s\" sev=\"%s\" p=\"%s:%u\" in=\"%s\"%s>", ex( m.rule ).c_str(), ex( m.sev ).c_str(), ex( rp ).c_str(), m.line, e ? ex( e->name ).c_str() : "",
                             heatByFinding.empty() ? "" : heatByFinding[ findingIndex ].c_str() );
            }
            emitEscaped( m.text );
            std::printf( "</f>" );
        }
        std::printf( "</lint>" );
        return 0;
    }
    return std::nullopt;
}

std::optional<int> runAround( const MainDispatch& d )
{
    using namespace rw;
    const Config&                     cfg          = d.cfg;
    const IngestResult&               ing          = d.ing;
    const Graph&                      g            = d.g;
    const std::vector<std::uint32_t>* fanInPtr     = d.fanInPtr;
    const std::vector<std::uint32_t>* cboPtr       = d.cboPtr;
    const std::vector<std::uint8_t>*  testedPtr    = d.testedPtr;
    const std::vector<std::uint32_t>* lcom4Ptr     = d.lcom4Ptr;
    const std::vector<std::uint32_t>* ampPtr       = d.ampPtr;
    // R-E (2026-08-17 harvest): same single-root condition every other verb's root= uses.
    const bool             aroundSingleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string_view aroundRootArg    = aroundSingleRoot ? cfg.roots[0] : std::string_view();

    // --around=SYMBOL: emit a focused ego-graph pack (bounded k-hop neighbourhood) instead of the
    // whole-repo map — "give me the context centered on THIS symbol".
    if( !cfg.around.empty() )
    {
        const NodeId focus = resolveFocus( ing, cfg.around );
        if( focus == kNoNode )
        {
            std::fprintf( stderr, "%s\n", selectorNotFoundMessage( ing, "ripwire: --around symbol not found: ",
                                                                   cfg.around, "--around=" ).c_str() );   // §B4.2
            return 1;
        }
        const EgoGraph eg = egoGraph( g, focus, cfg.aroundDepth, cfg.aroundFanout );
        std::vector<float> rank( ing.symbols.size(), 0.f );
        for( std::size_t i = 0; i < eg.nodes.size(); ++i )
        {
            rank[ eg.nodes[i] ] = 1.0f / ( 1.0f + float( eg.hopDist[i] ) );   // focus + closest neighbours lead
        }
        // §F1 — the two sibling blocks --around appends after its map, RENDERED AND CHARGED before the map's
        // header states est_tokens. They were emitted straight to stdout afterwards, so this verb reported the
        // map only: MEASURED on src/, `--around=Config` = 804 B at est_tokens="262" (3.07 B/tok, outside the
        // 2.36-2.59 markup band) because a 157-byte <compose> block rode in free. Same funnel as the default
        // map's four sections and the --for lens's two, at the same rates.
        //
        // S5-E HAS-A: compose view for the ego-graph neighbourhood.
        // B6.3: HTTP-route cross-service view for the same neighbourhood.
        rw::ChargedSection aroundCompose, aroundRoutes;
        if( !g.composeEdges.empty() )
        {
            aroundCompose = rw::chargeSection( [ & ]( std::FILE* f ) { packCompose( f, ing, g.composeEdges, eg.nodes ); },
                                                rw::kBytesPerTokenDefault );
        }
        if( !g.routeEdges.empty() )
        {
            aroundRoutes = rw::chargeSection( [ & ]( std::FILE* f ) { packRoutes( f, ing, g.routeEdges, eg.nodes ); },
                                               rw::kBytesPerTokenDefault );
        }

        // §B4b — G4: serialize() owns <r>…</r> and CLOSES it, so these two sibling blocks were a SECOND
        // top-level element (`--around=buildRecall` tailed `…</r><compose>…</compose>`, xmllint rejected it,
        // ripwire exited 0). See rw::aroundNeedsCtxWrap above for the full finding and the wrapper rule.
        // Trap #8 ("a disclosure has BYTES"): the 11 wrapper bytes are charged at the markup rate, like the
        // sections they enclose.
        const rw::CtxWrap wrap = rw::ctxWrapFor( aroundCompose, !g.composeEdges.empty(),
                                                   aroundRoutes,  !g.routeEdges.empty() );

        if( wrap.isNeeded )
        {
            std::fputs( "<ctx>", stdout );
        }

        serialize( stdout, ing, rank, g.outOff, g.outTargets, int( eg.nodes.size() ), cfg.mostImportantLast, cfg.metrics, fanInPtr, &g.ambOut, false, g.outProv.empty() ? nullptr : &g.outProv, cboPtr, testedPtr, lcom4Ptr, ampPtr, &g.unresolvedOut, g.bindLabel.empty() ? nullptr : &g.bindLabel, /*autoOrder=*/false, /*outEstTokens=*/nullptr, aroundCompose.tokens + aroundRoutes.tokens + wrap.tokens, /*ann=*/{}, /*statsFirstScreen=*/false, aroundRootArg );

        if( !g.composeEdges.empty() )
        {
            rw::emitChargedSection( stdout, aroundCompose, [ & ]{ packCompose( stdout, ing, g.composeEdges, eg.nodes ); } );
        }
        if( !g.routeEdges.empty() )
        {
            rw::emitChargedSection( stdout, aroundRoutes, [ & ]{ packRoutes( stdout, ing, g.routeEdges, eg.nodes ); } );
        }

        if( wrap.isNeeded )
        {
            std::fputs( "</ctx>", stdout );
        }
        return 0;
    }
    return std::nullopt;
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
            rank = ( rc.which == LexMode::NameExact ) ? lexicalScoresNameExactTiered( ing, cfg.query, &tierMul )
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
                        CandidateProvenance{ "query-personalized", 0, false }, redactPtr );
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
        writeHtml( htmlOut, ing, rank, g, mapTopK, HtmlColorExtras{ testedPtr, &htmlChurn, htmlChurnOk, cfg.colorBy } );
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
        wholeFile = rw::renderWholeFiles( ing, expandNodes, redactPtr, d.notesPtr, cfg.compress );   // D2: shaped candidate
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
        { "--edit-check",       !c.editCheckSym.empty()   }, { "--eval",          c.eval                  },
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
