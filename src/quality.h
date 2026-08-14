#pragma once

// quality.h — --quality-baseline / --quality-delta: the deterministic oracle for a code-quality CONVERGENCE
// LOOP. Snapshot the current per-symbol cognitive complexity, the duplicate-clone groups, and the dead-symbol
// set to a `.ripwire_quality_baseline` sidecar; then `--quality-delta` reports ONLY what got WORSE vs that
// baseline — the "delta, not absolute" discipline that lets a refine loop target *the regression it
// introduced* instead of chasing absolute numbers (the defense against Goodhart / metric-gaming). Exits 2 if
// any NEW regression (worse complexity over the bar, new duplication, newly-dead), like --arch.
//
// Why a baseline file (not a git diff): it is deterministic, git-independent, and matches the existing
// `--arch --baseline` pattern. A convergence loop baselines ONCE at the start, then re-runs --quality-delta
// after each edit — each step is one cheap warm call. Determinism: every record is an FNV-1a-64 hash (of the
// canonical id, or of a clone group's sorted member ids); the file is sorted; output is byte-stable.
//
// Honesty: this measures STRUCTURE (complexity / duplication / reachability), not data flow — it cedes
// use-after-move / taint / type errors to the compiler. Thresholds are heuristics; the loop applies judgment.

#include "model.h"
#include "ingest.h"             // ingest() — the HEAD-tree snapshot re-ingests the archived commit (computeHeadSnapshot)
#include "graph.h"
#include "clones.h"
#include "lintrules.h"          // findErrorMasking — the built-in error-masking rule table (GitClear +47% kind)
#include "arch.h"               // fnv1a64
#include "gitmine.h"            // shSingleQuote + gitFileCommitCountsInDayWindow — short-horizon-churn window mining
#include "filter.h"             // B10.1a: isTestPath — the general test-dir convention behind isTestScriptPath
#include "infra/Diagnostics.h"  // DEGRADED_PATH_ALERT — the degrade path when git archive/ingest fails (no-op under NDEBUG; a gate-visible degrade line needs its own fprintf)
#include "infra/jsonesc.h"      // L2 — rw::jsonesc::escapeMcp for staleAcksJsonArray's kind= field (the same posture serialize.h's jsonStr uses)

#include "btree.hpp"              // gtl btree_map — sorted like std::map, cache-friendly nodes (house rule: never std::map)
#include "infra/dynamic_map.hpp"  // S+tree scratch maps — bounded, no per-operation allocation in hot seen-set paths

#include <sys/stat.h>  // ::mkdir — the per-user cache-dir ladder (cacheDirLadder)
#include <unistd.h>    // ::getpid — unique HEAD-snapshot temp-dir suffix

#include <algorithm>
#include <atomic>       // Phase-M: the qsnap tmp-name sequence counter (atomicWriteQSnap); also the A5 process-once cache-sweep guard
#include <cctype>       // std::isxdigit/std::isdigit — B10.2d churn-blame porcelain parsing
#include <chrono>       // A5: the 30-day cache-blob age cutoff (evictOldCacheFamily)
#include <cstdio>
#include <cstdlib>
#include <cstring>      // std::memcpy / std::memcmp — POD (de)serialization of the qsnap blob
#include <filesystem>
#include <fstream>
#include <limits>       // std::numeric_limits<std::size_t>::max() — "no count cap" sentinel (evictOldCacheFamily)
#include <mutex>        // Phase-M: serialize concurrent ingest() (prefetch worker vs request thread)
#include <optional>     // L2 — computeStaleAcks' per-kind dispatch: nullopt = "not stale"
#include <sstream>
#include <string>
#include <type_traits>  // std::is_trivially_copyable_v — the qsnap POD put/get static_assert
#include <utility>
#include <vector>

namespace rw
{
namespace quality
{

inline const char*        kBaselineFile  = ".ripwire_quality_baseline";
constexpr std::uint32_t   kMinCloneTokens = 18;     // matches the --clones default (so both verbs see the same clones)
constexpr std::uint32_t   kCcxBar         = 15;     // SonarSource cognitive-complexity bar — a regression must end up OVER this

// Q1 — bars for the MEASURED agent-code failure modes: agent code runs 2.3×
// verbose, erodes structure in 77% of trajectories, drifts contracts. Each per-symbol kind mirrors ccx's
// "grew AND now over a bar" discipline (`now > was && now > BAR`) — a bar so a benign +1 line / +1 nest of an
// already-small function is not spam, and the reported set is genuinely-worse-AND-now-large. HEURISTICS (like
// kCcxBar): defensible defaults, the loop applies judgment; report numbers, never gate a normal run.
constexpr std::uint32_t   kLocBar         = 60;     // "large function" LOC bar (below Sonar's 75 default) — a verbosity regression must END UP over it (SIZE is the master variable, §1d)
constexpr std::uint32_t   kNestBar        = 4;      // max-nesting-depth bar — deep nesting (>3-4) is the structural-erosion signal; a regression must end up over it
constexpr std::uint32_t   kParamBar       = 5;      // param-count bar — a REGRESSION (grew AND now high), NOT the debunked absolute 7±2 rule (§1d kill-list); the growth is the signal, the bar just suppresses tiny-fn noise

// §D#4 / §E-17 — three GitClear-2026-backed kinds. Each fires ONLY on a regression vs baseline (the
// quality-delta contract), never on pre-existing debt. See the per-kind comments in computeSnapshot/computeDelta.
constexpr std::uint32_t   kShortHorizonDays        = 14;   // "new code rewritten within two weeks" window (+15% in AI code) — from git COMMIT TIMESTAMPS vs HEAD's epoch, not wall-clock (det-gate safe)
constexpr std::uint32_t   kShortHorizonMinCommits  = 2;    // only flag a symbol whose FILE already had ≥2 commits in the window (a genuine rewrite churn, not a first touch)
constexpr std::uint32_t   kReusedHelperMinFanin    = 3;    // "cross-file reuse declining": a NEW clone of a helper whose fan-in ≥ this is a reuse-connectivity regression (GitClear)

// Signal-to-noise round (2026-07-13, quality-delta noise rules) — MATERIALITY TIERS. A numeric
// regression whose DELTA (now − was) is below the kind's tier is reported sev="minor" and does not gate exit 2
// by itself: a +1-ccx edit to an already-over-the-bar function is a regression by the letter but noise that
// drowns the material findings a refine loop should chase. 0 = the kind has no minor tier (any delta is major).
// Presence kinds (duplication / dead-code / api-surface / error-masking / churn / reuse-decline) and nesting
// (every +1 nest is structural erosion) stay major. HEURISTICS like the bars: defensible, documented, judged.
constexpr std::uint32_t   kMinorCcxDelta   = 3;    // complexity: delta < 3 → minor
constexpr std::uint32_t   kMinorLocDelta   = 10;   // verbosity:  delta < 10 LOC → minor
constexpr std::uint32_t   kMinorParamDelta = 2;    // params:     +1 param → minor; +2 or more → major

// Signal-to-noise round — the per-finding ACK RATCHET sidecar (`--quality-ack[=REASON]`): each line records one
// deliberately-accepted finding; --quality-delta suppresses it (honestly, via acked="N") until the finding
// WORSENS past the acked magnitude, at which point it reappears. Committable, like the baseline sidecar.
inline const char*        kAcksFile = ".ripwire_quality_acks";

// D1 fix (HIGH): both sidecars above are FILE NAME constants, not paths — every read/write/remove
// site must resolve them against the ANALYZED ROOT, never the process CWD. The CLI is invoked
// `ripwire <dir> --quality-ack` and may run from ANY cwd (a wrapper script, an orchestrator batching
// several roots from one launch dir, a Makefile target) — a bare relative filename then reads/writes/
// deletes CWD's sidecar instead of `<dir>`'s. Observed live: --quality-ack on root B run from cwd A
// rewrote A's committed `.ripwire_quality_acks`; the stale-baseline self-heal (main.cpp) could have
// DELETED A's baseline the same way. The MCP server already root-qualified for exactly this reason
// (mcpverbs.h's SIDECAR LOCATION note); this is the one shared home so the CLI and MCP paths can never
// re-diverge again. Mirrors notes::notesPath's root + "/" + name discipline (notes.h).
inline std::string rootQualifiedSidecar( const std::string& root, const char* name )
{
    std::string p = root;
    if( !p.empty() && p.back() != '/' )
    {
        p += '/';
    }
    return p + name;
}

inline std::string baselinePath( const std::string& root ) { return rootQualifiedSidecar( root, kBaselineFile ); }
inline std::string acksPath( const std::string& root )     { return rootQualifiedSidecar( root, kAcksFile ); }

template<class Value>
using ScratchMap = stree::dyn::dynamic_map<std::uint64_t, Value, 32>;   // uint64 keys on Apple cache lines; use only when a hard capacity bound is obvious

inline bool insertScratchSeen( ScratchMap<std::uint8_t>& seen, std::uint64_t key, const char* capacityMsg )
{
    const auto [ it, inserted ] = seen.insert( { key, 1 } );
    if( it == seen.end() )
    {
        DEGRADED_PATH_ALERT( capacityMsg );
        return false;
    }
    return inserted;
}

// S2: the BASELINE-ONLY canonical id — `relForHash(path,root)::scope::name`. Byte-identical to the graph's
// g.canonId EXCEPT the path segment is made root-relative, so a COMMITTED .ripwire_quality_baseline is
// portable across root spellings (`ripwire .` vs `ripwire /abs/repo` produce the SAME baseline key + hash).
// The graph's g.canonId — and thus the emitted `id=` attribute and resolution — is left completely UNCHANGED;
// this key exists only where a baseline hash is taken (computeSnapshot / computeDelta). `root` is the ingest
// root as invoked (cfg.rootPath). Deterministic: a pure string function of (path, root, scope, name).
// §B1.3: the rule itself now lives ONCE, in resolve.h beside canonicalId — serialize.h's field-note target
// is the same identity and used to derive it independently, which is how the two would have drifted.
inline std::string baselineCanonId( const IngestResult& ing, NodeId i, std::string_view root )
{
    return canonicalIdRelTo( ing, ing.symbols[i], root );
}

// A deterministic snapshot of the structural-quality state. Each per-symbol metric map is keyed by
// hash(baselineCanonId) and stores the MAX over the overload set sharing that id (see computeSnapshot) — so a
// low-metric overload written last can never manufacture a phantom regression on the next delta (the trap that
// bit quality-delta once; mirrored identically on the delta side).
struct Snapshot
{
    gtl::btree_map<std::uint64_t, std::uint32_t> ccxBySym;    // hash(canonId) → MAX ccx (btree = sorted iteration for the byte-stable sidecar)
    gtl::btree_map<std::uint64_t, std::uint32_t> locBySym;    // Q1 verbosity  — hash(canonId) → MAX physical LOC (the master variable, §1d)
    gtl::btree_map<std::uint64_t, std::uint32_t> nestBySym;   // Q1 erosion    — hash(canonId) → MAX control-nesting depth
    gtl::btree_map<std::uint64_t, std::uint32_t> paramsBySym; // Q1 erosion    — hash(canonId) → MAX parameter count
    gtl::btree_map<std::uint64_t, std::uint32_t> defsBySym;   // hash(canonId) → COUNT of definitions sharing the id (an overload set's CARDINALITY, deliberately NOT a MAX — see computeSnapshot)
    gtl::btree_map<std::uint64_t, std::uint32_t> maskBySym;   // §D#4 error-masking — hash(canonId) → COUNT of error-masking constructs in the symbol (SUM over overloads, see computeSnapshot)
    gtl::btree_map<std::uint64_t, std::uint64_t> bodyHashBySym; // §D#4 short-horizon-churn — pathQualifiedKey(path,scope,name) → fnv1a64 of the RAW body bytes (change detection; literal-only edits move NO metric, so metrics can't detect them). Path-qualified since v6: a bare canonId key folded every scope-less same-named symbol ACROSS FILES into one join identity (the W1-S2 cross-file churn misattribution)
    std::vector<std::uint64_t>             cloneGroups; // sorted hash(sorted member canonIds)
    std::vector<std::uint64_t>             dead;        // sorted hash(canonId) of dead-candidate symbols
    std::vector<std::uint64_t>             publicApi;   // Q1 contract drift — sorted hash(canonId) of PUBLIC/exported symbols (see isPublicApi)
};

// Q1 api-surface — the PUBLIC/exported contract surface. DEFINITION (deterministic, documented):
// a symbol is PUBLIC iff it is DECLARED IN A HEADER file (`.h/.hpp/.hh/.hxx`) — the C/C++/ObjC export surface
// by convention, exactly the convention `isDeadCandidate` already uses ("header-exported by convention").
// Markdown sections and non-header (translation-unit-local) definitions are NOT public. This is a SET signal:
// contract drift = a public canonId present now but absent in the baseline (new exported surface), so it needs
// no MAX aggregation — set membership is overload-collision-proof (multiple overloads collapse to one canonId).
inline bool isPublicApi( const IngestResult& ing, NodeId i ) noexcept
{
    const Symbol& s = ing.symbols[i];
    if( s.kind == SymKind::Section )
    {
        return false; // markdown heading — not a code contract
    }
    const std::string& p = ing.files[ s.fileId ];
    const auto ends = [ & ]( std::string_view e )
    { return p.size() >= e.size() && p.compare( p.size() - e.size(), e.size(), e ) == 0; };
    return ends( ".h" ) || ends( ".hpp" ) || ends( ".hh" ) || ends( ".hxx" );
}

// Signal-to-noise round — TEST-FIXTURE paths are exempt from the dead-code and short-horizon-churn kinds:
// symbols in adversarial/golden fixture trees are dead (nothing calls a fixture) and churny (fixtures get
// regenerated) BY DESIGN, and on this repo's own dogfood runs they drowned the real findings. DEFINITION
// (deterministic, path-component based): a component named `fixture`/`fixtures` anywhere, or a component
// ending in `fix` whose immediately-preceding component is `test`/`tests` (the `test/anchorfix/` convention).
// The parent-dir requirement keeps real code dirs like `prefix/`, `bugfix/`, `hotfix/` in scope. Fixtures stay
// visible to every OTHER kind (a fixture with exploding complexity is still worth a look).
inline bool isFixturePath( std::string_view p ) noexcept
{
    std::string_view prev;
    std::size_t      start = 0;
    while( start <= p.size() )
    {
        const std::size_t      slash = p.find( '/', start );
        const std::string_view c     = p.substr( start, ( slash == std::string_view::npos ? p.size() : slash ) - start );
        if( c == "fixture" || c == "fixtures" )
        {
            return true;
        }
        if( c.size() > 3 && c.substr( c.size() - 3 ) == "fix" && ( prev == "test" || prev == "tests" ) )
        {
            return true;
        }
        if( !c.empty() && c != "." && c != ".." )
        {
            prev = c; // "." / ".." spellings never count as the test parent
        }
        if( slash == std::string_view::npos )
        {
            break;
        }
        start = slash + 1;
    }
    return false;
}

// B10.1a (signal-to-noise round 2) — TEST-SCRIPT exemption: a shell test-RUNNER script (test/*.sh — the
// general isTestPath test-dir convention from filter.h, so test/, tests/, spec/, etc. are ALL covered, not
// just a literal "test/" — combined with a shell-script extension) gets the SAME fixture-class treatment as
// isFixturePath for the dead-code and duplication kinds. Mechanism (the concrete false-positive this fixes):
// a shell helper function invoked via `$(...)`/direct call is a normal bash call, but sibling test scripts in
// this repo repeat near-identical setup/ok/no boilerplate BY CONVENTION (see e.g.
// test/cochangeboostcheck.sh's inertPair/rankOf, which quality-delta on this repo's own diffs false-flagged
// as both dead-code — nothing in the INDEXED tree calls a script's own helper except that same script — and
// cross-script duplication). Shell scripts stay visible to every OTHER kind (a test script with exploding
// complexity is still worth a look) — only dead-code and duplication treat them as fixture-class.
inline bool isTestScriptPath( std::string_view p ) noexcept
{
    if( !isTestPath( p ) )
    {
        return false;
    }
    const auto ends = [ & ]( std::string_view e )
    { return p.size() >= e.size() && p.compare( p.size() - e.size(), e.size(), e ) == 0; };
    return ends( ".sh" ) || ends( ".bash" ) || ends( ".zsh" );
}

// W1-S2 (2026-08-11) — TOP-LEVEL INVOCATION IS A USE: the fnv1a64 name-hash set of every callee invoked from
// FILE SCOPE (fromSymbol == kNoNode). buildGraph deliberately drops file-scope references from the call-graph
// CSR (no caller symbol → no edge — correct for PageRank and the ranked map), which starves the dead kind: a
// bash function whose ONLY call site is a top-level script statement has zero in-edges and was false-flagged
// dead (confirmed on hooks/ripwire-nudge.sh's helpers, while the fn→fn-called control was correctly silent —
// the same hole applies to any script language's module-level statements). The dead kind therefore consults
// these file-scope call sites as its second evidence source. The ref filter mirrors buildGraph's call-edge
// admission EXACTLY (Call|Macro roles; no inherit/doc-link/compose — a README backtick-mention must never
// mark a symbol live) with only the fromSymbol test inverted. NAME-level matching, not per-target resolution
// — the same heuristic level as the resolver's bare-name spray, and a collision errs in the safe direction
// (false-live, never false-dead). Sorted + deduped for binary_search; deterministic (reference order is).
inline std::vector<std::uint64_t> topLevelCalleeNameHashes( const IngestResult& ing )
{
    std::vector<std::uint64_t> hashes;
    for( const Reference& r : ing.references )
    {
        if( r.fromSymbol != kNoNode || r.isInherit || r.isDocLink || r.isCompose
            || ( r.role != RefRole::Call && r.role != RefRole::Macro ) )
        {
            continue;
        }
        hashes.push_back( fnv1a64( r.calleeName ) );
    }
    std::sort( hashes.begin(), hashes.end() );
    hashes.erase( std::unique( hashes.begin(), hashes.end() ), hashes.end() );
    return hashes;
}

// A "dead deletion-candidate": has a body, no caller in the indexed tree, not invoked from file scope, not
// header-exported, not a test fixture. A SIMPLE, internally-consistent heuristic — the delta only needs
// baseline↔current consistency, not parity with the fuller --dead-code verb. `topLevelCallees` is the
// sorted set topLevelCalleeNameHashes builds — both call sites build it ONCE outside their symbol loop.
inline bool isDeadCandidate( const IngestResult& ing, const Graph& g, NodeId i,
                             const std::vector<std::uint64_t>& topLevelCallees ) noexcept
{
    const Symbol& s = ing.symbols[i];
    if( s.kind == SymKind::Section )
    {
        return false; // markdown heading
    }
    if( s.sigEndByte >= s.endByte )
    {
        return false; // no body (decl / prototype)
    }
    const auto* ro = g.inEdges.rowOffsets();
    if( ro[i + 1] - ro[i] != 0 )
    {
        return false; // has at least one caller
    }
    if( std::binary_search( topLevelCallees.begin(), topLevelCallees.end(), fnv1a64( s.name ) ) )
    {
        return false; // W1-S2: invoked from file scope (a top-level script statement) — a use the CSR drops
    }
    const std::string& p = ing.files[ s.fileId ];
    const auto ends = [ & ]( std::string_view e )
    { return p.size() >= e.size() && p.compare( p.size() - e.size(), e.size(), e ) == 0; };
    if( ends( ".h" ) || ends( ".hpp" ) || ends( ".hh" ) || ends( ".hxx" ) )
    {
        return false; // header-exported by convention
    }
    if( isFixturePath( p ) )
    {
        return false; // fixtures are dead by design (noise rules)
    }
    if( isTestScriptPath( p ) )
    {
        return false; // B10.1a: shell test-runner helpers — $(...) calls invisible to the parser
    }
    return true;
}

// hash a clone group by its SORTED member canonical ids — so "this set of functions is duplicated" is the
// group's stable identity (adding a 3rd copy changes the set ⇒ a new group ⇒ reported as new duplication).
// S2: member ids are the root-RELATIVE baselineCanonId so a committed clone baseline is root-spelling-portable
// (member set identity is unchanged; only the path prefix inside each id is normalized). Deterministic.
inline std::uint64_t cloneGroupHash( const CloneGroup& cg, const IngestResult& ing, std::string_view root )
{
    std::vector<std::string> ids;
    for( NodeId m : cg.members )
    {
        if( m < ing.symbols.size() )
        {
            ids.push_back( baselineCanonId( ing, m, root ) );
        }
    }
    std::sort( ids.begin(), ids.end() );
    std::string joined;
    for( const std::string& x : ids ) { joined += x; joined.push_back( '\n' ); }
    return fnv1a64( joined );
}

// §D#4 error-masking — attribute each error-masking hit (findErrorMasking) to its ENCLOSING symbol by byte-span
// containment, then COUNT hits per baseline canonId. A symbol contains a hit iff the hit's start byte lies in
// the symbol's full def span [sigStartByte, endByte) in the same file. Overloads sharing a canonId SUM (the
// count is a magnitude, not a max — two overloads each masking once = 2 masks under that id, and the delta then
// fires when the total grows). Deterministic: findErrorMasking is deterministic and the fold is a pure sum.
//
// Attribution is O(hits · symbols-per-file) via a per-file symbol index; a hit inside no def (file-scope) is
// dropped (no owning symbol → nothing to attribute a regression to). Byte-span containment mirrors how ingest
// attributes References to their enclosing definition, so the same-file, same-span discipline is consistent.
inline gtl::btree_map<std::uint64_t, std::uint32_t> errorMaskCountsBySym( const IngestResult& ing, std::string_view root )
{
    gtl::btree_map<std::uint64_t, std::uint32_t> counts;
    const std::vector<ErrorMaskHit> hits = findErrorMasking( ing );
    if( hits.empty() )
    {
        return counts;
    }

    // per-file symbol id list (only real-body defs can enclose a masking block). `symbols[i].id == i`, so
    // the shared bucket-and-sort's `s.id` is the same value the hand-written loop pushed as `i`.
    const SymbolsByFile byFile = symbolsByFileInIdOrder( ing, []( const Symbol& s ) { return s.endByte > s.sigStartByte; } );
    for( const ErrorMaskHit& h : hits )
    {
        if( h.fileId >= byFile.size() )
        {
            continue;
        }
        // smallest enclosing def wins (a nested lambda/method inside a method) — pick the tightest [start,end)
        // that contains the hit so the count lands on the innermost owning symbol. Linear per file is fine.
        NodeId        owner   = kNoNode;
        std::uint32_t bestLen = UINT32_MAX;
        for( NodeId i : byFile[ h.fileId ] )
        {
            const Symbol& s = ing.symbols[i];
            if( h.startByte >= s.sigStartByte && h.startByte < s.endByte )
            {
                const std::uint32_t len = s.endByte - s.sigStartByte;
                if( len < bestLen ) { bestLen = len; owner = i; }
            }
        }
        if( owner != kNoNode )
        {
            ++counts[fnv1a64( canonicalId( relForHash( ing.files[ing.symbols[owner].fileId], root ), ing.symbols[owner].scope, ing.symbols[owner].name ) )];
        }
    }
    return counts;
}

// The ONE body-hash identity rule: fnv1a64( path \0 scope \0 name ), path root-relative (relForHash).
// PATH-QUALIFIED ALWAYS, including when scope is empty. canonicalId() DEGRADES to the bare name when a
// symbol has no scope (resolve.h) — fine for display, catastrophic as a comparison key: every scope-less
// `ok()` in a tree folds to ONE identity. --merge-scout hit it first (laneA adds a.sh::ok, laneB adds
// b.sh::ok -> conflicts="1"), then --quality-delta's short-horizon-churn (W1-S2 repro, 2026-08-11: a NEW
// shell fn rows() in one test script flagged churn against the same-named rows() in a file the change never
// touched — gates 2+3 judged a cross-file FOLD, not a symbol). mergescout::buildTreeIndex and lanes.h claims
// key byte-for-byte the same way — one key space, pinned by test/scoutkeycheck.sh, never a third scheme.
inline std::uint64_t pathQualifiedKey( std::string_view relPath, std::string_view scope, std::string_view name )
{
    std::string idText;
    idText.reserve( relPath.size() + scope.size() + name.size() + 2 );
    idText.append( relPath ).push_back( '\0' );
    idText.append( scope ).push_back( '\0' );
    idText.append( name );
    return fnv1a64( idText );
}

// §D#4 short-horizon-churn — a per-identity hash of the symbols' RAW body bytes, for CHANGE detection that
// metrics miss. `hot(){ return 2; }` → `hot(){ return 3; }` moves NO metric (same ccx/loc/nest/params), and
// clones.h normalization erases the literal (`$N`), so neither can tell the body changed — only a raw-byte
// hash can. We read each file ONCE (per-file, like findClones), hash each def's [sigStartByte,endByte) body,
// and fold overloads sharing an identity by hashing their SORTED per-symbol hashes (order-independent,
// stable). Deterministic: pure function of file bytes + spans. A file that won't read contributes nothing
// (degrade). Keys are pathQualifiedKey (above) on EVERY side — baseline, window-ref and working tree are
// only ever compared to each other, and a one-sided qualification makes every symbol read as rewritten
// (the trap the 1722-line comment used to pin). The churn loop in computeDelta derives its per-node lookup
// key through the same helper, so the join's surfaces cannot drift independently.
inline gtl::btree_map<std::uint64_t, std::uint64_t> bodyHashesBySym( const IngestResult& ing, std::string_view root )
{
    // per-file def ids with a real body (see errorMaskCountsBySym above on `symbols[i].id == i`).
    const SymbolsByFile byFile = symbolsByFileInIdOrder( ing, []( const Symbol& s ) { return s.endByte > s.sigStartByte; } );
    gtl::btree_map<std::uint64_t, std::vector<std::uint64_t>> perId;   // pathQualifiedKey → its symbols' raw-body hashes
    std::string bytes;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( byFile[f].empty() )
        {
            continue;
        }
        std::FILE* fp = std::fopen( ing.files[f].c_str(), "rb" );
        if( !fp )
        {
            continue;
        }
        std::fseek( fp, 0, SEEK_END );
        const long sz = std::ftell( fp );
        std::fseek( fp, 0, SEEK_SET );
        bytes.clear();
        if( sz > 0 )
        {
            bytes.resize( std::size_t( sz ) );
            if( std::fread( bytes.data(), 1, std::size_t( sz ), fp ) != std::size_t( sz ) )
            {
                bytes.clear();
            }
        }
        std::fclose( fp );
        if( bytes.empty() )
        {
            continue;
        }
        for( NodeId i : byFile[f] )
        {
            const Symbol& s = ing.symbols[i];
            if( s.endByte > bytes.size() || s.sigStartByte >= s.endByte )
            {
                continue;
            }
            const std::uint64_t key = pathQualifiedKey( relForHash( ing.files[ s.fileId ], root ), s.scope, s.name );
            perId[ key ].push_back( fnv1a64( std::string_view( bytes.data() + s.sigStartByte, s.endByte - s.sigStartByte ) ) );
        }
    }
    gtl::btree_map<std::uint64_t, std::uint64_t> out;
    for( auto& [ key, hs ] : perId )
    {
        std::sort( hs.begin(), hs.end() );                                    // order-independent overload fold
        std::string joined;
        for( std::uint64_t h : hs ) { char b[ 17 ]; std::snprintf( b, sizeof( b ), "%016llx", static_cast<unsigned long long>( h ) ); joined += b; }
        out[ key ] = fnv1a64( joined );
    }
    return out;
}

// ─── git-baseline helpers (the auto-vs-HEAD machinery behind --quality-delta / the quality_delta MCP verb) ───
//
// These four helpers used to live in main.cpp's anonymous namespace. They are relocated here — the one home
// that owns baselines — so BOTH the CLI (--quality-baseline / --quality-delta) and the MCP `quality_delta` /
// `quality_baseline` verbs call the SAME code (no duplication of the git-archive / stale-vs-HEAD logic). main.cpp
// re-exports them with `using` aliases so its existing call sites are byte-unchanged.

// S4: shared per-user cache-directory ladder: $TMPDIR/ripwire → $XDG_CACHE_HOME/ripwire →
// /tmp/ripwire-<uid>, always mode 0700. Keeping our artifacts one level below TMPDIR is a performance
// boundary as well as a security one: cache hygiene must never enumerate an unbounded shared TMPDIR full of
// unrelated agent-session files. Returns the dir with NO trailing slash. Deterministic per (user, env).
inline std::string cacheDirLadder()
{
    std::string d;
    const char* tmpDir = std::getenv( "TMPDIR" );
    if( tmpDir && *tmpDir )
    {
        d = tmpDir;
        while( d.size() > 1 && d.back() == '/' )
        {
            d.pop_back();
        }
        d += "/ripwire";
    }
    else if( const char* xdgCache = std::getenv( "XDG_CACHE_HOME" ); xdgCache && *xdgCache )
    {
        d = std::string( xdgCache ) + "/ripwire";
    }
    else
    {
        d = "/tmp/ripwire-" + std::to_string( static_cast<unsigned long long>( ::getuid() ) );
    }

    const int mkdirRc = ::mkdir( d.c_str(), 0700 );
    struct stat st {};
    if( mkdirRc == 0 || ( ::lstat( d.c_str(), &st ) == 0 && S_ISDIR( st.st_mode ) && st.st_uid == ::getuid() ) )
    {
        if( ::chmod( d.c_str(), 0700 ) == 0
            && ::lstat( d.c_str(), &st ) == 0 && S_ISDIR( st.st_mode ) && st.st_uid == ::getuid()
            && ( st.st_mode & 0777 ) == 0700 )
        {
            return d;
        }
    }
    return "/dev/null/ripwire-cache-unavailable";   // unsafe/unusable candidate: make cache I/O fail closed
}

// popen a shell command and return its trimmed stdout ("" on any failure — never crashes). THE one copy of
// the popen-trim shape: the git one-liners below and main.cpp's doctor probes (doctorPopenTrim) all call this.
inline std::string popenTrimmed( const std::string& cmd )
{
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        return {};
    }
    char        buf[ 4096 ];
    std::string out;
    while( std::fgets( buf, sizeof( buf ), pipe ) )
    {
        out += buf;
    }
    pclose( pipe );
    while( !out.empty() && ( out.back() == '\n' || out.back() == '\r' || out.back() == ' ' ) )
    {
        out.pop_back();
    }
    return out;
}

