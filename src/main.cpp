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
#include "editpreview.h"           // card A1: the PRE-APPLY contract preview (editpreview::run) — BEFORE mcp.h, which
                                   //   is what lets the MCP edit_check verb mirror it from mcpverbs.h
#include "slicediff.h"            // card A4: --slice=SYM:VAR --since=REV — the def-use slice as a DEPENDENCE diff
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
#include "cloneidiom.h"          // idiom-class demotion for clone findings — the closed 3-idiom shape classifier both --clones and the quality-delta duplication kind annotate rows with
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
#include "planlint.h"              // P3.2: --plan-lint=FILE — the house PLAN format's STRUCTURE check (cards vs the
                                    // status ledger, terminal glyphs, stale hourglass lines, undischarged owed mentions)
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
// (MCP has its own separate file, mcpCachePath in mcpindex.h — and it needs NO exclude field: every MCP
// ingest passes `{}` excludes and kDefaultMaxFileBytes, so a server serves exactly ONE configuration
// per root and its key can never collide across configurations.)
//
// N5-A: the same class-switch thrash, on the EXCLUDE axis. The key folded neither the exclude set nor
// --max-file-size, both of which decide WHICH FILES are extracted, so `ripwire .` and
// `ripwire . --exclude=bench/external` shared ONE blob. Measured on this repository (EVALS §"The
// auto-cache key ignores `--exclude`"): the excluded run deserialised the 686 MB un-excluded superset it
// then discarded — 536 ms of loadCache against 31 ms of parsing, versus 8 ms under an explicit
// --cache=PATH — and the moment that excluded run was DIRTY (any file changed since it last ran, the
// ordinary case in a working tree) it rewrote the shared blob with its SUBSET, leaving the next
// un-excluded run to cold-parse the whole excluded subtree (~15,000 files, 5.0 s).
//
// So the filename gains a third field, between the root hash and the class: `exclConfigHex` — the SAME
// key material (excludes + the family scheme tag + extractionIdentityTag() + maxFileBytes) that
// quality.h's qheadsnap/qsnap/qbody families have keyed on since P0.2. Reused, not re-derived: one body
// decides what "which files were extracted" hashes to, for every cache family in the tool.
//
// Two consequences, both intended. (1) One blob per (root, exclude config, class) — bounded by the same
// dir-wide `sweepStaleCacheBlobsOnce` hygiene pass that already bounds this family (prefix "ripwire-",
// 30-day age cutoff, then oldest-first down to kMaxCacheDirBytes); the new names carry that prefix, so
// they are inside the swept family by construction (gated: cacheexclkeycheck (f)). (2) A kParserVer /
// kCacheVersion bump now RENAMES the blob instead of overwriting it in place, because
// extractionIdentityTag() rides the key — the version-gated content check inside loadCache still exists
// and is still authoritative, and the orphaned old blob ages out on the 30-day pass like any other.
//
// Y4: resolved through resolveCacheBlobPath (quality.h) — the shard-aware, backward-compatible
// choke point every ripwire-*.bin blob path now routes through. See its comment for the full rationale.
constexpr std::uint32_t kAutoCacheScheme = 1;   // bump to rename ONLY this family (mergescout/gitoracle precedent)

std::string defaultCachePath( const std::string& root, bool captureValueUses,
                              const std::vector<std::string>& excludes, std::size_t maxFileBytes )
{
    char        absbuf[ PATH_MAX ];
    const char* abs = realpath( root.c_str(), absbuf ) ? absbuf : root.c_str();
    std::uint64_t h = 1469598103934665603ull;
    for( const char* c = abs; *c; ++c ) { h ^= static_cast<unsigned char>( *c ); h = rw::hashutil::fnv1aMultiply( h ); }
    const std::string exclHex = rw::quality::exclConfigHex( excludes, "auto" + std::to_string( kAutoCacheScheme ), maxFileBytes );
    char tail[ 64 ];
    std::snprintf( tail, sizeof( tail ), "ripwire-%016llx-%s-%s.bin",
                   static_cast<unsigned long long>( h ), exclHex.c_str(), captureValueUses ? "rich" : "lean" );
    return resolveCacheBlobPath( cacheDirLadder(), tail );
}

