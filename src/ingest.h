#pragma once

// ingest.h — Phase 2 INGEST: deterministic crawl + tree-sitter tags-query extraction.
//
// ingest( rootDir ):
//   1. crawl rootDir for candidate source paths (skip .git/, oversized, binary, generated);
//   2. SORT paths lexicographically (byte order) — load-bearing determinism;
//   3. parse each by extension via a constexpr extension -> {ts_language, tags.scm} table;
//   4. run ONE ts_query per file, map @definition.* -> Symbol, @reference.* -> Reference;
//   5. assign Symbol ids in (file, line, name) order so the whole pipeline is reproducible.
//
// Returns rw::IngestResult exactly as defined in model.h (the GRAPH/RANK/SERIALIZE contract).
// Single-threaded for v1 ("single-threaded is fine for v1"); tree-sitter parsers are
// not thread-safe, so multithreading would need one parser per worker (deferred).

#include "model.h"

#include <cctype>
#include <string_view>

namespace rw
{

// The crawl's per-file byte ceiling. A text file larger than this is skipped: at this size
// it is overwhelmingly generated/vendored/data (bundles, generated parsers, minified blobs, data
// tables) — noise for an architecture map, and it would dominate the cold-parse budget. The specific
// value also bounds a WORST CASE: tree-sitter's parse is quadratic on pathological comment-dense input
// (~4 s/MB²), so 4 MB caps such a file at ~1 min (real code parses linearly, ~0.7 s/MB). Overridable
// per run via --max-file-size (CLI) for repos with genuinely-large hand-authored source.
constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u;   // 4 MB (was 1 MB pre-2026-07)

// The JSON lane's OWN crawl ceiling (found live by bench/multiswe): .json is indexed for CONFIG
// keys, and real config files (package.json, tsconfig, angular.json…) are tens of KB at most — while
// 200KB-4MB pretty-printed .json is essentially always DATA (test corpora, benchmark datasets, exports)
// that slips under both the 4MB skip and the minified-line heuristic and explodes into tens of thousands
// of junk t="sec" symbols (measured: >2min ingest on a nlohmann/json historical tree vs 0.3s without the
// data files). Generous on purpose: every real-world config file observed is far below it.
constexpr std::size_t kMaxJsonConfigBytes = 256u * 1024u;          // 256 KB

// JSON-lane nesting ceiling (companion to kMaxJsonConfigBytes; see jsonNestsTooDeep in ingest.cpp): real
// config nests a handful of levels; hundreds means a parser-torture fixture or generated data whose
// tree-sitter error recovery goes superlinear. 512 is orders of magnitude above any config observed.
constexpr std::uint32_t kMaxJsonNestDepth = 512u;

// THE TOML LANE HAS NO CEILING OF ITS OWN, AND THAT IS A MEASURED DECISION — not an omission, and not a
// sibling the JSON pair above is still waiting for. The two constants exist because .json has a large,
// common DATA class wearing a config extension; TOML has no such class, so a matching pair would be
// theatre that only ever fires on a file no corpus contains. Measured over 90 real public repos
// (bench-assets/r4/repos, 321 .toml files) before this lane was written:
//   SIZE — p50 277 B, p90 3 578 B, p99 21 449 B, MAX 57 759 B. The largest real TOML in 90 repos is 57 KB,
//     which is a quarter of what kMaxJsonConfigBytes would allow and 1.4% of kDefaultMaxFileBytes. A
//     TOML-specific ceiling could not be set anywhere both above the observed max and below the generic
//     4 MB skip without being unreachable by construction.
//   PARSE — 270 of 321 parse clean; 50 of the 51 "failures" are cpython's test_tomllib/data/invalid/
//     deliberately-malformed fixtures, so the real failure rate is ~0.3%.
//   PATHOLOGY — none. `[` x100 000 = 17.4 ms · dotted key x50 000 = 7.0 ms · 50 000 `[[aot]]` = 58.7 ms ·
//     a 2 MB unterminated string = 21.7 ms. All LINEAR. That is the substantive difference from JSON,
//     whose error recovery goes superlinear (43 s for 100 KB of unclosed `[`) and forced jsonNestsTooDeep.
//     TOML is line-oriented, so a malformed line resynchronizes at the newline instead of nesting.
//   SCANNER — the vendored external scanner is stateless (create() returns NULL, serialize() returns 0,
//     never allocates), so it adds no serialization or leak hazard to weigh against a guard either.
// So .toml rides the GENERIC path only: the shared --max-file-size / kDefaultMaxFileBytes skip, which is
// already disclosed through skipped_oversize=. test/tomllangcheck.sh pins this decision from the outside —
// it indexes a 216 KB .toml (3.7x the corpus max, and past where the JSON ceiling would sit) and fails if
// anything drops it, so a ceiling cannot be added later without the gate saying so out loud.

// The crawl's default directory denylist (a .gitignore-lite): noise/vendor/build subtrees pruned entirely.
// Shared, not private to ingest.cpp, because a second crawler now exists — darkflags.h walks for CMake files,
// which ingest deliberately never collects (CMake is not one of the indexed grammars) — and a crawl that
// disagreed with this one about what counts as source would report gates from nested agent worktrees and
// build-output trees as if they were the repo's own. One table, both walkers.
constexpr std::string_view kCrawlSkipDirs[] = {
    ".git", ".claude", ".hg", ".svn", "node_modules", "vendor", "third_party",
    ".cache", "build", "dist", "out", "target", ".venv", "venv", "__pycache__",
    ".idea", ".vscode",
    // CMake / compiler-id build dirs (generated stubs, not source — break --around=main etc.)
    "asan", "build_prof", "CMakeFiles",
    // Generated output captures (docs/captures/ here): a doc that quotes every verb's output out-scores
    // the source for almost any query about the tool — 77% of --recall on this repo was capture text
    // (owner decision). A "captures" dir is generated evidence,
    // not a design document; skipping beats a ranking de-prioritization no held-out eval can measure.
    "captures" };

// Is this directory NAME (not path) one the crawl prunes? Also covers the JetBrains "cmake-build-*" convention.
inline bool isSkippedCrawlDir( std::string_view dirName ) noexcept
{
    for( std::string_view s : kCrawlSkipDirs )
    {
        if( dirName == s )
        {
            return true;
        }
    }
    return dirName.size() > 12 && dirName.compare( 0, 12, "cmake-build-" ) == 0;
}

// Crawl + parse rootDir into the symbol/reference model. Never throws: a bad file, missing
// grammar, or ABI mismatch degrades (skipped + stderr note), never aborts ingestion.
// excludeSubstr: drop any path containing one of these substrings (and prune matching dirs)
// — for vendored/generated trees not caught by the built-in dir denylist (--exclude=SUBSTR).
// cacheFile (--cache=PATH): incremental content-hash cache — unchanged files reuse cached facts,
// only changed files are re-parsed. Empty ⇒ full parse. Node ids are reassigned each run (not
// cached), so a warm run is byte-identical to a cold one.
// maxFileBytes: the crawl's per-file size ceiling (default kDefaultMaxFileBytes; --max-file-size).
// captureValueUses: include read/write use-sites for --uses / metrics-quality lenses. Default true
// preserves the complete index for library/MCP callers; the CLI default map may pass false because
// PageRank consumes calls/imports/inheritance/composition only.
// excludeLabel (multi-root workspaces ONLY, A12): when non-empty, each --exclude
// substring is matched against the LABELED spelling `<excludeLabel>/<root-relative-path>` instead of the
// crawled path — so ONE excludes list applies uniformly across roots and `--exclude=lib1/` scopes to the
// root labeled lib1. Empty (the default, every single-root call) ⇒ behavior byte-identical to today.
IngestResult ingest( const char* rootDir, const std::vector<std::string>& excludeSubstr = {},
                     std::string_view cacheFile = {}, std::size_t maxFileBytes = kDefaultMaxFileBytes,
                     bool captureValueUses = true, std::string_view excludeLabel = {} );

// ---- shared AST-query pass (powers --match structural search + --lint) ----
// Re-parse the already-crawled files in parallel and run one or more tree-sitter queries over each tree.
// Each spec's query is compiled against every grammar it is VALID for (others are skipped), so a
// C-family query simply doesn't fire on Python files, etc. A query must contain at least one @capture;
// each captured node becomes a match. Results are sorted (file, startByte, endByte, tag) — endByte is
// load-bearing: a nesting kind puts an outer and an inner capture at the SAME startByte, and without it
// the unstable sort leaks the parallel fan-out's arrival order (nondeterministic --match/--lint output).
struct AstQuerySpec { std::string query; std::string tag; };   // tag = lint rule name, or "" for raw --match
struct AstMatch     { std::uint32_t fileId; std::uint32_t startByte; std::uint32_t endByte; std::uint32_t line; std::string tag; std::string text; };

// maxMatches is PER SPEC TAG, not a shared pool (§P0.2). One walk of the tree serves every spec, but each
// tag's surviving rows are truncated against its OWN budget — so a query that saturates (e.g. every
// number_literal) can never starve a quiet one out of the result, which is what made `--lint` report
// `goto count="1"` on a tree holding two. Two specs sharing a tag deliberately share one budget.
// A tag whose kept count lands exactly ON maxMatches is a FLOOR: the caller must disclose it (the
// house rule --match already follows with hits_capped="1").
// uncompiledOut (optional): receives the query text of every spec that compiled for NO grammar — the
// caller can then refuse instead of presenting the resulting zero as a measurement (§P0.1's last gap).
std::vector<AstMatch> astQuery( const IngestResult& ing, const std::vector<AstQuerySpec>& specs, std::size_t maxMatches = 5000,
                                std::vector<std::string>* uncompiledOut = nullptr );

// ---- ONE parse pass serving N independent query GROUPS ----
// A group is a whole astQuery call's worth of work — its own spec table, its own per-TAG budget, its own
// uncompiled-spec disclosure — and it gets back exactly the vector astQuery would have returned for it.
// What is shared is the FILE WALK. `--lint` ran three astQuery passes (the built-in [AST] checks, the
// atoms pack, the cache pack) and every one of them re-read and re-parsed the whole corpus: three reads
// and three tree-sitter parses per file to answer three sets of questions about the SAME tree. Grouping
// them reads and parses each file ONCE and executes every group's queries against that one tree.
// Output is unchanged by construction: captures are bucketed per group as they are produced, and each
// bucket is then merged, sorted and truncated by exactly the code a standalone call runs.
//
// A group's rows normally come from its own TSQuery spec table. `walk` names a BUILT-IN TREE WALK
// instead — a check whose traversal no tree-sitter query can express, but which needs exactly the
// per-file work the query groups already do: one read, one parse, one newline index. Riding the shared
// walk is what stops such a check from re-reading and re-parsing the whole corpus for a FOURTH time.
// A walk group carries NO spec table (nothing to compile, nothing to disclose); it emits a single tag,
// so the per-tag budget below degenerates to one truncation of the sorted list — which is exactly the
// tail a standalone pass would run. Setting both `specs` and `walk` on one group is not supported.
enum class AstWalk : std::uint8_t
{
    None = 0,          // ordinary spec-driven group