// Run one short git query against `root` and return its whitespace-trimmed output (expected single-line), or
// "" on any failure. The shared shape behind gitHeadSha / gitWindowRefSha — `tail` is everything after
// `git -C <root>` INCLUDING redirects (so a caller can pipe, e.g. "rev-list HEAD 2>/dev/null | tail -1").
inline std::string gitOneLine( const std::string& root, const std::string& tail )
{
    return popenTrimmed( "git -c core.quotepath=false -C " + shSingleQuote( root ) + " " + tail );
}

// The current HEAD commit sha (full, trimmed), or "" if `root` is not a git repo with a resolvable HEAD.
// Used to STAMP a --quality-baseline sidecar and to detect a STALE one: a baseline pinned at a different HEAD
// (an abandoned/parallel session, or from before a commit) no longer describes this tree, so trusting it makes
// --quality-delta report a wall of false regressions.
inline std::string gitHeadSha( const std::string& root )
{
    return gitOneLine( root, "rev-parse --verify --quiet HEAD 2>/dev/null" );
}

// HEAD's committer date in ISO short form (YYYY-MM-DD) — the deterministic clock the L3 field-notes writer
// stamps a note with (git's committer date, %cs), NOT the wall clock. A note's line is then a PURE function of
// (the commit it was added under, target, text): byte-stable across machines and re-runs, the same det-gate
// discipline the churn window follows (system now() is never consulted). Reuses gitOneLine (the shared
// git-C+popen+trim shape). Empty on no-git / no-HEAD OR any output that is not exactly YYYY-MM-DD (10 chars,
// dashes at 4 and 7) — the caller degrades to a fixed epoch date. Read-only: `git log` never mutates the repo.
inline std::string gitCommitterDateIso( const std::string& root )
{
    const std::string out = gitOneLine( root, "log -1 --format=%cs HEAD 2>/dev/null" );
    if( out.size() != 10 || out[4] != '-' || out[7] != '-' )
    {
        return {};
    }
    return out;
}

// The commit-graph REACHABILITY check: is `ancestor` reachable from `descendant` (an ancestor of it, or the
// same commit) in `root`'s history? Uses the standard `git merge-base --is-ancestor` primitive (exit 0 = yes;
// 1 = no; anything else, including an unresolvable sha = degrade to false — never TRUST an unresolvable ref).
// Empty inputs degrade to false. Deterministic for fixed repo state.
//
// R3 (owner ruling, 2026-07-29): this used to ALSO back the stale-baseline carve-out — a
// `.ripwire_quality_baseline` pinned at a REACHABLE ancestor of HEAD was honored as a deliberate floor (B10.1b).
// That carve-out is REVOKED (a parallel session's ancestor-pinned sidecar produced 31 phantom regressions on
// the CLI while the MCP arm honestly reported zero); `selectBaseline` now decides staleness by STRICT sha
// equality and never calls this. The remaining caller is `binstale.h`'s "is the built binary older than the
// sources?" check, which is a genuine reachability question — do not delete this.
// ─── r27 (Lane C routing) — the OBJECT-NAME gate on every token that reaches a git argv ────────────────
//
// `shSingleQuote` stops SHELL injection, but the token still arrives as its own argv ENTRY, and git reads a
// leading `-` as an OPTION. Lane C's P0.1 defect is the proof this matters: `--pr-context=--output=FILE`
// reached `git diff` as an option and TRUNCATED a file outside the repo, exit 0. The durable defense is not
// quoting — it is refusing anything that is not a bare object name.
//
// A commit sha is 40 (SHA-1) or 64 (SHA-256) lowercase hex and NOTHING else: it cannot begin with `-`, cannot
// contain a path separator, and cannot spell an option. Checking that SHAPE is a complete defense on its own
// and needs no subprocess, so it is applied at both ends — at the trust boundary where an untrusted value is
// READ (readBaselineHeadSha, whose input is a COMMITTED, therefore clone-attacker-influenceable sidecar) and
// again at the SINK, here, because a future caller will not remember the boundary.
//
// KNOWN DUPLICATE, flagged by our own --quality-delta and left deliberately: `crossref::isBlobSha`
// (crossref.h) is the same predicate for git BLOB shas. It cannot be reused from here — crossref.h INCLUDES
// quality.h, so the dependency only runs one way. The consolidation is a one-line change in crossref.h
// (`isBlobSha` delegating to this), which is outside this lane's file boundary; it is written up in the lane
// report rather than done silently across a file this lane does not own.
inline bool isBareCommitSha( std::string_view s ) noexcept
{
    if( s.size() != 40 && s.size() != 64 )
    {
        return false;
    }
    for( char c : s )
    {
        if( !std::isxdigit( static_cast<unsigned char>( c ) ) )
        {
            return false;
        }
    }
    return true;
}

// Resolve `ref` to a concrete commit sha, or "" if it does not resolve to one. Belt AND braces: the ref is
// refused outright if it could be read as an option, and the ANSWER must itself be a bare object name — a
// `rev-parse` that echoes something else (a path, an error, a multi-line answer) is not trusted. Callers that
// hand a token to git should hand THIS result, never the caller's own string.
inline std::string gitResolveCommitSha( const std::string& root, const std::string& ref )
{
    if( ref.empty() || ref[0] == '-' )
    {
        return {};
    }
    const std::string out = gitOneLine( root, "rev-parse --verify --quiet " + shSingleQuote( ref + "^{commit}" ) + " 2>/dev/null" );
    return isBareCommitSha( out ) ? out : std::string{};
}

inline bool gitIsAncestor( const std::string& root, const std::string& ancestor, const std::string& descendant )
{
    if( ancestor.empty() || descendant.empty() )
    {
        return false;
    }
    // SINK GUARD (r27): both operands reach `std::system` as argv entries. merge-base has no file-writing
    // option today, which is the ONLY reason the sidecar-sourced `ancestor` was merely low severity rather
    // than the P0.1 data-loss bug — the shape is identical. Refuse anything that is not a bare object name.
    if( !isBareCommitSha( ancestor ) || !isBareCommitSha( descendant ) )
    {
        DEGRADED_PATH_ALERT( "quality: refusing a non-sha revision token on the merge-base path" );
        return false;                                          // degrade: "not reachable" → the caller self-heals the pin
    }
    const std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root )
                          + " merge-base --is-ancestor " + shSingleQuote( ancestor ) + " " + shSingleQuote( descendant )
                          + " >/dev/null 2>&1";
    return std::system( cmd.c_str() ) == 0;
}

// Signal-to-noise round — the CHURN-WINDOW reference commit: the newest commit STRICTLY OLDER than the
// short-horizon window (HEAD's committer epoch − `days`), or — for a repo younger than the window, where every
// commit is in-window — the OLDEST commit reachable from HEAD. Comparing a symbol's body at this ref vs the
// baseline (HEAD) proves the symbol was ALREADY rewritten inside the window by COMMITS, which is the churn
// evidence the current uncommitted edit alone can never supply. Deterministic: a pure function of repo state
// (HEAD epoch anchors the window — wall-clock is never consulted). "" on any failure (degrade: churn silent).
inline std::string gitWindowRefSha( const std::string& root, std::uint32_t days )
{
    const std::string epochStr = gitOneLine( root, "log -1 --format=%ct HEAD 2>/dev/null" );
    if( epochStr.empty() )
    {
        return {};
    }
    const std::int64_t headEpoch = std::strtoll( epochStr.c_str(), nullptr, 10 );
    if( headEpoch <= 0 )
    {
        return {};
    }

    // newest commit at-or-before the window floor (rev-list --min-age filters on committer time ≤ the bound;
    // cutoff−1 keeps a commit landing exactly ON the floor inside the window, matching gitmine's inclusive floor).
    const std::int64_t cutoff = headEpoch - std::int64_t( days ) * 86400;
    const std::string  preWindow = gitOneLine( root, "rev-list --max-count=1 --min-age=" + std::to_string( cutoff - 1 ) + " HEAD 2>/dev/null" );
    if( !preWindow.empty() )
    {
        return preWindow;
    }

    return gitOneLine( root, "rev-list HEAD 2>/dev/null | tail -1" );   // repo younger than the window → its first commit
}

// Does `root` sit in a git repo that HAS at least one commit? A WINDOWLESS probe (no --since), so it is true
// whenever history exists. This tells "git unavailable / not-a-repo / no-history" apart from "git fine, history
// exists, but a --since window matched zero commits". popen failure degrades to false.
inline bool gitRepoHasHistory( const std::string& root )
{
    const std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root )
                          + " rev-parse --verify --quiet HEAD 2>/dev/null";
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        return false;
    }
    char buf[ 128 ];
    bool gotHead = false;
    while( std::fgets( buf, sizeof( buf ), pipe ) )
    {
        if( buf[0] != '\n' && buf[0] != '\0' )
        {
            gotHead = true;
        }
    }
    const int rc = pclose( pipe );
    return rc == 0 && gotHead;
}

// A4-P1 — the HEAD-snapshot ingest cache. The HEAD tree is IMMUTABLE for a given HEAD sha, so its cold ingest
// (~12.5 s on the 1498-file corpus) is perfectly cacheable: we hand the archived-tree ingest an incremental
// content-hash cache file (the SAME format ingest()/loadCache()/saveCache() use for the auto-cache), so a
// second --quality-delta on an unchanged HEAD is a pure warm hit.
//
// NEVER-STALE by construction, on two independent guards:
//  1) FILENAME key = (realpath(repo-root), HEAD sha, the excludes list, a format tag). A different HEAD, a
//     different repo, or a different --exclude set → a different file → the wrong tree can never be loaded.
//  2) ingest()'s own cache header (magic + kCacheVersion + parserVer, checksum trailer) and its PER-FILE
//     content-hash gate. Even if guard 1 were bypassed, loadCache rejects a format/parserVer mismatch outright
//     and every file whose content hash differs is re-parsed — so a stale or foreign blob self-heals to a
//     correct cold parse, never wrong facts. (Verified in ingest.cpp: kParserVer bumps invalidate the header;
//     contentHash64(bytes) — content-, not path-keyed — gates each file.)
//
// PORTABLE across the per-run tmp root: the HEAD tree is materialized under a pid-suffixed tmpRoot that differs
// every run, but saveCache stores each key ROOT-RELATIVE (relForHash) and loadCache re-absolutizes it against
// the CURRENT tmpRoot (ingest.cpp T5), and the freshness gate is a CONTENT hash — so run 1's cache built under
// /…/ripwire-qhead-<pid1> warm-hits run 2 under /…/ripwire-qhead-<pid2> for the same HEAD. The cache file lives
// under cacheDirLadder() directly (NOT inside tmpRoot), so it survives the tmpRoot RAII teardown.
//
// Bump when the HEAD-snapshot cache SCHEME changes (independent of ingest's own kParserVer, which the blob
// header already self-validates). Folded into the filename key so an old-scheme file is simply never named.
constexpr std::uint32_t kHeadSnapCacheScheme = 1;

// The 16-hex repo key: fnv1a64 of realpath(root) (matching defaultCachePath) so two spellings of one repo
// share one warm cache AND one eviction group. A null realpath (missing path) degrades to the verbatim
// spelling — still correct, at worst one extra cold miss. Used by both the filename and the eviction glob.
inline std::string headSnapRepoHex( const std::string& root )
{
    char* rp = ::realpath( root.c_str(), nullptr );
    const std::string absRoot = rp ? std::string( rp ) : root;
    if( rp )
    {
        std::free( rp );
    }
    char hex[ 20 ];
    std::snprintf( hex, sizeof( hex ), "%016llx", static_cast<unsigned long long>( fnv1a64( absRoot ) ) );
    return std::string( hex );
}

// ─── P0.2 — the EXTRACTION-IDENTITY key (r27) ──────────────────────────────────────────────────────────
//
// THE BUG THIS CLOSES (it already fired, in production, silently). Every sha-keyed quality cache blob —
// qheadsnap (the HEAD ingest), qsnap (the computed HEAD Snapshot), qbody (the window-ref body hashes) —
// holds facts that are FUNCTIONS OF TREE-SITTER EXTRACTION: canonIds, ccx/loc/nest/params, raw-body hashes,
// clone groups, the dead set, the public-API set. Yet neither `kCacheVersion` nor `kParserVer` appeared in
// the blob header OR the filename key. Commit `28c7d32` bumped kParserVer 28→30 for a `qualifierOf` fix that
// corrected **80 wrong canonical ids** without touching kQSnapCacheScheme: the ingest blob self-heals on its
// own header guard, the qsnap blob does NOT — it was simply re-served, wrong canonIds and all. Layered on the
// r26 origin split (`fbc527e`) that is the nasty part: a stale baseline holds the wrong canonId → the working
// tree's correct canonId is absent from `base.locBySym` → a REAL regression classifies `origin="new-symbol"`
// → it does not gate. The origin split MASKS the poisoned cache instead of surfacing it.
//
// THE FIX, in both places (belt and braces, the same two-guard discipline the family already documents):
//   1. FILENAME KEY — folded in below, so an old-extraction blob is never NAMED again (no purge needed; the
//      owner's call is that correctness must come from the key, not from deleting blobs — disk is cheap and a
//      purge is a one-shot that the next bump re-opens).
//   2. BLOB HEADER — serializeSnapshot/deserializeSnapshot carry and verify the pair, so even a blob reached
//      by some other route (a hand-copied file, a hash collision) is rejected rather than believed.
//
// WHY A MIRROR, AND WHY IT CANNOT DRIFT: `kCacheVersion`/`kParserVer` live in ingest.cpp (a .cpp), not in
// ingest.h, so a header cannot link to them. Mirroring a constant is exactly the failure mode that produced
// this bug, so the mirror is not trusted — `test/qextractionkeycheck.sh` parses BOTH files and FAILS the
// suite the moment the two disagree, and `test/qschemetripcheck.sh` (which previously hashed only quality.h
// functions and never looked at ingest.cpp — precisely why this shipped) now hashes the ingest-side constant
// lines too. Bumping kParserVer without updating these two lines is a hard gate failure, not a silent miss.
// FOLLOW-UP for whoever owns ingest.{h,cpp}: promote the two constants into ingest.h and turn the gate into a
// `static_assert` — this lane's file boundary forbade editing those files.
constexpr std::uint32_t kIngestCacheVersionMirror = 13;   // MUST equal ingest.cpp's kCacheVersion (gated)
constexpr std::uint32_t kIngestParserVerMirror    = 64;   // MUST equal ingest.cpp's kParserVer   (gated)
                                                          // 64 = 2026-08-14 in-file test scope: every def carries a new
                                                          // syntactic testScope bit (Rust #[cfg(test)] mod / #[test] fn,
                                                          // Python class Test* / module-level def test_*, JS/TS
                                                          // describe(/it(/test( blocks, C# [Fact]/[Test]/[TestMethod])
                                                          // written into the cache record — a v63 blob has no such
                                                          // field, so it must be rejected. See test/testscopecheck.sh.
                                                          // 63 = 2026-08-12 markdown section tier: .md/.markdown parse
                                                          // with the vendored block grammar — headings (ATX + setext)
                                                          // become sections with REAL SPANS, parent-heading scopes and
                                                          // link/mention edges; the extracted SET and the spans change
                                                          // on any md-bearing tree, so v62 blobs must be rejected.
                                                          // 62 = 2026-08-12 module-constant round: C/C++ const-qualified
                                                          // module constants (and class-static constants) index
                                                          // case-blind — the extracted SET grows on any C/C++ tree,
                                                          // so a v61 blob misses rows (this file's own
                                                          // kIngestParserVerMirror is in the newly indexed family).
                                                          // 61 = 2026-08-11 YAML config-key tier: .yml/.yaml mapping
                                                          // keys (mdepth<=2, sequences transparent) indexed as t="sec"
                                                          // for the first time — changes the extracted SET on any
                                                          // YAML-bearing tree.
                                                          // 60 = 2026-08-10 language-port round (one shared bump):
                                                          // Python shapes (11 new tags.scm patterns, .pyi routing, the
                                                          // gated enum-member kind), Swift shapes (hand port of bb78f97)
                                                          // and the TypeScript #private gap, plus the shared finalSegment
                                                          // leading-'<' carve-out. All change the extracted SET -- see
                                                          // ingest.cpp kParserVer's own note for the per-language detail.
                                                          // The same 60 also carries the CUDA memory-space module
                                                          // bindings (cudacheck 7b close-out) -- uninitialized
                                                          // `__constant__`/`__device__`/`__managed__` tables now
                                                          // extract. All four land in one wave, so one bump covers
                                                          // them; a v59 blob misses rows on any of those trees.
                                                          // 59 = +TOML (.toml) config-key tier: a new grammar
                                                          // and a new .scm change the extracted SET.
                                                          // 47 (L3, 2026-08-08 audit) = `locals` counts
                                                          // DECLARATORS not declaration statements — see
                                                          // ingest.cpp kParserVer's own note.
                                                          // 46 = integration/quality-fleet merge of TWO independent
                                                          // 45s (the integrated ppalt+nestcal 45 below, and ev(G)'s
                                                          // 45 on feat/nest-profile) — fresh number, neither's blobs
                                                          // may be served.
                                                          // 45 (feat/nest-profile numbering) = essential complexity (44 was taken by the sibling
                                                          // nesting-quirk round; see ingest.cpp): RawDef/Symbol gain
                                                          // ev (u16 FLOOR) + evWhy (8×u8), a per-file def-record
                                                          // FORMAT change, and Swift guard_statement joins
                                                          // isDecisionType (a Swift cx VALUE change) — old caches
                                                          // hold numbers this build would not produce.
                                                          // 45 = integration/quality-fleet merge of the ppalt
                                                          // line (43 there) and the nestcal r1 line (44 there):
                                                          // the merged extraction matches neither, fresh number.
                                                          // 43 = ppalt disclosure: RawDef/Symbol gained a ppAlt
                                                          // field (def-record FORMAT change) — was 42 on its own
                                                          // branch, renumbered 43 at integration (collision with
                                                          // the independent 42 below).
                                                          // 42 = nested-closure span attribution: the tags-pass
                                                          // body-climb no longer adopts an ancestor whose body
                                                          // CONTAINS the def — cached JS/TS spans/metrics for
                                                          // nested closures were wrong, old blobs must miss.
                                                          // 41 = Phase 1 local-variable-indexing (PLAN.md
                                                          // 2026-08-06 evening): Symbol/RawDef gained a `locals`
                                                          // FLOOR field (C/C++ only), a per-file RawDef cache blob
                                                          // FORMAT change — old caches must be rejected.
                                                          // 40 = captureIncludes descends into import CONTAINERS: a
                                                          // `#if`-guarded #include/#import/`using`, a Python import under
                                                          // `if TYPE_CHECKING:` / `except ImportError:` / any body, a Rust
                                                          // `use` inside mod/fn/impl/trait, and a C# `using` inside a
                                                          // block-scoped namespace were all never visited by the old
                                                          // top-level-only scan, so v39 blobs carry SHORT include lists
                                                          // (and a --cochange surprising="1" false positive on any file
                                                          // that wraps its imports in one of them).
                                                          // 36 = H4 W3 V3-fixup L-1: a Rust container no longer scopes ITSELF
                                                          // (`mod util` was published as `util::util`) — per-def `scope` is a
                                                          // cached field, so v35 blobs carry the old ids and must be retired.
                                                          // 35 = H4 W3 MERGE (two in-flight 34s, never-reuse rule): RUST
                                                          // qualified-call widening (patterns + per-ref qualifier + per-def
                                                          // scope + method-span fix) AND the W2b-fixup operator re-split.
                                                          // 33 = H4 W2b (C++ qualified-call widening).
                                                          // 32 = H4 wave-2a (C# ?.-calls + TS/JS/Java qualified-new + ObjC field
                                                          // parity) — BOTH lanes bumped kParserVer and neither mirrored it; the
                                                          // orchestrator's merge missed it too, qschemetripcheck/qextractionkeycheck
                                                          // caught it post-merge (fixed on main; W2b hit the same drift in its
                                                          // worktree independently). Mirror in the SAME diff, every time.

// The extraction-identity tag folded into every sha-keyed filename key below. One string, one place.
inline std::string extractionIdentityTag()
{
    return "x" + std::to_string( kIngestCacheVersionMirror ) + "." + std::to_string( kIngestParserVerMirror );
}