// computeHeadSnapshot / gitHeadSha / gitRepoHasHistory / cacheDirLadder now live in quality.h (the
// baseline home) and are re-exported via the `using` aliases above — one shared copy for CLI + MCP.


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

    // An @FILE:LINE line seed (lane/at-seed) carries its own trailing digits: on an @-led token a
    // digit-led tail with NO dash is the seed's line, not a range attempt — the whole token is the
    // selector and resolveAtSeed reads the line half itself. "@src/f.cpp:120:5-10" still slices: its
    // tail has the dash, so the range strips here and "@src/f.cpp:120" resolves as the seed.
    if( token.front() == '@' && rangeStr.find( '-' ) == std::string_view::npos )
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
// §P4.1 — the --grep scan phases, computed AHEAD of this struct (see verbs_grep.h). Forward-declared so
// MainDispatch can carry a pointer to them without the grep section having to precede it; nullptr is the
// ordinary case (any run whose answering verb is not grep) and the verb then computes them inline.
struct GrepScanPhases;

// ── card A1: --edit-check=SYM --edit-payload=FILE --dry-run — WHO OWNS THE COMBINATION ────────────────
// --edit-payload and --dry-run were each spoken for: the first by the three CLI write verbs, the second by
// --edit-plan. Both of those handlers dispatch BEFORE the ingest pipeline, so without this predicate the
// preview never reaches --edit-check at all — it lands on "--edit-payload requires one of
// --replace-symbol-body…", a refusal that is true of yesterday's flag table and useless about what was typed.
// One predicate, read by all three handlers, so the ownership is stated once.
bool editPreviewRequested( const rw::Config& c ) noexcept
{
    return !c.editCheckSym.empty() && !c.editPayload.empty() && c.editPlanDryRun && !c.editPlanApply;
}

// the half-typed forms, refused where the caller can still see which flag is missing. Returns nullopt for
// every combination that is somebody else's business (including the complete preview, which the ordinary
// --edit-check handler answers after the tree is parsed).
std::optional<int> runEditPreviewGuard( const rw::Config& c )
{
    if( c.editCheckSym.empty() || !c.editPlan.empty() )
    {
        return std::nullopt;
    }
    if( !c.editPayload.empty() && c.editPlanApply )
    {
        std::fprintf( stderr, "ripwire: --edit-check --edit-payload is a PREVIEW and never writes — pass --dry-run, or apply the "
                              "payload with --replace-symbol-body=%.*s --edit-payload=%.*s\n",
                      int( c.editCheckSym.size() ), c.editCheckSym.data(), int( c.editPayload.size() ), c.editPayload.data() );
        return 1;
    }
    if( !c.editPayload.empty() && !c.editPlanDryRun )
    {
        std::fprintf( stderr, "ripwire: --edit-check --edit-payload previews an unwritten payload and requires --dry-run "
                              "(add --dry-run to preview; use --replace-symbol-body to actually write it)\n" );
        return 1;
    }
    if( c.editPayload.empty() && c.editPlanDryRun )
    {
        std::fprintf( stderr, "ripwire: --edit-check --dry-run needs the bytes to preview — pass --edit-payload=FILE "
                              "(or --edit-payload=- for stdin)\n" );
        return 1;
    }
    return std::nullopt;
}

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
    const GrepScanPhases*                 grepPhases = nullptr;   // §P4.1: prefetched grep scan (nullptr ⇒ compute inline)
    bool                                   valueUses  = false;     // card A1: the captureValueUses this run's ingest actually used, so the
                                                                    //   pre-apply preview re-parses its one spliced file the SAME way
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
#include "verbs_change.h"
#include "verbs_report.h"
#include "verbs_grep.h"