    // ---- unreachable-code detection (joern-lite CFG sketch; built-in --lint rule "unreachable-code") ----
    // Pure-syntactic, intra-block: walk every genuine block node (compound_statement / block /
    // statement_block) and, once an UNCONDITIONAL terminator statement (return/break/continue/throw, plus
    // Python raise) is seen at that block level, flag the NEXT non-comment sibling statement in the SAME
    // block as unreachable. Conservative by construction: no dataflow, no cross-branch reasoning, `goto`
    // excluded (label targets are ambiguous), and any jump-target sibling (labeled_statement /
    // case_statement) after the terminator stops the scan. Every finding carries tag "unreachable-code";
    // the group's rows come back sorted (file path, startByte) like any other group's. Implementation:
    // ur_walkTree in ingest.cpp, next to the rest of the rule's helpers.
    //
    // This is a WALK and not a spec table because the rule is an ORDERED scan of a block's statement
    // siblings — "the first non-comment statement after an unconditional exit" — which no tree-sitter
    // pattern can express. What it shares with the query groups is the read, the parse and the newline
    // index; the traversal stays its own.
    UnreachableCode,
};

// The unreachable-code rule's own budget, named so every caller spends the same one.
inline constexpr std::size_t kUnreachableMaxHits = 5000;

struct AstQueryGroup
{
    const std::vector<AstQuerySpec>* specs         = nullptr;   // borrowed — the caller owns the spec table
    std::size_t                      maxMatches    = 5000;      // per-TAG budget, same semantics as astQuery's
    std::vector<std::string>*        uncompiledOut = nullptr;   // optional, same semantics as astQuery's
    AstWalk                          walk          = AstWalk::None;   // non-None ⇒ built-in walk, no specs
};

// keptBytesOut (optional): the walk is where the corpus gets READ, so a pass that runs after it and needs
// the same text was re-reading every file the walk had just closed. Pass a vector and the walk MOVES each
// file's bytes into it at slot fileId (resized here, written only by the worker that owns that file, so
// distinct indices never race) — the reader downstream then works from memory instead of the disk.
// PARTIAL BY CONSTRUCTION, and the caller must treat it that way: only files the walk got as far as
// resolving a grammar for are populated, so a slot can be empty because the file was skipped (unknown
// extension, unreadable, binary, markdown) or because the file is genuinely empty. Both cases mean the
// same thing to a consumer — fall back to your own read, which is what every consumer did for every file
// before this existed — so an empty slot needs no separate "was it filled" flag to stay correct.
// Costs one corpus's worth of bytes held for as long as the caller keeps the vector; the caller decides
// whether that trade is worth it, which is why this is opt-in and not the default.
std::vector<std::vector<AstMatch>> astQueryGrouped( const IngestResult& ing, const std::vector<AstQueryGroup>& groups,
                                                    std::vector<std::string>* keptBytesOut = nullptr );

// ---- §P0.1: the shape of a user's tree-sitter query, so a capture-less one is never a silent zero ----
// astQuery reports CAPTURES, so a query that binds none matches nothing it can report:
// `--match='(if_statement)'` returned a clean, confident hits="0" while `--match='(if_statement) @i'`
// returned 5000. The zero was indistinguishable from a true negative and it already did damage — a capture
// recorded `--match='(goto_statement)' → hits="0"` and that was read as "this repo has no gotos". It has two.
//
// The caller uses this to either AUTO-CAPTURE (safe only for a single top-level pattern: appending ` @m` to
// it is exactly what the user would have typed) or REFUSE with the add-@name message — never to emit the
// bare zero. Both flags are scanned OUTSIDE double-quoted strings, so an anonymous node like `"("` does not
// unbalance the group count and an "@" inside a #match? argument is not mistaken for a capture.
struct AstQueryShape
{
    bool hasCapture       = false;   // an @capture appears outside any string literal
    bool isSingleTopLevel = false;   // exactly one top-level (…) or […] group, with nothing beside it
    bool hasComment = false;         // a `;` line comment — an appended capture could land inside it
};

inline AstQueryShape astQueryShape( std::string_view query )
{
    AstQueryShape shape;

    // scan once: track string state + group depth, note the first group and whether anything follows it
    int         depth = 0;
    bool        inString = false, closedTopLevelGroup = false, sawContentAfterTopLevelGroup = false;
    std::size_t topLevelGroupCount = 0;
    for( std::size_t i = 0; i < query.size(); ++i )
    {
        const char c = query[i];
        if( inString )
        {
            if( c == '\\' ) { ++i; continue; }                    // escape: skip the escaped byte
            if( c == '"' )
            {
                inString = false;
            }
            continue;
        }
        if( c == '"' ) { inString = true; continue; }
        // `;` starts a tree-sitter query line comment: everything to end-of-line is inert, so an `@` (or a
        // group char) inside it must not count — `(goto_statement) ; @x` binds NOTHING and used to slip
        // past this scan as "has a capture", resurrecting the bare hits="0" §P0.1 made unreachable.
        if( c == ';' )
        {
            shape.hasComment = true;
            while( i + 1 < query.size() && query[i + 1] != '\n' )
            {
                ++i;
            }
            continue;
        }
        if( c == '@' ) { shape.hasCapture = true; continue; }
        if( c == '(' || c == '[' )
        {
            if( depth == 0 )
            {
                ++topLevelGroupCount;
            }
            ++depth;
            continue;
        }
        if( c == ')' || c == ']' )
        {
            if( depth > 0 )
            {
                --depth;
            }
            if( depth == 0 )
            {
                closedTopLevelGroup = true;
            }
            continue;
        }
        if( depth == 0 && closedTopLevelGroup && !std::isspace( static_cast<unsigned char>( c ) ) )
        {
            sawContentAfterTopLevelGroup = true;
        }
    }

    shape.isSingleTopLevel = ( topLevelGroupCount == 1 ) && ( depth == 0 ) && !inString && !sawContentAfterTopLevelGroup;
    return shape;
}

// ---- local-variable-indexing plan, Phase 2 (PLAN.md 2026-08-06 evening) ----
// On-demand re-parse of ONE already-gated function's own byte span [sigStartByte, endByte) — reusing
// Phase 1's cc_isCountableLocalDecl/cc_declHasStructuredBinding predicates so the SET of declarations this
// walk visits is provably the same set Phase 1's `locals=` count already covers (no second, silently
// divergent rule). C/C++ only (model.h::localsCountedLang; the caller must gate on it — this function
// degrades to an empty result for any other lang rather than assert, since a caller mistake here is a
// missing finding, not a memory-safety issue). NEVER cached, NEVER promoted into IngestResult/Symbol/the
// call graph — call sites are expected to be RARE (only functions clearing naminglens.h's size+locals
// gate), so a fresh re-parse per call is the right cost/simplicity tradeoff, not a hot-path concern.
// `defBytes` = the exact substring `fileBytes.substr( sigStartByte, endByte - sigStartByte )` (a full
// function/method definition, which parses standalone under the C/C++ grammar); `defStartLine` = the
// 1-based file line `sigStartByte` falls on, so each fact's `line` is an ABSOLUTE file line, not a row
// local to the re-parsed substring.
std::vector<LocalNameFact> collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang );

}   // namespace rw