// The 16-hex EXCLUDES-config key: fnv1a64 of the exact exclude set + the family's scheme tag + the extraction
// identity + the file-size ceiling. This is the SECOND filename field so eviction groups per (repo, config) —
// different --exclude sets are independent cache families that never evict one another (mirrors the
// auto-cache's lean/rich split), while HEAD-sha churn is capped WITHIN a family. \x1f field separators keep
// "a","bc" distinct from "ab","c". One shared body for the qheadsnap/qsnap/qbody (and mergescout/gitoracle)
// families; each passes its own scheme tag so a format bump renames only its family.
//
// `maxFileBytes` (P0.2, second half): computeHeadSnapshot threads --max-file-size into the HEAD ingest but the
// key folded only `excludes` — so a default run followed by a `--max-file-size=100M` run warm-HIT the first
// blob and answered with the smaller file SET. It is a first-class part of "which files were extracted", so it
// belongs in the key exactly like excludes. Families with no size ceiling of their own (mergescout's "qms",
// gitoracle's "qhist") take the default and are unaffected.
inline std::string exclConfigHex( const std::vector<std::string>& excludes, const std::string& schemeTag,
                                  std::size_t maxFileBytes = kDefaultMaxFileBytes )
{
    std::string keyMat;
    for( const std::string& e : excludes ) { keyMat += e; keyMat.push_back( '\x1f' ); }
    keyMat += schemeTag;
    keyMat.push_back( '\x1f' );
    keyMat += extractionIdentityTag();                 // P0.2: a kParserVer/kCacheVersion bump renames every blob
    keyMat.push_back( '\x1f' );
    keyMat += std::to_string( maxFileBytes );          // P0.2: the file-size ceiling changes the extracted SET
    char hex[ 20 ];
    std::snprintf( hex, sizeof( hex ), "%016llx", static_cast<unsigned long long>( fnv1a64( keyMat ) ) );
    return std::string( hex );
}

inline std::string headSnapExclHex( const std::vector<std::string>& excludes, std::size_t maxFileBytes = kDefaultMaxFileBytes )
{
    return exclConfigHex( excludes, std::to_string( kHeadSnapCacheScheme ), maxFileBytes );
}

// Y4 — BLOB-COUNT SHARDING. The 2 GiB low-water sweep (kMaxCacheDirBytes below) bounds cache-dir
// BYTES but not blob COUNT: production shows 23,502 ripwire-*.bin blobs (mostly qheadsnap/qsnap/qbody churn —
// a new blob per commit per repo, across the ~20 parallel agent sessions this machine runs) sitting FLAT in
// one cache dir, so every sweep's directory listing is O(N) over a single huge readdir(). Shard by a
// 2-hex-char subdir keyed on the BLOB'S OWN FILENAME hash — the same technique git's object store uses for
// exactly the same reason — giving 256 buckets (~92 files each at today's production count), so both the
// common-case open() (one blob → one shard → no scan of the others) and the sweep's own readdir() (256 small
// listings instead of one huge one) stay cheap as the population grows.
//
// BACKWARD COMPATIBLE by construction, no migration step: `resolveCacheBlobPath` is the ONE choke point every
// blob-path builder below (and `defaultCachePath` in main.cpp) routes through, for BOTH reads and writes — an
// existing FLAT blob (written before this change) is found and reused right where it already is; a key is
// only WRITTEN into its shard the next time it is (re)computed. A blob absent from both locations is a clean
// miss, created fresh, in its shard. `evictOldCacheFamily` below sweeps both layouts, so an old flat blob
// still ages out on schedule even if its key is never rewritten.
inline std::string blobShardHex( std::string_view filename )
{
    char hex[ 3 ];
    std::snprintf( hex, sizeof( hex ), "%02x", static_cast<unsigned>( fnv1a64( filename ) & 0xff ) );
    return std::string( hex );
}

inline std::string resolveCacheBlobPath( const std::string& dir, const std::string& filename )
{
    namespace fs = std::filesystem;
    const std::string flatPath = dir + "/" + filename;
    std::error_code   existsEc;
    if( fs::exists( fs::path( flatPath ), existsEc ) && !existsEc )
    {
        return flatPath; // legacy flat blob — keep using it in place
    }

    const std::string shardDir = dir + "/" + blobShardHex( filename );
    std::error_code   mkEc;
    fs::create_directory( fs::path( shardDir ), mkEc );
    if( mkEc )
    {
        return flatPath; // degrade: couldn't make the shard dir (e.g. dir missing/unwritable) — fall back to flat rather than lose caching entirely
    }
    return shardDir + "/" + filename;
}

// Deterministic per-(repo, excludes, sha) cache filename: ripwire-<family>-<repoHex>-<exclHex>-<shaHex>.bin,
// resolved through the shard-aware `resolveCacheBlobPath` above. The (family, repo, excl) prefix is the
// eviction group; the sha suffix distinguishes commits within it. Every field is a fixed-width hex hash of
// git-controlled / realpath'd input → no path-injection into the filename. One shared body for the
// qheadsnap/qsnap/qbody families.
inline std::string shaKeyedCachePath( const char* family, const std::string& repoHex, const std::string& exclHex, const std::string& sha )
{
    const std::uint64_t shaKey = fnv1a64( sha );
    char tail[ 96 ];
    std::snprintf( tail, sizeof( tail ), "ripwire-%s-%s-%s-%016llx.bin",
                   family, repoHex.c_str(), exclHex.c_str(), static_cast<unsigned long long>( shaKey ) );
    return resolveCacheBlobPath( cacheDirLadder(), tail );
}

inline std::string headSnapCachePath( const std::string& repoHex, const std::string& exclHex, const std::string& headSha )
{
    return shaKeyedCachePath( "qheadsnap", repoHex, exclHex, headSha );
}

// Hygiene: within one (repo, excludes) FAMILY, keep at most `keep` HEAD-snapshot cache files (newest by mtime);
// delete older ones so HEAD-sha churn (a new file per commit) cannot grow the cache dir without bound. Scoping
// per family (repoHex-exclHex prefix) — not per bare repo — means alternating --exclude configs do not evict
// one another (the lean/rich lesson). `keepPath` (the file we are about to use) is always retained regardless of
// mtime granularity. Degrade-only: any filesystem error is swallowed via the error_code overloads — eviction is
// best-effort hygiene, never a correctness or crash risk.
// The prefix-generic body: keep the `keep` newest ".bin"/".cache" files whose name begins with `prefix`, delete older
// ones, always retain `keepPath`. Both the qheadsnap (ingest) and qsnap (Snapshot) cache families share this
// (rule-of-three: two families that evict identically → one evictor, not two copies that must stay in sync).
//
// A5 (cache-dir hygiene) generalization: a THIRD shape of sweep showed up (see sweepStaleCacheBlobsOnce below) —
// age-then-size across the WHOLE "ripwire-*" family rather than a keep-N-newest cap on one sub-family — so this
// is the rule-of-three consolidation the paragraph above already anticipated, not a second copy-pasted sweeper.
// Two independent, optional passes run BEFORE the original count cap (each a no-op at its zero default, so the
// qheadsnap/qsnap call sites below are byte-for-byte unaffected):
//   maxAgeDays > 0     — delete any matching blob older than that many days outright.
//   maxTotalBytes > 0  — if the family's surviving total still exceeds it, delete oldest-first until under.
// `keepPath` is never deleted by any pass, in every case.
//
// Y4: covers BOTH blob layouts — the legacy flat one (matching entries directly under `dir`) and the
// sharded one `resolveCacheBlobPath`/blobShardHex now write into (matching entries under `dir`'s 2-hex-char
// subdirectories, "00".."ff") — so a family's blobs are found and evicted correctly regardless of which
// layout wrote them, and a mid-migration mix of both is swept as one set. The 256 shard names are an EXACT,
// bounded set (never an open-ended recursive walk of a shared $TMPDIR that may hold unrelated large trees).
inline void evictOldCacheFamily( const std::string& dir, const std::string& prefix,
                                 const std::string& keepPath, std::size_t keep,
                                 double maxAgeDays = 0.0, std::uintmax_t maxTotalBytes = 0 )
{
    namespace fs = std::filesystem;

    struct Blob { fs::file_time_type mtime; std::uintmax_t byteSize; std::string path; };
    std::vector<Blob> mine;
    const auto matches = [ & ]( const std::string& name )
    {
        if( name.size() < prefix.size() || name.compare( 0, prefix.size(), prefix ) != 0 )
        {
            return false;
        }
        return ( name.size() >= 4 && name.compare( name.size() - 4, 4, ".bin" ) == 0 )
            || ( name.size() >= 6 && name.compare( name.size() - 6, 6, ".cache" ) == 0 );
    };

    // best-effort scan of ONE directory for matching cache artifacts, appending them to `mine`. Never aborts
    // the whole sweep on a per-shard error — a single unreadable shard just contributes nothing this round.
    const auto scanOneDir = [ & ]( const fs::path& d )
    {
        std::error_code sec;
        fs::directory_iterator sit( d, sec ), send;
        if( sec )
        {
            return;
        }
        for( ; sit != send; sit.increment( sec ) )
        {
            if( sec )
            {
                return;
            }
            const std::string name = sit->path().filename().string();
            if( !matches( name ) )
            {
                continue;
            }
            std::error_code te;
            const auto mt = fs::last_write_time( sit->path(), te );
            if( te )
            {
                continue;
            }
            std::error_code se;
            const auto sz = sit->file_size( se );
            mine.push_back( Blob{ mt, se ? std::uintmax_t( 0 ) : sz, sit->path().string() } );   // size-stat failure degrades to 0 (age/count passes still see the file)
        }
    };

    // top-level pass: flat legacy blobs directly under `dir`, PLUS collect the 2-hex-char shard subdir names
    // to recurse into afterward (one bounded extra readdir() per shard, never deeper).
    std::error_code       ec;
    std::vector<fs::path> shardDirs;
    fs::directory_iterator it( fs::path( dir ), ec ), end;
    if( ec )
    {
        return; // unreadable cache dir → nothing to evict, no crash
    }
    for( ; it != end; it.increment( ec ) )
    {
        if( ec )
        {
            return;
        }
        const std::string name = it->path().filename().string();
        if( name.size() == 2 && std::isxdigit( static_cast<unsigned char>( name[0] ) ) && std::isxdigit( static_cast<unsigned char>( name[1] ) ) )
        {
            std::error_code isdirEc;
            if( it->is_directory( isdirEc ) && !isdirEc )
            {
                shardDirs.push_back( it->path() );
            }
            continue;
        }
        if( !matches( name ) )
        {
            continue;
        }
        std::error_code te;
        const auto mt = fs::last_write_time( it->path(), te );
        if( te )
        {
            continue;
        }
        std::error_code se;
        const auto sz = it->file_size( se );
        mine.push_back( Blob{ mt, se ? std::uintmax_t( 0 ) : sz, it->path().string() } );   // size-stat failure degrades to 0 (age/count passes still see the file)
    }
    for( const fs::path& sd : shardDirs )
    {
        scanOneDir( sd );
    }

    // age pass: outright delete anything past the cutoff (disabled when maxAgeDays == 0).
    if( maxAgeDays > 0.0 )
    {
        const auto ageBudget = std::chrono::duration_cast<fs::file_time_type::duration>( std::chrono::duration<double, std::ratio<86400>>( maxAgeDays ) );
        const auto cutoff = fs::file_time_type::clock::now() - ageBudget;
        std::vector<Blob> kept;
        kept.reserve( mine.size() );
        for( const Blob& b : mine )
        {
            if( b.mtime < cutoff && b.path != keepPath )
            {
                std::error_code de;
                fs::remove( fs::path( b.path ), de );   // best-effort; a failed unlink just leaves an extra file
                continue;
            }
            kept.push_back( b );
        }
        mine.swap( kept );
    }

    // size pass: if the family is still over budget, delete oldest-first until under a LOW-WATER mark of
    // 7/8 budget (disabled when maxTotalBytes == 0). The hysteresis is F6's live-cache finding (B7.4,
    // 2026-07-14): trimming to exactly the budget left the dir hovering AT the ceiling, so every subsequent
    // process re-crossed it on its first write and paid deletion work on every save — sweep-to-low-water
    // buys ~12% burst headroom and makes the common next-process sweep a scan-only no-op.
    if( maxTotalBytes > 0 )
    {
        const std::uintmax_t lowWaterBytes = maxTotalBytes - maxTotalBytes / 8;
        std::uintmax_t totalBytes = 0;
        for( const Blob& b : mine )
        {
            totalBytes += b.byteSize;
        }
        if( totalBytes > maxTotalBytes )
        {
            std::sort( mine.begin(), mine.end(), []( const Blob& a, const Blob& b ){ return a.mtime < b.mtime; } );   // oldest first
            std::vector<Blob> kept;
            kept.reserve( mine.size() );
            for( const Blob& b : mine )
            {
                if( totalBytes > lowWaterBytes && b.path != keepPath )
                {
                    std::error_code de;
                    fs::remove( fs::path( b.path ), de );
                    totalBytes -= b.byteSize;
                    continue;
                }
                kept.push_back( b );
            }
            mine.swap( kept );
        }
    }

    // count pass (the original behavior): keep only the `keep` newest, delete the rest (disabled via keep == max()).
    if( keep != std::numeric_limits<std::size_t>::max() && mine.size() > keep )
    {
        std::sort( mine.begin(), mine.end(), []( const Blob& a, const Blob& b ){ return a.mtime > b.mtime; } );   // newest first
        for( std::size_t i = keep; i < mine.size(); ++i )
        {
            if( mine[i].path == keepPath )
            {
                continue;
            }
            std::error_code de;
            fs::remove( fs::path( mine[i].path ), de );   // best-effort; a failed unlink just leaves an extra file
        }
    }
}

// A5 (cache-dir hygiene) — --doctor measured ~11,914 ripwire-* blobs / 2.4 GB in the cache-ladder dir on a
// machine that runs ~20 parallel agent sessions across many repos. Only the qsnap/qheadsnap families above were
// ever capped (keep-2-newest); the MAIN parse cache (ripwire-<hash>-lean/rich.bin, defaultCachePath in main.cpp)
// shares the SAME "ripwire-" prefix and dir but had no evictor at all — every distinct (repo, verb-class) pair
// this machine has ever touched leaves a blob forever.
//
// Policy (decided): at saveCache time, at most once per process, best-effort and silent — first delete any
// ripwire-* blob older than kMaxCacheBlobAgeDays, THEN (only if the dir is still over budget) delete oldest-
// first until the dir total is under kMaxCacheDirBytes. `keepPath` (the blob this call is about to use/rewrite)
// is NEVER deleted by either pass, so a run can never evict the cache entry it is itself relying on.
//
// Concurrency is safe by CONSTRUCTION, not by locking: loadCache self-heals a missing/torn file to a cold
// reparse, and saveCache publishes via tmp-then-rename, so a blob another process deletes out from under a
// concurrent reader just looks like a cold miss — never a corrupt read. Two sweepers racing on the same file
// both call fs::remove, and a double-remove is a benign no-op (the second just gets ENOENT via the error_code
// overload). This sweep matches "ripwire-" (not a narrower family prefix), so it also backstops qsnap/qheadsnap
// blobs that outlive their own keep-2 cap between runs — one dir-wide safety net under the per-family caps.
constexpr double         kMaxCacheBlobAgeDays = 30.0;
constexpr std::uintmax_t kMaxCacheDirBytes    = 2ull * 1024 * 1024 * 1024;   // 2 GB
constexpr std::size_t    kMaxCacheBlobCount   = 4096;                         // bound every future hygiene scan

inline void sweepStaleCacheBlobsOnce( const std::string& dir, const std::string& keepPath )
{
    static std::atomic<bool> swept{ false };
    bool expected = false;
    if( !swept.compare_exchange_strong( expected, true ) )
    {
        return; // only the first saveCache in this process sweeps
    }

    evictOldCacheFamily( dir, "ripwire-", keepPath, kMaxCacheBlobCount, kMaxCacheBlobAgeDays, kMaxCacheDirBytes );
}

// The HEAD-snapshot INGEST cache family (ripwire-qheadsnap-<repoHex>-<exclHex>-<sha>.bin), capped per (repo,excl).
inline void evictOldHeadSnapCaches( const std::string& dir, const std::string& repoHex, const std::string& exclHex,
                                    const std::string& keepPath, std::size_t keep = 2 )
{
    evictOldCacheFamily( dir, "ripwire-qheadsnap-" + repoHex + "-" + exclHex + "-", keepPath, keep );
}

// A4-P1 (round 2) — the HEAD-snapshot *Snapshot* cache. The qheadsnap INGEST cache above only skips the parse;
// everything computeSnapshot then does on the HEAD tree — above all findClones + findClonesType3 (~2.3-2.7 s
// post-interning) and the per-symbol metric fold — is ALSO immutable for a given (HEAD sha, excludes, scheme),
// yet was recomputed on every --quality-delta. So we cache the computed HEAD-side Snapshot itself: on a warm hit
// we deserialize it and RETURN — skipping git archive, ingest, buildGraph, AND clone detection entirely. The
// working-tree side legitimately still pays its own clone pass + ingest (it changes between runs).
//
// NEVER-STALE, on the same two independent guards the ingest cache uses:
//  1) FILENAME key = (realpath repo-root, HEAD sha, excludes, a qsnap scheme tag) — a different HEAD / repo /
//     --exclude set / scheme names a different file → the wrong Snapshot can never be loaded.
//  2) Blob self-validation: a magic + scheme-version header, an embedded fnv1a64(headSha) that must match the
//     live HEAD, and an fnv1a64 content checksum trailer over the whole body. Any mismatch/truncation → the blob
//     is rejected and the full compute runs (which then rewrites a correct blob) — a stale/foreign blob can
//     never inject wrong facts.
//
// DETERMINISM (the hard contract — "faster must never change the answer"): the blob is serialized in the maps'
// sorted (btree) iteration order and the vectors' already-sorted order, so it is byte-stable run-to-run; more
// importantly the RESTORED Snapshot is field-for-field identical to a freshly-computed one (same hashes, same
// values, vectors re-sorted on load), and computeDelta consults `base` only by key lookup + binary_search — so
// a cached delta is byte-identical to an uncached one. Native-endian POD is fine: the det-gate is same-machine,
// and a foreign-arch blob simply fails the checksum → cold recompute (never wrong output).
// v2: the signal-to-noise round changed the SEMANTICS of a cached Snapshot's dead set (fixture paths exempt),
// so v1 blobs must never be served to a v2 binary (two binary versions sharing one cache dir would otherwise
// answer differently depending on who wrote first — a determinism hole). The scheme is in the filename key,
// so old blobs are simply never named again (and age out via the A5 sweep).
// v3 (F2/X4) — B10.1a (ffcc618) added `isTestScriptPath` to `isDeadCandidate` (shell test-runner
// scripts join header-exported symbols and fixture paths as dead-code-exempt) WITHOUT bumping this constant —
// exactly the determinism hole the v2 comment above exists to prevent: a pre-ffcc618 binary's qsnap blob
// (dead set computed under the OLD, narrower exemption) served to a current binary yields phantom
// quality-delta regressions on shell test-runner helpers. Bumped 2 → 3 here to retire every blob written
// before this fix. THE RULE (repeated from v2, now with teeth — see the tripwire below): any change to the
// SEMANTICS of what a cached Snapshot means — what counts as dead, what a clone group's identity is, what the
// serialized fields mean — requires a bump. A change that touches these functions' TEXT but not their
// MEANING (a rename, a reflow, a comment edit) does not.
//
// TRIPWIRE (test/qschemetripcheck.sh): hashes the concatenated source text of the manifest below and compares
// against a pinned hash committed beside it (`test/qschemetrip.hash`). A mismatch fails the gate with
// instructions: did the *semantics* of what a cached Snapshot represents change? → bump kQSnapCacheScheme AND
// re-pin the hash in the same diff. Refactor-only (no behavior change)? → just re-pin. Keep this manifest
// SMALL and edit it here (nowhere else) if the semantic surface grows:
//   isDeadCandidate            (quality.h) — the dead-set predicate itself
//   isFixturePath              (quality.h) — a fixture-path exemption isDeadCandidate calls into
//   isTestScriptPath           (quality.h) — the test-script exemption isDeadCandidate calls into (the exact
//                                             helper B10.1a added without a bump — the finding this guards)
//   topLevelCalleeNameHashes   (quality.h) — the file-scope (top-level script statement) call-site evidence
//                                             isDeadCandidate consults (W1-S2)
//   serializeSnapshot          (quality.h) — the on-disk blob shape
//   deserializeSnapshot        (quality.h) — the on-disk blob shape, read side
//   computeSnapshot            (quality.h) — the dead-set BUILDER (baseline side)
//   bodyHashesBySym            (quality.h) — the bodyHashBySym KEY semantics (the v6 keying change landed
//                                             without this line watching it — the exact drift this guards)
// v4 (r27 P0.2) — the blob header gained the EXTRACTION IDENTITY (kIngestCacheVersionMirror +
// kIngestParserVerMirror; see the long note at their declaration). Everything a Snapshot contains is a
// function of tree-sitter extraction, so a parserVer bump must retire the blob — it did not, and 28c7d32's
// 80 corrected canonIds were served from stale qsnaps for a whole round. Both the header AND the filename key
// now carry the pair, so a pre-r27 blob is neither named nor believed. A HEADER SHAPE change → bump.
// v5 — the Snapshot gained `defsBySym`, the overload set's CARDINALITY, because every other per-symbol kind
// is a MAX over that set and a MAX cannot see the set shrink (see computeSnapshot, and --edit-check's
// defs_was= which reads it). That is a BLOB SHAPE change AND a change to what a cached Snapshot contains, so
// a v4 blob deserialized here would be short by one map and must never be served: bumped, which renames every
// file through the excludes key as well.
// v6 (W1-S2, 2026-08-11) — bodyHashBySym's KEYS changed meaning: pathQualifiedKey (path\0scope\0name)
// instead of hash(canonicalId), which degrades to the bare name for scope-less symbols and folded every
// same-named one ACROSS FILES into one churn-join identity (a new rows() in one file flagged churn against
// the rows() in an untouched file). A v5 blob's body keys live in a different key space, so serving one to
// a v6 binary would make every scope-less symbol read as absent-from-baseline (churn silently disarmed):
// bumped, which renames every file through the excludes key as well.
// v6 (W1-S2, 2026-08-11) — `isDeadCandidate` gained the top-level-invocation exemption (a symbol invoked
// from FILE SCOPE — a bash/script top-level statement — is alive; see topLevelCalleeNameHashes above the
// predicate): the SEMANTICS of a cached Snapshot's dead set narrowed, so a v5 blob's dead set (computed
// without the exemption) served to this binary would resurrect the exact false positives the fix retires.
// No extraction change (the file-scope references were always captured — buildGraph just never turned them
// into edges), so kParserVer/the mirrors deliberately did NOT move.
constexpr std::uint32_t kQSnapCacheScheme = 6;
constexpr char          kQSnapMagic[4]    = { 'Q', 'S', 'N', 'P' };

// The qsnap EXCLUDES-config key folds the qsnap SCHEME (independent of the ingest cache's kHeadSnapCacheScheme)
// so a qsnap-format bump renames every file → old-scheme blobs are simply never named again. It also folds the
// extraction identity + maxFileBytes (see exclConfigHex).
inline std::string qsnapExclHex( const std::vector<std::string>& excludes, std::size_t maxFileBytes = kDefaultMaxFileBytes )
{
    return exclConfigHex( excludes, "qsnap" + std::to_string( kQSnapCacheScheme ), maxFileBytes );
}

// a distinct "qsnap" family prefix so the ingest and Snapshot families never collide and evict independently.
inline std::string qsnapCachePath( const std::string& repoHex, const std::string& exclHex, const std::string& headSha )
{
    return shaKeyedCachePath( "qsnap", repoHex, exclHex, headSha );
}

// Cap the qsnap family to the 2 newest per (repo, excludes) — same hygiene, same shared evictor as qheadsnap.
inline void evictOldQSnapCaches( const std::string& dir, const std::string& repoHex, const std::string& exclHex,
                                 const std::string& keepPath, std::size_t keep = 2 )
{
    evictOldCacheFamily( dir, "ripwire-qsnap-" + repoHex + "-" + exclHex + "-", keepPath, keep );
}

// Signal-to-noise round — the WINDOW-REF body-hash cache family ("ripwire-qbody-"): the per-canonId raw-body
// hashes of the tree at gitWindowRefSha, the committed-thrash evidence side of short-horizon-churn. Immutable
// for a given (repo, excludes, ref sha) exactly like the HEAD snapshot, cached with the SAME two never-stale
// guards (sha-keyed filename + the self-validating qsnap blob format — we reuse serializeSnapshot with only
// bodyHashBySym populated, validated against the REF sha). A distinct filename family so qbody blobs are never
// read as full HEAD Snapshots or vice versa, and the two families evict independently.
// v2 (r27 P0.2): the shared qsnap blob header gained the extraction identity — a body-hash blob is just as
// extraction-derived as a full Snapshot, so this family retires with it.
// v3 (W1-S2): bodyHashBySym keys became pathQualifiedKey (see kQSnapCacheScheme v6). The blob header's
// scheme check would already reject a v2 blob — but as CORRUPT (alert + stderr), not a clean miss; bumping
// the family renames every file so old blobs are simply never named again.
constexpr std::uint32_t kQBodyCacheScheme = 3;

inline std::string qbodyExclHex( const std::vector<std::string>& excludes, std::size_t maxFileBytes = kDefaultMaxFileBytes )
{
    return exclConfigHex( excludes, "qbody" + std::to_string( kQBodyCacheScheme ), maxFileBytes );
}

inline std::string qbodyCachePath( const std::string& repoHex, const std::string& exclHex, const std::string& refSha )
{
    return shaKeyedCachePath( "qbody", repoHex, exclHex, refSha );
}

// append one trivially-copyable POD to the blob buffer (native layout; see the determinism note above).
template<class T>
inline void qsnapPut( std::string& buf, const T& v )
{
    static_assert( std::is_trivially_copyable_v<T>, "qsnap serializes PODs only" );
    buf.append( reinterpret_cast<const char*>( &v ), sizeof( T ) );
}