namespace
{


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
        serialize( m, ing, rank, g.outOff, g.outTargets, k, cfg.mostImportantLast, cfg.metrics, fanInPtr, &g.ambOut, cfg.stable, mapProvPtr, cboPtr, testedPtr, lcom4Ptr, ampPtr, &g.unresolvedOut, g.bindLabel.empty() ? nullptr : &g.bindLabel, mapAutoOrder, /*outEstTokens=*/nullptr, extraPayloadTokens, mapAnn, /*statsFirstScreen=*/false, mapRootArg, &g.locPinOut );
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
                       g.bindLabel.empty() ? nullptr : &g.bindLabel, mapAutoOrder, /*outEstTokens=*/nullptr, mapProvPtr, mapAnn, mapRootArg, &g.locPinOut );
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
                           g.bindLabel.empty() ? nullptr : &g.bindLabel, mapAutoOrder, &mapEstTokens, mapProvPtr, mapAnn, mapRootArg, &g.locPinOut );
        }
        else
        {
            serialize( out, ing, rank, g.outOff, g.outTargets, mapTopK, cfg.mostImportantLast, cfg.metrics, fanInPtr, &g.ambOut, cfg.stable, mapProvPtr, cboPtr, testedPtr, lcom4Ptr, ampPtr, &g.unresolvedOut, g.bindLabel.empty() ? nullptr : &g.bindLabel, mapAutoOrder, &mapEstTokens, payloadTokens, mapAnn, /*statsFirstScreen=*/false, mapRootArg, &g.locPinOut );
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
        // lane/tc-sliceat: beside --slice, the at flag is that verb's LINE SEED (runSlice consumes it —
        // ARISE seeds its slicer at (file, line[, variable])), so the pair COMPOSES and never surfaces
        // as a dropped-verb warning; alone, the at flag is still the enclosing-chain report (runAt).
        { "--at",               !c.atSpec.empty() && c.sliceSpec.empty() },
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
        { "--plan-lint",        !c.planLintFile.empty()   },   // P3.2: runPlanLint, right after runDocDrift
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
    // lane/safe-delete + lane/paper-slice wired dispatch (right after --edit-check, precedence table order)
    // but not this chain, so both verbs accepted --json and silently emitted XML at exit 0.
    if( !c.safeDeleteSym.empty() )
    {
        return "--safe-delete";
    }
    if( !c.sliceSpec.empty() )
    {
        return "--slice";
    }
    if( !c.atSpec.empty() )
    {
        return "--at";
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
    if( !c.planLintFile.empty() )
    {
        return "--plan-lint";
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
    if( cfg.editPlan.empty() && !cfg.editCheckSym.empty() )
    {
        return std::nullopt;   // card A1: --dry-run beside --edit-check is the PREVIEW's mode flag, not this verb's
    }
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
    if( editCount == 0 && !cfg.editCheckSym.empty() )
    {
        return std::nullopt;   // card A1: --edit-payload beside --edit-check is the PREVIEW's payload, not a write
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

    // card A1: the four payload refusals — unreadable, EMPTY (never a delete), oversize against
    // --max-file-size, and NUL-bearing (rw::looksBinary itself, so the claim is exactly the condition that
    // would drop the file from the index) — now live ONCE in editpreview.h and are shared with the pre-apply
    // preview. Two copies of this ladder is two places for an agent to meet two vocabularies for one refusal.
    std::string payload, payloadErr;
    if( !rw::editpreview::readPayload( cfg.editPayload, cfg.maxFileBytes, payload, payloadErr ) )
    {
        std::fprintf( stderr, "ripwire: %s\n", payloadErr.c_str() );
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
    if( std::optional<int> guarded = runEditPreviewGuard( cfg ) )
    {
        return *guarded;   // card A1: a half-typed preview, refused where the missing flag is still nameable
    }
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
                cachePath = defaultCachePath( r.arg, needsValueUses, cfg.excludes, cfg.maxFileBytes );
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
            autoCache = defaultCachePath( root, needsValueUses, cfg.excludes, cfg.maxFileBytes );
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

    // §P4.1 — the grep scan runs ALONGSIDE the graph build; verbs_grep.h's startGrepScanPrefetch owns every
    // condition and the degrade path, and is handed §B11.4's own dispatch winner rather than a guess.
    GrepScanPhases    grepPhases;
    std::thread       grepPhaseWorker = startGrepScanPrefetch( cfg, ing, verbPrec.winner, grepPhases );
    const Graph       g               = buildGraph( ing, scipPtr, !cfg.pinCensus.empty() );
    joinGrepScanPrefetch( grepPhaseWorker );

    // --pin-census (src/pincensus.h): written straight after the graph build, BEFORE verb dispatch, so it
    // reflects the resolver and is produced whichever verb the run serves. The root condition is the map's
    // own (mapRootArg's), so census ids join to `id=` by string equality. An unopenable path is a LOUD
    // note, never a silent no-op — an eval that believes it measured something it did not is the worst case.
    if( !cfg.pinCensus.empty() )
    {
        const std::string censusPath( cfg.pinCensus );
        const bool        oneRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
        if( !writePinCensus( censusPath.c_str(), g.pinCensus, ing, oneRoot ? cfg.roots[0] : std::string_view() ) )
        {
            std::fprintf( stderr, "ripwire: --pin-census could not write '%s'\n", censusPath.c_str() );
        }
    }

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
                           ampPtr, cboPtr, testedPtr, lcom4Ptr, impurePtr, forChurn, redactCounts, redactPtr, notesPtr,
                           grepPhases.valid ? &grepPhases : nullptr, needsValueUses };

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

    // lane/at-seed: the FILE:LINE enclosing-chain report, right after --slice (same location-seeded family).
    if( std::optional<int> handled = runAt( dsp ) )
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

    if( std::optional<int> handled = runPlanLint( dsp ) )
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