// read one POD, advancing `p`; false (no advance) if fewer than sizeof(T) bytes remain before `end`.
template<class T>
inline bool qsnapGet( const char*& p, const char* end, T& out )
{
    if( end - p < static_cast<std::ptrdiff_t>( sizeof( T ) ) )
    {
        return false;
    }
    std::memcpy( &out, p, sizeof( T ) );
    p += sizeof( T );
    return true;
}

// Serialize a Snapshot to a self-validating blob: [magic][scheme][cacheVer][parserVer][fnv(headSha)] then each
// of the 9 fields as a uint32 count followed by its flat records (btree maps in sorted key order, vectors
// as-is), then an fnv1a64 checksum over all preceding bytes. Byte-stable for a fixed Snapshot.
// P0.2 (r27): cacheVer/parserVer are the EXTRACTION IDENTITY every field below is a function of — see the note
// at kIngestCacheVersionMirror. They are in the filename key too; carrying them here as well means a blob
// reached by any other route (hand-copied, collided) is REJECTED rather than believed.
inline std::string serializeSnapshot( const Snapshot& s, const std::string& headSha )
{
    std::string buf;
    buf.append( kQSnapMagic, 4 );
    qsnapPut( buf, kQSnapCacheScheme );
    qsnapPut( buf, kIngestCacheVersionMirror );
    qsnapPut( buf, kIngestParserVerMirror );
    qsnapPut( buf, fnv1a64( headSha ) );

    const auto putValMap = [ & ]( const gtl::btree_map<std::uint64_t, std::uint32_t>& m )
    { qsnapPut( buf, std::uint32_t( m.size() ) ); for( const auto& [ k, v ] : m ) { qsnapPut( buf, k ); qsnapPut( buf, v ); } };
    const auto putHashMap = [ & ]( const gtl::btree_map<std::uint64_t, std::uint64_t>& m )
    { qsnapPut( buf, std::uint32_t( m.size() ) ); for( const auto& [ k, v ] : m ) { qsnapPut( buf, k ); qsnapPut( buf, v ); } };
    const auto putVec = [ & ]( const std::vector<std::uint64_t>& v )
    { qsnapPut( buf, std::uint32_t( v.size() ) ); for( std::uint64_t x : v ) { qsnapPut( buf, x ); } };

    putValMap( s.ccxBySym );
    putValMap( s.locBySym );
    putValMap( s.nestBySym );
    putValMap( s.paramsBySym );
    putValMap( s.defsBySym );
    putValMap( s.maskBySym );
    putHashMap( s.bodyHashBySym );
    putVec( s.cloneGroups );
    putVec( s.dead );
    putVec( s.publicApi );

    const std::uint64_t sum = fnv1a64( std::string_view( buf.data(), buf.size() ) );
    qsnapPut( buf, sum );
    return buf;
}

// Deserialize + validate. Returns false (leaving `out` untouched) on any short/corrupt/mismatched blob — the
// caller then treats a present-but-invalid file as corrupt (alert + recompute) and an absent file as a clean
// miss. Vectors are re-sorted so computeDelta's binary_search invariant holds regardless of on-disk order.
inline bool deserializeSnapshot( const std::string& blob, const std::string& headSha, Snapshot& out )
{
    if( blob.size() < 4 + 3 * sizeof( std::uint32_t ) + sizeof( std::uint64_t ) + sizeof( std::uint64_t ) )
    {
        return false;                                          // smaller than magic+scheme+cacheVer+parserVer+sha+trailer
    }
    const char*       data    = blob.data();
    const std::size_t bodyLen = blob.size() - sizeof( std::uint64_t );   // trailer = last 8 bytes
    std::uint64_t     stored  = 0;
    std::memcpy( &stored, data + bodyLen, sizeof( std::uint64_t ) );
    if( stored != fnv1a64( std::string_view( data, bodyLen ) ) )
    {
        return false; // checksum
    }

    const char* p   = data;
    const char* end = data + bodyLen;                          // never parse into the trailer
    if( std::memcmp( p, kQSnapMagic, 4 ) != 0 )
    {
        return false;
    }
    p += 4;
    std::uint32_t scheme = 0;
    if( !qsnapGet( p, end, scheme ) || scheme != kQSnapCacheScheme )
    {
        return false;
    }

    // P0.2 — the EXTRACTION IDENTITY guard. Every field below is a function of tree-sitter extraction, so a
    // blob written by a binary with a different kCacheVersion/kParserVer describes a DIFFERENT corpus and must
    // be rejected outright (self-healing recompute), never merged or trusted.
    std::uint32_t blobCacheVer = 0, blobParserVer = 0;
    if( !qsnapGet( p, end, blobCacheVer )  || blobCacheVer  != kIngestCacheVersionMirror )
    {
        return false;
    }
    if( !qsnapGet( p, end, blobParserVer ) || blobParserVer != kIngestParserVerMirror )
    {
        return false;
    }

    std::uint64_t shaHash = 0;
    if( !qsnapGet( p, end, shaHash ) || shaHash != fnv1a64( headSha ) )
    {
        return false;
    }

    Snapshot s;
    const auto getValMap = [ & ]( gtl::btree_map<std::uint64_t, std::uint32_t>& m ) -> bool
    {
        std::uint32_t n = 0;
        if( !qsnapGet( p, end, n ) )
        {
            return false;
        }
        for( std::uint32_t i = 0; i < n; ++i )
        {
            std::uint64_t k;
            std::uint32_t v;
            if( !qsnapGet( p, end, k ) || !qsnapGet( p, end, v ) )
            {
                return false;
            }
            m[k] = v;
        }
        return true;
    };
    const auto getHashMap = [ & ]( gtl::btree_map<std::uint64_t, std::uint64_t>& m ) -> bool
    {
        std::uint32_t n = 0;
        if( !qsnapGet( p, end, n ) )
        {
            return false;
        }
        for( std::uint32_t i = 0; i < n; ++i )
        {
            std::uint64_t k, v;
            if( !qsnapGet( p, end, k ) || !qsnapGet( p, end, v ) )
            {
                return false;
            }
            m[k] = v;
        }
        return true;
    };
    const auto getVec = [ & ]( std::vector<std::uint64_t>& v ) -> bool
    {
        std::uint32_t n = 0;
        if( !qsnapGet( p, end, n ) )
        {
            return false;
        }
        v.reserve( n );
        for( std::uint32_t i = 0; i < n; ++i )
        {
            std::uint64_t x;
            if( !qsnapGet( p, end, x ) )
            {
                return false;
            }
            v.push_back( x );
        }
        return true;
    };

    if( !getValMap( s.ccxBySym ) || !getValMap( s.locBySym ) || !getValMap( s.nestBySym ) || !getValMap( s.paramsBySym ) || !getValMap( s.defsBySym ) || !getValMap( s.maskBySym ) || !getHashMap( s.bodyHashBySym ) || !getVec( s.cloneGroups ) || !getVec( s.dead ) || !getVec( s.publicApi ) )
    {
        return false;
    }

    std::sort( s.cloneGroups.begin(), s.cloneGroups.end() );   // computeDelta binary_searches these — enforce order
    std::sort( s.dead.begin(),        s.dead.end() );
    std::sort( s.publicApi.begin(),   s.publicApi.end() );
    out = std::move( s );
    return true;
}

// Read a qsnap blob whole. Returns 1 = readable non-empty file (out filled), 0 = absent/empty/unreadable/not-a-regular-file (a
// CLEAN miss — no alert). A present-but-invalid blob still returns 1 here; deserializeSnapshot then rejects it,
// and the caller alerts. Binary-safe (no getline/text translation).
inline int readQSnapBlob( const std::string& path, std::string& out )
{
    // L1 (Linux runtime probe): opening a DIRECTORY succeeds on Linux/glibc and fails on macOS, so a
    // non-regular file at a cache-blob path is a platform-split hazard rather than a clean miss — it cost
    // ingest.cpp's loadCache an abort (see isRegularFileAt there). A qsnap blob is always a REGULAR file
    // (atomicWriteQSnap renames one into place); every other shape is a miss on every platform, which is
    // exactly what this function's 0 already means, so it stays silent and the caller recomputes.
    {
        struct stat probe;
        if( ::stat( path.c_str(), &probe ) != 0 || !S_ISREG( probe.st_mode ) )
        {
            return 0;
        }
    }

    std::ifstream f( path, std::ios::binary | std::ios::ate );
    if( !f )
    {
        return 0;
    }
    const std::streamsize sz = f.tellg();
    if( sz <= 0 )
    {
        return 0;
    }
    out.resize( static_cast<std::size_t>( sz ) );
    f.seekg( 0 );
    if( !f.read( out.data(), sz ) ) { out.clear(); return 0; }
    return 1;
}

// ─── Phase-M concurrency seam ───────────────────────────────────────────────────────────────────────
//
// ingest() writes PROCESS-GLOBAL caches (ingest.cpp: compiledQueryCache / queryFor's static table) that are
// single-writer BY DESIGN — populated single-threaded, then read lock-free by the parse pool. The long-lived
// MCP server's Phase-M qsnap PREFETCH worker is the first source of a CONCURRENT ingest: a background
// HEAD-snapshot warm that can overlap a request thread's own ingest (a getIndex rebuild, or a lazy
// quality_delta). Because ingest.cpp is out of edit scope, we serialize at every ingest CALL SITE in the
// server with this one process-wide mutex. Uncontended (the common single-request-thread case) it is ~20 ns;
// when the worker and a request both need to ingest, one waits — correct, since both produce byte-identical
// facts. Held ONLY around the ingest-heavy region, NEVER around a warm qsnap cache HIT (those stay lock-free).
inline std::mutex& headSnapshotIngestMutex()
{
    static std::mutex m;
    return m;
}

// Atomic qsnap publish (§2b atomic-publish gate: no partial blob is ever visible at qsnapCachePath). Write the
// blob to a UNIQUE tmp file (pid + a monotone counter → distinct even between the request thread's lazy write
// and the prefetch worker's write of the SAME sha), flush, then rename() — POSIX rename is atomic within a
// directory, so a concurrent reader (readQSnapBlob here, or a separate ripwire process) sees either the OLD
// complete file or the NEW complete file, never a torn half-written one. This REPLACES the direct
// `ofstream(..., trunc)` that was torn-read-prone (a reader could observe a zero-length / partially-written
// blob mid-write and reject a perfectly good sha), hardening the lazy path too. Degrade-only: any IO failure
// unlinks the tmp and returns false → the next lazy/prefetch pass simply rewrites it.
inline bool atomicWriteQSnap( const std::string& path, const std::string& blob )
{
    static std::atomic<std::uint64_t> seq{ 0 };
    const std::string tmp = path + ".tmp." + std::to_string( ::getpid() )
                          + "." + std::to_string( seq.fetch_add( 1, std::memory_order_relaxed ) );
    {
        std::ofstream of( tmp, std::ios::binary | std::ios::trunc );
        if( !of )
        {
            return false;
        }
        of.write( blob.data(), static_cast<std::streamsize>( blob.size() ) );
        of.flush();
        if( !of ) { std::error_code e; std::filesystem::remove( std::filesystem::path( tmp ), e ); return false; }
    }
    if( std::rename( tmp.c_str(), path.c_str() ) != 0 )
    { std::error_code e; std::filesystem::remove( std::filesystem::path( tmp ), e ); return false; }
    return true;
}

// ─── shared plumbing for the two archived-tree consumers (HEAD snapshot / churn window-ref) ─────────────

// probe one qsnap-format blob: 1 = valid hit (`out` filled), 0 = clean miss (absent/empty/unreadable),
// -1 = present but corrupt/mismatched (caller decides whether to alert). Never throws.
inline int probeSnapshotBlob( const std::string& path, const std::string& sha, Snapshot& out )
{
    std::string blob;
    if( readQSnapBlob( path, blob ) != 1 )
    {
        return 0;
    }
    return deserializeSnapshot( blob, sha, out ) ? 1 : -1;
}

// RAII owner of a materialized commit tree — keep alive while reading file bytes through its ingest result.
struct TmpTreeGuard
{
    std::string p;
    ~TmpTreeGuard() { if( !p.empty() ) { std::error_code e; std::filesystem::remove_all( std::filesystem::path( p ), e ); } }
};

// Materialize `committish`'s committed tree into a fresh pid-suffixed temp dir under the hardened cache
// ladder (per-user; never the repo) via `git archive | tar -x`. Returns the temp root, or "" on any failure
// (degrade-alerted; a half-made dir is cleaned up here — on success the CALLER owns cleanup via TmpTreeGuard).
inline std::string materializeCommitTree( const std::string& root, const std::string& committish, const char* tag )
{
    namespace fs = std::filesystem;

    // r27 (Lane C routing) — RESOLVE THE REVISION FIRST. `git archive --output=FILE` really does write a file
    // (measured), so this is the P0.1 shape one careless caller away from being the same data-loss bug. Every
    // caller today passes "HEAD" or a rev-list sha, so this is a latent hole, not a live one — which is
    // exactly when it is cheapest to close. Resolving through `rev-parse --verify` and requiring a bare
    // object name is the real defense; quoting is not, and a LEADING `--` is not either (git would read the
    // revision as a pathspec and the command would silently archive nothing — Lane C measured that too), so
    // the separator goes AFTER the revision.
    const std::string rev = gitResolveCommitSha( root, committish );
    if( rev.empty() )
    { DEGRADED_PATH_ALERT( "quality: commit-tree revision does not resolve to a commit — refusing to archive" ); return {}; }

    std::error_code ec;
    const std::string tmpRoot = cacheDirLadder() + "/ripwire-" + tag + "-" + std::to_string( ::getpid() );
    fs::remove_all( fs::path( tmpRoot ), ec );                 // stale leftover from a crashed prior run
    if( !fs::create_directories( fs::path( tmpRoot ), ec ) && ec )
    { DEGRADED_PATH_ALERT( "quality: cannot create commit-tree temp dir" ); return {}; }

    const std::string extract = "git -c core.quotepath=false -C " + shSingleQuote( root )
                              + " archive --format=tar " + shSingleQuote( rev ) + " -- 2>/dev/null | tar -x -C " + shSingleQuote( tmpRoot ) + " 2>/dev/null";
    if( std::system( extract.c_str() ) != 0 )
    {
        DEGRADED_PATH_ALERT( "quality: git archive failed — committed tree unavailable" );
        std::error_code e;
        fs::remove_all( fs::path( tmpRoot ), e );
        return {};
    }
    return tmpRoot;
}

// T0.1 — build a quality Snapshot from the HEAD version of the tree, so `--quality-delta` (and the MCP
// quality_delta verb) works at "before I push" with ZERO start-of-task ritual when no explicit
// `.ripwire_quality_baseline` sidecar exists. Mechanism: `git archive HEAD` streams a tar of the committed
// tree, extracted into a fresh temp dir under the hardened cacheDirLadder(); we ingest + buildGraph +
// computeSnapshot on that temp root and clean it up. The temp root is passed as the snapshot's own `root`, so
// every baseline key is the SAME root-RELATIVE baselineCanonId (relForHash) the working-tree side produces —
// the two sides compare key-for-key regardless of where the HEAD tree was materialized (S2 spelling-independence).
//
// Determinism: HEAD content is fixed, so the extracted tree, its ingest, and the snapshot are byte-stable
// run-to-run on a fixed tree state → the delta is byte-identical. The HEAD side goes through the IDENTICAL
// computeSnapshot / per-canonId MAX aggregation as the working tree, so overloads collapse to one canonId with
// the MAX metric on BOTH sides — a low-metric overload can never manufacture a phantom regression.
//
// Degrade (never throw): non-git root, no HEAD (unborn / detached with no committed tree), git unavailable, or
// a failed archive/extract/ingest → returns {snapshot, false}. rootPath is shell-escaped (shSingleQuote) and
// quotepath=false — no injection, deterministic path handling.
inline Snapshot computeSnapshot( const IngestResult& ing, const Graph& g, std::string_view root );   // fwd — defined below; computeHeadSnapshot reuses it
// `excludes` MUST mirror the working-tree side's cfg.excludes (A4-F5): the HEAD snapshot is compared key-for-key
// against the working tree, and any in-edge-derived kind (dead-code, api-surface) diverges if one side honors
// --exclude and the other does not — e.g. a helper called only from tests/ is dead on a --exclude=tests working
// tree but alive on an unfiltered HEAD → a phantom "dead-code" regression + exit 2 on an untouched tree. Default
// {} keeps every existing call site (mcp.h, the CLI before it threads cfg.excludes) compiling and unchanged.
inline std::pair<Snapshot, bool> computeHeadSnapshot( const std::string& root, const std::string_view* cacheNever = nullptr,
                                                      std::size_t maxFileBytes = kDefaultMaxFileBytes,
                                                      const std::vector<std::string>& excludes = {} )
{
    (void)cacheNever;

    // 1) require a git repo with a resolvable HEAD tree — the SAME windowless `rev-parse --verify HEAD` probe
    //    gitRepoHasHistory runs (one source of truth; was an inline copy of it before F13 dedup).
    if( !gitRepoHasHistory( root ) )
    {
        return { Snapshot {}, false };
    }

    // Cache keys, computed ONCE and shared by both the Snapshot cache (this step) and the ingest cache (step 3).
    const std::string headSha   = gitHeadSha( root );        // non-empty: gitRepoHasHistory passed above
    const bool        useCache  = !headSha.empty();
    const std::string repoHex   = useCache ? headSnapRepoHex( root )     : std::string{};
    const std::string exclHex   = useCache ? headSnapExclHex( excludes, maxFileBytes ) : std::string{};   // ingest-cache family
    const std::string qExclHex  = useCache ? qsnapExclHex( excludes, maxFileBytes )    : std::string{};   // Snapshot-cache family
    const std::string qsnapPath = useCache ? qsnapCachePath( repoHex, qExclHex, headSha ) : std::string{};

    // 1b) SNAPSHOT cache probe — a warm hit returns the fully-computed HEAD Snapshot and skips git archive,
    //     ingest, buildGraph, AND clone detection entirely (the ~2.4 s the ingest cache alone could not save).
    //     Absent/empty file → clean miss (no alert); present-but-invalid → corrupt (alert) → fall through to a
    //     full recompute that rewrites a correct blob.
    if( useCache )
    {
        Snapshot cached;
        const int hit = probeSnapshotBlob( qsnapPath, headSha, cached );
        if( hit == 1 )
        {
            return { std::move( cached ), true }; // HIT
        }
        if( hit == -1 )
        {
            // the fprintf is the visible line in ALL build types (test/qsnapcachecheck.sh (e) gates on it);
            // DEGRADED_PATH_ALERT compiles out under NDEBUG.
            std::fprintf( stderr, "ripwire: quality: HEAD Snapshot cache corrupt — recomputing\n" );
            DEGRADED_PATH_ALERT( "quality: HEAD Snapshot cache corrupt — recomputing" );
        }
    }

    // Phase-M: serialize the ingest-heavy region against a concurrent ingest (the qsnap prefetch worker vs a
    // request thread), since ingest() writes single-writer process-global query caches (§2b). Held from here
    // through the atomic write below; the warm cache-probe above stays OUTSIDE the lock (lock-free hit).
    std::lock_guard<std::mutex> ingestLk( headSnapshotIngestMutex() );

    // Re-probe under the lock: whoever else held it (the lazy path or the prefetch worker) may have JUST
    // written the qsnap for this exact sha — take that hit instead of redundantly recomputing (worker + lazy
    // converge on one compute). Same validation as the pre-lock probe; a corrupt blob still falls through.
    if( useCache )
    {
        Snapshot cached2;
        if( probeSnapshotBlob( qsnapPath, headSha, cached2 ) == 1 )
        {
            return { std::move( cached2 ), true };                   // HIT (won by the thread we waited on)
        }
    }

    // 2) materialize HEAD into a private temp dir under the hardened cache ladder (per-user; not the repo).
    //    A unique suffix (pid) keeps concurrent runs from colliding. Cleaned up via RAII teardown.
    const std::string tmpRoot = materializeCommitTree( root, "HEAD", "qhead" );
    if( tmpRoot.empty() )
    {
        return { Snapshot {}, false };
    }
    TmpTreeGuard guard{ tmpRoot };

    // 3) ingest + graph + snapshot the HEAD tree. The HEAD tree is immutable for a given HEAD sha, so we hand
    //    the ingest an incremental content-hash cache keyed on (repo, HEAD sha, excludes) — a warm re-run is a
    //    pure cache hit instead of a ~12.5 s cold parse (A4-P1). The blob self-validates (parserVer + checksum
    //    + per-file content hash) and is stored root-relative, so it can NEVER serve stale/foreign facts and is
    //    portable across the pid-suffixed tmpRoot. Any cache IO failure degrades inside ingest() to a cold
    //    parse — byte-identical output either way. The working-tree side's excludes are applied here too
    //    (A4-F5) so both trees see the same file set. (Keys were computed once in step 1.)
    const std::string cachePath  = useCache ? headSnapCachePath( repoHex, exclHex, headSha ) : std::string{};
    IngestResult headIng = ingest( tmpRoot.c_str(), excludes, useCache ? std::string_view( cachePath ) : std::string_view{}, maxFileBytes );

    // Hygiene: cap each (repo, excludes) family to the 2 newest files (delete older sha's). Done AFTER the
    // ingest so the file we just wrote/used is the newest → always retained. Best-effort; never throws.
    if( useCache )
    {
        evictOldHeadSnapCaches( cacheDirLadder(), repoHex, exclHex, cachePath, 2 );
    }
    if( headIng.symbols.empty() && headIng.files.empty() )
    { DEGRADED_PATH_ALERT( "quality: HEAD tree ingested empty — falling back to run --quality-baseline first" ); return { Snapshot{}, false }; }
    const Graph headG = buildGraph( headIng, nullptr );

    // root = tmpRoot so keys are root-relative and match the working-tree side key-for-key (S2).
    Snapshot snap = computeSnapshot( headIng, headG, tmpRoot );

    // Persist the computed Snapshot so the NEXT --quality-delta on this HEAD skips everything above (clone
    // detection included). Best-effort: a failed write just means the next run recomputes — never a crash. The
    // written file is the newest in its family, so eviction (below) always retains it.
    if( useCache )
    {
        const std::string blob = serializeSnapshot( snap, headSha );
        atomicWriteQSnap( qsnapPath, blob );                 // tmp+rename — never a torn read (§2b atomic publish)
        evictOldQSnapCaches( cacheDirLadder(), repoHex, qExclHex, qsnapPath, 2 );
    }
    return { std::move( snap ), true };
}

// Signal-to-noise round — the committed-thrash evidence for short-horizon-churn: the per-canonId RAW-body
// hashes of the tree at the churn-window reference commit (gitWindowRefSha). A symbol whose baseline (HEAD)
// body differs from this ref's body — or that is absent here but present at HEAD — was already written/
// rewritten by COMMITS inside the window; only such a symbol may flag churn when the working tree rewrites it
// again. Same materialize-ingest-hash pipeline as computeHeadSnapshot, minus the graph/clone/metric passes it
// does not need, and cached in its own qbody family (warm re-runs are a blob read). Degrade (never throw):
// no history / no ref / failed archive/ingest → {empty, false}, and the churn kind simply reports nothing.
inline std::pair<gtl::btree_map<std::uint64_t, std::uint64_t>, bool>
computeWindowRefBodyHashes( const std::string& root, std::uint32_t days,
                            const std::vector<std::string>& excludes = {},
                            std::size_t maxFileBytes = kDefaultMaxFileBytes )
{
    if( !gitRepoHasHistory( root ) )
    {
        return { {}, false };
    }
    const std::string refSha = gitWindowRefSha( root, days );
    if( refSha.empty() )
    {
        return { {}, false };
    }

    const std::string repoHex   = headSnapRepoHex( root );
    const std::string exclHex   = headSnapExclHex( excludes, maxFileBytes );   // ingest-cache family (shared with qheadsnap)
    const std::string qbExclHex = qbodyExclHex( excludes, maxFileBytes );
    const std::string qbodyPath = qbodyCachePath( repoHex, qbExclHex, refSha );

    // warm probe (lock-free, same discipline as the qsnap probe): absent/empty → clean miss; corrupt → alert +
    // recompute. The blob validates against the REF sha, so a foreign/stale blob can never serve wrong facts.
    {
        Snapshot cached;
        const int hit = probeSnapshotBlob( qbodyPath, refSha, cached );
        if( hit == 1 )
        {
            return { std::move( cached.bodyHashBySym ), true };
        }
        if( hit == -1 )
        {
            std::fprintf( stderr, "ripwire: quality: window-ref body cache corrupt — recomputing\n" );
            DEGRADED_PATH_ALERT( "quality: window-ref body cache corrupt — recomputing" );
        }
    }

    // Phase-M: ingest() writes single-writer process-global caches — serialize like computeHeadSnapshot (§2b).
    std::lock_guard<std::mutex> ingestLk( headSnapshotIngestMutex() );

    // re-probe under the lock: another thread may have just published this exact ref.
    {
        Snapshot cached2;
        if( probeSnapshotBlob( qbodyPath, refSha, cached2 ) == 1 )
        {
            return { std::move( cached2.bodyHashBySym ), true };
        }
    }

    const std::string tmpRoot = materializeCommitTree( root, refSha, "qref" );
    if( tmpRoot.empty() )
    {
        return { {}, false };
    }
    TmpTreeGuard guard{ tmpRoot };

    // the ref tree is immutable for its sha → reuse the qheadsnap INGEST cache family keyed by refSha (the
    // family's keep-2 cap holds exactly the HEAD blob + this ref blob between commits).
    const std::string ingestCachePath = headSnapCachePath( repoHex, exclHex, refSha );
    IngestResult refIng = ingest( tmpRoot.c_str(), excludes, std::string_view( ingestCachePath ), maxFileBytes );
    evictOldHeadSnapCaches( cacheDirLadder(), repoHex, exclHex, ingestCachePath, 2 );
    if( refIng.symbols.empty() && refIng.files.empty() )
    { DEGRADED_PATH_ALERT( "quality: churn-window ref tree ingested empty — churn evidence unavailable" ); return { {}, false }; }

    Snapshot bodyOnly;
    bodyOnly.bodyHashBySym = bodyHashesBySym( refIng, tmpRoot );   // pathQualifiedKey on EVERY side of the churn join (baseline, this ref, working tree, per-node lookup) — a one-sided keying change makes every symbol read as rewritten   // root = tmpRoot → root-relative keys (S2)

    atomicWriteQSnap( qbodyPath, serializeSnapshot( bodyOnly, refSha ) );
    evictOldCacheFamily( cacheDirLadder(), "ripwire-qbody-" + repoHex + "-" + qbExclHex + "-", qbodyPath, 2 );
    return { std::move( bodyOnly.bodyHashBySym ), true };
}

// ─── Y2 (P2) — the qchurn family: memoizes gitmine::gitLogNameOnlyRaw's `git log --name-only` ──────────
// walk (431 ms on a large private C++ corpus; every rich verb — --for, --metrics, --exemplar — pays it once
// per invocation, main.cpp:5392/5404). DECIDED key ("Y2 churn-memo key"):
// (realpath(root), HEAD sha, window-months, gitWindowRefSha). Concretely: `coSince` stands in for
// "window-months" — it IS the window (currently always "18 months ago"), kept as the verbatim string
// rather than an int-parse so any future caller's window text is captured exactly, not just the ones
// shaped like "<N> months ago"; and `gitmine::gitWindowBoundarySha(root, coSince)` is the "gitWindowRefSha"
// component, adapted to THIS window's actual semantics — `coSince` resolves against WALL-CLOCK now() (git's
// approxidate parser), unlike quality.h's own HEAD-epoch-anchored short-horizon window, so a cheap fresh
// boundary probe (see its doc comment) is what makes (headSha, coSince) alone insufficient and the 4th key
// component necessary — without it a cache written yesterday would silently keep serving today's `--for`
// after the "18 months ago" cutoff has quietly moved a day's worth of commits across the boundary.
//
// Committed-history-only (the memo never sees uncommitted state): gitLogNameOnlyRaw is a pure `git log`
// walk — no working-tree inspection at all — and the cached RAW per-commit (epoch, path) stream is resolved
// against the CALLER's current `ing` fresh on every call (never itself cached), so a dirty file added/
// removed since the cache was written still resolves correctly; only the committed-history walk is skipped
// on a hit. Review point (opus): no current rich-verb consumer of gitCoChangeAndChurn threads any
// uncommitted/dirty signal INTO it — main.cpp's two call sites (5392/5404) pass only root/ing/coSince/
// maxFiles/churnMonths/onlyRoot, none of which reflect working-tree diffs; the amp= metric's OTHER half
// (qmetrics.callerCount) comes from the live in-memory graph, not from this function, so folding uncommitted
// state in here would be both unnecessary and (per the decided key) explicitly out of scope.
//
// No excludes component: gitLogNameOnlyRaw never looks at `ing` or --exclude (it is the raw, unresolved git
// history stream) — exclusion is applied later, in resolveCommitStream, against the live `ing`.
// SCHEME 2 (2026-07-31, the H4 round's merge-churn lane): gitLogNameOnlyRaw's walk now carries
// gitmine::kMergeDiffArgs, so the RAW per-commit (epoch, paths) stream it caches has different CONTENT for
// the same (root, HEAD sha, coSince, boundarySha) — a merge commit now names the files it introduced itself.
// None of the four key components can see that, so without this bump a blob written by a merge-blind binary
// would keep serving the old stream to a fixed binary: the exact silent-zero the fix removes, restored by
// cache. Bumping the scheme makes every pre-existing blob a clean miss (deserialize checks it), not a wrong
// answer. This is the qchurn cache's OWN version — not kParserVer, which keys extraction and is untouched.
constexpr std::uint32_t kQChurnCacheScheme = 2;
constexpr char          kQChurnMagic[4]    = { 'Q', 'C', 'H', 'N' };

inline std::string serializeRawCommitStream( const RawCommitStream& raw, const std::string& keyMat )
{
    std::string buf;
    buf.append( kQChurnMagic, 4 );
    qsnapPut( buf, kQChurnCacheScheme );
    qsnapPut( buf, fnv1a64( keyMat ) );
    qsnapPut( buf, std::uint32_t( raw.commits.size() ) );
    for( const RawCommitStream::Commit& c : raw.commits )
    {
        qsnapPut( buf, c.epoch );
        qsnapPut( buf, std::uint32_t( c.paths.size() ) );
        for( const std::string& p : c.paths )
        {
            qsnapPut( buf, std::uint32_t( p.size() ) );
            buf.append( p.data(), p.size() );
        }
    }
    const std::uint64_t sum = fnv1a64( std::string_view( buf.data(), buf.size() ) );
    qsnapPut( buf, sum );
    return buf;
}

inline bool deserializeRawCommitStream( const std::string& blob, const std::string& keyMat, RawCommitStream& out )
{
    if( blob.size() < 4 + sizeof( std::uint32_t ) + sizeof( std::uint64_t ) + sizeof( std::uint64_t ) )
    {
        return false;
    }
    const char*       data    = blob.data();
    const std::size_t bodyLen = blob.size() - sizeof( std::uint64_t );
    std::uint64_t     stored  = 0;
    std::memcpy( &stored, data + bodyLen, sizeof( std::uint64_t ) );
    if( stored != fnv1a64( std::string_view( data, bodyLen ) ) )
    {
        return false; // checksum
    }

    const char* p   = data;
    const char* end = data + bodyLen;
    if( std::memcmp( p, kQChurnMagic, 4 ) != 0 )
    {
        return false;
    }
    p += 4;
    std::uint32_t scheme = 0;
    if( !qsnapGet( p, end, scheme ) || scheme != kQChurnCacheScheme )
    {
        return false;
    }
    std::uint64_t keyHash = 0;
    if( !qsnapGet( p, end, keyHash ) || keyHash != fnv1a64( keyMat ) )
    {
        return false;
    }

    std::uint32_t nCommits = 0;
    if( !qsnapGet( p, end, nCommits ) )
    {
        return false;
    }
    RawCommitStream r;
    r.commits.reserve( nCommits );
    for( std::uint32_t i = 0; i < nCommits; ++i )
    {
        RawCommitStream::Commit c;
        if( !qsnapGet( p, end, c.epoch ) )
        {
            return false;
        }
        std::uint32_t nPaths = 0;
        if( !qsnapGet( p, end, nPaths ) )
        {
            return false;
        }
        c.paths.reserve( nPaths );
        for( std::uint32_t j = 0; j < nPaths; ++j )
        {
            std::uint32_t len = 0;
            if( !qsnapGet( p, end, len ) )
            {
                return false;
            }
            if( end - p < static_cast<std::ptrdiff_t>( len ) )
            {
                return false;
            }
            c.paths.emplace_back( p, len );
            p += len;
        }
        r.commits.push_back( std::move( c ) );
    }
    out = std::move( r );
    return true;
}

// The memoized drop-in for gitCoChangeAndChurn: same signature, same return contract, but the expensive
// `git log --name-only` walk is skipped on a warm hit (blob self-validates against `keyMat`; any mismatch —
// wrong headSha, wrong coSince, drifted boundary, or a corrupt/foreign blob — is a clean miss that falls
// through to a full recompute, never a wrong answer). No git repo / no resolvable HEAD degrades straight to
// the uncached walk (which itself degrades to an empty stream — gitLogNameOnlyRaw's own contract).
inline std::vector<std::vector<std::uint32_t>> gitCoChangeAndChurnCached(
    const std::string& root, const IngestResult& ing, const char* coSince, std::size_t maxFiles,
    unsigned churnMonths = 0, std::vector<std::uint32_t>* outChurn = nullptr,
    std::uint32_t onlyRoot = UINT32_MAX )
{
    if( !hasEnclosingGitRepo( root ) )
    {
        return resolveCommitStream( RawCommitStream{}, ing, maxFiles, churnMonths, outChurn, onlyRoot );
    }

    const std::string headSha = gitHeadSha( root );
    if( headSha.empty() )
    {
        return resolveCommitStream( gitLogNameOnlyRaw( root, coSince ), ing, maxFiles, churnMonths, outChurn, onlyRoot );
    }

    const std::string repoHex  = headSnapRepoHex( root );
    const std::string boundary = gitWindowBoundarySha( root, coSince );   // cheap — no --name-only
    std::string       keyMat   = headSha;
    keyMat.push_back( '\x1f' ); keyMat += coSince;
    keyMat.push_back( '\x1f' ); keyMat += boundary;
    keyMat += "qchurn" + std::to_string( kQChurnCacheScheme );
    const std::string cachePath = shaKeyedCachePath( "qchurn", repoHex, std::string{}, keyMat );

    RawCommitStream raw;
    std::string      blob;
    if( readQSnapBlob( cachePath, blob ) == 1 && deserializeRawCommitStream( blob, keyMat, raw ) )
    {
        return resolveCommitStream( raw, ing, maxFiles, churnMonths, outChurn, onlyRoot );   // warm hit — no walk
    }

    raw = gitLogNameOnlyRaw( root, coSince );                                      // cold — the 431 ms walk
    atomicWriteQSnap( cachePath, serializeRawCommitStream( raw, keyMat ) );         // best-effort; a failed
                                                                                     // write just recomputes next time
    return resolveCommitStream( raw, ing, maxFiles, churnMonths, outChurn, onlyRoot );
}

// `root` = the ingest root exactly as invoked (cfg.rootPath). It is folded into every baseline key via
// baselineCanonId so the written sidecar is root-spelling-independent (S2). g.canonId is still consulted only
// as the "has a canonical id" presence gate — the HASHED key is the root-relative baselineCanonId, never g's.
inline Snapshot computeSnapshot( const IngestResult& ing, const Graph& g, std::string_view root = {} )
{
    Snapshot snap;
    const std::vector<std::uint64_t> topLevelCallees = topLevelCalleeNameHashes( ing );   // W1-S2: dead-kind evidence, built once
    for( NodeId i = 0; i < ing.symbols.size(); ++i )
    {
        if( i >= g.canonId.size() || g.canonId[i].empty() )
        {
            continue;
        }
        const std::uint64_t key = fnv1a64( baselineCanonId( ing, i, root ) );
        const Symbol&       s   = ing.symbols[i];
        // overloads share a canonical id (scope+name) → keep the MAX of each per-symbol metric per id, not
        // last-writer-wins; otherwise a low-metric overload written last makes every later delta report a
        // phantom regression forever (THE trap). Every new per-symbol kind mirrors this MAX exactly.
        { std::uint32_t& slot = snap.ccxBySym[ key ];    slot = std::max( slot, s.ccx ); }
        { std::uint32_t& slot = snap.locBySym[ key ];    slot = std::max( slot, s.loc ); }
        { std::uint32_t& slot = snap.nestBySym[ key ];   slot = std::max( slot, std::uint32_t( s.maxNest ) ); }
        { std::uint32_t& slot = snap.paramsBySym[ key ]; slot = std::max( slot, std::uint32_t( s.params ) ); }
        // THE ONE KIND THAT IS NOT A MAX, and the reason is the MAX itself. Every metric above collapses the
        // overload set to its largest member, which makes the set's CARDINALITY unrecoverable — so removing an
        // overload whose metrics are below the max moves nothing at all, on either side of a comparison, while
        // a call site that used it stops binding. --edit-check reads this count as defs_was to see exactly that
        // (editcheck.h). A COUNT is overload-collision-proof for the opposite reason a MAX is: it is the one
        // number a collision cannot hide. (maskBySym is the other non-MAX kind; it sums for its own reason.)
        { std::uint32_t& slot = snap.defsBySym[ key ];    slot += 1; }
        if( isDeadCandidate( ing, g, i, topLevelCallees ) )
        {
            snap.dead.push_back( key );
        }
        if( isPublicApi( ing, i ) )
        {
            snap.publicApi.push_back( key );
        }
    }
    // duplication baseline = both exact (Type-1/2) AND gapped (Type-3) groups, folded into one set. A
    // Type-3 pair hashes by its sorted member canonIds exactly like an exact group, so introducing a NEW
    // near-clone changes the set ⇒ the delta flags it. Both passes are deterministic → the set is stable.
    for( const CloneGroup& cg : findClones( ing, int( kMinCloneTokens ) ) )
    {
        snap.cloneGroups.push_back( cloneGroupHash( cg, ing, root ) );
    }
    for( const CloneGroup& cg : findClonesType3( ing, int( kMinCloneTokens ) ) )
    {
        snap.cloneGroups.push_back( cloneGroupHash( cg, ing, root ) );
    }

    // §D#4 error-masking baseline: per-canonId count of error-masking constructs (the SUM the delta compares).
    snap.maskBySym = errorMaskCountsBySym( ing, root );

    // §D#4 short-horizon-churn baseline: per-canonId RAW-body hash so the delta detects a rewrite that moved no
    // metric (a literal-only edit). Compared, never bar-checked — presence-or-difference IS the rewrite signal.
    snap.bodyHashBySym = bodyHashesBySym( ing, root );

    std::sort( snap.dead.begin(),        snap.dead.end() );
    std::sort( snap.cloneGroups.begin(), snap.cloneGroups.end() );
    std::sort( snap.publicApi.begin(),   snap.publicApi.end() );
    snap.publicApi.erase( std::unique( snap.publicApi.begin(), snap.publicApi.end() ), snap.publicApi.end() );  // overloads collapse to one canonId
    return snap;
}

inline bool writeBaseline( const Snapshot& s, const std::string& path, std::string_view headSha = {} )
{
    std::ofstream f( path, std::ios::trunc );
    if( !f ) { DEGRADED_PATH_ALERT( "quality: cannot write baseline file" ); return false; }
    // v2 adds the Q1 kinds (loc/nest/params/api). Format is line-oriented + kind-tagged, so a v1 baseline (no
    // loc/nest/params/api lines) reads fine here — readBaseline skips unknown kinds and treats absent kinds as
    // empty; a v2 baseline read by an OLD binary likewise skips lines it doesn't know. Re-baseline after an
    // upgrade (a v1 baseline lacking the new lines makes every current public/large symbol a fresh "was 0"
    // regression by design — that is the intended re-baseline prompt, not a bug).
    // v3 (W1-S2): the body-hash record is `bodyq` — pathQualifiedKey keys, replacing the bare-canonId-keyed
    // `body` record. The TAG is renamed with the keying so the two key spaces can never mix: an old
    // baseline's `body` lines are skipped as unknown here (churn quietly reports nothing until the next
    // re-baseline — precision-first, same degrade as no-git), and an old binary skips `bodyq` symmetrically.
    f << "# ripwire quality baseline v3 — regenerate with --quality-baseline; do not hand-edit\n";
    // STALENESS STAMP: the HEAD commit the baseline was pinned at. --quality-delta compares this to the
    // current HEAD and, if they differ (a baseline left by an abandoned/parallel session, or from before a
    // commit), IGNORES the sidecar and falls back to the git-HEAD auto-baseline instead of reporting a wall
    // of false regressions against a floor that no longer describes this tree. Empty in a non-git root
    // (then the current HEAD is empty too → they match → the deliberately-pinned baseline is honored). The
    // "head" record is an unknown kind to readBaseline, so it is skipped by the snapshot reader on both old
    // and new binaries — only readBaselineHeadSha consults it.
    if( !headSha.empty() )
    {
        f << "head " << headSha << '\n';
    }
    for( const auto& [h, v] : s.ccxBySym )
    {
        f << "ccx " << std::hex << h << std::dec << ' ' << v << '\n';
    }
    for( const auto& [h, v] : s.locBySym )
    {
        f << "loc " << std::hex << h << std::dec << ' ' << v << '\n';
    }
    for( const auto& [h, v] : s.nestBySym )
    {
        f << "nest " << std::hex << h << std::dec << ' ' << v << '\n';
    }
    for( const auto& [h, v] : s.paramsBySym )
    {
        f << "params " << std::hex << h << std::dec << ' ' << v << '\n';
    }
    for( const auto& [h, v] : s.maskBySym )
    {
        f << "mask " << std::hex << h << std::dec << ' ' << v << '\n'; // §D#4 error-masking count
    }
    for( const auto& [h, v] : s.defsBySym )
    {
        f << "defs " << std::hex << h << std::dec << ' ' << v << '\n'; // overload-set CARDINALITY (a count, not a max)
    }
    for( const auto& [h, v] : s.bodyHashBySym )
    {
        f << "bodyq " << std::hex << h << ' ' << v << std::dec << '\n'; // §D#4 short-horizon-churn raw-body hash, pathQualifiedKey-keyed (both hex)
    }
    for( std::uint64_t h : s.cloneGroups )
    {
        f << "clone " << std::hex << h << std::dec << '\n';
    }
    for( std::uint64_t h : s.dead )
    {
        f << "dead " << std::hex << h << std::dec << '\n';
    }
    for( std::uint64_t h : s.publicApi )
    {
        f << "api " << std::hex << h << std::dec << '\n';
    }
    return true;
}

// Returns true only when `path` is a file that actually LOOKS like a baseline. r27 SUSPICION-A, second half:
// this used to return true for a 0-byte (or wholly unrecognizable) file purely because the ifstream opened —
// so a truncated sidecar, a failed write, or an `: > .ripwire_quality_baseline` left behind by a script became
// "a valid baseline in which nothing existed". Combined with the empty-baseline oracle fix in computeDelta,
// that would classify EVERY finding new-symbol and gate nothing, silently. A file that yields no comment
// header, no `head` stamp and no record line is not an empty baseline — it is a broken one; report it absent
// (alerting), and the caller falls back to the git-HEAD auto-baseline, which is the correct floor.
inline bool readBaseline( const std::string& path, Snapshot& out )
{
    std::ifstream f( path );
    if( !f )
    {
        return false;
    }
    std::size_t recognizedLineCount = 0;
    std::string line;
    while( std::getline( f, line ) )
    {
        if( line.empty() )
        {
            continue;
        }
        if( line[0] == '#' ) { ++recognizedLineCount; continue; }     // the format's own header comment counts as structure
        std::istringstream is( line );
        std::string        kind;
        is >> kind;
        // per-symbol MAX metrics: "<kind> <hexhash> <value>". A malformed line degrades + skips (never the
        // silent hash-0 insert). An UNKNOWN kind (e.g. a future record read by this binary) is skipped
        // gracefully so forward/backward baseline versions never crash.
        const auto readValMap = [ & ]( gtl::btree_map<std::uint64_t, std::uint32_t>& m, const char* what )
        { std::uint64_t h = 0; std::uint32_t v = 0; is >> std::hex >> h >> std::dec >> v;
          if( is.fail() ) { DEGRADED_PATH_ALERT( what ); return; } m[h] = v; };
        const auto readSet = [ & ]( std::vector<std::uint64_t>& v, const char* what )
        { std::uint64_t h = 0; is >> std::hex >> h;
          if( is.fail() ) { DEGRADED_PATH_ALERT( what ); return; } v.push_back( h ); };
        // "<kind> <hexkey> <hexval>" — both 64-bit hex (the raw-body-hash map). Malformed → degrade + skip.
        const auto readHashMap = [ & ]( gtl::btree_map<std::uint64_t, std::uint64_t>& m, const char* what )
        { std::uint64_t h = 0, v = 0; is >> std::hex >> h >> v;
          if( is.fail() ) { DEGRADED_PATH_ALERT( what ); return; } m[h] = v; };

        if( kind == "ccx" || kind == "loc" || kind == "nest" || kind == "params" || kind == "mask" || kind == "body" || kind == "clone" || kind == "dead" || kind == "api" || kind == "head" || kind == "defs" )
        {
            ++recognizedLineCount;                                    // structure seen — this file IS a baseline
        }

        if( kind == "ccx" )
        {
            readValMap( out.ccxBySym, "quality: malformed baseline ccx line skipped" );
        }
        else if( kind == "loc" )
        {
            readValMap( out.locBySym, "quality: malformed baseline loc line skipped" );
        }
        else if( kind == "nest" )
        {
            readValMap( out.nestBySym, "quality: malformed baseline nest line skipped" );
        }
        else if( kind == "params" )
        {
            readValMap( out.paramsBySym, "quality: malformed baseline params line skipped" );
        }
        else if( kind == "mask" )
        {
            readValMap( out.maskBySym, "quality: malformed baseline mask line skipped" );
        }
        else if( kind == "defs" )
        {
            readValMap( out.defsBySym, "quality: malformed baseline defs line skipped" );
        }
        else if( kind == "bodyq" )   // v3 tag — a v2 `body` line is bare-canonId-keyed (a different key space) and falls through to the unknown-kind skip
        {
            readHashMap( out.bodyHashBySym, "quality: malformed baseline bodyq line skipped" );
        }
        else if( kind == "clone" )
        {
            readSet( out.cloneGroups, "quality: malformed baseline clone line skipped" );
        }
        else if( kind == "dead" )
        {
            readSet( out.dead, "quality: malformed baseline dead line skipped" );
        }
        else if( kind == "api" )
        {
            readSet( out.publicApi, "quality: malformed baseline api line skipped" );
        }
        // else: unknown kind (older/newer format) → skip silently, do not crash.
    }
    if( recognizedLineCount == 0 )
    {
        DEGRADED_PATH_ALERT( "quality: baseline file is empty/unrecognizable — treating it as absent" );
        out = Snapshot{};
        return false;
    }
    std::sort( out.cloneGroups.begin(), out.cloneGroups.end() );
    std::sort( out.dead.begin(),        out.dead.end() );
    std::sort( out.publicApi.begin(),   out.publicApi.end() );
    return true;
}

// The HEAD sha a baseline was pinned at (the "head <sha>" record written by writeBaseline), or "" if the
// file is absent, predates the staleness stamp, or does not carry a bare object name.
//
// r27 TRUST BOUNDARY (Lane C routing). This value came out of `.ripwire_quality_baseline`, which is a
// COMMITTED file — so on a cloned repo its contents are attacker-influenceable — and it used to flow VERBATIM
// into `gitIsAncestor`'s `git merge-base --is-ancestor '<sha>' …` argv (the old stale-sidecar self-heal; the
// R3 ruling below removed that reachability hop, so today the value only ever reaches a STRING COMPARE against
// `gitHeadSha` inside `selectBaseline` — no argv at all). `shSingleQuote` blocked the shell but not git's own
// option parsing, which is precisely the shape of the P0.1 `--pr-context=--output=FILE` data-loss defect. Only
// `merge-base`'s lack of a file-writing option kept this one benign. The shape check stays regardless: a
// pinned sha is 40/64 hex or it is not a pinned sha, anything else is dropped here, and the empty result
// routes into the documented "unstamped pin is stale" path — i.e. a tampered sidecar is DISTRUSTED, never
// obeyed. `writeBaseline` only ever writes `gitHeadSha`'s output, so no legitimate sidecar is affected.
inline std::string readBaselineHeadSha( const std::string& path )
{
    std::ifstream f( path );
    if( !f )
    {
        return {};
    }
    std::string line;
    while( std::getline( f, line ) )
    {
        if( line.rfind( "head ", 0 ) == 0 )
        {
            std::string sha = line.substr( 5 );
            while( !sha.empty() && ( sha.back() == '\r' || sha.back() == ' ' || sha.back() == '\t' ) )
            {
                sha.pop_back();
            }
            if( isBareCommitSha( sha ) )
            {
                return sha;
            }
            DEGRADED_PATH_ALERT( "quality: baseline head stamp is not a bare commit sha — ignoring the pin" );
            return {};
        }
    }
    return {};
}

// ─── R3 (owner ruling, 2026-07-29) — the ONE baseline-selection seam, shared by BOTH arms ───────────────
//
// `--quality-delta` (main.cpp) and the `quality_delta` MCP verb (mcpverbs.h) each used to decide for
// themselves whether a `.ripwire_quality_baseline` sidecar still describes this tree, and they DISAGREED:
//   • MCP: any pinned sha != current HEAD sha ⇒ STALE (drop it, auto-baseline vs git HEAD).
//   • CLI: stale ONLY when the pinned sha was also UNREACHABLE from HEAD (`gitIsAncestor` false) — the
//     B10.1b "reachable ancestor = a deliberately-pinned floor" carve-out.
// The incident that ended the argument: a PARALLEL session's sidecar, pinned at a commit that happened to be
// an ancestor of this session's HEAD, made the CLI report 31 phantom regressions on a tree the MCP verb (same
// binary, same repo, same second) correctly reported as clean. A floor pinned at some OTHER commit describes
// some OTHER tree; everything committed since then reads as a working-tree regression. The carve-out is
// REVOKED — STRICT sha equality is the rule on both arms, and it lives HERE so there is exactly one copy.
//
// What stays per-arm is POLICY, expressed by `removeStaleFile`, not the staleness test:
//   • CLI passes true  → the stale sidecar is silently UNLINKED (self-heal: the next run sees no file at all
//     rather than rediscovering the same dead pin), marker "git-HEAD (stale sidecar removed)" — but ONLY when
//     the unlink actually landed; a FAILED unlink reports "…ignored" like the read-only arm (see below).
//   • MCP passes false → read-only verb, the file is left alone, marker "git-HEAD (stale sidecar ignored)".
// Both cases are recorded ONLY in the `baseline=`/`"baseline"` marker — no stderr spam, which is the B10.1b
// noise fix that survives the ruling intact.
//
// NON-GIT ROOTS are unaffected: `gitHeadSha` returns "" and an unstamped sidecar's pin reads "", so ""=="" and
// the sidecar is honored — the only floor such a tree can have (there is no HEAD to fall back to).
enum class BaselineSource : std::uint8_t
{
    Sidecar = 0,      // a readable sidecar pinned at the CURRENT HEAD sha (or a non-git root) — honored as the floor
    Stale   = 1,      // a readable sidecar pinned at ANY other sha — dropped (R3); the caller falls back to git HEAD
    Absent  = 2,      // no readable sidecar (missing, or empty/unrecognizable per readBaseline) — caller falls back
};

// The seam's answer. `snapshot` carries the pinned floor and is EMPTY unless `source == Sidecar`; `marker` is
// the `baseline=` value both arms report verbatim (one spelling table, so the two surfaces cannot drift again).
//
// `staleFileRemoved` closes the w1 MED finding: it reports what happened ON DISK, not what the caller asked
// for, so a caller can word its own messages truthfully. It is true only when a stale sidecar is genuinely
// gone after this call — never on the read-only (`removeStaleFile=false`) arm, whose stale file always
// survives, and never when the unlink failed.
struct BaselineSelection
{
    Snapshot       snapshot;                                   // the pinned floor — meaningful only when isSidecarHonored()
    BaselineSource source = BaselineSource::Absent;
    const char*    marker = "git-HEAD";                        // static storage; safe to hold as a bare pointer
    bool           staleFileRemoved = false;                   // Stale only: the unlink LANDED (file gone from disk)

    bool isSidecarHonored() const noexcept { return source == BaselineSource::Sidecar; }
    bool isSidecarStale()   const noexcept { return source == BaselineSource::Stale; }
    // "the stale pin is STILL sitting there" — true on the read-only arm, and on the CLI arm when the unlink
    // failed. This is the predicate a caller's user-facing wording must branch on (never `removeStaleFile`).
    bool isStaleFileOnDisk() const noexcept { return source == BaselineSource::Stale && !staleFileRemoved; }
};

// Read `sidecarPath` and decide whether it is still a valid floor for `root`'s CURRENT HEAD. `removeStaleFile`
// = the CLI's self-heal policy: a best-effort unlink of a stale sidecar. The unlink can FAIL (read-only parent
// dir, permissions, a racing sibling run) and the marker then tells the truth about the DISK rather than the
// intent — "git-HEAD (stale sidecar ignored)", the same honest string the read-only arm uses, because
// ignored-not-removed is exactly what happened — plus one DEGRADED_PATH_ALERT so the plain build can observe
// the degrade. `staleFileRemoved` carries the same fact to the caller, which needs it to word its own fatal
// message (a "no <file>" message is false while the file is still on disk). `sidecarPath` must already be
// ROOT-QUALIFIED by the caller (baselinePath) — this function can DELETE it, and a bare relative name would
// resolve against the process CWD (D1).
inline BaselineSelection selectBaseline( const std::string& root, const std::string& sidecarPath, bool removeStaleFile )
{
    VERIFY( !sidecarPath.empty() );

    BaselineSelection sel;
    if( !readBaseline( sidecarPath, sel.snapshot ) )
    {
        sel.snapshot = Snapshot{};                             // readBaseline already clears on the unrecognizable path; belt and braces
        sel.source   = BaselineSource::Absent;
        sel.marker   = "git-HEAD";
        return sel;
    }

    // R3: STRICT equality, no reachability hop. Note the ordering — gitHeadSha's ~15 ms popen is paid only
    // when a sidecar actually exists, exactly as before.
    const std::string pinnedSha = readBaselineHeadSha( sidecarPath );
    const std::string headSha   = gitHeadSha( root );
    if( pinnedSha == headSha )
    {
        sel.source = BaselineSource::Sidecar;
        sel.marker = "sidecar";
        return sel;
    }

    // Stale. The DEFAULT marker is the read-only truth ("ignored") and the self-heal upgrades it to "removed"
    // only after the unlink is confirmed — so the marker can never claim a removal that did not happen.
    sel.snapshot = Snapshot{};
    sel.source   = BaselineSource::Stale;
    sel.marker   = "git-HEAD (stale sidecar ignored)";
    if( removeStaleFile )
    {
        // best-effort unlink; ROOT-qualified, never a foreign cwd's sidecar. remove() answers true when IT
        // unlinked the file; false with a CLEAR error_code means the path was already gone (a racing sibling
        // run self-healed it first — also "removed" as far as the disk is concerned); false with a SET
        // error_code (read-only parent dir, EACCES, EPERM) means the file SURVIVED this call. The ec is read,
        // not swallowed — the whole point of the finding is that an unread ec let the marker lie.
        std::error_code delEc;
        const bool      didUnlink   = std::filesystem::remove( std::filesystem::path( sidecarPath ), delEc );
        const bool      isStillHere = !didUnlink && static_cast<bool>( delEc );

        if( !isStillHere )
        {
            sel.staleFileRemoved = true;
            sel.marker           = "git-HEAD (stale sidecar removed)";
        }
        // §B12.11: "the baseline still falls back to git HEAD" is only true when this tree HAS a git HEAD —
        // a sidecar can be Stale (pinned at a real, non-empty sha) on a tree where `headSha` is now "" (no
        // git HEAD: not a repo, or git unavailable), and the unqualified claim is then false in the exact
        // state it fires in. The caller's own fatal already gets this right (mcpverbs.h's "no
        // .ripwire_quality_baseline and no git HEAD to auto-compare against"), so no consumer is misled
        // today — but the alert itself should not assert a fallback that does not exist.
        else if( headSha.empty() )
        {
            DEGRADED_PATH_ALERT( "quality: could not unlink the stale .ripwire_quality_baseline sidecar — it STAYS on disk and is merely IGNORED this run; this tree has no git HEAD to fall back to either, so this run has no baseline floor at all" );
        }
        else
        {
            DEGRADED_PATH_ALERT( "quality: could not unlink the stale .ripwire_quality_baseline sidecar — it STAYS on disk and is merely IGNORED this run; the baseline still falls back to git HEAD" );
        }
    }
    return sel;
}

// ─── B10.2d — short-horizon-churn SELF vs AMBIENT split ────────────────────────────────────────────────
//
// The three existing gates (file churn-hot / this diff rewrites the symbol / committed thrash evidence)
// establish that a symbol IS short-horizon churn. This pass answers a NARROWER question about the CURRENT
// uncommitted edit specifically: does it MODIFY pre-existing (committed) lines that were themselves last
// touched inside the churn window (SELF — genuine thrash, keep current severity), or does it only ADD new
// lines / touch lines that predate the window (AMBIENT — the file is hot, but this particular edit isn't
// touching hot content) — sev=minor, facet churn="ambient".
//
// Mechanism: `git diff --unified=0 HEAD -- path` gives zero-context unified-diff hunks
// ("@@ -oldStart[,oldCount] +newStart[,newCount] @@"; git omits a count of 1). A hunk with oldCount==0 is a
// PURE INSERTION — no old line touched, can never itself prove SELF ("the diff only ADDS lines", verbatim).
// For an oldCount>0 hunk whose NEW-side range overlaps the symbol's CURRENT [line, line+loc-1] span (from the
// working-tree ingest — the only line numbers ripwire has), `git blame --porcelain HEAD -L
// oldStart,+oldCount -- path` reports each touched OLD line's real last-commit committer-time; ANY such time
// inside the window ⇒ SELF. No external diff/blame library — parsed by hand (sscanf against the two
// count-optional header forms), consistent with the rest of this file's popen-based git mining.
//
// Degrade-only, in every direction: an unparseable hunk header is skipped (that hunk contributes nothing);
// a failed diff/blame subprocess (no git, no HEAD, path absent at HEAD) yields no output, so the loop simply
// never sets `hot` → AMBIENT, the safe default that never inflates severity on missing evidence. Deterministic
// for a fixed HEAD + fixed working tree (both diff and blame are pure functions of on-disk/committed state).

// Blame `root`'s HEAD over `relPath`'s [startLine, startLine+lineCount-1] and report whether ANY line in that
// range was last committed at or after `windowCutoffEpoch` (the same cutoff basis gitFileCommitCountsInDayWindow
// and gitWindowRefSha use: HEAD's own committer epoch minus the window, never wall-clock).
inline bool gitBlameRangeHasWindowCommit( const std::string& root, const std::string& relPath,
                                          std::uint32_t startLine, std::uint32_t lineCount, std::int64_t windowCutoffEpoch )
{
    if( startLine == 0 || lineCount == 0 )
    {
        return false;
    }
    const std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root )
                          + " blame --porcelain -L " + std::to_string( startLine ) + ",+" + std::to_string( lineCount )
                          + " HEAD -- " + shSingleQuote( relPath ) + " 2>/dev/null";
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        return false;
    }
    bool hot = false;
    char buf[ 512 ];
    while( std::fgets( buf, sizeof( buf ), pipe ) )
    {
        std::string_view ln( buf );
        while( !ln.empty() && ( ln.back() == '\n' || ln.back() == '\r' ) )
        {
            ln.remove_suffix( 1 );
        }
        // a porcelain block-header line: 40 lowercase-hex sha, then " <origLine> <finalLine>[ <numLines>]".
        const bool isHeaderSha = ln.size() >= 40
            && std::all_of( ln.begin(), ln.begin() + 40, []( char c ){ return std::isxdigit( static_cast<unsigned char>( c ) ); } )
            && ( ln.size() == 40 || ln[40] == ' ' );
        if( isHeaderSha )
        {
            continue; // the sha itself carries no date — wait for its committer-time line
        }
        if( ln.rfind( "committer-time ", 0 ) == 0 )
        {
            const std::int64_t t = std::strtoll( std::string( ln.substr( 15 ) ).c_str(), nullptr, 10 );
            if( t >= windowCutoffEpoch ) { hot = true; break; }     // one hot line is enough — short-circuit
        }
    }
    pclose( pipe );
    return hot;
}

// One zero-context unified-diff hunk, in the two coordinate systems the SELF test needs: the OLD-side range
// (what `git blame` is asked about) and the NEW-side range (what the symbol's working-tree line span is
// compared against). SoA is pointless for four u32s read together — this is one cache line either way.
struct DiffHunk
{
    std::uint32_t oldStart = 0;
    std::uint32_t oldCount = 0;
    std::uint32_t newStart = 0;
    std::uint32_t newCount = 0;
};
static_assert( sizeof( DiffHunk ) == 16, "DiffHunk is a 4×u32 POD" );

// P3 (r27) — the RUN-SCOPED hunk memo. `git diff --unified=0 HEAD -- <path>` is a pure function of (HEAD,
// working tree), both FIXED for the life of one --quality-delta call (the code's own section comment says so),
// yet churnEditTouchesHotLine spawned it once PER SYMBOL: a subprocess-shim log showed EIGHT byte-identical
// spawns for a single dirty file. Caller owns the storage (house rule — views/handles at seams, no hidden
// process-global state that a second root or a second MCP request would silently share).
using DiffHunkMemo = HashMap<std::string, std::vector<DiffHunk>>;

// Parse `relPath`'s zero-context hunk headers vs HEAD. Degrade-only: no git / no HEAD / path absent at HEAD →
// an EMPTY vector, which the caller reads as "no evidence" → AMBIENT (never inflates severity).
inline std::vector<DiffHunk> gitDiffHunksVsHead( const std::string& root, const std::string& relPath )
{
    std::vector<DiffHunk> hunks;
    const std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root )
                          + " diff --unified=0 --no-color HEAD -- " + shSingleQuote( relPath ) + " 2>/dev/null";
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe ) { DEGRADED_PATH_ALERT( "quality: churn hunk diff could not be spawned" ); return hunks; }

    char buf[ 4096 ];
    while( std::fgets( buf, sizeof( buf ), pipe ) )
    {
        if( buf[0] != '@' || buf[1] != '@' )
        {
            continue; // only hunk-header lines matter here
        }
        int oldStart = 0, oldCount = 1, newStart = 0, newCount = 1;
        if( std::sscanf( buf, "@@ -%d,%d +%d,%d @@", &oldStart, &oldCount, &newStart, &newCount ) == 4 ) {}
        else if( std::sscanf( buf, "@@ -%d,%d +%d @@", &oldStart, &oldCount, &newStart ) == 3 ) { newCount = 1; }
        else if( std::sscanf( buf, "@@ -%d +%d,%d @@", &oldStart, &newStart, &newCount ) == 3 ) { oldCount = 1; }
        else if( std::sscanf( buf, "@@ -%d +%d @@", &oldStart, &newStart ) == 2 ) { oldCount = 1; newCount = 1; }
        else
        {
            continue; // malformed/unexpected header — skip (degrade per-hunk)
        }
        if( oldStart < 0 || oldCount < 0 || newStart < 0 || newCount < 0 )
        {
            continue; // git never emits these; refuse rather than wrap
        }

        hunks.push_back( DiffHunk{ std::uint32_t( oldStart ), std::uint32_t( oldCount ),
                                   std::uint32_t( newStart ), std::uint32_t( newCount ) } );
    }
    pclose( pipe );
    return hunks;
}

// Memoized accessor: one `git diff` spawn per PATH per run, not per symbol. A path with no hunks memoizes the
// empty vector too, so a repeatedly-queried clean path costs one spawn, not N.
inline const std::vector<DiffHunk>& diffHunksMemoized( DiffHunkMemo& memo, const std::string& root, const std::string& relPath )
{
    const auto it = memo.find( relPath );
    if( it != memo.end() )
    {
        return it->second;
    }
    return memo.emplace( relPath, gitDiffHunksVsHead( root, relPath ) ).first->second;
}

// Does the CURRENT uncommitted edit to `relPath` (vs HEAD) modify any pre-existing line that overlaps the
// symbol's current [symStart, symStart+symLoc-1] span AND was itself last committed inside the window? See the
// section comment above for the full mechanism. `symStart`/`symLoc` come straight from the working-tree
// Symbol (s.line / s.loc). `memo` is the caller-owned per-run hunk cache (P3).
inline bool churnEditTouchesHotLine( DiffHunkMemo& memo, const std::string& root, const std::string& relPath,
                                     std::uint32_t symStart, std::uint32_t symLoc, std::int64_t windowCutoffEpoch )
{
    if( symStart == 0 )
    {
        return false;
    }
    const std::uint32_t symEnd = symStart + ( symLoc > 0 ? symLoc - 1 : 0 );

    for( const DiffHunk& h : diffHunksMemoized( memo, root, relPath ) )
    {
        if( h.oldCount == 0 )
        {
            continue; // pure insertion — never SELF by itself ("adds lines")
        }

        // Overlap test in NEW-file (working-tree) coordinates, matching the symbol's own line numbers.
        //
        // r27 PURE-DELETION FIX: a deletion hunk is `@@ -o,c +n,0 @@` — it has NO new-side lines, and git
        // reports n = the line AFTER which the deleted text sat. Computing the end as `n + newCount - 1`
        // collapsed that to the EMPTY range [n,n], which considers the line BEFORE the seam and never the line
        // AFTER it. That asymmetry has no justification in the diff format: the edit's footprint is the SEAM
        // between new lines n and n+1, and BOTH adjacent lines are equally "next to what was removed". Under
        // the old collapse a deletion at a symbol's leading edge (n = symStart-1) fell entirely before the
        // symbol, was never blamed, and the row silently downgraded from churn="self" (major, GATES) to
        // churn="ambient" (sev=minor, does not gate) — a gating finding lost to an off-by-one.
        // HONESTY, measured (r27): the asymmetry is real, but no fixture was found in which fixing it flips an
        // emitted row — the churn kind's gate 2 requires the symbol's own raw body to have changed, which in
        // practice always produces a second hunk that already overlaps. So this is a correctness fix to the
        // hunk math with a conservative blast radius, not a behavior change with a demonstrated before/after.
        // It cannot manufacture noise on its own either: SELF still requires `git blame` to prove the deleted
        // lines were themselves last committed inside the churn window.
        const std::uint32_t hunkNewStart = h.newStart;
        const std::uint32_t hunkNewEnd   = ( h.newCount > 0 ) ? hunkNewStart + h.newCount - 1 : hunkNewStart + 1;
        if( hunkNewEnd < symStart || hunkNewStart > symEnd )
        {
            continue; // this hunk falls outside the symbol
        }

        if( gitBlameRangeHasWindowCommit( root, relPath, h.oldStart, h.oldCount, windowCutoffEpoch ) )
        {
            return true;                                             // one hot line is enough — short-circuit
        }
    }
    return false;
}

// one reported regression (something the change made WORSE).
struct Regression
{
    std::string   kind;   // "complexity" | "duplication" | "dead-code" | "verbosity" | "nesting" | "params" | "api-surface"
                          //   | "error-masking" | "short-horizon-churn" | "new-clone-of-reused-helper" (§D#4)
    std::string   sym;    // canonical id (or, for duplication, the space-joined member ids)
    std::uint32_t was = 0;
    std::uint32_t now = 0;
    std::uint64_t key = 0;        // STABLE identity for the ack ratchet: the per-symbol baselineCanonId hash, or the clone-group hash (root-spelling-independent, never display text).
                                  //   short-horizon-churn rows carry pathQualifiedKey instead (W1-S2): a bare canonId folds scope-less same-named symbols across files, so one ack would suppress — and one finding would name — the WRONG file's symbol
    bool          isMinor = false;// materiality tier: true = below the kind's minor-delta bar → reported sev="minor", does not gate exit 2
    std::string   facet;          // B10.2 — optional classification facet (attribute NAME chosen by the kind in main.cpp):
                                  //   short-horizon-churn: "self" | "ambient"; api-surface: "new-symbol" | "contract-change". Empty = no facet.
    bool          isNewSymbol = false;// r26 ORIGIN axis: true = the finding exists ONLY because the code is new (emitted origin="new-symbol",
                                  //   counted in new-symbol=, never gates); false = preexisting-worse. See the ORIGIN block in computeDelta.
    // P2.5 (r27) — the LOCATOR. `sym` is a canonical id whose display tail is often a bare, one-letter local
    // (`sym="cc"`), so the report the agent is told to run at every "done" moment named findings it could not
    // grep for. path is ROOT-RELATIVE (the same relForHash spelling every other sidecar key uses), line is the
    // defining symbol's 1-based start line; together they are emitted as p="path:line". For the two clone
    // kinds (a relation over a member SET, not one symbol) this is the member whose canonId sorts FIRST — the
    // same member that leads the members= list, so the two agree. Empty path = no locator available (a symbol
    // with no file, or a degraded lookup) → the attribute is simply omitted, never faked.
    std::string   path;
    std::uint32_t line = 0;

    // P0.3 (r27) — ZERO MAGNITUDE. A finding with was == now == 0 carries no magnitude at all, so the ack
    // ratchet's `now <= ackNow` test degenerates to `0 <= 0` = "always suppressed" — a permanent blank check,
    // which the ack contract explicitly promises never to be. See ackKindToken below for the fix.
    bool isZeroMagnitude() const noexcept { return was == 0 && now == 0; }
};

// §P6.6: `sym` is a canonical id `path::scope::name` (resolve.h::canonicalId) whose PATH segment is
// `ing.files[...]` AS THE CALLER SPELLED THE ROOT — an absolute root then makes sym= carry a 150+ char
// absolute prefix, while `path` above is already root-relative (relForHash, the same spelling every other
// sidecar key uses). Normalize sym's path segment the same way, for DISPLAY ONLY: this must never touch
// canonId itself, or Regression::key (the ack-ratchet identity) — see arch.h's relForHash comment, the S2
// trap: canonId stays load-bearing for resolution far beyond any one report. Both main.cpp's --json and XML
// quality-delta emitters call this so the two stay in lockstep.
//
// A duplication/new-clone-of-reused-helper row's sym is a space-joined member LIST — normalize each member
// independently. A bare name (free function, scope-less — canonicalId's own degrade case) has no "::" and
// passes through unchanged.
inline std::string displaySym( const std::string& sym, std::string_view root )
{
    std::string      out;  out.reserve( sym.size() );
    std::size_t      tokenStart = 0;
    while( tokenStart <= sym.size() )
    {
        const std::size_t      sp    = sym.find( ' ', tokenStart );
        const std::string_view token = std::string_view( sym ).substr( tokenStart, sp == std::string::npos ? std::string::npos : sp - tokenStart );
        const std::size_t      sep   = token.find( "::" );   // path never contains "::" — only scope/name do
        if( sep != std::string_view::npos ) { out += relForHash( token.substr( 0, sep ), root ); out += token.substr( sep ); }
        else
        {
            out += token;
        }
        if( sp == std::string::npos )
        {
            break;
        }
        out += ' ';
        tokenStart = sp + 1;
    }
    return out;
}

// ─── Signal-to-noise round: the per-finding ACK RATCHET ────────────────────────────────────────────────
//
// `.ripwire_quality_acks` — one line per deliberately-accepted finding:
//     ack <kind> <16-hex identity key> <acked magnitude> <reason to end of line>
// --quality-ack[=REASON] merges every finding the CURRENT delta reports into this file; --quality-delta then
// suppresses a finding whose (kind, key) is acked at a magnitude ≥ its current `now` — and RE-REPORTS it the
// moment it worsens past that (the ratchet: an ack accepts a finding AT its acked size, never a blank check).
// Suppression is always honest: the report header carries acked="N". The map key is "<kind> <16hex>" (a plain
// string, collision-free, sorted) so the rewritten file is byte-stable. Unknown/malformed lines degrade+skip
// exactly like readBaseline. Deliberately NOT pinned to a HEAD sha: an acked finding ("fixture, dead by
// design") stays accepted across commits until the file is edited or the finding worsens.
struct AckRecord
{
    std::string   kind;
    std::uint64_t key    = 0;
    std::uint32_t ackNow = 0;     // the magnitude the finding was accepted at (the ratchet floor)
    std::string   reason;
};

inline std::string ackMapKey( const std::string& kind, std::uint64_t key )
{
    char hex[ 20 ];
    std::snprintf( hex, sizeof( hex ), "%016llx", static_cast<unsigned long long>( key ) );
    return kind + " " + hex;
}

// ─── P0.3 (r27) — ZERO-MAGNITUDE ACKS ARE NOT A BLANK CHECK ────────────────────────────────────────────
//
// THE BUG. `applyAckRatchet` suppresses on `r.now <= ackNow`. The api-surface tier-A push emits was=now=0 for
// BOTH `origin="new-symbol"` (additive surface, sev=minor, NEVER gates) and `surface="contract-change"` (a
// preexisting symbol flipped private → public: major, GATES) under the SAME (kind, key) ack identity. So
// acking the harmless new-code rows — which `--quality-ack` does wholesale, and which is 209 of this repo's
// own 402 committed ack lines — means the later, genuine private→public flip on that same symbol hits
// `0 <= 0` and is suppressed FOREVER. `dead-code` (always now=0, 6 more lines) has the identical shape. That
// is precisely the "an ack accepts a finding AT its acked size, never a blank check" contract, violated.
//
// THE FIX. A zero-magnitude finding has no magnitude to ratchet on, so it must ack on IDENTITY + ORIGIN
// instead: the ack token for such a row carries `:new-symbol` or `:preexisting`, making the two rows two
// different acks. An ack recorded against the new-symbol row therefore cannot suppress the contract-change
// row. Findings WITH a magnitude (complexity, verbosity, duplication, an api-surface param-arity change, …)
// are untouched — their ratchet already works, and splitting them would churn the sidecar for no gain.
//
// MIGRATION OF THE 215 ALREADY-COMMITTED ROWS (documented, not silent — see also readAckRecords):
// a legacy BARE token (`api-surface`/`dead-code`, no `:`) with ackNow == 0 is read as the `:new-symbol`
// variant and rewritten in that spelling by the next `--quality-ack`. Rationale, and why this direction:
//   * ackNow == 0 ⟺ zero-magnitude — every other kind's `now` is a count/tokens/fan-in strictly above its bar,
//     so the discriminator is exact, not a guess.
//   * The overwhelming majority of those rows WERE new-symbol rows (that is the class --quality-ack sweeps up).
//     Keeping them preserves their real meaning: the additive-surface noise stays suppressed.
//   * The rows we cannot distinguish — a legacy ack that really was recorded against a contract-change — are
//     re-surfaced and GATE again. That is the FAIL-CLOSED direction: a re-surfaced finding costs one honest
//     re-ack with a reason; a silently-kept one is the bug being fixed. Never resolve an ambiguity in favour
//     of "green".
// The rewrite is visible in `git diff .ripwire_quality_acks` — the ack file is committed precisely so a
// change in what is suppressed is reviewable.
inline std::string ackKindToken( const std::string& kind, bool isZeroMagnitude, bool isNewSymbol )
{
    if( !isZeroMagnitude )
    {
        return kind;
    }
    return kind + ( isNewSymbol ? ":new-symbol" : ":preexisting" );
}

inline std::string ackKindToken( const Regression& r )
{
    return ackKindToken( r.kind, r.isZeroMagnitude(), r.isNewSymbol );
}

// Read side of the migration above: a bare (colon-free) kind token acked at magnitude 0 is a pre-r27
// zero-magnitude ack → normalize it to the `:new-symbol` variant so it keeps suppressing exactly the class it
// was almost certainly recorded for, and so writeAckRecords self-heals the file into the new spelling.
inline std::string normalizeLegacyAckKind( const std::string& kind, std::uint32_t ackNow )
{
    if( ackNow != 0 || kind.find( ':' ) != std::string::npos )
    {
        return kind;
    }
    return kind + ":new-symbol";
}

// B10.1c — MERGE-FRIENDLY canonical format: one ack per line, `ackMapKey` (kind+hex) order on every write (a
// gtl::btree_map iterates sorted by construction, so writeAckRecords below is ALWAYS sorted — never
// last-writer-order). Two independent sessions each appending DIFFERENT new findings to an already-sorted
// file produce two pure, non-overlapping insertions — exactly what a 3-way text merge resolves cleanly
// without a conflict; only two sessions racing to CREATE the file from nothing is a true add/add conflict
// (unavoidable by file format alone — see PLAN's evidence). The reader is tolerant of anything a sorted-write
// invariant does NOT itself guarantee: lines out of order (e.g. hand-edited, or merged from an older,
// unsorted revision), CRLF line endings (a file merged in from a Windows checkout), and blank/comment lines
// anywhere — so a round-trip (read whatever is on disk → merge in new findings → write) always SELF-HEALS the
// file back to canonical sorted order regardless of what shape it arrived in. Grammar (also the header
// line below): `ack <kind> <16-hex-key> <ackNow> <reason to end of line>`.
//
// D2 — DUPLICATE (kind,key) LINES MERGE BY max(ackNow), never last-wins. The sorted-write invariant
// above means a file THIS binary wrote never contains a duplicate key, but the reader must still tolerate one
// that arrived some other way (a hand-edit, an unlucky 3-way merge of two divergent ack files, an older
// binary's output) — and a naive `out[key] = ...` overwrite lets whichever duplicate happens to sort LAST in
// the file silently LOWER an already-accepted ratchet floor (a finding legitimately acked at magnitude 20
// reappears as a fresh regression because a stray "acked at 1" line follows it). The floor may only ever go
// up via a duplicate, so keep the max — same MAX-not-last discipline computeSnapshot already uses for
// per-symbol metrics (see the comment there). The reason string travels with whichever record wins the max.
inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path )
{
    gtl::btree_map<std::string, AckRecord> out;
    std::ifstream f( path );
    if( !f )
    {
        return out;
    }
    std::string line;
    while( std::getline( f, line ) )
    {
        while( !line.empty() && ( line.back() == '\r' || line.back() == '\n' ) )
        {
            line.pop_back(); // CRLF tolerance (merged-in Windows checkout)
        }
        if( line.empty() || line[0] == '#' )
        {
            continue;
        }
        std::istringstream is( line );
        std::string tag, kind;
        std::uint64_t key = 0;
        std::uint32_t ackNow = 0;
        is >> tag >> kind >> std::hex >> key >> std::dec >> ackNow;
        if( tag != "ack" || is.fail() ) { DEGRADED_PATH_ALERT( "quality: malformed ack line skipped" ); continue; }
        kind = normalizeLegacyAckKind( kind, ackNow );               // P0.3 migration — see the note at ackKindToken
        std::string reason;
        std::getline( is, reason );
        while( !reason.empty() && reason.front() == ' ' )
        {
            reason.erase( reason.begin() );
        }
        while( !reason.empty() && reason.back() == '\r' )
        {
            reason.pop_back(); // CRLF tolerance on the trailing field too
        }

        const std::string mapKey = ackMapKey( kind, key );
        const auto        it     = out.find( mapKey );
        if( it == out.end() || ackNow > it->second.ackNow )
        { // D2: max(ackNow) wins, not last-line
            out[ mapKey ] = AckRecord{ kind, key, ackNow, reason };
        }
    }
    return out;
}

inline bool writeAckRecords( const std::string& path, const gtl::btree_map<std::string, AckRecord>& acks )
{
    std::ofstream f( path, std::ios::trunc );
    if( !f ) { DEGRADED_PATH_ALERT( "quality: cannot write acks file" ); return false; }
    f << "# ripwire quality acks v1 — written by --quality-ack; a finding stays suppressed until it worsens past its acked magnitude\n";
    f << "# format: ack <kind> <16-hex-key> <ackNow> <reason to end of line> — one per line, kept SORTED by (kind,key) on every write (merge-friendly)\n";
    for( const auto& [ mapKey, r ] : acks )                       // btree order → byte-stable, always-sorted file (the merge-friendly guarantee)
    {
        char hex[ 20 ];
        std::snprintf( hex, sizeof( hex ), "%016llx", static_cast<unsigned long long>( r.key ) );
        f << "ack " << r.kind << ' ' << hex << ' ' << r.ackNow << ' ' << ( r.reason.empty() ? "(no reason given)" : r.reason ) << '\n';
    }
    return true;
}

// Drop every regression already acked at a magnitude ≥ its current `now`; return how many were suppressed
// (the honest acked="N" header count). A worsened finding (now > acked floor) survives — the ratchet.
// P0.3: the lookup token is ackKindToken, not the bare kind — a ZERO-magnitude finding acks on identity +
// ORIGIN, so an ack taken against the never-gating new-symbol row can no longer suppress the gating
// contract-change row for the same symbol.
inline std::size_t applyAckRatchet( std::vector<Regression>& regs, const gtl::btree_map<std::string, AckRecord>& acks )
{
    if( acks.empty() )
    {
        return 0;
    }
    const std::size_t before = regs.size();
    regs.erase( std::remove_if( regs.begin(), regs.end(),
                                [ & ]( const Regression& r )
                                {
                                    const auto it = acks.find( ackMapKey( ackKindToken( r ), r.key ) );
                                    return it != acks.end() && r.now <= it->second.ackNow;
                                } ),
                regs.end() );
    return before - regs.size();
}

// ─── L2 — STALE-ACK DISCLOSURE ─────────────────────────────────────────────────────────────────────────
//
// `.ripwire_quality_acks` has acquisition (--quality-ack) and a worsen-past-acked-magnitude ratchet
// (applyAckRatchet above) but no retirement surface: an ack whose target symbol was deleted, or whose
// finding kind no longer fires on a symbol that survived, sits in the ledger forever, invisibly. A past
// round hand-retired 109 such dead rows out of this repo's own committed acks file — a whole session of
// manual audit for a question the tool could answer in one pass. The in-repo precedent for exactly this
// shape is --notes: a note whose target no longer resolves is flagged dangling="1" against the LIVE
// symbol/file set (main.cpp's --notes handler). This mirrors that pattern for acks.
//
// The wrinkle notes does not have: an ack's identity is a ONE-WAY HASH (`ackMapKey` = kind + hex(key)),
// never the plain canonId, so there is no string to re-resolve — the check has to go the other direction,
// hashing every CURRENT candidate and asking whether the acked key is still among them. `Snapshot` already
// carries exactly the per-kind key spaces needed, computed once via computeSnapshot on the WORKING TREE
// (never the regression baseline — staleness asks "does this still describe reality", not "would it
// regress again relative to some floor"):
//   complexity/verbosity/nesting/params — ccxBySym/locBySym/nestBySym/paramsBySym. locBySym is the
//     existence oracle (computeSnapshot populates it for EVERY symbol with a canonId, the same fact
//     computeDelta's r26 origin axis leans on); if the key survives, the matching metric's CURRENT value
//     decides whether it still crosses that kind's bar.
//   dead-code / api-surface — locBySym for existence, membership in the current `dead` / `publicApi` set
//     for whether the state the finding named is still true right now.
//   error-masking — locBySym for existence, `maskBySym[key] > 0` for whether a masking construct is still
//     there (maskBySym only carries symbols with at least one hit — see errorMaskCountsBySym — so absence
//     IS zero, not "unknown").
//   duplication / new-clone-of-reused-helper — the ack key IS a member-set hash (cloneGroupHash), not a
//     single symbol's key, so there is no one "target" to test existence of; only whether that EXACT group
//     still clones today is checkable. Its absence is reported finding-gone, never target-gone: decomposing
//     the hash back to its members is not possible from the ledger alone, and this project reports floors,
//     not guesses (CLAUDE.md's honesty contract) — claiming a symbol is "gone" with no evidence for it
//     would be exactly the kind of guess that contract forbids.
//   short-horizon-churn — the key is pathQualifiedKey, a third space; bodyHashBySym (populated for every
//     symbol with a real body) is its existence oracle. Whether the churn condition itself still holds
//     needs a HISTORICAL reference this function does not have, so a churn ack whose key still resolves to
//     a body is left alone: reporting finding-gone without evidence would be the same forbidden guess.
// An unrecognized kind (a future addition, or a hand-edited line) is left unclassified rather than guessed
// — same "degrade, do not fabricate" rule readAckRecords already applies to a malformed line.
//
// Deterministic by construction: `acks` is a gtl::btree_map, so iterating it is already (kind,key) sorted
// — the emitted row order needs no extra sort.
enum class StaleAckWhy : std::uint8_t
{
    TargetGone,   // no symbol/group this key could refer to exists at HEAD/current
    FindingGone,  // the target still exists, but no finding of the acked kind currently fires on it
};

struct StaleAck
{
    std::string  kind;          // the RAW ack kind token, including any :new-symbol/:preexisting facet (P0.3)
    std::uint64_t key = 0;
    StaleAckWhy  why  = StaleAckWhy::TargetGone;
};

// One per-kind oracle, each returning nullopt for "not stale" — split out so the dispatcher below reads as
// a flat kind->oracle table instead of one large branch-and-compute body (that shape was the round's own
// first draft, at ccx=64: --quality-delta flagged it against itself, which is the gate this file's own
// contract asks for — see the L2 header comment above for the per-kind RATIONALE these implement).
//
// complexity/verbosity/nesting/params share one shape: locBySym is the existence oracle, then the kind's
// own metric map decides whether it still crosses that kind's bar.
inline std::optional<StaleAckWhy> staleForMetricKind( std::string_view base, std::uint64_t key, const Snapshot& snap )
{
    if( snap.locBySym.find( key ) == snap.locBySym.end() )
    {
        return StaleAckWhy::TargetGone;
    }
    const gtl::btree_map<std::uint64_t, std::uint32_t>* m
        = ( base == "complexity" ) ? &snap.ccxBySym
        : ( base == "verbosity" )  ? &snap.locBySym
        : ( base == "nesting" )    ? &snap.nestBySym
                                    : &snap.paramsBySym;
    const std::uint32_t bar
        = ( base == "complexity" ) ? kCcxBar
        : ( base == "verbosity" )  ? kLocBar
        : ( base == "nesting" )    ? kNestBar
                                    : kParamBar;
    const auto           it  = m->find( key );
    const std::uint32_t  now = ( it == m->end() ) ? 0u : it->second;
    return ( now <= bar ) ? std::optional<StaleAckWhy>( StaleAckWhy::FindingGone ) : std::nullopt;
}

// dead-code / api-surface share one shape too: locBySym for existence, membership in the CURRENT set
// (`dead` / `publicApi`) for whether the state the finding named is still true right now.
inline std::optional<StaleAckWhy> staleForSetMembership( std::uint64_t key, const Snapshot& snap, const std::vector<std::uint64_t>& liveSet )
{
    if( snap.locBySym.find( key ) == snap.locBySym.end() )
    {
        return StaleAckWhy::TargetGone;
    }
    return std::binary_search( liveSet.begin(), liveSet.end(), key ) ? std::nullopt : std::optional<StaleAckWhy>( StaleAckWhy::FindingGone );
}

inline std::optional<StaleAckWhy> staleForErrorMasking( std::uint64_t key, const Snapshot& snap )
{
    if( snap.locBySym.find( key ) == snap.locBySym.end() )
    {
        return StaleAckWhy::TargetGone;
    }
    const auto it = snap.maskBySym.find( key );   // absent or zero — maskBySym only carries symbols with >=1 hit
    return ( it == snap.maskBySym.end() || it->second == 0 ) ? std::optional<StaleAckWhy>( StaleAckWhy::FindingGone ) : std::nullopt;
}

// duplication / new-clone-of-reused-helper: the key IS a member-set hash, not one symbol's key, so a miss
// here is always finding-gone — never target-gone (decomposing the hash back to its members is not
// possible from the ledger alone; see the L2 header comment for why that is the honest classification).
inline std::optional<StaleAckWhy> staleForCloneKind( std::uint64_t key, const Snapshot& snap )
{
    return std::binary_search( snap.cloneGroups.begin(), snap.cloneGroups.end(), key ) ? std::nullopt : std::optional<StaleAckWhy>( StaleAckWhy::FindingGone );
}

// short-horizon-churn: bodyHashBySym (pathQualifiedKey-keyed) is its existence oracle; whether the churn
// condition itself still holds needs a historical reference this function does not have, so a surviving
// key is left alone rather than guessed finding-gone (see the L2 header comment).
inline std::optional<StaleAckWhy> staleForChurn( std::uint64_t key, const Snapshot& snap )
{
    return ( snap.bodyHashBySym.find( key ) == snap.bodyHashBySym.end() ) ? std::optional<StaleAckWhy>( StaleAckWhy::TargetGone ) : std::nullopt;
}

inline std::vector<StaleAck> computeStaleAcks( const gtl::btree_map<std::string, AckRecord>& acks, const Snapshot& snap )
{
    std::vector<StaleAck> out;
    for( const auto& [ mapKey, rec ] : acks )
    {
        (void) mapKey; // the (kind,key) it was derived from — rec already carries both fields
        // The ':new-symbol' / ':preexisting' suffix (see ackKindToken) is an ORIGIN facet on a
        // zero-magnitude finding, not a different finding kind — strip it before dispatching so
        // "dead-code:preexisting" and "dead-code:new-symbol" both resolve to the one dead-code oracle.
        const std::size_t      colon = rec.kind.find( ':' );
        const std::string_view base  = ( colon == std::string::npos ) ? std::string_view( rec.kind )
                                                                       : std::string_view( rec.kind ).substr( 0, colon );

        std::optional<StaleAckWhy> why;
        if( base == "complexity" || base == "verbosity" || base == "nesting" || base == "params" )
        {
            why = staleForMetricKind( base, rec.key, snap );
        }
        else if( base == "dead-code" )
        {
            why = staleForSetMembership( rec.key, snap, snap.dead );
        }
        else if( base == "api-surface" )
        {
            why = staleForSetMembership( rec.key, snap, snap.publicApi );
        }
        else if( base == "error-masking" )
        {
            why = staleForErrorMasking( rec.key, snap );
        }
        else if( base == "duplication" || base == "new-clone-of-reused-helper" )
        {
            why = staleForCloneKind( rec.key, snap );
        }
        else if( base == "short-horizon-churn" )
        {
            why = staleForChurn( rec.key, snap );
        }
        // an unrecognized kind (a future addition, or a hand-edited line) is left unclassified rather than
        // guessed — same "degrade, do not fabricate" rule readAckRecords already applies to a malformed line.
        if( why.has_value() )
        {
            out.push_back( { rec.kind, rec.key, *why } );
        }
    }
    return out;
}

// The XML `<sa kind= key= why=/>` rows and their JSON `"sa":[...]` sibling, extracted here so neither
// caller repeats the loop: main.cpp's runQualityDelta (already well over budget before this feature) would
// otherwise carry the branch twice (XML and JSON), and mcpverbs.h's qualityDeltaJson is a THIRD site that
// needs the identical JSON shape (test/mcpclidiffcheck.sh LENS2 pins the CLI and MCP surfaces to the same
// key set). XML's kind is never escaped, matching the existing `<r kind=…>` regression rows (main.cpp
// prints those unescaped too) — both are drawn from the closed kind vocabulary, so a hand-edited ack file
// can only make it a different plain token, never markup. JSON's kind IS escaped (rw::jsonesc::escapeMcp,
// the same posture serialize.h's jsonStr already uses for --json): unlike an XML attribute, one stray `"`
// in a hand-edited ack line would otherwise emit syntactically invalid JSON, not just an ugly value.
inline std::string staleAcksXml( const std::vector<StaleAck>& staleAcks )
{
    std::string out;
    for( const StaleAck& sa : staleAcks )
    {
        char hex[ 20 ];
        std::snprintf( hex, sizeof( hex ), "%016llx", static_cast<unsigned long long>( sa.key ) );
        out += "<sa kind=\"";
        out += sa.kind;
        out += "\" key=\"";
        out += hex;
        out += "\" why=\"";
        out += ( sa.why == StaleAckWhy::TargetGone ? "target-gone" : "finding-gone" );
        out += "\"/>";
    }
    return out;
}

inline std::string staleAcksJsonArray( const std::vector<StaleAck>& staleAcks )   // returns `"sa":[...]`, ready to splice in
{
    std::string out = "\"sa\":[";
    bool        first = true;
    for( const StaleAck& sa : staleAcks )
    {
        if( !first )
        {
            out += ",";
        }
        first = false;
        char hex[ 20 ];
        std::snprintf( hex, sizeof( hex ), "%016llx", static_cast<unsigned long long>( sa.key ) );
        out += "{\"kind\":\"";
        out += rw::jsonesc::escapeMcp( sa.kind );
        out += "\",\"key\":\"";
        out += hex;
        out += "\",\"why\":\"";
        out += ( sa.why == StaleAckWhy::TargetGone ? "target-gone" : "finding-gone" );
        out += "\"}";
    }
    out += "]";
    return out;
}

// current state vs baseline → only what got worse.
//   complexity/verbosity/nesting/params: a symbol the change pushed/kept OVER the bar (now > baseline AND
//     now > BAR; a NEW symbol counts with baseline 0). Each is a per-symbol metric whose overloads share a
//     canonId → aggregated to the per-id MAX on BOTH sides (mirrors computeSnapshot) so a low-metric overload
//     can never manufacture a phantom regression (THE trap — do not reintroduce it).
//   duplication: a clone group whose member-set is not in the baseline.
//   dead-code: a dead-candidate not in the baseline.
//   api-surface: a PUBLIC/exported symbol (isPublicApi) whose canonId is not in the baseline set (contract
//     drift — new exported surface; §1c 2606.21804). A SET signal → overload-collision-proof by construction.
// `root` = the ingest root exactly as invoked; every baseline COMPARISON key is the root-relative
// baselineCanonId (S2) so a committed baseline matches regardless of how the root was spelled on either run.
// The human-readable `Regression.sym` keeps the FULL g.canonId (display only — never hashed/compared), so the
// reported symbol string and the emitted `id=` remain byte-identical to before.
// `excludes`/`maxFileBytes` mirror the working-tree ingest config and are threaded into the churn kind's
// window-ref snapshot (computeWindowRefBodyHashes) so both sides of the evidence compare see one file set —
// the same A4-F5 discipline computeHeadSnapshot follows. Defaults keep the MCP call site unchanged.
inline std::vector<Regression> computeDelta( const IngestResult& ing, const Graph& g, const Snapshot& base,
                                             std::string_view root = {},
                                             const std::vector<std::string>& excludes = {},
                                             std::size_t maxFileBytes = kDefaultMaxFileBytes )
{
    std::vector<Regression> regs;

    // A4-P10 — HOIST the per-symbol baseline key. `fnv1a64( baselineCanonId(...) )` materializes a canonical-id
    // string + hashes it; the passes below (4 metric kinds × 2 loops each, dead, api-surface, error-masking,
    // short-horizon-churn) each recomputed it per symbol → ~8× redundant string builds per symbol per call.
    // Compute it ONCE here (0 for a symbol with no canonId — those are skipped by every pass anyway) and let the
    // passes index `keyByNode[i]`. Byte-identical output: same hash values, just computed once instead of eight.
    std::vector<std::uint64_t> keyByNode( ing.symbols.size(), 0 );
    for( NodeId i = 0; i < ing.symbols.size(); ++i )
    {
        if( i < g.canonId.size() && !g.canonId[i].empty() )
        {
            keyByNode[i] = fnv1a64( baselineCanonId( ing, i, root ) );
        }
    }

    // ─── r26 ORIGIN AXIS: preexisting-worse vs new-symbol ──────────────────────────────────────────────
    // The exit code used to fire on ANY major unacked finding, which meant every large-but-fine NEW symbol
    // ("was=0" complexity/verbosity/nesting/params rows, and one api-surface row per new export) landed in
    // the same exit-2 pile as the genuinely-useful "this function that already existed got worse" catch.
    // A report whose acceptance criterion is negotiated per finding is not an acceptance criterion, so the
    // two are now separated: only PREEXISTING-worse findings gate; new-symbol findings stay printed.
    //
    // THE ORACLE is `base.locBySym` — computeSnapshot populates it for EVERY symbol that has a canonId
    // (public or not, body or not), so "is this canonId in locBySym" is the one clean, kind-independent
    // "existed at the baseline" test. It generalizes the api-surface kind's own isNewSymbol tier (B10.2e),
    // which used exactly this map, to all ten kinds rather than adding a parallel mechanism.
    //
    // PER-KIND RULE (the ambiguous kinds decided deliberately, not by default):
    //   complexity / verbosity / nesting / params / api-surface / error-masking — the finding IS a symbol:
    //     classify by that symbol's canonId. Direct.
    //   dead-code — the finding is "this symbol is now dead". A symbol that existed and LOST its last caller
    //     is preexisting-worse; a symbol born uncalled is new-symbol (that is a "you have not wired it up
    //     yet" note about new code, not a regression of anything that worked before).
    //   duplication / new-clone-of-reused-helper — the finding is a RELATION over a member set, not one
    //     symbol, so "the symbol existed" needs a decision: a group counts as preexisting-worse iff AT LEAST
    //     ONE member existed at the baseline — i.e. the new copy eroded code that was already there (the
    //     high-value half of these kinds, and the whole point of the reuse-decline kind: the reused helper is
    //     preexisting — r27 made that an ENFORCED precondition at the reuse kind's own fan-in test, where it
    //     had until then been only an assertion in this comment). A group whose members are ALL new is new code duplicating itself:
    //     real information, still printed, but nothing that existed got worse. A member with no canonId
    //     (key 0) is unclassifiable and is NOT counted as evidence of preexistence.
    //   short-horizon-churn — ALWAYS preexisting by construction: its gate 2 already requires the symbol to
    //     be present in the baseline's bodyHashBySym ("a symbol absent from the baseline is a first write,
    //     never a REwrite"), so this kind can never produce a new-symbol row. Recorded explicitly below
    //     rather than derived, so the invariant is visible at the push site.
    //
    // WHAT "PREEXISTING" CANNOT DETECT (stated in the XML comment + --help too): identity is the
    // root-relative canonId `path::scope::name`, so a symbol that was RENAMED or MOVED to another file reads
    // as new on the current side — a regression carried in with a move classifies new-symbol and does not
    // gate. There is no rename detection here and adding one would make the classification non-deterministic
    // (a similarity heuristic), which the determinism law forbids.
    //
    // DEGRADE, FAIL-CLOSED: a pre-Q1 (v1-format) baseline sidecar carries no `loc ` lines at all, so the
    // oracle is empty and NOTHING could be classified. Rather than silently disarming the exit code on an
    // unreadably-old baseline, classify every finding as preexisting-worse (gating) and alert — the honest
    // outcome is "re-baseline", never "green because I could not tell".
    // r27 SUSPICION-A FIX — `!base.locBySym.empty()` alone CONFLATED two opposite situations, and got the
    // second one factually wrong:
    //   (i)  a pre-Q1 (v1-format) sidecar, which has ccx/clone/dead/api records but no `loc ` lines → the
    //        oracle really is unavailable → fail closed (gate everything) + alert. Correct, keep.
    //   (ii) a baseline that is legitimately, COMPLETELY empty — a README-only first commit, a docs/JSON-only
    //        HEAD, a root pointed at a non-source subdirectory. HEAD genuinely has no canonId symbols, so the
    //        oracle is PERFECT ("nothing existed; every finding is new"), yet every finding was classified
    //        preexisting-worse and GATED, under an alert that told the user their baseline was in a stale
    //        pre-Q1 format. Wrong answer AND wrong explanation.
    // The discriminator is exact, not a heuristic: computeSnapshot populates locBySym for EVERY symbol that has
    // a canonId, so ANY other per-symbol record existing while locBySym is empty is only possible for a v1
    // sidecar; a genuinely-empty HEAD leaves every map and vector empty together.
    const bool baselineIsWhollyEmpty = base.locBySym.empty() && base.ccxBySym.empty() && base.nestBySym.empty()
                                    && base.paramsBySym.empty() && base.maskBySym.empty() && base.bodyHashBySym.empty()
                                    && base.cloneGroups.empty() && base.dead.empty() && base.publicApi.empty();
    const bool originOracleOk = !base.locBySym.empty() || baselineIsWhollyEmpty;
    if( !originOracleOk )
    {
        DEGRADED_PATH_ALERT( "quality: baseline has no per-symbol loc map (pre-Q1 format) — origin unclassifiable, gating every finding" );
    }

    const auto existedAtBaseline = [ & ]( std::uint64_t symKey )
    {
        if( !originOracleOk )
        {
            return true; // fail closed — see the degrade note above
        }
        return base.locBySym.find( symKey ) != base.locBySym.end();
    };

    // A clone group is new-symbol only when EVERY member is new (see the per-kind rule above).
    // r27 SUSPICION-B FIX: this loop asked `existedAtBaseline` per member, but a member with key 0 (no
    // canonId) short-circuits past it, so with the oracle UNAVAILABLE a group of such members still returned
    // true — "new-symbol", never gates — while every OTHER kind was busy failing CLOSED on the same missing
    // oracle. One unclassifiable kind silently disarming the exit code is exactly the shape of the bug the
    // fail-closed rule exists to prevent. Answer the oracle question FIRST, once, for the whole group.
    const auto cloneGroupIsNew = [ & ]( const CloneGroup& cg )
    {
        if( !originOracleOk )
        {
            return false; // fail closed — preexisting-worse, gates
        }
        for( NodeId m : cg.members )
        {
            if( m < keyByNode.size() && keyByNode[m] != 0 && existedAtBaseline( keyByNode[m] ) )
            {
                return false;
            }
        }
        return true;
    };

    // P2.5 (r27) — the LOCATOR stamp. Fill the row's p="path:line" from the symbol that produced it, right
    // after the push so no call site has to restate the whole aggregate initializer. Root-relative path (the
    // relForHash spelling every sidecar key already uses) + the symbol's own 1-based start line.
    const auto stampLoc = [ & ]( NodeId i )
    {
        VERIFY( !regs.empty() );
        if( i >= ing.symbols.size() )
        {
            return; // degrade: no locator rather than a wrong one
        }
        const Symbol& s = ing.symbols[i];
        if( s.fileId >= ing.files.size() )
        {
            return;
        }
        regs.back().path = std::string( relForHash( ing.files[ s.fileId ], root ) );
        regs.back().line = s.line;
    };

    // The clone kinds' locator: the member whose canonId sorts FIRST, so p= names the same symbol that leads
    // the emitted members= list rather than an arbitrary NodeId-order pick.
    const auto stampCloneLoc = [ & ]( const CloneGroup& cg )
    {
        NodeId      best   = NodeId( -1 );
        std::string bestId;
        for( NodeId m : cg.members )
        {
            if( m >= g.canonId.size() || g.canonId[m].empty() )
            {
                continue;
            }
            if( best == NodeId( -1 ) || g.canonId[m] < bestId ) { best = m; bestId = g.canonId[m]; }
        }
        if( best != NodeId( -1 ) )
        {
            stampLoc( best );
        }
    };

    // One per-symbol metric kind: aggregate the CURRENT side to the same per-canonId MAX the snapshot stores
    // (overloads share an id), compare per-id MAX vs the baseline's per-id MAX, report each id once at its
    // first symbol, and flag only when it GREW and now exceeds the bar. `metricOf` reads the metric off a
    // Symbol; `baseMap` is the matching baseline map. Identical treatment for ccx/loc/nest/params guarantees
    // the trap is handled the same way for every one of them.
    // `minorDelta` is the kind's materiality tier: a regression whose growth (now − was) is under it is
    // reported sev="minor" and does not gate exit 2 (0 = no tier, every regression is major).
    const auto perSymbolKind =
        [ & ]( const char* kindName, std::uint32_t bar, std::uint32_t minorDelta,
               const gtl::btree_map<std::uint64_t, std::uint32_t>& baseMap,
               auto metricOf )
    {
        ScratchMap<std::uint32_t> nowBySym( ing.symbols.size() );
        for( NodeId i = 0; i < ing.symbols.size(); ++i )
        {
            if( i >= g.canonId.size() || g.canonId[i].empty() )
            {
                continue;
            }
            std::uint32_t& slot = nowBySym[ keyByNode[i] ];
            slot = std::max( slot, metricOf( ing.symbols[i] ) );
        }
        ScratchMap<std::uint8_t> reported( ing.symbols.size() );
        for( NodeId i = 0; i < ing.symbols.size(); ++i )
        {
            if( i >= g.canonId.size() || g.canonId[i].empty() )
            {
                continue;
            }
            const std::uint64_t key   = keyByNode[i];
            if( !insertScratchSeen( reported, key, "quality: per-symbol seen scratch capacity exceeded" ) )
            {
                continue; // already reported at an earlier overload
            }
            const auto          nowIt = nowBySym.find( key );
            if( nowIt == nowBySym.end() )
            {
                continue; // corrupt/inconsistent ids: degrade by skipping
            }
            const std::uint32_t now = nowIt->second;
            const auto          it  = baseMap.find( key );
            const std::uint32_t was = ( it == baseMap.end() ) ? 0u : it->second;
            if( now > was && now > bar )
            {
                regs.push_back( { kindName, g.canonId[i], was, now, key, minorDelta > 0 && now - was < minorDelta,
                                  {}, !existedAtBaseline( key ) } );          // origin: the finding IS this symbol
                stampLoc( i );
            }
        }
    };

    perSymbolKind( "complexity", kCcxBar,   kMinorCcxDelta,   base.ccxBySym,    []( const Symbol& s ){ return s.ccx; } );
    perSymbolKind( "verbosity",  kLocBar,   kMinorLocDelta,   base.locBySym,    []( const Symbol& s ){ return s.loc; } );
    perSymbolKind( "nesting",    kNestBar,  0,                base.nestBySym,   []( const Symbol& s ){ return std::uint32_t( s.maxNest ); } );
    perSymbolKind( "params",     kParamBar, kMinorParamDelta, base.paramsBySym, []( const Symbol& s ){ return std::uint32_t( s.params ); } );

    // PERF (P5W2) — the working-tree clone pass is the dominant --quality-delta cost: on a large private C++ corpus the
    // Type-3 pass alone is ~2.7-3.2 s (60 M intra-bucket pair-visits; tokenization is only ~3 %). It is a PURE
    // function of the working tree (ing), yet BOTH consumers below — the `duplication`/§D#4-3 new-clone report
    // AND the reuse-connectivity report — used to call findClones/findClonesType3 independently, so each pass
    // ran TWICE per call (~46 % of the whole verb was redundant recompute). Compute each pass ONCE here and let
    // both consumers read the same vectors. Byte-identical BY CONSTRUCTION: both functions are deterministic
    // pure functions, so their single result is field-for-field the value both call sites received before.
    const std::vector<CloneGroup> exactClones = findClones( ing, int( kMinCloneTokens ) );
    const std::vector<CloneGroup> type3Clones = findClonesType3( ing, int( kMinCloneTokens ) );

    // duplication: a clone group (exact Type-1/2 OR gapped Type-3) whose member-set is not in the
    // baseline set. Both passes hash by the same sorted-member-canonId identity, so a change that
    // introduces a NEW near-clone (Type-3) is flagged exactly like a new exact copy. `now` carries the
    // group's tokens; the reported set is deduped by the same emitted-hash guard both passes share (an
    // exact and a near group can never share a member-set hash, so no double-report).
    gtl::btree_map<std::uint64_t, std::uint8_t> dupSeen;
    const auto reportNewClones =
        [ & ]( const std::vector<CloneGroup>& cgs )
    {
        for( const CloneGroup& cg : cgs )
        {
            const std::uint64_t h = cloneGroupHash( cg, ing, root );
            if( std::binary_search( base.cloneGroups.begin(), base.cloneGroups.end(), h ) )
            {
                continue;
            }
            // B10.1a: a clone group ENTIRELY composed of test-SCRIPT members is fixture-class noise — sibling
            // shell test scripts repeat near-identical setup/ok/no boilerplate by convention (see
            // isTestScriptPath); exempt only when every member is a test script, so a real src/ ↔ test-script
            // clone (still worth a look) is unaffected.
            bool allTestScript = !cg.members.empty();
            for( NodeId m : cg.members )
            {
                if( m >= ing.symbols.size() || !isTestScriptPath( ing.files[ ing.symbols[m].fileId ] ) ) { allTestScript = false; break; }
            }
            if( allTestScript )
            {
                continue;
            }
            if( !dupSeen.insert( { h, 1 } ).second )
            {
                continue; // same member-set already reported this run
            }
            std::vector<std::string> ids;
            for( NodeId m : cg.members )
            {
                if( m < g.canonId.size() )
                {
                    ids.push_back( g.canonId[m] );
                }
            }
            std::sort( ids.begin(), ids.end() );
            std::string joined;
            for( std::size_t k = 0; k < ids.size(); ++k )
            {
                joined += ids[k];
                if( k + 1 < ids.size() )
                {
                    joined += " | ";
                }
            }
            regs.push_back( { "duplication", joined, 0, cg.tokens, h, false, {}, cloneGroupIsNew( cg ) } );   // ack identity = the member-set hash; origin = "no member existed"
            stampCloneLoc( cg );
        }
    };
    reportNewClones( exactClones );
    reportNewClones( type3Clones );

    const std::vector<std::uint64_t> topLevelCallees = topLevelCalleeNameHashes( ing );   // W1-S2: dead-kind evidence, built once
    for( NodeId i = 0; i < ing.symbols.size(); ++i )
    {
        if( i >= g.canonId.size() || g.canonId[i].empty() || !isDeadCandidate( ing, g, i, topLevelCallees ) )
        {
            continue;
        }
        if( !std::binary_search( base.dead.begin(), base.dead.end(), keyByNode[i] ) )
        {
            regs.push_back( { "dead-code", g.canonId[i], 0, 0, keyByNode[i], false, {},
                              !existedAtBaseline( keyByNode[i] ) } );          // origin: born uncalled (new) vs lost its last caller (preexisting)
            stampLoc( i );
        }
    }

    // api-surface (contract drift) — B10.2e TIERED into two shapes on the PUBLIC/exported surface:
    //   (A) a public canonId not yet in the baseline public set. Tiered by whether the canonId existed in
    //       ANY baseline per-symbol map at all (locBySym is populated for EVERY symbol with a canonId,
    //       public or not — see computeSnapshot — so its absence is a clean, single-map "genuinely new
    //       symbol" test that also covers "its enclosing file is new", since a new file's symbols are
    //       trivially absent from every baseline map too): absent ⇒ additive new-feature surface, not a
    //       contract break → sev=minor, facet surface="new-symbol". Present (existed at baseline in some
    //       form, e.g. a visibility flip from private → public) ⇒ facet surface="contract-change", stays major.
    //   (B) a public canonId ALREADY in the baseline public set whose declared parameter COUNT changed vs
    //       baseline: a genuine signature edit on code external callers may already depend on. ANY delta
    //       counts (not gated by kParamBar/kMinorParamDelta the way the separate `params` kind is — a public
    //       contract's arity moving by even 1 is externally observable regardless of function size) → stays
    //       major, facet surface="contract-change", was/now = the parameter counts. BOTH sides are the
    //       per-canonId MAX over EVERY symbol sharing the key — mirroring computeSnapshot's own paramsBySym
    //       aggregation EXACTLY, public and non-public alike, NOT just the public overload set. Two reasons:
    //       constructors are the common multi-overload case (a default ctor alongside a parameterized one),
    //       and comparing a single arbitrarily-iterated overload's raw count against the baseline's
    //       MAX-aggregated one would manufacture a phantom regression on an UNCHANGED overload set purely
    //       from NodeId iteration order (the exact "overload trap" this file guards against everywhere else).
    //       And §P13.4: canonicalId degrades to the BARE NAME for scope-less free functions, so same-named
    //       symbols COLLIDE across files and languages (a 4-param module-level Python `add` shares its key
    //       with a 2-param C header `add`). The baseline side (computeSnapshot) folds ALL of them into its
    //       MAX; a public-only now-side reads a lower MAX for the same unchanged set → a phantom
    //       contract-change row, and a gating exit, on a CLEAN tree (gate: test/qualitycrosslangcheck.sh).
    //       Same-set aggregation on both sides makes a clean tree vacuously regression-free by construction.
    //       Known, accepted cost: a colliding non-public same-name symbol with a higher arity masks a real
    //       arity change on the public one — inherent to bare-name keying, identical to the `params` kind.
    // Report each canonId once — overloads collapse to one canonId, so gate on "not already reported this
    // key" to avoid one <r> per overload.
    gtl::btree_map<std::uint64_t, std::uint32_t> nowParamsBySym;
    for( NodeId i = 0; i < ing.symbols.size(); ++i )
    {
        if( i >= g.canonId.size() || g.canonId[i].empty() )
        {
            continue;
        }
        std::uint32_t& slot = nowParamsBySym[ keyByNode[i] ];
        slot = std::max( slot, std::uint32_t( ing.symbols[i].params ) );
    }
    ScratchMap<std::uint8_t> apiSeen( ing.symbols.size() );
    for( NodeId i = 0; i < ing.symbols.size(); ++i )
    {
        if( i >= g.canonId.size() || g.canonId[i].empty() || !isPublicApi( ing, i ) )
        {
            continue;
        }
        const std::uint64_t key = keyByNode[i];
        if( !insertScratchSeen( apiSeen, key, "quality: api seen scratch capacity exceeded" ) )
        {
            continue; // overload of an already-reported symbol
        }

        if( !std::binary_search( base.publicApi.begin(), base.publicApi.end(), key ) )
        {
            const bool isNewSymbol = !existedAtBaseline( key );                // SAME oracle the r26 origin axis uses — one source of truth
            regs.push_back( { "api-surface", g.canonId[i], 0, 0, key, isNewSymbol, isNewSymbol ? "new-symbol" : "contract-change", isNewSymbol } );
            stampLoc( i );
            continue;
        }

        const auto pit = base.paramsBySym.find( key );
        if( pit == base.paramsBySym.end() )
        {
            continue; // no baseline params recorded — nothing to compare
        }
        const std::uint32_t nowParams = nowParamsBySym[ key ];                // MAX-aggregated — see the overload-trap note above
        if( nowParams != pit->second )
        {
            regs.push_back( { "api-surface", g.canonId[i], pit->second, nowParams, key, false, "contract-change", false } );   // origin: reached only for a symbol already in the baseline public set
            stampLoc( i );
        }
    }

    // ── §D#4-1 error-masking (GitClear +47%) ──────────────────────────────────────────────────────────────
    // NEW error-masking constructs vs baseline, per symbol: aggregate the current side to a per-canonId COUNT
    // (SUM over overloads, mirroring computeSnapshot's errorMaskCountsBySym), and flag a symbol whose count
    // GREW vs the baseline count (was 0 for a symbol/mask absent from the baseline). No bar — any NEW masking
    // construct is the regression; the count magnitude is the was/now signal. A pre-existing empty catch in an
    // UNTOUCHED symbol keeps the same count on both sides → not flagged (the quality-delta contract).
    {
        const gtl::btree_map<std::uint64_t, std::uint32_t> nowMask = errorMaskCountsBySym( ing, root );
        // report each canonId once, at its first defining symbol (a mask count is a per-canonId magnitude).
        ScratchMap<std::uint8_t> maskSeen( ing.symbols.size() );
        for( NodeId i = 0; i < ing.symbols.size(); ++i )
        {
            if( i >= g.canonId.size() || g.canonId[i].empty() )
            {
                continue;
            }
            const std::uint64_t key = keyByNode[i];
            const auto          nit = nowMask.find( key );
            if( nit == nowMask.end() )
            {
                continue; // this symbol masks no errors now
            }
            if( !insertScratchSeen( maskSeen, key, "quality: mask seen scratch capacity exceeded" ) )
            {
                continue; // already reported at an earlier overload of this id
            }
            const std::uint32_t now = nit->second;
            const auto          bit = base.maskBySym.find( key );
            const std::uint32_t was = ( bit == base.maskBySym.end() ) ? 0u : bit->second;
            if( now > was )
            {
                regs.push_back( { "error-masking", g.canonId[i], was, now, key, false, {}, !existedAtBaseline( key ) } );
                stampLoc( i );
            }
        }
    }

    // ── §D#4-2 short-horizon churn (GitClear +15% "new code rewritten within two weeks") ───────────────────
    // A symbol flags iff THREE independent gates all hold (signal-to-noise round, 2026-07-13):
    //   1. its FILE had ≥ kShortHorizonMinCommits commits in the last kShortHorizonDays (git COMMIT TIMESTAMPS
    //      vs HEAD's epoch — deterministic, NOT wall-clock);
    //   2. THIS diff rewrites it: the symbol exists in the baseline AND its RAW-body hash differs (a raw-byte
    //      hash, not metrics — `return 2` → `return 3` moves no metric yet IS a rewrite). A symbol ABSENT from
    //      the baseline is a FIRST write, not a REwrite — brand-new symbols never flag (the old behavior fired
    //      on every added symbol in an active file by construction, drowning real thrash);
    //   3. COMMITTED thrash evidence: the symbol's baseline (HEAD) body differs from its body at the churn-
    //      window reference commit — or it first appeared inside the window — i.e. commits ALREADY rewrote it
    //      recently and the working tree is rewriting it AGAIN. Without this gate the current uncommitted edit
    //      alone counted as churn, flagging every touched symbol in any active file. Markdown Sections and
    //      test-fixture paths are exempt (docs and fixtures churn by design — the noise rules).
    // All three gates join on pathQualifiedKey, never the bare canonId — see bodyHashesBySym's doc
    // (W1-S2 cross-file misattribution; gate: test/qualitysignalcheck.sh §1d).
    // Git access uses computeDelta's own `root` (= cfg.rootPath on the CLI, the real repo root over MCP);
    // no git / no HEAD / no obtainable window ref → this kind simply reports nothing (degrade, precision-first).
    {
        const std::vector<std::uint32_t> commitCounts = gitFileCommitCountsInDayWindow( std::string( root ), ing, kShortHorizonDays );
        const bool anyChurn = std::any_of( commitCounts.begin(), commitCounts.end(),
                                           []( std::uint32_t c ){ return c >= kShortHorizonMinCommits; } );
        if( anyChurn )
        {
            const auto [ refBody, refOk ] = computeWindowRefBodyHashes( std::string( root ), kShortHorizonDays, excludes, maxFileBytes );
            if( refOk )
            {
                const gtl::btree_map<std::uint64_t, std::uint64_t> nowBody = bodyHashesBySym( ing, root );

                // fixture exemption, hoisted per file (path scan once, not per symbol).
                std::vector<std::uint8_t> fixtureByFile( ing.files.size(), 0 );
                for( std::uint32_t f = 0; f < ing.files.size(); ++f )
                {
                    fixtureByFile[f] = isFixturePath( ing.files[f] ) ? 1 : 0;
                }

                // B10.2d — SELF-vs-AMBIENT window cutoff, same basis as gates 1/3 (HEAD's own committer epoch
                // minus the window, never wall-clock). A failed lookup (should not happen here since refOk
                // already proved resolvable history, but kept defensive) leaves churnCutoffEpoch==0, which
                // degrades every symbol below to AMBIENT (churnEditTouchesHotLine is gated on `> 0`).
                std::int64_t churnCutoffEpoch = 0;
                {
                    const std::string epochStr = gitOneLine( std::string( root ), "log -1 --format=%ct HEAD 2>/dev/null" );
                    if( !epochStr.empty() )
                    {
                        const std::int64_t headEpoch = std::strtoll( epochStr.c_str(), nullptr, 10 );
                        if( headEpoch > 0 )
                        {
                            churnCutoffEpoch = headEpoch - std::int64_t( kShortHorizonDays ) * 86400;
                        }
                    }
                }

                // P3 (r27) — ONE `git diff --unified=0 HEAD -- <path>` spawn per PATH for the whole loop. The
                // diff is a pure function of (HEAD, working tree), both fixed for this call, yet it used to be
                // re-spawned per symbol (measured: 8 byte-identical spawns for a single dirty file).
                DiffHunkMemo             churnHunkMemo;
                ScratchMap<std::uint8_t> churnSeen( ing.symbols.size() );
                for( NodeId i = 0; i < ing.symbols.size(); ++i )
                {
                    if( i >= g.canonId.size() || g.canonId[i].empty() )
                    {
                        continue;
                    }
                    const Symbol& s = ing.symbols[i];
                    if( s.kind == SymKind::Section )
                    {
                        continue; // doc sections churn by design (exempt)
                    }
                    if( s.fileId >= commitCounts.size() || commitCounts[s.fileId] < kShortHorizonMinCommits )
                    {
                        continue;
                    }
                    if( fixtureByFile[s.fileId] )
                    {
                        continue; // fixtures churn by design (exempt)
                    }
                    // W1-S2: join on the path-qualified identity, NOT keyByNode — a scope-less symbol's
                    // bare-canonId key folded every same-named symbol in the tree into one identity, so
                    // gates 2+3 judged cross-file FOLDS (see bodyHashesBySym's doc; gate: §1d).
                    const std::uint64_t key = pathQualifiedKey( relForHash( ing.files[ s.fileId ], root ), s.scope, s.name );
                    if( !insertScratchSeen( churnSeen, key, "quality: churn seen scratch capacity exceeded" ) )
                    {
                        continue; // one report per (file, scope, name) identity — same-file overloads fold
                    }
                    const auto nb = nowBody.find( key );
                    if( nb == nowBody.end() )
                    {
                        continue; // no hashable body now (decl only) → nothing to rewrite
                    }
                    const auto bb = base.bodyHashBySym.find( key );
                    if( bb == base.bodyHashBySym.end() )
                    {
                        continue; // gate 2: absent from baseline = a first write, never churn
                    }
                    if( bb->second == nb->second )
                    {
                        continue; // gate 2: this diff does not rewrite it
                    }
                    const auto rb = refBody.find( key );
                    // gate 3: rewritten across window commits (ref ≠ baseline body), or first COMMITTED inside the window.
                    if( rb != refBody.end() && rb->second == bb->second )
                    {
                        continue;
                    }

                    // B10.2d: SELF vs AMBIENT — does THIS diff modify a pre-existing line that was itself
                    // last committed inside the window? See the section comment above churnEditTouchesHotLine.
                    const bool self = churnCutoffEpoch > 0
                                    && churnEditTouchesHotLine( churnHunkMemo, std::string( root ),
                                                                std::string( relForHash( ing.files[ s.fileId ], root ) ),
                                                                s.line, s.loc, churnCutoffEpoch );
                    regs.push_back( { "short-horizon-churn", g.canonId[i], 0, commitCounts[ s.fileId ], key,
                                      !self, self ? "self" : "ambient", false } );   // now = window commit count on the file; origin: ALWAYS preexisting (gate 2 above required a baseline body)
                    stampLoc( i );
                }
            }
        }
    }

    // ── §D#4-3 reuse-connectivity decline: a NEW clone of a REUSED (high-fan-in) helper (GitClear) ──────────
    // A clone group (exact Type-1/2 OR gapped Type-3) whose member-SET is NOT in the baseline (a copy this diff
    // just introduced) AND that contains a member with fan-in ≥ kReusedHelperMinFanin — i.e. the new code
    // duplicates the ROLE of an existing well-reused helper instead of calling it ("cross-file reuse declining").
    // Reuses the SAME new-group gate the duplication kind uses, so it can only fire on a freshly-added copy,
    // never on pre-existing debt. Fan-in = the symbol's in-edge count in the CSR (who depends on it). Reported
    // once per new qualifying group (its member list); now = the group's max member fan-in (the reuse it eroded).
    {
        const auto* ro = g.inEdges.rowOffsets();
        gtl::btree_map<std::uint64_t, std::uint8_t> reuseSeen;   // clone-group count is not strictly bounded by symbol count, so keep the unbounded sorted map here
        const auto reportReusedClones = [ & ]( const std::vector<CloneGroup>& cgs )
        {
            for( const CloneGroup& cg : cgs )
            {
                const std::uint64_t h = cloneGroupHash( cg, ing, root );
                if( std::binary_search( base.cloneGroups.begin(), base.cloneGroups.end(), h ) )
                {
                    continue; // group already existed → not new
                }
                // r27 SUSPICION-C FIX — "the reused helper is preexisting BY CONSTRUCTION" was asserted here
                // (and in fbc527e's commit message) but never ENFORCED: fan-in ≥ 3 is trivially reached by a
                // brand-new helper that three brand-new call sites use, so an all-new blob of code duplicating
                // ITSELF was reported under a kind whose entire meaning is "you eroded reuse that already
                // existed". The claim is now a precondition: the qualifying high-fan-in member must have
                // EXISTED at the baseline. Nothing is lost — an all-new self-duplication is still reported by
                // the `duplication` kind, which is where it belongs.
                std::uint32_t maxFanin = 0;
                for( NodeId m : cg.members )
                {
                    if( m >= ing.symbols.size() )
                    {
                        continue;
                    }
                    if( m >= keyByNode.size() || keyByNode[m] == 0 )
                    {
                        continue; // unclassifiable member — never evidence of preexisting reuse
                    }
                    if( !existedAtBaseline( keyByNode[m] ) )
                    {
                        continue; // a NEW helper's fan-in is not reuse this change eroded
                    }
                    maxFanin = std::max( maxFanin, std::uint32_t( ro[m + 1] - ro[m] ) );                    // in-edge count = fan-in
                }
                if( maxFanin < kReusedHelperMinFanin )
                {
                    continue; // no PREEXISTING reused helper in the group
                }
                if( !reuseSeen.insert( { h, 1 } ).second )
                {
                    continue; // same member-set already reported
                }
                std::vector<std::string> ids;
                for( NodeId m : cg.members )
                {
                    if( m < g.canonId.size() )
                    {
                        ids.push_back( g.canonId[m] );
                    }
                }
                std::sort( ids.begin(), ids.end() );
                std::string joined;
                for( std::size_t k = 0; k < ids.size(); ++k )
                {
                    joined += ids[k];
                    if( k + 1 < ids.size() )
                    {
                        joined += " | ";
                    }
                }
                regs.push_back( { "new-clone-of-reused-helper", joined, 0, maxFanin, h, false, {}, cloneGroupIsNew( cg ) } );   // now = the eroded helper's fan-in; ack identity = the member-set hash
                stampCloneLoc( cg );
            }
        };
        reportReusedClones( exactClones );
        reportReusedClones( type3Clones );
    }

    std::sort( regs.begin(), regs.end(), []( const Regression& a, const Regression& b )
    { return a.kind != b.kind ? a.kind < b.kind : a.sym < b.sym; } );
    return regs;
}

}   // namespace quality
}   // namespace rw
