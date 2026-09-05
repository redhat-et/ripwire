#pragma once

// mcp.h — --mcp: expose ripwire as an MCP tool over stdio. Newline-delimited
// JSON-RPC 2.0; three methods (initialize / tools/list / tools/call). Hand-rolled minimal
// JSON (sufficient for these well-formed shapes) — no JSON library dependency.
//
// This file is the SERVER ENTRY: the verb registry (kMcpVerbTable) + runMcp() (the stdio
// dispatch loop + the tools/list JSON stanzas). The rest of the MCP implementation was split
// out (mechanical concern-split) into four one-way-included headers:
//   • mcpjson.h  — the JSON-RPC protocol layer (parse/escape helpers; no index dependency)
//   • mcpindex.h — the warm in-memory McpIndex, staleness/watcher machinery, getIndex(),
//                  the workspace registry, and the stable content-handle system   (includes mcpjson.h)
//   • mcpverbs.h — the per-verb text/JSON builders (for/lego/impact/uses/connect/fetch_body/…)  (includes mcpindex.h)
//   • mcpedit.h  — the symbol-addressed EDIT verbs + runEditVerb()                 (includes mcpindex.h)
// Include direction is strictly one-way: mcpjson → mcpindex → {mcpverbs, mcpedit} → mcp. No cycles.

#include "mcpverbs.h"      // the read/flagship verb builders runMcp dispatches to (pulls mcpindex.h → mcpjson.h)
#include "mcpedit.h"       // the edit verbs + runEditVerb runMcp dispatches to

#include "infra/stdinline.h"     // R4: readByteSafeLine — the byte-safe stdin line reader the request loop runs on
#include "infra/blanktext.h"     // §S3: hasVisibleContent / blankPayloadSpelling + the derived kBlankRanges table

#include <cstdio>          // stdin / std::fputs — the stdio request loop
#include <iostream>        // no longer used HERE (R4 retired the std::cin getline) — kept because downstream
                           // translation units have long picked <iostream> up through this header
#include <string>
#include <cstdlib>         // ::realpath — the workspace-pin canonicalization (mcpCanonRoot)
#include <climits>         // PATH_MAX
#include <unistd.h>        // ::getcwd — R2a: the launch-cwd assumed root (resolved once at startup)

namespace rw
{

// ─── MCP verb registry (A4-S2) ───────────────────────────────────────────────────────────────
// The single source of truth for "what verbs does this server expose" outside the hand-written
// tools/list JSON stanzas below (see `method == "tools/list"` further down this file). Consumers
// that need the verb NAMES (e.g. wrap.h's recipe printer) read this table instead of re-deriving
// or hand-copying the list, so a new verb can't ship without showing up everywhere that matters.
//
// *** KEEP IN SYNC WITH tools/list BELOW ***  Adding/removing/renaming a `{"name":"..."}` stanza
// in the tools/list JSON must add/remove/rename the matching row here, in the same relative
// order, and update kMcpVerbCount. test/wrapverbscheck.sh enforces this at test time by diffing
// a live tools/list call against `ripwire wrap claude`'s output — it fails loudly on drift even
// if this comment is ignored.
enum class McpVerbGroup { Read, FlagshipReflex, Edit };

struct McpVerbInfo
{
    const char*   name;    // exact "name" field from the tools/list stanza
    const char*   blurb;   // short one-line description for recipe / doc surfaces (NOT the full MCP description)
    McpVerbGroup  group;   // read | flagship-reflex | edit — how wrap.h buckets the recipe listing
};

inline constexpr McpVerbInfo kMcpVerbTable[] = {
    // ── read verbs (no side effects) ──
    { "analyze",                 "architecture map for a directory (PageRank + signatures + call graph)", McpVerbGroup::Read },
    { "find_symbol",             "one symbol's 1-hop neighborhood (callers + callees)",                    McpVerbGroup::Read },
    { "find_referencing_symbols","direct (1-hop) callers of a symbol",                                     McpVerbGroup::Read },
    { "grep",                    "trigram literal search, hits annotated with enclosing symbol",           McpVerbGroup::Read },
    { "cochange",                "files that historically change together with a file",                   McpVerbGroup::Read },
    { "memory_recall",           "most relevant memory notes / docs for a task, full text",                McpVerbGroup::Read },
    { "situational_awareness",   "blast radius / tests_to_run / forgotten co-change / hotspots for a diff", McpVerbGroup::Read },
    { "mentions",                "docs that name a code symbol in a backtick",                             McpVerbGroup::Read },
    { "for",                     "task-lens ranked, signatures-only inventory of building blocks",         McpVerbGroup::Read },
    { "lego",                    "one interface's contract + every implementor",                           McpVerbGroup::Read },
    { "owners",                  "bus-factor / recency-weighted author ownership per file",                McpVerbGroup::Read },
    { "fetch_body",              "full (or partial-range) source of a symbol, by stable handle",           McpVerbGroup::Read },
    { "batch",                   "N read sub-queries answered in one call — deduped one-turn context sweep", McpVerbGroup::Read },
    // ── flagship-reflex verbs (write-moment / before-you-call-it-done / is-it-safe-to-change) ──
    { "exemplar",                "repo's best-in-class instance of a kind, to imitate before you write",   McpVerbGroup::FlagshipReflex },
    { "quality_delta",           "only what your working tree made WORSE vs baseline, before you call it done", McpVerbGroup::FlagshipReflex },
    { "quality_baseline",        "pin the quality floor (writes .ripwire_quality_baseline sidecar)",       McpVerbGroup::FlagshipReflex },
    { "impact",                  "transitive blast radius of a symbol (is it safe to change?)",            McpVerbGroup::FlagshipReflex },
    { "uses",                    "the resolvable use-sites of a symbol (call/read/write/import/extends)",  McpVerbGroup::FlagshipReflex },
    { "path_between",            "shortest directed call path from A to B (does A reach B, and how?)",     McpVerbGroup::FlagshipReflex },
    { "connect",                 "minimal connecting subgraph over N symbols (how do they relate?)",       McpVerbGroup::FlagshipReflex },
    // L4: the one-call orientation front door + B11 verb parity. `pack_task` is a
    // DISPATCH-only synonym for `explore` (same handler, same tools/list-less discoverability trade — see
    // the tools/list `explore` description) — it gets no separate row here (kMcpVerbCount stays in lockstep
    // with the number of ADVERTISED tools, not every callable alias).
    { "explore",                 "ONE-call task orientation: routed ranking + bodies + callers + notes + tests_to_run under a budget", McpVerbGroup::FlagshipReflex },
    { "from_trace",              "map a pasted stack trace / sanitizer report / compiler error onto indexed symbols", McpVerbGroup::FlagshipReflex },
    { "edit_check",              "did MY edit change a contract callers depend on, vs git HEAD",            McpVerbGroup::FlagshipReflex },
    // The cross-branch + dark-content verbs. `stray_content`/`whereis` answer "where
    // does this content live?" across every branch (the question `git cherry` cannot); `flags` answers
    // "what is built but dark here?". `merge_scout` stays CLI-only (it takes a hand-authored ref LIST).
    { "whereis",                 "which branch's tree defines or mentions SYM (and does the live line have it?)", McpVerbGroup::FlagshipReflex },
    { "stray_content",           "per branch: content it authored that HEAD lacks — unmerged vs superseded",  McpVerbGroup::FlagshipReflex },
    { "flags",                   "what is BUILT but DARK: compile / CMake option / getenv gates + guarded size", McpVerbGroup::Read },
    { "doc_drift",               "which markdown doc claims are now false: dead file:line, gone symbols, stale numbers", McpVerbGroup::Read },
    // lane/tc-sliceat: the ARISE def-use slice (arXiv:2605.03117) as an MCP read — the CLI --slice
    // contract verb-for-verb (inventory / VAR rows / flow / the @FILE:LINE seed), one emitter, two surfaces.
    { "slice",                   "per-line def-use rows of one variable inside one definition (+ transitive flow)", McpVerbGroup::Read },
    // ── edit verbs (side-effecting; safety contract = refusal leaves the file byte-identical) ──
    { "replace_symbol_body",     "replace a symbol's entire definition with new_body",                     McpVerbGroup::Edit },
    { "insert_before_symbol",    "insert text immediately before a symbol's definition",                   McpVerbGroup::Edit },
    { "insert_after_symbol",     "insert text immediately after a symbol's definition",                    McpVerbGroup::Edit },
};

inline constexpr std::size_t kMcpVerbCount = 31;   // +1 lane/tc-sliceat: the `slice` read verb
static_assert( sizeof( kMcpVerbTable ) / sizeof( kMcpVerbTable[0] ) == kMcpVerbCount,
               "kMcpVerbTable size drifted from kMcpVerbCount — update both together (A4-S2)" );

// The @FILE:LINE line-seed sentence, SPLICED into every stanza whose selector resolves it (the
// kExemplarSelectionRule pattern: one constant, nine descriptions, zero drift). This is the no-name
// selector for the agent that holds a LOCATION — a diff hunk, a compiler error, a stack frame — and the
// tools/list description is the only place an MCP agent can learn a spelling exists: an unadvertised
// selector does not exist on this surface. The CLI twin of this sentence is the --at help text (cli.h)
// and the contract is test/atcheck.sh; the MCP gate is mcpverbscheck §7.
inline constexpr std::string_view kAtSeedDocClause =
    "@FILE:LINE (a 1-based line-seed, e.g. @src/main.cpp:120) also resolves: the innermost definition "
    "enclosing that line — paste a location from a diff/error/stack frame instead of a name; a bad seed "
    "is refused with a specific diagnosis, never guessed.";

// The short form for the other @-capable stanzas (A4-R7 trimmed descriptions: the full sentence once, on
// the verbs that headline the moment, a pointer elsewhere — the inputSchema field description carries the
// per-field wording either way, from kMcpRequiredFields' needs column).
inline constexpr std::string_view kAtSeedShortClause = "@FILE:LINE line-seeds resolve here too (see find_symbol).";

// The NAME-matching scan verbs' variant (mentions/owners, 2026-08-30 decision round): these verbs match by
// NAME, so a line-seed cannot narrow the scan — instead it REBINDS to the innermost enclosing definition
// and the answer says so ('sym'), the one-step-smart-defaults posture: the call carries the answer, never
// a pass-the-name-yourself retry.
inline constexpr std::string_view kAtSeedRebindClause =
    "An @FILE:LINE line-seed rebinds to the innermost definition enclosing that line and answers for it, "
    "disclosing the rebound name as 'sym' (see find_symbol for the seed grammar).";

// §B6 M14: the batch verb's EXCLUSION count, DERIVED. batch's tools/list stanza named its exclusions in a
// hand-written parenthetical ("NOT the edit or quality_baseline verbs") that covered 4 of the verbs it
// actually refuses — exactly the kind of number that is only ever wrong because someone hand-counted it.
//
// The subtraction is now the WHOLE of it: every ADVERTISED verb, minus the set batch serves (mcpverbs.h's
// kBatchServedVerbs — the registry runBatchSub itself dispatches from). Verifier N1: M14's first version
// subtracted a further `- 1` "for batch itself", which DOUBLE-counted it — `batch` is advertised and is
// absent from kBatchServedVerbs, so the first subtraction has already excluded it, and the count came out
// 15 where 16 verbs actually refuse. That the assert passed is the tell: it pinned the wrong number, so it
// would have fired on a future CORRECT edit. The stanza's own prose lists the exclusions by name and lists
// SEVENTEEN of them (3 edit + quality_baseline + quality_delta + batch + the 10 whole-repo/cross-branch
// verbs + slice, the lane/tc-sliceat per-definition read not yet in the sweep), which is the arithmetic
// below and was never the number printed beside it.
//
// P17 (capture-audit 2026-09-04): slice and edit_check joined kBatchServedVerbs, so the count moves 17 → 15
// by the SAME subtraction — nothing here is hand-recounted, the assert is what pins the prose to it.
//
// The static_assert is the build-time tripwire; test/mcptranchecheck.sh's M14 arm is the runtime one, and
// it derives its expectation by ENUMERATION (it asks the live batch arm which verbs refuse and counts them)
// rather than by re-running this formula — a gate that restates the formula cannot catch the formula.
inline constexpr std::size_t kBatchExcludedCount = kMcpVerbCount - kBatchServedCount;
static_assert( kBatchExcludedCount == 15,
               "the batch tools/list stanza spells kBatchExcludedCount in prose — a verb joined or left "
               "kMcpVerbTable / kBatchServedVerbs; update the stanza's number and this assert together" );

// V3/F4: how far kBatchExcludedCount moves when the git-backed verbs are omitted from tools/list. The
// subtraction is over the git-only verbs batch does NOT serve, because those are the ones sitting in the
// EXCLUDED half of the count; `owners` is git-only AND batch-served, so dropping it removes one from each
// side of the subtraction and leaves the difference alone. Derived from the two tables rather than written
// as "2" for the same reason M14's own count is derived: a hand-counted intersection is only ever wrong.
constexpr std::size_t mcpGitOnlyNotBatchServed() noexcept
{
    std::size_t notServed = 0;
    for( const mcprefuse::McpGitOnlyVerb& row : mcprefuse::kMcpGitOnlyVerbs )
    {
        bool served = false;
        for( const std::string_view batchVerb : kBatchServedVerbs )
        {
            if( std::string_view( row.verb ) == batchVerb ) { served = true; break; }
        }
        if( !served )
        {
            ++notServed;
        }
    }

    return notServed;
}
static_assert( mcpGitOnlyNotBatchServed() < kBatchExcludedCount,
               "every advertised verb would be batch-excluded once the git verbs are omitted — the two "
               "tables have drifted into overlap and the pruned batch count would be nonsense" );

// The number `batch`'s tools/list prose states, for a catalog that may or may not be pruned. Lives here,
// beside the arithmetic it depends on, so the tools/list assembly reads it rather than deciding it.
constexpr std::size_t mcpBatchExcludedCount( bool gitVerbsOmitted ) noexcept
{
    return gitVerbsOmitted ? kBatchExcludedCount - mcpGitOnlyNotBatchServed() : kBatchExcludedCount;
}

// finding #8: is `verb` one of the git-only omission set (mcprefusal.h's kMcpGitOnlyVerbs)? Shared by the
// served-list builder below, so "which verbs are git-only" has one answer rather than a second inline loop.
constexpr bool mcpIsGitOnlyVerb( std::string_view verb ) noexcept
{
    for( const mcprefuse::McpGitOnlyVerb& row : mcprefuse::kMcpGitOnlyVerbs )
    {
        if( verb == std::string_view( row.verb ) )
        {
            return true;
        }
    }
    return false;
}

// finding #8: the SERVED half of batch's tools/list description — the "each verb is one of for/grep/…/
// owners/cochange/…" slash-list — used to be a hand-copied literal that named `owners` unconditionally, even
// on a non-git pinned root where `owners` is itself OMITTED from tools/list (it is git-only AND
// batch-served — the one row mcpGitOnlyNotBatchServed's comment already calls out). Advertising, inside
// batch's own prose, a verb that tools/list does not otherwise advertise sends a caller looking for a tool
// this server does not offer here — the same class of dishonesty §B6 M14 fixed for the EXCLUDED half of
// this sentence, now applied to the served half. Built from kBatchServedVerbs (mcpverbs.h) rather than
// duplicated as a second literal, so the two cannot drift the way the hand-copied one did.
inline std::string mcpBatchServedVerbsList( bool gitVerbsOmitted )
{
    std::string out;
    bool        first = true;
    for( const std::string_view v : kBatchServedVerbs )
    {
        if( gitVerbsOmitted && mcpIsGitOnlyVerb( v ) )
        {
            continue;
        }
        if( !first )
        {
            out += "/";
        }
        out += v;
        first = false;
    }
    return out;
}

// ─── Protocol versions ───────────────────────────────────────────────────────────────────────
inline constexpr std::string_view kMcpLatestProtocolVersion = "2025-11-25";
inline constexpr std::string_view kMcpHttpFallbackProtocolVersion = "2025-03-26";
inline constexpr std::string_view kMcpServerInstructions =
    "Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus "
    "uses before changing a symbol; run edit_check after an edit and quality_delta before declaring work "
    "done. Use batch for several independent read queries in one turn. Fetch bodies only after ranked "
    "retrieval. Counts marked as floors are not totals; zero means none found, not none exists.";
inline constexpr std::string_view kMcpProtocolVersions[] =
{
    kMcpLatestProtocolVersion,
    "2025-06-18",
    kMcpHttpFallbackProtocolVersion,
    "2024-11-05"
};

inline bool isMcpProtocolVersionSupported( std::string_view version ) noexcept
{
    for( const std::string_view supported : kMcpProtocolVersions )
    {
        if( version == supported )
        {
            return true;
        }
    }
    return false;
}

// ─── Transport policy (stdio vs the remote HTTP transport) ────────────────────────────────────────
// The JSON-RPC request handler (dispatchMcpLine) is shared byte-for-byte between the stdio loop and the
// HTTP server (mcpserver.h). The ONLY behavioural difference between the two transports lives in this
// struct — everything else (verb dispatch, output bytes, staleness, redaction) is transport-agnostic.
//   • pinnedRoot — empty over stdio (a request may name ANY path). Non-empty over the remote transport:
//     the listener serves exactly ONE workspace fixed at startup ("one listener =
//     ONE workspace"). A tools/call whose `path`/`paths` names a DIFFERENT tree is refused with a clean
//     error and NO index rebuild; an OMITTED path defaults to the pinned workspace.
//   • defaultRoot (D3/D4, X7) — stdio's own, SOFTER counterpart of pinnedRoot: non-empty only when
//     `ripwire <root> --mcp` was given a startup root (mutually exclusive with pinnedRoot — stdio never
//     sets pinnedRoot). An OMITTED path defaults to it for every verb, mirroring the HTTP default-to-pinned
//     step above; but unlike pinnedRoot, an EXPLICIT path naming a different tree is only refused for the 3
//     EDIT verbs (a read verb reaching across a sibling checkout is a feature stdio has always offered).
//   • editsAllowed — true over stdio (a co-located agent). false over the remote transport by default
//     (a remote agent editing local files is a categorically different trust
//     contract, so an edit verb is refused (file byte-identical) unless the operator opted in with
//     --allow-remote-edits, which also forces the bearer-token requirement.
//   • assumedRoot (R2a, the 2026-08-12 usage mine) — the SOFTEST tier, below defaultRoot: the shipped
//     install (`ripwire wrap …` → bare `--mcp`, no startup root) refused every omitted `path`, and the
//     mine shows a missing `path` is THE dominant MCP failure mode. But that server still has a root:
//     the directory its host launched it in (MCP hosts launch stdio servers in the workspace). Resolved
//     once at startup (getcwd, guarded — never "/" and never $HOME itself: a crawl of either is nobody's
//     workspace, so those keep the explicit-path refusal), consulted ONLY when a request omits `path`
//     AND no defaultRoot/pinnedRoot exists, and always DISCLOSED in the response envelope
//     (`_assumed_root`) — one-step-smart-defaults: the cheapest complete answer, said out loud.
//     Empty ⇒ the pre-R2a "every request names its own path" refusal, unchanged.
//   • pinnedRootHasGit (V3/F4) — meaningful ONLY beside a non-empty pinnedRoot: can the git-backed verbs
//     (mcprefusal.h's kMcpGitOnlyVerbs) answer about that workspace at all? Resolved ONCE at listener
//     startup (mcpserver.h) because the workspace is fixed for the listener's life and the probe forks git.
//     false ⇒ those verbs are OMITTED from tools/list and the omission is announced in `instructions`.
//     Defaults TRUE so every stdio path (which never pins) advertises the full catalog untouched — see
//     the omitGitVerbs comment in the tools/list branch for why omission is pinned-only.
//   - pinnedRootIsGitDir (finding #7) — meaningful ONLY when pinnedRootHasGit is false: does the workspace
//     sit INSIDE a git repo at all (`.git` present, `rev-parse --show-toplevel` succeeds) that simply has
//     no HEAD commit yet, versus not being a git repo in the first place? The two causes were collapsed
//     into one sentence ("this server's workspace is not a git repository") that is FALSE for the first
//     case — a `git init` with no commit IS a git repository, it has no HEAD, exactly the qualifier every
//     git-only verb's OWN refusal already carries ("not a git repository (or no HEAD commit)"). Resolved
//     ONCE at listener startup alongside pinnedRootHasGit (one more `git rev-parse` fork, only when the
//     first probe already failed — never on the common git-with-history path). Meaningless (left false)
//     when pinnedRootHasGit is true, since the disclosure it feeds is never rendered in that case.
struct McpDispatchPolicy
{
    std::string pinnedRoot;         // "" = stdio (no pinning); non-empty = the remote transport's fixed workspace key/root
    bool        editsAllowed = true;   // false = refuse the 3 edit verbs (remote default)
    std::string defaultRoot;        // "" = no stdio startup root given; else the canonicalized `ripwire <root> --mcp` root
    std::string assumedRoot;        // "" = no guessable root; else the canonicalized launch cwd (stdio, no startup root) — see above
    bool        pinnedRootHasGit = true;   // see above — only read when pinnedRoot is non-empty
    bool        pinnedRootIsGitDir = false;   // see above — only read when pinnedRootHasGit is false
};

// canonicalize a root path for the workspace-pin comparison: realpath when it resolves, else the string
// as-is (a registered multi-root workspace KEY is not a filesystem path — it compares as its literal key).
inline std::string mcpCanonRoot( const std::string& root )
{
    char buf[ PATH_MAX ];
    if( ::realpath( root.c_str(), buf ) )
    {
        return std::string( buf );
    }
    return root;
}

// R2a: resolve the launch cwd as the bare stdio server's assumed root — see McpDispatchPolicy::
// assumedRoot for the contract. Guarded here, once: "/" and $HOME itself are nobody's workspace (a
// crawl of either is a mistake, not a smart default), and a getcwd failure degrades to "" — the
// pre-R2a missing-path refusal, never a guess.
inline std::string mcpResolveAssumedRoot()
{
    char cwdBuf[ PATH_MAX ];
    if( ::getcwd( cwdBuf, sizeof( cwdBuf ) ) == nullptr )
    {
        return {};
    }
    const std::string launchCwd = mcpCanonRoot( cwdBuf );
    const char* const homeEnv   = std::getenv( "HOME" );
    const std::string homeCanon = homeEnv ? mcpCanonRoot( homeEnv ) : std::string{};
    if( launchCwd == "/" || ( !homeCanon.empty() && launchCwd == homeCanon ) )
    {
        return {};
    }
    return launchCwd;
}

// R2a: rebind an OMITTED `path` to the assumed root (the softest tier — a pre-composed refusal, both
// harder root tiers, and an explicit path all take precedence). Returns the disclosure sentence for the
// result envelope's `_assumed_root` sibling, or "" when nothing was assumed — the honesty rule: an
// assumed answer says it assumed.
inline std::string mcpAssumeRootIfOmitted( const McpDispatchPolicy& policy, std::string& path, bool priorRefusal )
{
    if( priorRefusal || !policy.pinnedRoot.empty() || !policy.defaultRoot.empty() || policy.assumedRoot.empty() || !path.empty() )
    {
        return {};
    }
    path = policy.assumedRoot;
    return "[assumed root: " + policy.assumedRoot + " — no path was given, so this answer is about the server's launch directory; pass path= to ask about another tree]";
}

// R2a: the `_assumed_root` envelope-sibling fragment (the mcpReingestField shape): "" when nothing was
// assumed, else the JSON field ready to splice — keeps the ternary out of the response assembly.
inline std::string mcpAssumedRootField( const std::string& note )
{
    if( note.empty() )
    {
        return {};
    }
    return ",\"_assumed_root\":\"" + mcpdetail::jsonEscape( note ) + "\"";
}

// is `candidatePath` the workspace root itself, or STRICTLY inside it — a path-COMPONENT prefix, so a
// sibling directory that merely shares a text prefix (root "/repo" vs candidate "/repo-foo") never matches.
// `canonRoot` must already be canonicalized (mcpCanonRoot); `candidatePath` is canonicalized here so callers
// can pass the raw request argument straight through. Used by the stdio edit-verb workspace pin (X7): the
// containment check, not a hand-rolled string comparison, is what makes "outside the root" mean anything.
inline bool mcpPathInsideRoot( const std::string& canonRoot, const std::string& candidatePath )
{
    if( canonRoot.empty() )
    {
        return false; // an unset root contains nothing — never treat "" as "everywhere"
    }
    const std::string canonCandidate = mcpCanonRoot( candidatePath );
    if( canonCandidate == canonRoot )
    {
        return true;
    }
    const std::string prefix = canonRoot.back() == '/' ? canonRoot : canonRoot + "/";
    return canonCandidate.size() > prefix.size() && canonCandidate.compare( 0, prefix.size(), prefix ) == 0;
}

// is `name` one of the 3 side-effecting edit verbs? (the remote transport refuses these unless opted in).
//
// §H2 — this predicate ALSO gates the pre-dispatch required-field check in dispatchMcpLine, for one reason:
// these are the verbs where a missing argument is not a wrong ANSWER but a wrong WRITE. The three edit arms
// guarded `path` + `symbol` and never tested the PAYLOAD field, so an omitted new_body / text reached
// runEditVerb as an empty string and was APPLIED — replace_symbol_body with no new_body answered
// {"applied":…} and DELETED the definition from disk, on both transports. A read verb reaches the same
// missing-field message by FALL-THROUGH (only if no arm matched, i.e. only if every conjunct was
// remembered); for a write verb that is too late and too easy to forget, so the verdict is taken from the
// table (mcprefusal.h's kMcpRequiredFields, rendered by the SAME missingArgMsg the fall-through uses, so
// there is one wording in one place) BEFORE the dispatch chain — no getIndex(), no open, no byte written.
//
// Keyed on this predicate rather than written out as three more arm conjuncts because the conjunct list is
// exactly what drifted from the table, and because a FOURTH edit verb then inherits the check by joining
// the one list that already decides "does this write" — which as of the wave-1 sweep is literally true:
// isMcpEditVerb reads `kMcpVerbTable`'s own `McpVerbGroup::Edit` column, so "joining the list" is joining the
// registry. When this sentence was first written the predicate spelled the three names out and the claim was
// aspirational; see the sweep note at isMcpEditVerb. Deliberately NOT hoisted for the read verbs: the
// enumeration arm of test/mcpeditpresencecheck.sh shows all 27 other required-field cases already refuse
// correctly, and hoisting it for them would reorder refusals other gates pin (connect reports a bad
// `radius` before an absent `symbols`).
//
// So the edit arms below must NOT re-state the payload as a conjunct, and must never read an absent payload
// as "splice nothing". An OMITTED payload and an explicit `new_body:""` are the same refusal, on argPresent's
// emptiness contract — the meaning "present" already has for all 13 schema-typed string fields, and the one
// the table's own wording implies ("the complete, well-formed replacement definition"). An empty new_body is
// NOT read as a delete-the-body request: it is the mistyped/unset argument that used to delete bodies.
//
// ── ITEM A (pre-wave verifier, MED): the equivalence class is WIDER than "" ─────────────────────────────
//
// The ruling above was pinned as "present" == `!newBody.empty()`, so anything of size >= 1 passed it — and a
// WHITESPACE-ONLY payload still deleted the definition and reported {"applied":…}: `new_body:" "`, `"\n"`,
// `"\t"`, `"   \n\t  "` each replaced `int alpha( int x ) { return x + 1; }` with a blank line, on stdio AND
// over HTTP with --allow-remote-edits. The verifier is right that this is the same finding: the class the §H2
// ruling belongs to is "a payload that carries NO DEFINITION", and the table's own words for the field are
// "the complete, well-formed replacement definition". Nothing whose every character is invisible is that.
//
// THE RULING, and its bright line. A payload carries content iff it has at least ONE code point that occupies
// a visible column. NUL is deliberately not its own case: a payload of NULs is no more a definition than a
// payload of spaces, and a client that reached `U+0000` for a definition has the same unset-argument bug.
// (A NUL *inside* real content is untouched — the rule is about payloads that are ENTIRELY invisible, never
// about individual bytes. This comment SPELLS the character rather than containing one; see the F3 note in
// src/infra/blanktext.h for what the literal byte cost.)
//
// An INVALID UTF-8 byte counts as CONTENT, and so does an unassigned (Cn) code point: garbage bytes are a
// different problem with a different fix, and silently widening a write refusal to cover them would blame this
// field. The asymmetry is deliberate and it has a direction — over-refusing costs a rejected write the caller
// sees in a named refusal and can retry; under-refusing DELETES a definition and reports success.
//
// ── WAVE-1 VERIFIER (F2, MED) + (F3, MED) — MOVED to src/infra/blanktext.h ─────────────────────────────────────
//
// The derived blank-code-point TABLE, the two UTF-8 walks over it (hasVisibleContent / blankPayloadSpelling)
// and the two verifier findings that shaped them now live in **src/infra/blanktext.h**, included at the top of this
// file. §S3 (capture-audit-4) found `--note-add` answering the SAME "present but carries nothing" question
// with a THIRD, weaker predicate, so the rule was hoisted out of this MCP server rather than copied again.
// The ruling ABOVE and the SCOPE below are MCP's and stay here; the table is text machinery and is not.
//
// SCOPE — the three PAYLOAD fields only (`new_body`, `text`), never the read verbs' required strings. That is
// not timidity, it is that the widening would be WRONG for them: `pattern:" "` is a legitimate literal search
// for a space, and `symbol:" "` / `task:" "` / `file:" "` / `handle:" "` already refuse truthfully with the
// spelling echoed ("symbol not found: ' '") — a second sentence for a case already refused correctly is noise.
// insert_before/insert_after are ruled the SAME as replace even though inserting whitespace is benign
// (they only insert): a per-verb carve-out at a write seam is how the next one gets forgotten, and "the text
// to insert" is not a description of a blank.
// ── WAVE-1 SWEEP (this lane): the guard that was never wired to the table it already has ─────────────────
//
// This predicate used to spell the three names out as a disjunction, immediately under a comment claiming that
// "a FOURTH edit verb then inherits the check by joining the one list that already decides 'does this write'".
// The claim was false: the list a new verb joins is `kMcpVerbTable`, which has declared `McpVerbGroup::Edit`
// for exactly these three since A4-S2 — the disjunction here was a SECOND list, and the one a fourth verb
// would not be in. That matters more than the usual duplicate-table complaint because this predicate is the
// sole gate on THREE safety decisions: the remote transport's edit refusal (`!policy.editsAllowed`), the
// off-workspace-root refusal for writes, and §H2's pre-dispatch required-field check. A fourth edit verb added
// to the registry would have shipped with none of them, writing to disk over an un-opted-in remote transport
// with an unchecked payload — which is §H2 and the remote-edit contract, both, in one omission.
//
// So the verdict now comes from the registry's own group column. Same answer today (asserted below), and a new
// row tagged Edit inherits all three guards by existing.
inline bool isMcpEditVerb( std::string_view name ) noexcept
{
    for( const McpVerbInfo& verb : kMcpVerbTable )
    {
        if( name == verb.name )
        {
            return verb.group == McpVerbGroup::Edit;
        }
    }

    return false;   // an unadvertised name is not a write — the unknown-tool refusal owns that request
}

// how many registry rows are tagged Edit? The tripwire below is a FLOOR, not a count, and it only fires in
// the dangerous direction: a fourth edit verb raises the number and passes, while DELETING the group tag or
// downgrading a write verb to Read drops it and fails the build — and that drift would silently open all three
// guards named above, with no test failing, because every gate on this surface names the verbs it probes.
consteval std::size_t mcpEditVerbCount() noexcept
{
    std::size_t editVerbCount = 0;
    for( const McpVerbInfo& verb : kMcpVerbTable )
    {
        if( verb.group == McpVerbGroup::Edit )
        {
            ++editVerbCount;
        }
    }

    return editVerbCount;
}

static_assert( mcpEditVerbCount() >= 3,
               "fewer than 3 kMcpVerbTable rows are tagged McpVerbGroup::Edit — isMcpEditVerb reads that tag, "
               "and a write verb that loses it loses the remote-edit refusal, the workspace check AND the §H2 "
               "payload-presence check at once. A FOURTH edit verb raises this floor; nothing lowers it." );

// V3/F4: is this server's catalog PRUNED of the git-backed verbs (mcprefusal.h's kMcpGitOnlyVerbs)? Both
// methods that touch the catalog read this ONE predicate — `initialize` announces the omission and
// `tools/list` performs it — because a catalog that omits without announcing, or announces without
// omitting, is worse than either.
//
// PINNED-ONLY, and the scope is the whole argument. A pinned listener serves ONE workspace and REFUSES a
// `path` naming a different tree, so "this workspace has no git" and "these verbs cannot answer for any
// request this server will accept" are the same statement. Every stdio server — bare, or with a
// `ripwire <root> --mcp` startup root — still answers read verbs about ANY path the caller names, so its
// git verbs CAN succeed and omitting them would advertise LESS than the truth, which is the same class of
// dishonesty as advertising more. Contract gate: test/mcptoolprunecheck.sh, arms (A)/(F)/(G).
inline bool mcpOmitsGitVerbs( const McpDispatchPolicy& policy ) noexcept
{
    return !policy.pinnedRoot.empty() && !policy.pinnedRootHasGit;
}

// the result of handling one JSON-RPC request line — shared by both transports.
struct McpDispatchResult
{
    std::string resp;                 // the JSON-RPC response bytes (no framing) — empty + isNotification for a notification
    bool        isNotification = false;   // true ⇒ a JSON-RPC notification: NO reply is sent (stdio skips; HTTP → 202)
    std::string timingVerb;           // the method, refined to the tool name for tools/call (MEASURE-FIRST timing attribution)
};

// Handle ONE JSON-RPC request line and build its response. This is the SINGLE request-handling path both
// the stdio loop (runMcp) and the HTTP server (runMcpHttp, mcpserver.h) route through, so a given JSON-RPC
// body returns byte-identical bytes regardless of transport ("the
// JSON-RPC layer is byte-identical; only the transport wrapper is new"). `policy` carries the only
// transport-specific behaviour (workspace pinning + edit refusal). Never throws — a bad path / OOM must
// not std::terminate a long-lived server.
inline McpDispatchResult dispatchMcpLine( const std::string& line, int topK, bool stable, bool noRedact,
                                          const McpDispatchPolicy& policy )
{
    McpDispatchResult out;
    {
        // ── §H3: the FRAMING GATE — before a single field is read out of this frame ─────────────────────────
        //
        // A truncated frame used to be DISPATCHED, because the key-position scanner happily reads a complete
        // `params` out of a cut-off envelope: a mid-stream `replace_symbol_body` with no closing brace REWROTE
        // THE FILE, a `tools/list` with no closing brace returned a full successful listing, and the truncated
        // tail at EOF was refused with a cause about a field whose value was sitting in the bytes. See
        // mcpjson.h's checkFrame for the scan and for why it is a completeness gate, not a second parser.
        //
        // Placed in the SHARED handler, so stdio (where the edit verbs live and where `ripwire wrap claude`
        // runs) gets the check the HTTP transport got for free from Content-Length. Answered with id:null on
        // purpose: JSON-RPC 2.0 requires a null id whenever the id could not be reliably detected, and in a
        // frame we have just judged un-whole no field is reliable — including that one.
        if( const mcpdetail::FrameCheck frame = mcpdetail::checkFrame( line );
            frame.shape != mcpdetail::FrameShape::Object )
        {
            const mcprefuse::McpFrameRefusal fr = mcprefuse::frameRefusal( frame.shape, frame.got );
            out.resp = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":" + std::to_string( fr.code )
                     + ",\"message\":\"" + mcpdetail::jsonEscape( fr.message ) + "\"}}";
            return out;
        }

        const mcpdetail::RawId rid = mcpdetail::findRawId( line );

        // §B6 M6a/M7: `method` is read for its SHAPE first. A present-but-wrong-typed method (`"method":5`) used
        // to read as ABSENT and land on `-32700 "parse error"` — a JSON document that parsed perfectly, told its
        // sender their writer was broken. Absent and wrong-shaped are now two different sentences, both naming
        // the field, both from mcprefusal.h's row for it.
        const mcpdetail::RawValue methodRaw = mcpdetail::findRawValue( line, "method" );
        const std::string         method    = methodRaw.isQuoted ? mcpdetail::findString( line, "method" ) : std::string{};

        std::string timingVerb = method;   // refined to the tool name inside the tools/call branch

        // JSON-RPC 2.0: a message with a method but WITHOUT an "id" key is a NOTIFICATION — replying is
        // forbidden (every MCP client sends notifications/initialized right after initialize; answering it
        // with an error breaks handshakes). A literal id:null still gets a reply (the key was present).
        // An envelope with no usable method is NOT a notification — a notification is defined by its method —
        // so it falls through to the two envelope refusals below and is answered, and the server stays alive.
        if( !rid.hasId && !method.empty() )
        {
            out.isNotification = true;
            out.timingVerb     = timingVerb;
            return out;
        }

        const std::string id = rid.token;
        std::string       resp;

        const bool omitGitVerbs = mcpOmitsGitVerbs( policy );   // V3/F4 — read once; both methods must agree

        // the envelope's own two shape/presence faults, checked once for all three methods.
        const McpObjectArg paramsArg = mcpObjectArg( line, "params" );
        if( methodRaw.isPresent && !methodRaw.isQuoted )
        {
            resp = "{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"error\":{\"code\":-32600,\"message\":\""
                 + mcpdetail::jsonEscape( mcprefuse::badValueRefusal( "method", methodRaw.text ) ) + "\"}}";
        }
        else if( !methodRaw.isPresent )
        {
            resp = "{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"error\":{\"code\":-32600,\"message\":\""
                 + mcpdetail::jsonEscape( mcprefuse::missingEnvelopeField( "method" ) ) + "\"}}";
        }
        else if( !paramsArg.refusal.empty() )
        {
            resp = "{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"error\":{\"code\":-32600,\"message\":\""
                 + mcpdetail::jsonEscape( paramsArg.refusal ) + "\"}}";
        // §B6 M11: `ping` — the one utility method both advertised protocol versions define, and the server
        // answered it with "method not found". A client using it as a liveness probe concludes the server is
        // broken. The spec's contract is exactly this: an empty result object, no params read, no side effect.
        }
        else if( method == "ping" )
        {
            resp = "{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"result\":{}}";
        }
        else if( method == "initialize" )
        {
            // W3FIX H3: the key lookups are TOP-LEVEL-only now (mcpjson.h's findKeyValuePos), and
            // protocolVersion is the ONE argument that legitimately lives one level down — the spec puts it at
            // `params.protocolVersion`. Spelled as two explicit reads (the spec position first, then a
            // top-level fallback for the clients that flatten it) rather than as an any-depth mode every other
            // caller would then have to reason about.
            const std::string initParams  = paramsArg.span;   // §B6 M7: the SHAPE-checked span (a wrong-typed `params` refused above)

            // §B6 M11: a WRONG-TYPED protocolVersion (`protocolVersion:5`) used to read as ABSENT, because
            // findString returns "" for a non-string value — so the server silently negotiated its latest
            // version for a client that had asked for something it could not even parse. That is the exact
            // absent-vs-wrong-shape collapse M7 fixed one level up the envelope, surviving on the one field
            // the envelope's own handshake reads. Both positions are shape-checked (spec position first, then
            // the top-level fallback for clients that flatten it), and a present-but-not-a-string value is
            // REFUSED with the domain and the value as typed instead of being answered around.
            //
            // An unknown but well-formed STRING version still negotiates the latest supported one — that is
            // the spec's own handshake behaviour ("If the server does not support the requested version, it
            // MUST respond with a version it does support"), and it is not the finding.
            const McpStringArg nestedVerArg = mcpStringArg( initParams, "protocolVersion" );
            const McpStringArg lineVerArg   = nestedVerArg.value.empty() && nestedVerArg.refusal.empty()
                                            ? mcpStringArg( line, "protocolVersion" )
                                            : McpStringArg{};
            if( !nestedVerArg.refusal.empty() || !lineVerArg.refusal.empty() )
            {
                resp = "{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"error\":{\"code\":-32602,\"message\":\""
                     + mcpdetail::jsonEscape( !nestedVerArg.refusal.empty() ? nestedVerArg.refusal : lineVerArg.refusal )
                     + "\"}}";
            }
            else
            {
                const std::string requestedVersion = !nestedVerArg.value.empty() ? nestedVerArg.value : lineVerArg.value;
                const std::string_view negotiatedVersion = isMcpProtocolVersionSupported( requestedVersion )
                                                         ? std::string_view( requestedVersion )
                                                         : kMcpLatestProtocolVersion;
                resp = "{\"jsonrpc\":\"2.0\",\"id\":" + id +
                       ",\"result\":{\"protocolVersion\":\"" + std::string( negotiatedVersion ) +
                       "\",\"serverInfo\":{\"name\":\"ripwire\",\"version\":\"1.0\"},\"capabilities\":{\"tools\":{}},"
                       "\"instructions\":\"" + mcpdetail::jsonEscape( std::string( kMcpServerInstructions )   // V3/F4: the
                                                    + mcprefuse::gitOnlyOmissionNote( omitGitVerbs, policy.pinnedRootIsGitDir ) ) + "\"}}";  // omission announces itself, finding #7: qualified by which cause it is
            }
        }
        else if( method == "tools/list" )
        {
            // §B6 M4: is `path` actually REQUIRED of this caller? Only when this server cannot supply a root
            // itself — no `ripwire <root> --mcp` startup root and no pinned remote workspace. That is the
            // DEFAULT shipped install (`ripwire wrap claude` passes no startup root), which is why every
            // `required` omitting `path` was wrong for almost every real deployment; but it is not a constant,
            // and a schema that declared it unconditionally would be newly wrong for the rooted server. Each
            // server answers for itself.
            //
            // V4: the try is here for the same reason as the one in the tools/call branch, which states the
            // invariant — a bad path or an OOM must not std::terminate a long-lived server. This branch was
            // outside it, and it is the single LARGEST allocation the server ever makes: one ~60 KB string
            // built by concatenating 30 verb stanzas, two of which (`exemplar`'s spliced selection rule and
            // `batch`'s std::to_string count) allocate again mid-expression. Those were the two sites the
            // verifier named as pre-existing; they are covered here, at the statement that owns them.
            //
            // Honest limit, stated rather than implied: the fallback below itself allocates, so this converts
            // "terminate on OOM" into "reply -32603 on OOM unless even a ~90-byte string cannot be built". It
            // is not a total no-allocation guarantee and does not claim to be — it is the same guarantee the
            // tools/call try already provides, now covering the branch that allocates the most.
            try
            {
            // R2a: assumedRoot joins the "can this server supply a root itself?" question — the M4
            // principle ("path is required exactly when this server cannot supply a root") is unchanged;
            // what changed is that the bare-`--mcp` stdio server now usually CAN (its launch cwd), so the
            // shipped install's schema stops demanding a field the dispatch no longer needs. The guarded
            // cases (cwd = "/" or $HOME ⇒ assumedRoot stays empty) keep declaring it required, truthfully.
            const bool pathIsRequired = policy.defaultRoot.empty() && policy.pinnedRoot.empty() && policy.assumedRoot.empty();
            const std::size_t batchExcluded = mcpBatchExcludedCount( omitGitVerbs );   // V3/F4
            // A4-R7: descriptions trimmed to decision-relevant content (when to use / what it answers /
            // the one non-obvious caveat) — cut repeated boilerplate ("Reach for this...", restated XML
            // shape agents don't need to CHOOSE the verb) that every connected agent paid for at session
            // start. Parameter schemas and every verb name are unchanged.
            resp = "{\"jsonrpc\":\"2.0\",\"id\":" + id +
                   ",\"result\":{\"tools\":["
                   // §B6 M10: the ORDER claim is split into its two true halves. \"ranked by PageRank\" was true of
                   // MEMBERSHIP (which symbols make the top-K) and false of the EMITTED order (this server runs the
                   // stable ordering, so rows come out grouped by file in a byte-stable order, not rank-descending).
                   // The header stanza's order= attribute names the emitted order; k= is absent under it, so an
                   // agent that wants the rank must read membership, not row position.
                   "{\"name\":\"analyze\",\"description\":\"Architecture map for a directory: signatures and the call graph for the top symbols. Use when landing cold in a repo or subdir, before reading files; for a task-scoped inventory use 'for', for one symbol's neighborhood find_symbol. path = directory to map. MEMBERSHIP is by PageRank (the top-K most important symbols are the ones served); the emitted ORDER is the stable file-grouped order, not rank-descending — read order= in the first-screen stanza, which also carries files=/symbols=/shown= and the ambiguous=/unresolved= completeness gauges.\","
                   + mcprefuse::toolMetadataFor( "analyze", pathIsRequired ) + "},"
                   "{\"name\":\"find_symbol\",\"description\":\"A symbol's 1-hop neighborhood: the symbol (with a fetch_body handle) plus direct callers (calledBy) and callees (calls). Full transitive reach: 'impact'. Read/write/import sites, not just calls: 'uses'. JSON {symbol, calledBy, calls, defs, count, hop_tested, hop_untested, counts_floor}; both arrays are FLOORS and the payload says why. limit/offset page them. symbol = final name segment (add scope to disambiguate); " + std::string( kAtSeedDocClause ) + "\","
                   + mcprefuse::toolMetadataFor( "find_symbol", pathIsRequired ) + "},"
                   "{\"name\":\"find_referencing_symbols\",\"description\":\"Direct (1-hop) callers of a symbol, each with a fetch_body handle. For the full transitive blast radius use 'impact', for read/write/import sites 'uses'. JSON {symbol, calledBy, defs, count, hop_tested, hop_untested, counts_floor}; calledBy is a FLOOR and the payload says why. limit/offset page it. " + std::string( kAtSeedShortClause ) + "\","
                   + mcprefuse::toolMetadataFor( "find_referencing_symbols", pathIsRequired ) + "},"
                   // verifier N8: limit/offset are DECLARED here because they are HONORED (mcpPageArgs →
                   // pageWindow, the same trio the CLI --grep applies). This was the only paged CLI verb whose
                   // MCP twin disclosed capped:true at 100 hits with no knob to raise or walk past it.
                   "{\"name\":\"grep\",\"description\":\"Trigram literal search; each hit annotated with its enclosing symbol (which function/class it is in). pattern = the literal; in=any lifts the span tiering (by default the tightest non-empty tier is served and what was held back rides as suppressed_comment/suppressed_string); limit/offset page the hits (first 100, has_more/next_offset end the loop). total/shown/capped/hits_capped and complete= are defined in the answer's own legend.\","
                   + mcprefuse::toolMetadataFor( "grep", pathIsRequired ) + "},"
                   "{\"name\":\"cochange\",\"description\":\"Files that historically change together with this file — the co-edit partners. dep_capable=false means neither side could carry one (sh/md/json/binary), so surprising is undefined rather than informative. file = the file (a path SUFFIX is enough); limit/offset page the partners; the root names the mined window and its sub-window denominator.\","
                   + mcprefuse::toolMetadataFor( "cochange", pathIsRequired ) + "},"
                   // §B6 M15 / verifier N5: top_k is the budget knob this verb's own est_tokens disclosure implies. It
                   // was hardcoded to 8 with no way to ask for less, on the one MCP verb that can return ~180 KB,
                   // while the CLI --recall began honoring --top-k in this round's Wave 1.
                   "{\"name\":\"memory_recall\",\"description\":\"Most relevant memory notes / docs for a task, full text — the few that matter, not the whole corpus. path = docs/memory dir; task = what you're working on; top_k = docs to return, 1..1000 (default 8), refused outside that band, never clamped; budget_tokens = the body ceiling in tokens (default 8000) — it SHAPES to fit, the CLI --recall's --max-tokens, not --token-budget's refuse-if-over GATE, and the header discloses max_tokens= and every cut.\","
                   + mcprefuse::toolMetadataFor( "memory_recall", pathIsRequired ) + "},"
                   "{\"name\":\"situational_awareness\",\"description\":\"The 5 things to know about a diff, as JSON: blast_radius, tests_to_run, forgotten (usual co-change partners missing from this diff), hotspot_alert, modules_touched. diff/files optional — defaults to 'git diff HEAD'. files is a STRING of comma-separated paths (files=\\\"src/a.cpp,src/b.h\\\"), not an array; an array is refused rather than read as absent, which would answer about the working tree instead of the files you named.\","
                   + mcprefuse::toolMetadataFor( "situational_awareness", pathIsRequired ) + "},"
                   "{\"name\":\"mentions\",\"description\":\"Docs (markdown plans/designs) that name a code symbol in a backtick. symbol = the code symbol name; limit/offset page the files. " + std::string( kAtSeedRebindClause ) + "\","
                   + mcprefuse::toolMetadataFor( "mentions", pathIsRequired ) + "},"
                   "{\"name\":\"for\",\"description\":\"Task-lens ranked, signatures-only inventory of the building blocks most relevant to a task (cx=complexity, in=reuse-count). task = the task in plain words; budget_tokens = an optional ceiling (the CLI --for --token-budget). The header carries route= (which ranker answered, and why), confidence=/margin_pct= (how sharp the ranked head is — low means a starting point, not an answer) and lens= (the per-row columns this dialect does not measure).\","
                   + mcprefuse::toolMetadataFor( "for", pathIsRequired ) + "},"
                   "{\"name\":\"lego\",\"description\":\"Interface-to-impls view for ONE named interface/base: its method contract plus EVERY implementor (own-language only), each with file path. Use when implementing against a KNOWN interface (contrast 'for', which sprays top interfaces for a task). type = interface/base name, or file:name to disambiguate; " + std::string( kAtSeedShortClause ) + "\","
                   + mcprefuse::toolMetadataFor( "lego", pathIsRequired ) + "},"
                   + mcprefuse::gitOnlyStanza( omitGitVerbs, "{\"name\":\"owners\",\"description\":\"Bus-factor: recency-weighted (6-month half-life) author ownership per file. symbol = optional, restricts to the file that defines it; limit/offset page the rows. at= is the commit these numbers were computed at (+dirty = the working tree differed). " + std::string( kAtSeedRebindClause ) + "\","
                   + mcprefuse::toolMetadataFor( "owners", pathIsRequired ) + "}," ) +
                   // EDIT verbs — symbol-addressed writes. The safety contract IS the feature: any refusal leaves the file byte-identical.
                   "{\"name\":\"replace_symbol_body\",\"description\":\"Replace a symbol's ENTIRE definition (signature through closing brace) with new_body — splices over the full def span, preserving every byte outside it verbatim; new_body must be a complete, well-formed definition. REFUSES with the file byte-unchanged when: not found (lists nearest names), ambiguous (lists file:line candidates — retry with 'file'), the index is stale (call any read verb first), the target is a SYMLINK, or a concurrent external write is detected. path = repo dir, or paths = workspace roots (writes land in the correct root's real file); symbol = def name, or @FILE:LINE (the innermost definition enclosing that line — paste it from a diff hunk or error); file = optional path substring; new_body = the replacement. The receipt's span is the POST-EDIT byte range, not the region overwritten.\","
                   + mcprefuse::toolMetadataFor( "replace_symbol_body", pathIsRequired ) + "},"
                   "{\"name\":\"insert_before_symbol\",\"description\":\"Insert text immediately BEFORE a symbol's definition (its first byte); a trailing newline is added only if missing. Same refusal contract as replace_symbol_body (not found / ambiguous / stale index / symlink / concurrent write, file unchanged). path/paths, symbol (@FILE:LINE accepted) and file as replace_symbol_body; text = the text to insert. The receipt's span is the POST-EDIT range of the inserted text; replaced_bytes is always 0.\","
                   + mcprefuse::toolMetadataFor( "insert_before_symbol", pathIsRequired ) + "},"
                   "{\"name\":\"insert_after_symbol\",\"description\":\"Insert text immediately AFTER a symbol's definition (past its final byte, which is preserved exactly); a leading newline is added only if missing. Same refusal contract as replace_symbol_body. path/paths, symbol (@FILE:LINE accepted) and file as replace_symbol_body; text = the text to insert. The receipt's span is the POST-EDIT range of the inserted text; replaced_bytes is always 0.\","
                   + mcprefuse::toolMetadataFor( "insert_after_symbol", pathIsRequired ) + "},"
                   // T4 lazy-body verb — the read verbs return signatures + a stable `handle`; fetch the full body ONLY when needed.
                   "{\"name\":\"fetch_body\",\"description\":\"Full (or partial-range) source of a symbol's definition, addressed by the stable `handle` a read verb attached to it (bodies on request, not by default). start_line/end_line are optional, 1-based, INCLUSIVE and BODY-RELATIVE (line 1 = the def's first line), clamped and UTF-8-safe; omit both for the whole body — the response reports start_line/end_line/total_lines/partial. Refuses a malformed, stale or unresolvable handle; overloads sharing one handle add ambiguous_handle rather than serving the wrong one. handle = from a read verb; holding a LOCATION instead, " + std::string( kAtSeedShortClause ) + "\","
                   + mcprefuse::toolMetadataFor( "fetch_body", pathIsRequired ) + "},"
                   // ─── flagship-reflex verbs: the write-moment (exemplar), the before-you-call-it-done (quality_delta/quality_baseline), and the is-it-safe-to-change (impact/uses/path) reflexes an MCP-only agent otherwise cannot reach.
                   // §B6 M13: the selection rule is exemplar.h's kExemplarSelectionRule, SPLICED IN rather than
                   // paraphrased — this stanza used to describe an ordering the selector does not use.
                   "{\"name\":\"exemplar\",\"description\":\"BEFORE writing a function / method / class / struct / interface / variable, get the repo's single best-in-class instance of that kind to imitate — signature AND full body. " + std::string( kExemplarSelectionRule ) + ". Beats grep/find_symbol: those find A definition, this ranks every definition and returns the one worth copying. kind = fn|method|class|struct|iface|var, OR a task string (its top match's kind is used).\","
                   + mcprefuse::toolMetadataFor( "exemplar", pathIsRequired ) + "},"
                   "{\"name\":\"quality_delta\",\"description\":\"Your PR self-check, run every time you think a change is DONE — pairs with the CLI-only --test-gate (names the tests to run + the untested blast radius; not MCP-exposed) to form the two-step pre-PR gate. Reports ONLY what your working tree made WORSE vs baseline, across 10 measured failure modes (complexity, verbosity, nesting, params, new duplication, new dead code, new public API surface, error-masking, short-horizon churn, new clone of a reused helper). Read-only; auto-compares vs git HEAD with no setup, or a pinned .ripwire_quality_baseline sidecar if present and not stale (baseline says which). sev=minor does not gate; acked findings stay suppressed until one worsens. at= is the commit compared at (+dirty = the working tree differed).\","
                   + mcprefuse::toolMetadataFor( "quality_delta", pathIsRequired ) + "},"
                   "{\"name\":\"quality_baseline\",\"description\":\"PIN the quality floor: writes .ripwire_quality_baseline stamped with the current git HEAD sha, snapshotting complexity / duplication / dead-code / API surface. Call once at the start of non-trivial work, then quality_delta compares against this pinned floor instead of HEAD. Side-effecting (writes a file) — skip it for a simple 'before I push' check, quality_delta already compares vs HEAD with zero setup.\","
                   + mcprefuse::toolMetadataFor( "quality_baseline", pathIsRequired ) + "},"
                   // §B6 M4: limit/offset are DECLARED here because they are HONORED (mcpPageArgs → pageWindow),
                   // which is what the legend has always instructed. Before this they were undeclared and
                   // silently ignored, so the two answers were byte-identical with and without them.
                   "{\"name\":\"impact\",\"description\":\"IS IT SAFE TO CHANGE X? — the TRANSITIVE blast radius of a symbol via calls, ranked by PageRank. Use before modifying or deleting a symbol; it beats find_referencing_symbols (direct callers only), and 'uses' catches the read/write/import sites calls miss. Call edges are name-based, so reaches= is a FLOOR and this is a strong lead, not a proof — the answer's legend names every cause. The listing shows the top 40 by rank unless you raise it with limit=N (offset=M pages; has_more/next_offset end the loop). symbol = the name (file:name disambiguates); " + std::string( kAtSeedDocClause ) + "\","
                   + mcprefuse::toolMetadataFor( "impact", pathIsRequired ) + "},"
                   "{\"name\":\"uses\",\"description\":\"The STATICALLY RESOLVABLE use-sites of a symbol, not just calls: role (call | read | write | import | extends), file:line, and enclosing symbol. Use to see the footprint before renaming or changing a name — find_referencing_symbols and impact follow only calls. external=\\\"1\\\" means no definition in the indexed tree; count=\\\"0\\\" is a real answer, and counts_floor=\\\"1\\\" says count= is a FLOOR (the legend names the causes). symbol = the bare name, the union across same-named defs (file:name narrowing is CLI-only); an @FILE:LINE seed serves the enclosing definition's sites and of= echoes it as typed. limit/offset page the sites.\","
                   + mcprefuse::toolMetadataFor( "uses", pathIsRequired ) + "},"
                   "{\"name\":\"path_between\",\"description\":\"Does A REACH B, and HOW? — the shortest directed CALL path between two symbols, hop-by-hop. reachable=\\\"0\\\" hops=\\\"0\\\" is a valid 'not reachable' answer — call edges are name-based, so a missing dynamic/callback edge can hide a real path. Named path_between because 'path' is the repo-root arg. from/to: " + std::string( kAtSeedShortClause ) + "\","
                   + mcprefuse::toolMetadataFor( "path_between", pathIsRequired ) + "},"
                   // --connect: the N-symbols-how-do-they-relate reflex (R7-lean description by design: one sentence, when-to-use + what-it-answers).
                   "{\"name\":\"connect\",\"description\":\"When a task touches 2..16 named symbols, returns the minimal subgraph RELATING them - terminals, the fewest joining intermediaries (with signatures), and call edges in true direction - finding the shared-caller joins a directed path_between cannot; unrelated symbols are reported honestly in <unconnected>. symbols = array or comma-string of names; " + std::string( kAtSeedShortClause ) + " radius = undirected hop bound, an integer in 1..12 (default 6) — a value outside that band is refused, never clamped or wrapped.\","
                   + mcprefuse::toolMetadataFor( "connect", pathIsRequired ) + "},"
                   // L4 — the one-call orientation front door + B11 verb parity. `explore` is
                   // the SAME handler as the CLI --pack-task; the older name `pack_task` still dispatches (tools/call
                   // name=="pack_task" works) but is not separately advertised here — see mcp.h's kMcpVerbTable comment.
                   "{\"name\":\"explore\",\"description\":\"ONE-call task orientation: the routed+anchored ranking, full bodies of the top hits, their 1-hop callers, field notes, and tests_to_run — ALL under one deterministic byte budget, in a fixed section order (ranking > bodies > callers > notes > tests) that degrades gracefully and reports every truncation. Replaces the for -> fetch_body -> find_referencing_symbols -> memory_recall dance when you want the whole orientation at once; for JUST the ranked inventory use 'for'. Same handler as the CLI --pack-task. ALIAS: tools/call name='pack_task' answers this exact tool with these exact arguments (it gets no separate tools/list entry). task = the task in plain words; budget_tokens = optional (default 6000); partition = optional 2..16, refused outside that band — FANNING OUT to N agents on ONE task? Ask for it and get one shared core plus N minimally-overlapping slices carved along the call graph's own communities, budget_tokens then meaning ONE agent's budget. Read overlap_max/split before trusting the slices.\","
                   + mcprefuse::toolMetadataFor( "explore", pathIsRequired ) + "},"
                   "{\"name\":\"from_trace\",\"description\":\"Paste a stack trace / sanitizer report / compiler error and get it mapped onto indexed symbols, ranked INNERMOST-first: the parsed <trace> frame map, the ranked suspects' signatures, and the innermost in-corpus symbol's FULL body. Out-of-corpus frames are listed and counted, never ranked, and the counters CLOSE (in_corpus = suspects + merged + unresolved). Each frame binds by its own NAME first, falling back to the def enclosing its line only when that name is absent or ambiguous — resolved_by= and any name-vs-line disagreement are disclosed, never silently rebound. Same handler as the CLI --from-trace. A failing-test trace also gets a test_hop block reaching the source symbols behind the assertion, labelled heuristic. trace = the raw trace TEXT (paste it, don't hand-translate it into a query); budget_tokens optional.\","
                   + mcprefuse::toolMetadataFor( "from_trace", pathIsRequired ) + "},"
                   "{\"name\":\"edit_check\",\"description\":\"Just edited a symbol? Did its CONTRACT (param count + publicness) change vs git HEAD, and which 1-hop callers are NOW INCOMPATIBLE with the new arity by fixed-arity evidence (not a guess — every folded definition disagrees)? This is call sites worth OPENING, not a proof: call edges are matched by NAME, so a same-named callee this tool does not index can flag a caller that never touches the edited symbol at all, and a clean tree can carry a nonzero incompatible= with nothing edited. status is one of unchanged / new-symbol / contract-change, and callers= is itself a FLOOR — 'no incompatible caller' is not proof of safety either. Fast and targeted; for the same question over a WHOLE diff use quality_delta. symbol = the def name (file:name to disambiguate); at= names the commit compared against. " + std::string( kAtSeedShortClause ) + " PRE-APPLY PREVIEW: pass new_body to ask the same question about a replacement that has NOT been written — it is spliced in memory, re-parsed, and the answer carries preview=1. Nothing is written; a payload that does not parse, or does not define the symbol, is refused.\","
                   + mcprefuse::toolMetadataFor( "edit_check", pathIsRequired ) + "},"
                   // The cross-branch + dark-content verbs. Read-only git plumbing, no index
                   // coupling for the first two (they read OTHER refs' blobs, which the index never ingested).
                   + mcprefuse::gitOnlyStanza( omitGitVerbs, "{\"name\":\"whereis\",\"description\":\"WHERE DOES THIS CONTENT LIVE? Which branch's tree defines or mentions a symbol, HEAD first, with on-head=0 naming the case this verb exists for: content that lives only on a branch (a finished fix stranded on 1 of 30 refs). Each distinct blob is read once (content-addressed), so N branches cost about one tree. kind=def on a REF row is a LEXICAL heuristic (ref blobs are raw text, never ingested) — for HEAD's parsed answer use find_symbol/fetch_body. symbol = the name, or an @FILE:LINE seed; kind = optional ref-name substring filter, echoed as filter=; limit/offset page the hits (first 60). at= is HEAD's sha, always sha-only. Single-root; read-only.\","
                   + mcprefuse::toolMetadataFor( "whereis", pathIsRequired ) + "}," ) +
                   mcprefuse::gitOnlyStanza( omitGitVerbs, "{\"name\":\"stray_content\",\"description\":\"Per branch: the lines its own divergent work AUTHORED (vs its merge-base with HEAD) that the live line does NOT have. Four verdicts (unmerged+superseded+merged+unknown=refs): v=unmerged is genuinely absent; v=superseded means the live line re-implemented the work — the case `git cherry` structurally cannot see; merged branches are omitted and counted; v=unknown is a branch this scan could NOT analyse at all (no merge-base, unrelated history), not a fourth kind of divergence. Every file row carries its raw del/redone/sim evidence. Line-granular, not semantic. kind = optional ref-name substring filter, echoed as filter=; limit/offset page the refs. Single-root; read-only.\","
                   + mcprefuse::toolMetadataFor( "stray_content", pathIsRequired ) + "}," ) +
                   "{\"name\":\"flags\",\"description\":\"WHAT IS BUILT BUT DARK here — the answer to 'why don't I see feature X?'. Harvests all three gate patterns (ifndef/define header gates, CMake option(), getenv reads) with each gate's kind, DEFAULT, the size of the code it guards, and its read sites. When a name is both a header gate and a CMake option the CMake default wins and the header shows as an also row. Lexical, not preprocessed: it reports the in-repo default, never the value your build used. kind = optional gate-name substring filter, echoed as filter=. symbol = optional GATE NAME, switching to the FLIP lens for that one gate: what becomes live, who holds it, what it reaches, which tests cover it. An unknown gate name is refused with near-misses, never answered empty.\","
                   + mcprefuse::toolMetadataFor( "flags", pathIsRequired ) + "},"
                   "{\"name\":\"doc_drift\",\"description\":\"WHICH OF THIS REPO'S DOC CLAIMS ARE NOW FALSE. Verifies the CHECKABLE anchors in every markdown file against the live index and returns ONLY the ones that no longer hold: file:line refs (missing-file / past-eof / line-moved), backticked symbol mentions (undefined), `= N` constants and `[N]` array extents. Read this BEFORE trusting a design doc, plan or audit you did not just write. Every lane deliberately under-reports; checked + unchecked = anchors, each declined check named. A failed anchor the AUTHOR DATED is kind=dated-record, counted in dated= rather than drift=, so drift= is the LIVE rot. Prose, Status lines and dates are not checked. kind = optional doc-path filter, echoed as filter=; limit/offset page the docs.\","
                   + mcprefuse::toolMetadataFor( "doc_drift", pathIsRequired ) + "},"
                   // lane/tc-sliceat — the ARISE def-use slice (the CLI --slice contract verb-for-verb; sliceBundleText is the ONE emitter both surfaces call).
                   "{\"name\":\"slice\",\"description\":\"WHERE IS THIS VARIABLE DEFINED AND USED inside one function — NAME-BASED intra-procedural def-use rows of one variable inside ONE uniquely-resolved definition (the ARISE slicer, arXiv:2605.03117). symbol alone lists the sliceable locals to pick from; add var (or spell symbol as SYM:VAR / file:name:VAR) for the per-line rows. flow=back|fwd|both adds the TRANSITIVE data-flow slice over reaching-definition edges, bounded by depth (1..32, default 8; a cutting bound emits flow_truncated). @FILE:LINE seeds resolve here and complete the paper's (file, line[, variable]) seed. Reaching definitions are flow-sensitive for C-family and Python (reach=cfg), source-order elsewhere (reach=linear). Its LIMITS — name-based, intra-procedural, line-granular, DATA dependence only — are stated clause by clause in the answer's own legend. Served: C/C++/ObjC (+CUDA/Metal), Python, JS/TS, Go, Java, Rust; every other language refuses loudly. Single-root; read-only.\","
                   + mcprefuse::toolMetadataFor( "slice", pathIsRequired ) + "},"
                   // A4-R3 batch — one-turn context sweep: N read sub-queries in ONE round-trip, merged + deduped.
                   "{\"name\":\"batch\",\"description\":\"ONE-TURN CONTEXT SWEEP: answer up to 16 heterogeneous READ sub-queries in a single call (the deterministic $0 counterpart of a parallel-search agent). queries = array over the SAME path, in EITHER grammar: {verb, ...args} objects, or the CLI --batch file's own \\\"verb:arg\\\" strings (queries=[\\\"for:parse the config\\\",\\\"callers:escapeXml\\\"]) - one grammar, both front doors; each verb is one of " + mcpBatchServedVerbsList( omitGitVerbs ) + " (plus the ALIASES callers=find_referencing_symbols and callees=find_symbol) with that verb's own args. The other " + std::to_string( batchExcluded ) + " advertised verbs are NOT batchable: side effects (the 3 edit verbs, quality_baseline), a heavy both-trees pass (quality_delta), no nesting (batch), and whole-repo / cross-branch scope (situational_awareness, memory_recall, connect, explore — and its alias pack_task — from_trace, " + mcprefuse::batchGitOnlyExcludedNames( omitGitVerbs ) + "flags, doc_drift). Result is one <batch> of <q i verb ok> elements IN ORDER, each sub-answer verbatim in CDATA; a failing sub-query is an inline ok=0 err= entry and never fails the batch; identical payloads dedup; over 16 caps honestly.\","
                   + mcprefuse::toolMetadataFor( "batch", pathIsRequired ) + "}"
                   "]}}";
            }
            catch( ... )
            {
                resp = "{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"error\":{\"code\":-32603,\"message\":\"internal error\"}}";
            }
        }
        else if( method == "tools/call" )
        {
            // A3-F6/A4-F26: the tool `name` and EVERY per-verb argument (path/symbol/file/task/…) are scoped to
            // the request's params span so an envelope-level string — most notably a string request-id equal to
            // a key literal (id:"path", or id:"name") — can no longer shadow the real argument. `name` lives at
            // params level (spec: {"params":{"name":..,"arguments":{..}}}), OUTSIDE `arguments`, so it is scoped
            // to `params` directly rather than to `args` (which prefers the narrower `arguments` object) or, as
            // before this fix, to the whole raw `line` (which left it reading the envelope, unscoped). args/params
            // are "" when there is no params object ⇒ every arg reads absent ⇒ the verb's own missing-args error
            // path fires (the pre-F6 whole-line scan is gone for every other arg; this closes the same gap for `name`).
            // §B6 M7: `name` and `arguments` through the SAME guarded readers every other field uses. Both were
            // on the bare findString/findObject path, and both collapsed present-but-wrong-shaped onto absent:
            // `"name":5` was reported as "missing required field: name" (a field the caller DID send), and a
            // wrong-typed `arguments` — a number, or the common host bug of a STRING of JSON — was SILENTLY
            // IGNORED, falling back to the `params` scope so the caller's `path` disappeared and the verb
            // answered about the default startup root. The scope selection (prefer `arguments`, else `params`)
            // is spelled here now instead of inside a helper that could not refuse.
            const std::string  params   = paramsArg.span;
            const McpObjectArg argsArg  = mcpObjectArg( params, "arguments" );
            const std::string  args     = argsArg.isPresent ? argsArg.span : params;
            const McpStringArg nameArg  = mcpStringArg( params, "name" );            // params-level, before arguments — the tool selector
            const std::string  name     = nameArg.value;
            if( !name.empty() )
            {
                timingVerb = name; // MEASURE-FIRST: attribute the wall to the actual verb
            }
            // ── W3FIX H5: every STRING argument through the ONE guarded reader ─────────────────────────────
            //
            // Verifier N11 wired mcpStringArg into `files` and stopped there, so thirteen sibling fields kept
            // the bare findString path and kept ACCEPTING-AND-IGNORING a wrong-shaped value: `diff:["a","b"]`
            // read as absent and situational_awareness answered about the working-tree git diff and reported it
            // clean with total confidence (the N11 finding, one field over), and `kind`/`symbol` on whereis /
            // stray_content / flags / doc_drift / owners silently dropped a non-string filter.
            //
            // `strArg` is the seam: it reads through mcpStringArg and REMEMBERS the first refusal, so adding a
            // string argument inherits the shape check instead of inheriting the bug. Declaration order below
            // IS the reporting order when a request carries two bad shapes — deterministic, and the same on
            // both arms because the order is the table's, not the reader's.
            //
            // §B6 M7: the accumulator is SEEDED with the envelope's own two shape faults, so they are reported
            // ahead of any argument's — `name` decides which verb's fields are even judged, and a wrong-shaped
            // `arguments` means every argument read below is about the wrong scope, so naming an argument first
            // would send the caller to fix the wrong thing.
            std::string shapeRefusal = !nameArg.refusal.empty() ? nameArg.refusal : argsArg.refusal;
            const auto  strArg = [ & ]( const char* field ) -> std::string
            {
                const McpStringArg a = mcpStringArg( args, field );
                if( shapeRefusal.empty() && !a.refusal.empty() )
                {
                    shapeRefusal = a.refusal;
                }
                return a.value;
            };

            std::string       path    = strArg( "path" );     // may be REBOUND to a workspace key by `paths` below (A11)
            std::string       assumedRootNote;                // R2a: non-empty ⇒ path was defaulted to the launch cwd; disclosed by textResult (declared here so the lambda captures it)
            const std::string symbol  = strArg( "symbol" );
            const std::string pattern = strArg( "pattern" );
            const std::string file    = strArg( "file" );
            const std::string task    = strArg( "task" );
            const std::string type    = strArg( "type" );     // lego verb: the interface/base name
            const std::string files   = strArg( "files" );    // N11: schema-typed STRING (comma-separated paths), never an array
            const std::string diff    = strArg( "diff" );     // H5: same class as `files` — an array here answered about the wrong tree
            const std::string newBody = strArg( "new_body" ); // replace_symbol_body
            // P9: the edit verbs' post-check opt-out. Default TRUE — the receipt carries its own
            // verification unless the caller says otherwise; a wrong-shaped value refuses like every other
            // typed argument rather than reading as absent (mcpBoolArg).
            const McpBoolArg postCheckArg = mcpBoolArg( args, "post_check" );
            if( shapeRefusal.empty() && !postCheckArg.refusal.empty() )
            {
                shapeRefusal = postCheckArg.refusal;
            }
            const bool postCheck = !postCheckArg.isPresent || postCheckArg.value;
            const std::string text    = strArg( "text" );     // insert_before/after
            const std::string handle  = strArg( "handle" );   // T4 fetch_body
            const std::string kind    = strArg( "kind" );     // exemplar kind token; whereis/stray_content/flags/doc_drift name filter
            const std::string from    = strArg( "from" );     // path verb: source symbol
            const std::string to      = strArg( "to" );       // path verb: destination symbol
            const std::string trace   = strArg( "trace" );    // L4 from_trace: the raw trace TEXT
            const std::string var     = strArg( "var" );      // slice: the variable to slice (optional — bare = inventory)
            const std::string flow    = strArg( "flow" );     // slice: back|fwd|both (validated in sliceText, the CLI wording)
            // §5a decision 3: the OPT-IN compact legend posture, the MCP twin of the CLI --legend=compact.
            // "" and "full" are the default (byte-identical to what this surface always emitted); "compact"
            // swaps the prose for the versioned schema id and leaves every row byte and every data /
            // completeness attribute alone. A value outside the set is refused, never read as the default —
            // the closed-set rule the `in` argument's own history (P6-2) established for this server.
            const std::string legendArg = strArg( "legend" );
            // F9 (capture-audit verify-wave2 2026-09-05): ABSENT and PRESENT-BUT-EMPTY are two different
            // requests, and `legendArg.empty()` collapsed them — `legend:""` was read as the default and
            // answered 5,090 bytes at exit 0, where the CLI's own `--legend=` refuses ("--legend= is empty —
            // it needs full or compact"). M6's empty-value rule was applied to the 60 CLI flags and missed
            // the field this wave added. The presence bit comes from the same raw reader every other MCP
            // argument's shape check uses.
            const bool legendIsPresent = mcpdetail::findRawValue( args, "legend" ).isPresent;

            // ── W3FIX H4/M5: every NUMERIC argument through the ONE guarded reader ─────────────────────────
            //
            // N2/N3 closed limit/offset/radius and stopped there, so five numeric arguments kept findInt's
            // stop-at-the-first-non-digit read and the raw casts on top of it:
            //   partition:4294967299   → `std::uint32_t(…)` WRAPPED modulo 2^32 and ran a 3-way fan-out;
            //                            partition:2^32 wrapped to 0 and served a single bundle; 0/-1/17 were
            //                            silently ignored. This is N3's radius bug, verbatim, one field over.
            //   top_k:"1e3"            → 1 (one document returned where a thousand were asked for);
            //   top_k:2^40             → silently CLAMPED to the undeclared ceiling 1000;
            //   budget_tokens:"1e3"    → 1, i.e. a bundle truncated to nothing under a budget never typed;
            //   start_line:3.9         → 3 (the fetch_body range answered about a different line span).
            // Every one of them is now the same refusal sentence limit/offset speak, from the same table.
            // `intArg` shares the shapeRefusal accumulator with `strArg`: one gate, one reporting order.
            const auto intArg = [ & ]( const char* field, long long least, long long most ) -> McpIntArg
            {
                const McpIntArg a = mcpIntArg( args, field, least, most );
                if( shapeRefusal.empty() && !a.refusal.empty() )
                {
                    shapeRefusal = a.refusal;
                }
                return a;
            };

            const McpIntArg startArg = intArg( "start_line", 1, kMcpPageValueMax );   // Feature 2 partial-range
            const McpIntArg endArg   = intArg( "end_line",   1, kMcpPageValueMax );   //   (both optional, body-relative)
            const long long startLine = startArg.value;
            const long long endLine   = endArg.value;
            const bool      hasStart  = startArg.isPresent;
            const bool      hasEnd    = endArg.isPresent;

            const McpIntArg   budgetArg    = intArg( "budget_tokens", 1, kMcpPageValueMax );   // L4 explore/from_trace
            const std::size_t budgetTokens = budgetArg.isPresent ? std::size_t( budgetArg.value ) : 0;   // absent ⇒ the shared default

            const McpIntArg topKArg    = intArg( "top_k", 1, kMcpRecallTopKMax );      // §B6 M15 memory_recall budget knob
            const int       recallTopK = topKArg.isPresent ? int( topKArg.value ) : 8;  // 8 = the historic default

            const McpIntArg     partitionArg   = intArg( "partition", packpartition::kMinPartitions, packpartition::kMaxPartitions );   // --partition=N over MCP
            const std::uint32_t partitionCount = partitionArg.isPresent ? std::uint32_t( partitionArg.value ) : 0u;   // absent ⇒ one un-split bundle

            // slice's flow bound — the CLI --slice-depth's 1..32 band, refused (never clamped) via the shared
            // reader; the flow-pairing half of the contract (depth needs flow) lives in sliceText, which is
            // the only point that sees both fields together.
            static_assert( slicev::kSliceFlowDepthMin == 1 && slicev::kSliceFlowDepthMax == 32,
                           "the depth refusal names the band 1..32 in mcprefusal.h's kMcpValueFields and in the "
                           "tools/list slice stanza — the core's band moved; move all three wordings with it" );
            const McpIntArg sliceDepthArg = intArg( "depth", slicev::kSliceFlowDepthMin, slicev::kSliceFlowDepthMax );

            // Index-staleness stamp (CocoIndex lineage idea): every tool RESULT carries the identity
            // of the index it was answered from, so a caller holding results from two different calls can
            // detect "these came from different index states" without a side channel. ONE line, deterministic
            // for an unchanged tree, IDENTICAL shape across every verb.
            //
            // Placement: this is a SIBLING of "content" inside "result", not appended to the verb's own text.
            // Several verbs (grep/cochange/situational_awareness/mentions) return raw JSON as their text
            // payload and existing gates do json.loads() on that exact string (mcprobustcheck.sh, situ
            // diffcheck.sh) — appending a trailing marker line to the text would corrupt valid JSON into
            // invalid JSON and break those gates for a reason that has nothing to do with staleness. A
            // same-shaped field in the envelope is just as discoverable to an agent (it's still in the same
            // tool-call result), costs the same one line, and can never corrupt a verb's own payload format
            // (JSON, XML, or plain text) — so it's the version of "append a trailing marker" that is actually
            // uniform across every verb, per the requirement.
            const auto indexStamp = [ & ]( const std::string& root ) -> std::string
            {
                const McpIndex& mix = getIndex( root );
                char buf[ 96 ];
                std::snprintf( buf, sizeof( buf ), "[index: files=%zu symbols=%zu hash=%08x]",
                                mix.ing.files.size(), mix.ing.symbols.size(),
                                (unsigned)( mix.contentHash & 0xFFFFFFFFu ) );
                return buf;
            };

            // P1-15 `_reingest` (a second envelope sibling, same reasoning as `_index`): `_index` says which
            // tree STATE answered, `_reingest` what the server had to DO to get there. Contract on
            // McpIndex::incrementalPasses, gate test/mcpincrementalcheck.sh. Read BEFORE the verb runs.
            const std::uint64_t passesAtEntry = mcpIndexSlot().incrementalPasses;
            const auto textResult = [ & ]( const std::string& text )
            {
                // stamp FIRST, then the pass count: on a verb that never touched the index, building the
                // stamp is what forces the rebuild, and one `+` chain would not sequence those two reads.
                const std::string stamp = indexStamp( path );
                // R2a: `_assumed_root` — a third envelope sibling (mcpAssumedRootField), emitted ONLY when
                // the request omitted `path` and the launch-cwd default answered.
                // Card A3: `_fresh` — a fourth sibling, on EVERY response, because it is the one of these
                // an agent needs without having asked for it: does this answer still describe the tree I am
                // editing? `_index` and `_reingest` both require a second data point to interpret (a stamp
                // means nothing alone; a cost means nothing without knowing a pass ran). `_fresh` is
                // self-contained by construction, and it is placed after the stamp for the same sequencing
                // reason — it reads the pass count that building the stamp may have moved.
                return "{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"result\":{\"content\":[{\"type\":\"text\",\"text\":\""
                     + mcpdetail::jsonEscape( text ) + "\"}],\"_index\":\"" + mcpdetail::jsonEscape( stamp )
                     + "\"" + mcpReingestField( passesAtEntry ) + mcpFreshFields( passesAtEntry )
                     + mcpAssumedRootField( assumedRootNote ) + "}}";
            };
            const auto errResult = [ & ]( int code, const char* msg )
            { return "{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"error\":{\"code\":" + std::to_string( code ) + ",\"message\":\"" + msg + "\"}}"; };
            // dynamic-message variant (edit verbs build refusal messages that embed symbol names / candidate
            // file:line lists) — JSON-escape so a path with a quote or a control byte can't corrupt the response.
            const auto errResultMsg = [ & ]( int code, const std::string& msg )
            { return "{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"error\":{\"code\":" + std::to_string( code ) + ",\"message\":\"" + mcpdetail::jsonEscape( msg ) + "\"}}"; };
            // §B6 M8: the shared not-found renderers, bound to THIS request's index. Seven verbs on both
            // arms answered a bare "symbol not found" — no echo of what the caller typed, no near-miss —
            // while the CLI twin has carried both since A3-F16a and the `flags` verb below carries both
            // today. mcprefusal.h owns the wording; these two lambdas only supply the index.
            // Verifier N7: the trailing guidance clause is looked up BY VERB from the same table row that
            // owns the field's wording, instead of being written out at each call site — that is what let
            // the batch arm serve three of these sentences with the guidance half missing.
            const auto notFoundSym  = [ & ]( std::string_view spelling ) -> std::string
            { return mcprefuse::notFound( getIndex( path ).ing, "symbol", spelling, mcprefuse::notFoundHintFor( name, "symbol" ) ); };
            const auto notFoundKind = [ & ]( std::string_view noun, std::string_view spelling ) -> std::string
            { return mcprefuse::notFound( getIndex( path ).ing, noun, spelling ); };

            // success envelope for an edit verb: the JSON payload as text content + the fresh _index stamp
            // (the index was just invalidated, so indexStamp() rebuilds and reports the NEW post-edit state).
            const auto editResult = [ & ]( const mcpedit::Outcome& oc )
            { return oc.ok ? textResult( oc.resultJson ) : errResultMsg( oc.errCode, oc.message ); };

            // The envelope EVERY paged verb shares (grep / impact / whereis): read the window once, refuse a
            // bad one once, and otherwise hand the validated window to the verb. Written as one shape rather
            // than as the same three-line if/else copied into three dispatch arms, because those copies ARE
            // the complexity — a --quality-delta pass reads three of them as exactly that, and it is right to.
            const auto pagedResult = [ & ]( auto&& buildWithPage ) -> std::string
            {
                const McpPageParse pg = mcpPageArgs( args );
                if( !pg.refusal.empty() )
                {
                    return errResultMsg( -32602, pg.refusal );
                }
                return buildWithPage( pg.page );
            };

            // A3-F3: per-REQUEST secret-redaction tally, wired into every body/doc-emission verb
            // below (for / exemplar / memory_recall / fetch_body) — the MCP server redacts by default
            // exactly like the CLI (its output lands in a cloud LLM context by construction). Null under
            // `--mcp --no-redact` (every seam then passes source through verbatim). Summarized to stderr
            // after the response — stdout is protocol-only.
            RedactCounts        redactCounts;
            RedactCounts* const redactPtr = noRedact ? nullptr : &redactCounts;

            // A11: the additive `paths` array — 2+ roots resolve to a registered
            // workspace key that REPLACES `path` for this request; a 1-element array degrades to that path.
            // `path` and `paths` together is a usage error. Single `path` requests are untouched (back-compat).
            bool pathsUsageError = false;
            {
                // W3FIX M8: through the guarded ARRAY reader. `paths:5` used to read as absent, so the request
                // fell through to `path` and was refused with "missing required field: path" — a field the
                // caller never touched, about a field they did send in the wrong shape.
                const McpArrayArg              pathsArg = mcpArrayArg( args, "paths", false, 1, 16 );
                const std::vector<std::string> rootArgs = pathsArg.strings;
                if( !pathsArg.refusal.empty() )
                {
                    resp = errResultMsg( -32602, pathsArg.refusal );
                    pathsUsageError = true;
                }
                else if( !rootArgs.empty() && !path.empty() )
                {
                    resp = errResult( -32602, "pass either `path` or `paths`, not both" );
                    pathsUsageError = true;
                }
                else if( !rootArgs.empty() )
                {
                    std::string wsErr;
                    path = mcpWorkspaceKey( rootArgs, wsErr );
                    if( path.empty() ) { resp = errResultMsg( -32602, wsErr );  pathsUsageError = true; }
                }
            }

            // V3/RN1: did the CALLER name the tree? Read before the pinned / startup-root / assumed-cwd
            // tiers rebind an empty `path` — afterwards nothing tells "you asked" from "we picked one".
            const bool rootFromCaller = !path.empty();

            // ── Remote-transport policy gates — no-op over stdio ────────────────────────────────────────
            // These fire ONLY when policy.pinnedRoot is set (the HTTP transport). Both are checked BEFORE
            // the try{} below, so a refusal never calls getIndex() → the workspace-pinning gate can assert
            // mcpRebuildCounter() is unchanged, and a refused remote edit never touches a byte on disk.
            if( !pathsUsageError && !policy.pinnedRoot.empty() )
            {
                // (a) workspace pinning: one listener serves ONE workspace fixed at startup. An OMITTED path
                //     defaults to it; a path naming a DIFFERENT tree is refused with no rebuild.
                if( path.empty() )
                {
                    path = policy.pinnedRoot;                                  // default to the pinned workspace
                }
                else if( mcpCanonRoot( path ) != policy.pinnedRoot )
                {
                    resp = errResultMsg( -32602, "path is outside this server's workspace (this listener serves one "
                                                 "fixed workspace, pinned at startup) — omit `path` to use it, or run a "
                                                 "second server for the other tree" );
                    pathsUsageError = true;   // reuse the skip-flag: no try{}, no getIndex(), no rebuild
                }
                // (b) edit verbs refused over the remote transport unless the operator opted in.
                if( !pathsUsageError && !policy.editsAllowed && isMcpEditVerb( name ) )
                {
                    resp = errResultMsg( -32601, "edit verbs are disabled over the remote transport (start the listener "
                                                 "with --allow-remote-edits to enable them; that also forces the bearer token)" );
                    pathsUsageError = true;   // file stays byte-identical — the edit verbs' whole safety contract
                }
            }

            // ── stdio startup-root default + edit-verb workspace pin (D3/D4, X7) ───────────────────────────
            // Fires only when `ripwire <root> --mcp` was actually given a startup root (policy.defaultRoot
            // non-empty) and only over stdio (policy.pinnedRoot empty — the remote gates above already
            // handled the HTTP case and always set pathsUsageError before falling through if they refused).
            // An omitted `path` defaults to that root for EVERY verb (the D3 half of the fix — before this,
            // the positional startup root was silently ignored by the stdio loop). An EXPLICIT `path` that
            // canonicalizes outside the root is refused, but ONLY for the 3 EDIT verbs — read verbs stay
            // unrestricted, matching stdio's existing "a request may name any path" contract (the D4 half:
            // the incident was an edit verb splicing a file into the wrong repo, not a read reaching one).
            if( !pathsUsageError && policy.pinnedRoot.empty() && !policy.defaultRoot.empty() )
            {
                if( path.empty() )
                {
                    path = policy.defaultRoot;
                }
                else if( isMcpEditVerb( name ) && !mcpPathInsideRoot( policy.defaultRoot, path ) )
                {
                    resp = errResult( -32602, "path outside workspace; start the server on that root or pass an absolute in-root path" );
                    pathsUsageError = true;   // file stays byte-identical — same refusal contract as every other edit refusal
                }
            }

            // ── R2a (the 2026-08-12 usage mine): a bare server's omitted `path` rebinds to the launch cwd,
            // disclosed via textResult's `_assumed_root` sibling — precedence + guards live in
            // mcpAssumeRootIfOmitted / mcpResolveAssumedRoot, the full contract on McpDispatchPolicy.
            assumedRootNote = mcpAssumeRootIfOmitted( policy, path, pathsUsageError );

            // ── §B6 M3: does `path` name a readable DIRECTORY? ONE check, every verb, before dispatch ───────
            //
            // The false-zero class: a nonexistent `path` — and a FILE passed as `path` — produced all-zero
            // SUCCESS reports (files=0, total=0, "0 relevant of 0 documents") with the same `_index` hash on
            // analyze / grep / for / flags / doc_drift / memory_recall, so "this tree is empty", "there is no
            // such tree" and "that is a file" were one answer; the CLI exits 1 on the first of them. The sibling
            // sweep found the blast radius is wider than the zeros: three MORE verbs answer successfully
            // (batch / explore / from_trace) and the remaining ~20 "refuse" with a FALSE CAUSE — "symbol not
            // found: 'x'" when there is no tree to look in, "not a git repository" for a path that does not
            // exist at all. ONE check before the chain makes all of them name the real condition.
            //
            // Placed AFTER the `paths` rebind and both policy gates (so it judges the path the request will
            // actually use, including a defaulted startup root) and BEFORE the dispatch chain, so a bad path
            // never reaches getIndex() — no rebuild, and for an edit verb no byte written. An EMPTY-but-real
            // directory is NOT a fault: "nothing there" and "no such place" are different answers, which is the
            // CLI's own rule.
            if( !pathsUsageError && !path.empty() )
            {
                if( const std::string rootErr = mcpRootRefusal( path ); !rootErr.empty() )
                {
                    resp = errResultMsg( -32602, rootErr );
                    pathsUsageError = true;   // reuse the skip-flag: no dispatch, no getIndex(), no byte written
                }
            }

            // ── W3FIX M4: an argument this verb does not DECLARE refuses, with a near-miss ──────────────────
            // `explore` honored budget_tokens while token_budget / max_tokens were dropped in silence. Checked
            // against the verb's own inputSchema row (mcprefusal.h's kMcpVerbFields, `pack_task` resolving to
            // `explore`'s row); an unadvertised NAME yields no field set and falls through to the unknown-tool
            // refusal below, which is the actionable message for that request.
            if( !pathsUsageError )
            {
                const std::string fieldErr = mcpUnknownFieldRefusal( args, name, mcprefuse::declaredFieldsFor( name ) );
                if( !fieldErr.empty() )
                {
                    resp = errResultMsg( -32602, fieldErr );
                    pathsUsageError = true;   // reuse the skip-flag: no dispatch, no getIndex(), no byte written
                }
            }

            // ── W3FIX H5: a wrong-SHAPED string argument refuses, before any verb serves a default ─────────
            // Placed AFTER the two policy gates on purpose: over the remote transport an off-workspace path is
            // the more specific fix and must keep winning (and must keep refusing before getIndex()), and the
            // stdio default-root rebind must have happened before `path` is judged present.
            if( !pathsUsageError && !shapeRefusal.empty() )
            {
                resp = errResultMsg( -32602, shapeRefusal );
                pathsUsageError = true;   // reuse the skip-flag: no dispatch, no getIndex(), and for an edit verb no byte written
            }

            // D3 / §B6 M7: the per-verb "missing required field" message. It used to be a hand-written
            // if-chain here, a SECOND hand-written chain in the batch arm ("missing pattern"), and a third,
            // richer sentence on the CLI (flag + problem + EXAMPLE) — one condition, three wordings, and
            // only the CLI's told the caller what to type. The chain is now mcprefusal.h's verb+field
            // TABLE, rendered by both MCP arms; the only per-arm part is `argPresent`, which reads this
            // arm's already-parsed locals. Evaluated lazily (only if every dispatch arm below declines to
            // match); a name that matches no known verb yields "" and falls through to the unknown-tool
            // refusal below, which is now a DIFFERENT message rather than the same conflated one.
            const auto argPresent = [ & ]( std::string_view field ) -> bool
            {
                if( field == "symbol" )
                {
                    return !symbol.empty();
                }
                if( field == "pattern" )
                {
                    return !pattern.empty();
                }
                if( field == "file" )
                {
                    return !file.empty();
                }
                if( field == "task" )
                {
                    return !task.empty();
                }
                if( field == "type" )
                {
                    return !type.empty();
                }
                if( field == "kind" )
                {
                    return !kind.empty();
                }
                if( field == "from" )
                {
                    return !from.empty();
                }
                if( field == "to" )
                {
                    return !to.empty();
                }
                if( field == "handle" )
                {
                    return !handle.empty();
                }
                if( field == "trace" )
                {
                    return !trace.empty();
                }
                // ITEM A: the two PAYLOAD fields answer presence with hasVisibleContent, not `!empty()` — a
                // whitespace-only payload is the same unset-argument bug as an omitted one and used to DELETE
                // the definition while reporting {"applied":…}. See the ruling at isMcpEditVerb above for the
                // exact class and for why the read verbs' required strings are deliberately NOT widened.
                if( field == "new_body" )
                {
                    return hasVisibleContent( newBody );
                }
                if( field == "text" )
                {
                    return hasVisibleContent( text );
                }
                if( field == "path" )
                {
                    return !path.empty();
                }
                // M8: PRESENCE, not shape — the array readers own the shape verdict, and this predicate must
                // answer "did the request carry this field at all" so a wrong-shaped one is never reported
                // missing (which is the collapse M8 exists to undo).
                if( field == "queries" )
                {
                    return mcpArrayArg( args, "queries", false ).isPresent;
                }
                if( field == "symbols" )
                {
                    return mcpArrayArg( args, "symbols", true ).isPresent;
                }
                return true;   // a field this arm does not parse cannot be reported missing by it
            };
            const auto missingArgMsg = [ & ]() -> std::string
            {
                if( path.empty() )
                {
                    return mcprefuse::missingPathRefusal();
                }
                return mcprefuse::missingFieldRefusal( name, argPresent );
            };

            try   // a bad path / OOM must not std::terminate the long-lived server
            {
                // §H2: a WRITE verb's required set is judged from the table BEFORE dispatch — see isMcpEditVerb.
                //
                // V4: this gate sits INSIDE the try, and that is the whole point of where it sits. It COMPOSES a
                // refusal sentence — missingArgMsg → missingFieldRefusal builds a std::string, and the F2 clause
                // below appends to it — so it is an allocating step, and every allocating step of this handler
                // owes the invariant the comment on this very `try` states. It used to sit one line ABOVE the
                // try: an allocation excluded from the guard by the guard's own opening line. The
                // `if( !pathsUsageError )` that used to gate the try from outside is now the first arm of the
                // dispatch chain below, which is what makes room for this.
                if( !pathsUsageError && isMcpEditVerb( name ) )
                {
                    if( std::string missingEditArg = missingArgMsg(); !missingEditArg.empty() )
                    {
                        // F2: name WHICH invisible code points were sent, when any were. G5: the payload FIELD
                        // and the NOUN the sentence calls it by both come from kMcpRequiredFields — the table
                        // that already decides which field each edit verb requires — rather than from a ternary
                        // here. The ternary was a second list of exactly the kind §H2's own fix removed, and it
                        // is why both inserts said "and no definition" about a field contracted as "the text to
                        // insert". Guarded on a non-empty `path` because an ABSENT path short-circuits
                        // missingArgMsg to the universal path sentence, which is about a different field and
                        // must not collect a clause explaining a payload the caller has not been told about yet.
                        if( !path.empty() )
                        {
                            const std::string_view payloadField = mcprefuse::editPayloadField( name );
                            const std::string_view editPayload  = payloadField == "new_body" ? std::string_view( newBody )
                                                                                             : std::string_view( text );
                            const auto [ blankCodePointCount, blankSpelling ] = blankPayloadSpelling( editPayload );
                            missingEditArg += mcprefuse::blankPayloadClause( blankCodePointCount, blankSpelling, payloadField );
                        }

                        resp = errResultMsg( -32602, missingEditArg );
                        pathsUsageError = true;   // reuse the skip-flag: no dispatch, no getIndex(), no byte written
                    }
                }

                // §B6 M1: the MCP twin of the CLI's multi-root refusal enumeration, as ONE gate reading ONE
                // table (mcprefusal.h's kMcpSingleRootVerbs). Wave 1 built singleRootRefusal and wired it to
                // quality_baseline alone; the other single-root verbs went on answering a `paths` workspace
                // with a refusal of their own that named a FALSE cause — "not a git repository" about two real
                // git repos, "symbol not found" about a symbol find_symbol returns on the same paths. Joining
                // by ADDING CALL SITES was the instruction; a table plus one call site is the same join with
                // one fewer place to forget, and the consteval floor beside the table makes a forgotten row a
                // build error. quality_baseline's own inline check is now this gate — one sentence, one origin.
                if( !pathsUsageError && isMcpMultiRootPath( path ) )
                {
                    if( const std::string_view because = mcprefuse::singleRootReason( name ); !because.empty() )
                    {
                        resp            = errResultMsg( -32602, mcprefuse::singleRootRefusal( name, because ) );
                        pathsUsageError = true;
                    }
                }

                // A pre-dispatch refusal — a bad `paths` (checked above), the §H2 write gate, or the M1
                // single-root gate just above — has already composed the entire response, so dispatch nothing.
                // This empty arm is the `if( !pathsUsageError )` that used to wrap the try from outside.
                if( pathsUsageError ) { }
                else if( name == "analyze" && !path.empty() )
                {
                    // A3-F17 mapped an empty analysis to a JSON-RPC error, naming TWO causes: "empty corpus or
                    // unreadable directory". §B6 M3 established that BOTH of those were wrong about this arm:
                    //   • an empty corpus does NOT return "" — analyzeToString always emits the legend, so the
                    //     arm was UNREACHABLE for the case it was written for (which is exactly why the
                    //     false-zero class shipped: the guard that should have caught it never fired);
                    //   • an unreadable/nonexistent/file `path` is refused BEFORE dispatch now, by the one
                    //     shared root check above, which names which of those three it actually is.
                    // What remains is the one cause that genuinely yields "": open_memstream failing to
                    // allocate (captureXml degrades to "" rather than dereferencing NULL). That is an internal
                    // resource failure, so it gets -32603 and says so, instead of blaming the caller's path for
                    // a condition their path cannot cause. Kept rather than deleted: the degrade path is real,
                    // and a verb that silently returned empty text would read as "the repo is empty XML".
                    const std::string t = analyzeToString( path, topK, stable );
                    resp = t.empty() ? errResult( -32603, "could not render the map (out of memory while building the output buffer) — the path itself is fine" )
                                     : textResult( t );
                }
                else if( ( name == "find_symbol" || name == "find_referencing_symbols" ) && !path.empty() && !symbol.empty() )
                {
                    // M13: these two page like their CLI twins (--callers/--callees are both in
                    // honorsPaging), through the same mcpPageArgs window grep/impact/uses/whereis use.
                    resp = pagedResult( [ & ]( McpPageArgs pg )
                    {
                        const std::string j = symbolQueryJson( path, symbol, name == "find_referencing_symbols", pg );
                        return j.empty() ? errResultMsg( -32602, notFoundSym( symbol ) ) : textResult( j );
                    } );
                }
                else if( name == "grep" && !path.empty() && !pattern.empty() )
                {
                    // verifier N8: grep pages through the SAME window both other paged verbs use.
                    // R-H: `in` is the CLI --grep-in twin — code (default) or any. Wave-3 verifier P6-2:
                    // an unknown value used to read as the default and silently return the TIERED answer
                    // (`in:"Any"` measured 3 rows with suppressed_string="38", against 41 for `in:"any"`)
                    // — a closed set that swallows a typo in the direction that hides rows. The old
                    // rationale, "this verb has no refusal channel per-argument", was false: mcprefusal.h
                    // registers the field and the batch surface already refuses loudly. Both dialects now
                    // read the value through grepInModeFromArg, so they cannot disagree about the set.
                    rw::GrepIn        grepInMode = rw::GrepIn::Code;
                    const std::string inRefusal  = rw::grepInModeFromArg( strArg( "in" ), grepInMode );
                    if( !inRefusal.empty() )
                    {
                        resp = errResultMsg( -32602, inRefusal );
                    }
                    else
                    {
                        resp = pagedResult( [ & ]( McpPageArgs pg ) { return textResult( grepHitsJson( path, pattern, pg, grepInMode ) ); } );
                    }
                }
                else if( name == "cochange" && !path.empty() && !file.empty() )
                {
                    // M13: pages like the CLI --cochange twin (a honorsPaging member).
                    resp = pagedResult( [ & ]( McpPageArgs pg )
                    {
                        const std::string j = cochangePartnersJson( path, file, pg );
                        return j.empty() ? errResultMsg( -32602, mcprefuse::fileNotFound( getIndex( path ).ing, file ) )
                                         : textResult( j );
                    } );
                }
                else if( name == "memory_recall" && !path.empty() && !task.empty() )
                {
                    // §B6 M15: `top_k` (default 8, the historic hardcode) — the budget lever the in-band
                    // est_tokens disclosure has always implied, and the CLI's --recall now honors.
                    // Body ceiling parity with the CLI: recall is bounded by default on BOTH front doors
                    // (kDefaultRecallMaxTokens, header-disclosed) — `budget_tokens` raises it explicitly,
                    // the same shaping knob explore/from_trace already declare. 0 (unbounded) is no longer
                    // reachable by omission, only by an explicit large value.
                    // H9: hand recallText the TOKEN count, not a byte budget converted here. The conversion
                    // used to live at this call site and at the CLI's, and both then handed the builder a
                    // byte number the header could no longer name — which is why `budget_tokens=1500` applied
                    // a 1500-token ceiling and disclosed none. recall.h's recallBytesForTokens owns it now.
                    const std::size_t recallTokens = budgetArg.isPresent ? std::size_t( budgetArg.value )
                                                                         : kDefaultRecallMaxTokens;
                    resp = textResult( recallText( path, task, recallTopK, recallTokens, redactPtr ) );
                }
                else if( name == "situational_awareness" && !path.empty() )
                {
                    // diff source: explicit `diff` or `files` list, else default to the working-tree git diff.
                    // N11 (`files`) and W3FIX H5 (`diff`): a non-STRING value for EITHER refuses before this
                    // branch runs (the shared shapeRefusal gate above), rather than falling through to that
                    // default — the default is a correct answer to a question the caller did not ask.
                    const std::string src = !diff.empty() ? diff : files;
                    // H6: a `files`/`diff` list naming nothing indexed REFUSES here, before the report is
                    // built — the pre-fix arm answered it with all-empty arrays and a green _fresh, which a
                    // caller checking only for an `error` key reads as "your edit has no blast radius".
                    const std::string listRefusal = situationFileListRefusal( path, src );
                    const std::string j           = listRefusal.empty() ? situationDiffJson( path, src ) : std::string();
                    resp = !listRefusal.empty() ? errResultMsg( -32602, listRefusal )
                         : j.empty()            ? errResult( -32602, "no changed files given and no git diff" )
                                                : textResult( j );
                }
                else if( name == "mentions" && !path.empty() && !symbol.empty() )
                {
                    // §B11.1: the V2-1 guard, same shared sentence as `uses` — this verb takes the same
                    // `symbol` field through the same bare-name resolver, so a qualified spelling used to come
                    // back as "symbol not found" about a symbol that plainly exists.
                    const std::string refusal = qualifiedSelectorRefusal( getIndex( path ).ing, symbol, "--mentions=" );
                    if( !refusal.empty() )
                    {
                        resp = errResultMsg( -32602, refusal );
                    }
                    else
                    {
                        resp = pagedResult( [ & ]( McpPageArgs pg )   // M13
                        {
                            const std::string j = mentionsJson( path, symbol, pg );
                            return j.empty() ? errResultMsg( -32602, notFoundSym( symbol ) ) : textResult( j );
                        } );
                    }
                }
                else if( name == "for" && !path.empty() && !task.empty() )
                {
                    // M13: `budget_tokens` — the same knob the CLI --for takes, absent here until now.
                    const std::string t = forTaskText( path, task, redactPtr,
                                                       budgetArg.isPresent ? std::size_t( budgetArg.value ) : 0 );
                    resp = t.empty() ? errResult( -32602, "no symbols found" ) : textResult( t );
                }
                else if( name == "lego" && !path.empty() && !type.empty() )
                {
                    // D8 fix: legoText now only returns "" on genuine not-found — a resolved type with zero
                    // implementors comes back as real content (implementors="0" + contract), so this message
                    // is no longer conflating two different failures.
                    const std::string t = legoText( path, type, redactPtr );
                    resp = t.empty() ? errResultMsg( -32602, notFoundKind( "type", type ) ) : textResult( t );
                }
                else if( name == "whereis" && !path.empty() && !symbol.empty() )
                {
                    // §B6 M4: limit/offset are read by the SAME mcpPageArgs the batch arm uses (mcpverbs.h).
                    // L6 (capture-audit 2026-09-04): an UNRESOLVABLE @FILE:LINE seed is now its own refusal
                    // — the shared triple (flag + problem + the per-fault clause selectorrefuse.h speaks for
                    // the CLI), not a hits="0" answer about the literal string. `seedFault` distinguishes it
                    // from the non-git degrade, which is the other way whereisText returns "".
                    resp = pagedResult( [ & ]( McpPageArgs pg )
                    {
                        bool              seedFault = false;
                        const std::string t = whereisText( path, symbol, kind, crossref::kWhereisHits, pg, &seedFault );
                        if( seedFault )
                        {
                            return errResultMsg( -32602, mcprefuse::notFound( getIndex( path ).ing, "symbol", symbol ) );
                        }
                        return t.empty() ? errResult( -32602, "not a git repository (or no HEAD commit) — no refs to search" ) : textResult( t );
                    } );
                }
                else if( name == "stray_content" && !path.empty() )
                {
                    // `kind` doubles as the optional ref-name substring filter (no dedicated arg needed).
                    resp = pagedResult( [ & ]( McpPageArgs pg )   // M13
                    {
                        const std::string t = strayContentText( path, kind, crossref::kStrayFilesPerRef, pg );
                        return t.empty() ? errResult( -32602, "not a git repository (or no HEAD commit) — no refs to compare" ) : textResult( t );
                    } );
                }
                else if( name == "flags" && !path.empty() )
                {
                    // `kind` doubles as the optional gate-name substring filter; `symbol` (optional) names ONE
                    // gate and switches the verb to the CLI's --flip lens: that gate's flip blast radius.
                    if( !symbol.empty() )
                    {
                        std::vector<std::string> nearMisses;
                        const std::string        t = flipText( path, symbol, flipimpact::kMaxFlipRows, nearMisses );
                        if( t.empty() )
                        {
                            std::string msg = "no gate named '" + symbol + "' — call flags without `symbol` for the gate table";
                            if( !nearMisses.empty() )
                            {
                                msg += " (did you mean";
                                for( std::size_t i = 0; i < nearMisses.size(); ++i )
                                {
                                    msg += ( i ? ", '" : " '" ) + nearMisses[i] + "'";
                                }
                                msg += "?)";
                            }
                            resp = errResultMsg( -32602, msg );
                        }
                        else { resp = textResult( t ); }
                    }
                    else
                    {
                        const std::string t = flagsText( path, kind, darkflags::kMaxSitesShown );
                        resp = t.empty() ? errResult( -32603, "internal error" ) : textResult( t );
                    }
                }
                else if( name == "doc_drift" && !path.empty() )
                {
                    // `kind` doubles as the optional doc-path substring filter.
                    resp = pagedResult( [ & ]( McpPageArgs pg )   // M13
                    {
                        const std::string t = docDriftText( path, kind, docdrift::kMaxAnchorsShown, pg );
                        return t.empty() ? errResult( -32603, "internal error" ) : textResult( t );
                    } );
                }
                else if( name == "owners" && !path.empty() )
                {
                    // `symbol` is optional — empty string means all files.
                    // the two failures were run together under one sentence; with no `symbol` given only one
                    // of them is even possible, so each is now reported as itself.
                    // §B11.1: the V2-1 guard (shared sentence, see qualifiedSelectorRefusal). Empty `symbol`
                    // has no colon, so the all-files form cannot reach it.
                    const std::string refusal = qualifiedSelectorRefusal( getIndex( path ).ing, symbol, "--owners=" );
                    if( !refusal.empty() ) { resp = errResultMsg( -32602, refusal ); }
                    else
                    {
                    resp = pagedResult( [ & ]( McpPageArgs pg )   // M13
                    {
                        const std::string t = ownersText( path, symbol, pg );
                        return t.empty() ? errResultMsg( -32602, symbol.empty()
                                                ? std::string( "no git history for this tree (owners is mined from git; not a repo, or no commits)" )
                                                : notFoundSym( symbol ) )
                                         : textResult( t );
                    } );
                    }
                }
                // ─── flagship-reflex verbs ───
                else if( name == "exemplar" && !path.empty() && ( !kind.empty() || !task.empty() ) )
                {
                    // `kind` (a kind token) OR `task` (a task string) — either resolves to a target kind by ROLE.
                    const std::string arg = !kind.empty() ? kind : task;
                    const std::string t   = exemplarText( path, arg, redactPtr );
                    resp = t.empty() ? errResult( -32602, "no matching exemplar (no symbol of that kind, or the task matched nothing)" ) : textResult( t );
                }
                else if( name == "impact" && !path.empty() && !symbol.empty() )
                {
                    // §B6 M4: limit/offset are read by the SAME mcpPageArgs the batch arm uses (mcpverbs.h).
                    resp = pagedResult( [ & ]( McpPageArgs pg )
                    {
                        const std::string t = impactText( path, symbol, pg );
                        return t.empty() ? errResultMsg( -32602, notFoundSym( symbol ) ) : textResult( t );
                    } );
                }
                else if( name == "uses" && !path.empty() && !symbol.empty() )
                {
                    // V2-1: same shared guard as the batch dispatch — a qualified file:name spelling whose
                    // bare name IS defined refuses instead of answering external="1" (a false claim).
                    const std::string refusal = usesSelectorRefusal( getIndex( path ).ing, symbol );
                    // LB-G: limit/offset are read by the SAME mcpPageArgs impact uses, because this verb now
                    // honors them — it grew a default site cap in that round and needs the hatch to match.
                    resp = refusal.empty() ? pagedResult( [ & ]( McpPageArgs pg )
                                             { return textResult( usesText( path, symbol, pg ) ); } )   // count="0" stays a valid answer
                                           : errResultMsg( -32602, refusal );
                }
                else if( name == "path_between" && !path.empty() && !from.empty() && !to.empty() )
                {
                    const std::string t = pathText( path, from, to );
                    resp = t.empty() ? errResultMsg( -32602, pathEndpointRefusal( getIndex( path ).ing, from, to ) )
                                     : textResult( t );
                }
                // `connect` — symbols as a JSON string array (the schema form) or a comma-string (lenient);
                // optional integer radius (core clamps to 1..12). One global computation, not a batch of paths.
                else if( name == "connect" && !path.empty() )
                {
                    // W3FIX M8: the array/comma-string read AND its 2..16 element-count domain come from the
                    // shared guarded reader. `symbols:5` used to read as absent ("missing required field:
                    // symbols" for a field that WAS sent) and `symbols:["main"]` got a bespoke fourth dialect
                    // ("connect needs 2..16 symbols (got 1)") with neither the domain clause nor an example.
                    const McpArrayArg              symbolsArg = mcpArrayArg( args, "symbols", true, 2, connectcfg::kMaxTerminals );
                    const std::vector<std::string> specs      = symbolsArg.strings;
                    // verifier N3: the radius went through a bare `std::uint32_t( radArg )` cast, so it wrapped
                    // MODULO 2^32 — radius:2^40 became 0, clamped to 1, and the verb answered a 1-hop question
                    // while echoing radius="1" as if that is what was asked. radius:3.7 truncated to 3; 0, -5
                    // and "abc" all silently became the default 6. §B8.1 ruled a value outside a declared band
                    // is REFUSED, not clamped, and that ruling stopped at the CLI's --connect-radius. Same
                    // shared reader as limit/offset, same band, same sentence shape.
                    static_assert( connectcfg::kMaxRadius == 12 && connectcfg::kMinRadius == 1,
                                   "the radius refusal names the band 1..12 in mcprefusal.h's kMcpValueFields and in the "
                                   "tools/list connect stanza — the core's clamp band moved; move both wordings with it" );
                    // N6: the missing-`symbols` refusal is the M7 table's sentence, not this branch's own
                    // pre-M7 wording — the specifics ("2..16 symbol names") live in the table's needs-text.
                    // M8 splits it from its twin: ABSENT is the M7 missing-field sentence, PRESENT-BUT-WRONG
                    // (bad shape or a count outside 2..16) is the M8 bad-value sentence, and they no longer
                    // share one message that was only ever right about one of them.
                    const McpIntArg   radiusArg = mcpIntArg( args, "radius", connectcfg::kMinRadius, connectcfg::kMaxRadius );
                    std::string       connErr   = !radiusArg.refusal.empty()  ? radiusArg.refusal
                                                : !symbolsArg.refusal.empty() ? symbolsArg.refusal
                                                : !symbolsArg.isPresent       ? mcprefuse::missingFieldRefusal( "connect" )
                                                                              : std::string{};
                    const std::uint32_t rad = radiusArg.isPresent ? std::uint32_t( radiusArg.value ) : connectcfg::kDefaultRadius;
                    const std::string   t   = connErr.empty() ? connectText( path, specs, rad, connErr, redactPtr ) : std::string{};
                    resp = t.empty() ? errResultMsg( -32602, connErr ) : textResult( t );
                }
                else if( name == "quality_delta" && !path.empty() )
                {
                    std::string       qerr;
                    const std::string j = qualityDeltaJson( path, qerr );
                    resp = j.empty() ? errResultMsg( -32602, qerr.empty() ? std::string( "quality-delta unavailable" ) : qerr ) : textResult( j );
                }
                else if( name == "quality_baseline" && !path.empty() )
                {
                    // §B6 M9: over a multi-root `paths` workspace this verb used to render the raw \x1f-separated
                    // workspace REGISTRY KEY into a client-facing message — "could not write <key>/.ripwire_
                    // quality_baseline (unwritable directory?)" under -32603. Three lies in one sentence: an
                    // internal key shown as a path, an INTERNAL-ERROR code for a caller usage error, and a
                    // filesystem cause for a request-shape problem (the directory was perfectly writable; there
                    // simply is no single directory to write ONE sidecar into for N roots).
                    //
                    // The refusal is mcprefusal.h's singleRootRefusal, and §B6 M1 has now JOINED it: the
                    // multi-root check that used to sit here inline is the shared pre-dispatch gate above,
                    // reading kMcpSingleRootVerbs, so this verb's reason lives in the same table as the other
                    // six instead of being the one hand-written instance. Control only reaches here on a
                    // single-root path. It never renders the workspace key.
                    std::string       qerr;
                    const std::string j = qualityBaselineJson( path, qerr );
                    resp = j.empty() ? errResultMsg( -32603, qerr.empty() ? std::string( "could not write baseline" ) : qerr ) : textResult( j );
                }
                // L4: `explore` — ONE-call task orientation (routed ranking + bodies + callers + notes + tests_to_run
                // under a budget), the SAME handler --pack-task's CLI path calls (packTaskBundleText, packtask.h). D3:
                // "not-supported reflex" would be wrong for this pack — the emitted bundle is never "" for a resolved
                // task (the header comment always renders), so unlike most read verbs there is no not-found error here.
                // `pack_task` is the dispatch-only alias (same branch, not separately advertised in tools/list above).
                else if( ( name == "explore" || name == "pack_task" ) && !path.empty() && !task.empty() )
                {
                    // W3FIX H4: `partition` used to be a bare `std::uint32_t( partitionArg )` cast — N3's
                    // radius bug, one field over — so partition:4294967299 ran a 3-way fan-out and
                    // partition:2^32 served a single bundle, both silently. The band is a DECLARED domain now
                    // (mcpIntArg above), and this tripwire holds the three places that spell it together.
                    static_assert( packpartition::kMinPartitions == 2 && packpartition::kMaxPartitions == 16,
                                   "the partition refusal names the band 2..16 in mcprefusal.h's kMcpValueFields and in the "
                                   "tools/list explore stanza — the core's band moved; move both wordings with it" );
                    static_assert( kMcpRecallTopKMax == 1000,
                                   "the top_k refusal names the band 1..1000 in mcprefusal.h's kMcpValueFields and in the "
                                   "tools/list memory_recall stanza — move all three together" );
                    resp = textResult( packTaskText( path, task, budgetTokens, redactPtr, partitionCount ) );
                }
                // L4: `from_trace` — maps a pasted stack-trace/sanitizer/compiler-error TEXT onto indexed symbols
                // (fromTraceBundleText, tracelocus.h) — the SAME assembler --from-trace's CLI path calls.
                else if( name == "from_trace" && !path.empty() && !trace.empty() )
                {
                    const std::string t = fromTraceText( path, trace, budgetTokens, redactPtr );
                    resp = t.empty() ? errResult( -32602, "no stack-trace / sanitizer / compiler frames found in `trace` — nothing to map" ) : textResult( t );
                }
                // L4: `edit_check` — did SYM's contract (params/publicness) change vs git HEAD (editCheckBundleText,
                // editcheck.h) — the SAME contract-comparison core --edit-check's CLI path calls.
                else if( name == "edit_check" && !path.empty() && !symbol.empty() )
                {
                    // §A6a: the verb now words its own refusal (symbol-not-found, or the ambiguity refusal —
                    // a symbol matching several definition SITES has several contracts, and this verb answers
                    // about one), so this stays the same single payload-or-refusal branch it always was.
                    const EditCheckReply r = editCheckText( path, symbol, newBody );   // card A1: new_body ⇒ PREVIEW, never a write
                    resp = r.payload.empty() ? errResultMsg( -32602, r.refusal ) : textResult( r.payload );
                }
                // lane/tc-sliceat: the ARISE def-use slice — sliceText owns the whole contract (resolution,
                // the @FILE:LINE seed, flow/depth pairing, every refusal), mirroring the CLI runSlice.
                else if( name == "slice" && !path.empty() && !symbol.empty() )
                {
                    if( ( legendIsPresent && legendArg.empty() )
                        || ( !legendArg.empty() && legendArg != "compact" && legendArg != "full" ) )
                    {
                        resp = errResultMsg( -32602, mcprefuse::badValueRefusal( "legend", legendArg ) );
                    }
                    else
                    {
                    const SliceReply r = sliceText( path, symbol, var, flow,
                                                    sliceDepthArg.isPresent ? int( sliceDepthArg.value ) : 0, redactPtr,
                                                    legendArg == "compact" );
                    resp = r.payload.empty() ? errResultMsg( -32602, r.refusal ) : textResult( r.payload );
                    }
                }
                // EDIT verbs — `file` (optional) is the disambiguating file-path substring for a same-named
                // symbol; the PAYLOAD is non-empty by the §H2 write-verb gate above (see isMcpEditVerb).
                else if( name == "replace_symbol_body" && !path.empty() && !symbol.empty() )
                {
                    resp = editResult( runEditVerb( path, mcpedit::Op::ReplaceBody, symbol, file, newBody, postCheck ) );
                }
                else if( name == "insert_before_symbol" && !path.empty() && !symbol.empty() )
                {
                    resp = editResult( runEditVerb( path, mcpedit::Op::InsertBefore, symbol, file, text, postCheck ) );
                }
                else if( name == "insert_after_symbol" && !path.empty() && !symbol.empty() )
                {
                    resp = editResult( runEditVerb( path, mcpedit::Op::InsertAfter, symbol, file, text, postCheck ) );
                // T4 lazy-body verb: return a def's full source by its stable handle (or a staleness/refusal message).
                }
                else if( name == "fetch_body" && !path.empty() && !handle.empty() )
                {
                    // Feature 2: a range is in play if EITHER bound was given. A lone start_line ⇒ start..EOF
                    // (endLine defaults to a huge value → clamps to the last line); a lone end_line ⇒ 1..end.
                    const bool      hasRange = hasStart || hasEnd;
                    const long long s        = hasStart ? startLine : 1;
                    const long long e        = hasEnd   ? endLine   : ( hasStart ? (long long)0x7fffffff : 0 );
                    const FetchOutcome fo = fetchBody( path, handle, s, e, hasRange, redactPtr );
                    // V3/RN1: withHandleRootProvenance owns the omitted-`path`-vs-rename fork.
                    resp = fo.ok ? textResult( fo.resultJson )
                                 : errResultMsg( fo.errCode, mcprefuse::withHandleRootProvenance(
                                       fo.message, fo.unresolvedHandle && !rootFromCaller, path ) );
                }
                // A4-R3 batch verb: N read sub-queries over `path` in one round-trip. A malformed/empty
                // `queries` array is a whole-request error; a bad SUB-query (unknown verb, missing arg, not
                // found) is an inline per-<q> error and never fails the batch. Over-cap batches are honest
                // (capped="1", n<requested) rather than silently truncated.
                else if( name == "batch" && !path.empty() )
                {
                    // N6: an ABSENT `queries` speaks the M7 table's sentence. W3FIX M8 splits its twin back
                    // out: `queries:5` and `queries:[1,"x",null]` are PRESENT-but-wrong-shaped, and answering
                    // those with "missing required field: queries" tells the caller to send a field they did
                    // send — the absent-vs-wrong-shape collapse. Wrong shape now gets the M8 bad-value
                    // sentence with the domain and the value as typed.
                    const McpArrayArg queriesArg = mcpArrayArg( args, "queries", false );
                    const std::string arr        = queriesArg.isPresent ? queriesArg.span : std::string{};
                    if( !queriesArg.refusal.empty() )
                    {
                        resp = errResultMsg( -32602, queriesArg.refusal );
                    }
                    else if( !queriesArg.isPresent )
                    {
                        resp = errResultMsg( -32602, mcprefuse::missingFieldRefusal( "batch" ) );
                    }
                    else
                    {
                        // M5 (capture-audit 2026-09-04): BOTH grammars. `queries` may be the
                        // `{verb, …args}` objects this surface has always taken, OR the `"verb:arg"` lines
                        // the CLI --batch file takes — the capture's own example used the second and got a
                        // refusal captioned as a success. The string form is accepted only when EVERY
                        // element names a verb batch actually serves (isBatchCliSpec), so the hostile
                        // `queries:[1,"x",null]` the M8 bad-value refusal covers keeps getting that
                        // refusal instead of being reinterpreted as a sub-query named "x". Objects win a
                        // mixed array: an array that already parses as objects is answered as one.
                        std::vector<std::string> objs = mcpdetail::arrayObjects( arr );
                        // F8 (capture-audit verify-wave2 2026-09-05): a MIXED array used to fall through to
                        // the object reader, which discards the strings — two sub-queries in, one answered,
                        // and `requested="1"` telling the caller they asked for one:
                        //   queries:["callers:rankGraphTeleport", {"verb":"slice","symbol":"…"}]
                        //   → <batch n="1" requested="1" cap="16">…  exit 0, isError unset
                        // requested= is the CALLER'S array length or it is not a disclosure, and dropping a
                        // member in silence is the HIGH class this round exists to remove. M5 is what makes
                        // mixing a natural mistake — both grammars are now documented as accepted — so the
                        // two are accepted separately and never blended: an array is all objects or all
                        // served-verb strings, and anything else is refused NAMING the count that would have
                        // been dropped. (Objects still win nothing by default: an all-object array parses as
                        // objects, an all-string array as specs, exactly as before.)
                        // the TOP-LEVEL elements — not arrayStrings, which also finds the keys and values
                        // INSIDE each object and would call every object array "mixed" (measured: an
                        // all-object one-element array read as 1 object + 4 strings).
                        const std::vector<std::string> elems = mcpdetail::arrayTopLevelElements( arr );
                        std::size_t nObjElems = 0, nStrElems = 0;
                        for( const std::string& e : elems )
                        {
                            if( !e.empty() && e.front() == '{' ) { ++nObjElems; }
                            else if( !e.empty() && e.front() == '"' ) { ++nStrElems; }
                        }
                        if( nObjElems > 0 && nStrElems > 0 )
                        {
                            resp = errResultMsg( -32602,
                                       "queries mixes the two grammars: " + std::to_string( nObjElems )
                                     + " sub-query object(s) and " + std::to_string( nStrElems )
                                     + " \"verb:arg\" string(s). Send one or the other — a mixed array can only be "
                                       "answered by dropping members, and this verb does not drop members silently "
                                       "(e.g. [{\"verb\":\"callers\",\"symbol\":\"parseArgs\"}] or [\"callers:parseArgs\"])" );
                            objs.clear();
                        }
                        else if( objs.empty() )
                        {
                            const std::vector<std::string> specs = mcpdetail::arrayStrings( args, "queries" );
                            const bool allServed = !specs.empty()
                                                && std::all_of( specs.begin(), specs.end(),
                                                                []( const std::string& q ) { return isBatchCliSpec( q ); } );
                            if( allServed )
                            {
                                for( const std::string& q : specs )
                                {
                                    if( std::string obj = batchObjectFromCliSpec( q ); !obj.empty() )
                                    {
                                        objs.push_back( std::move( obj ) );
                                    }
                                }
                            }
                        }
                        const std::size_t               requested = objs.size();
                        if( !resp.empty() )
                        {
                            // the mixed-array refusal above already answered this request
                        }
                        else if( requested == 0 )
                        {
                            resp = errResultMsg( -32602, mcprefuse::badValueRefusal( "queries", arr ) );
                        }
                        else
                        {
                            const std::size_t     take = std::min<std::size_t>( requested, kBatchCap );
                            std::vector<BatchSub> subs;
                            subs.reserve( take );
                            for( std::size_t i = 0; i < take; ++i )
                            {
                                subs.push_back( runBatchSub( path, objs[i], topK, stable, redactPtr ) );
                            }
                            resp = textResult( batchText( subs, requested, kBatchCap ) );
                        }
                    }
                }
                else
                {
                    // §B6 M9: "unknown tool or missing args" ran TWO failures with different fixes into one
                    // sentence and named neither the verb nor a near-miss — with the whole 30-name registry
                    // in-process one call away. Split: a known verb with an incomplete argument set gets the
                    // table's message (above); an unrecognised name gets its own refusal, WITH the near-miss
                    // the `flags` verb has offered since it shipped.
                    const std::string missing = missingArgMsg();
                    if( !missing.empty() )
                    {
                        resp = errResultMsg( -32602, missing );
                    }
                    else
                    {
                        std::vector<std::string_view> knownVerbs;
                        knownVerbs.reserve( kMcpVerbCount + std::size( mcprefuse::kMcpVerbAliases ) );
                        for( const McpVerbInfo& info : kMcpVerbTable )
                        {
                            knownVerbs.push_back( info.name );
                        }
                        // W3FIX M4: the callable ALIASES join the near-miss pool (a `packtask` typo should land
                        // on `pack_task`, which this server answers) — the printed COUNT below stays the
                        // advertised one, which is what "call tools/list for the N available tools" promises.
                        const std::size_t advertisedCount = knownVerbs.size();
                        for( const mcprefuse::McpVerbAlias& alias : mcprefuse::kMcpVerbAliases )
                        {
                            knownVerbs.push_back( alias.alias );
                        }
                        // code stays -32602 (what this arm has always sent for an unknown tool); the FIX
                        // here is the message, and changing the code too would break callers switching on it
                        // for a reason unrelated to the finding.
                        resp = errResultMsg( -32602, mcprefuse::unknownVerbRefusal( knownVerbs, name, advertisedCount ) );
                    }
                }
            }
            catch( ... )
            {
                resp = errResult( -32603, "internal error" );
            }

            // one deterministic per-request summary line when anything was masked (no-op otherwise) —
            // mirrors the CLI's end-of-run reportRedactions, on stderr so the JSON-RPC stream stays clean.
            reportRedactions( stderr, redactCounts );
        }
        // §B6 M6: the `method.empty()` → `-32700 "parse error"` arm that used to sit here is GONE. It was the
        // catch-all four unrelated inputs shared — a truncated frame, a spec-legal batch array, a wrong-typed
        // `method`, and real garbage — each of which now has its own refusal with its own code, upstream of
        // this chain (the framing gate and the two envelope checks above). By the time control reaches here,
        // `method` is a non-empty string, so this arm could only ever have been reached by the four cases that
        // no longer arrive: keeping it would be keeping the sentence that made them indistinguishable.
        else
        {
            resp = "{\"jsonrpc\":\"2.0\",\"id\":" + id + ",\"error\":{\"code\":-32601,\"message\":\"method not found\"}}";
        }

        out.resp       = std::move( resp );
        out.timingVerb = std::move( timingVerb );
        return out;
    }
}

// stdio MCP loop: one JSON object per line. Returns the process exit code. `root`/`roots` are the
// positional args `ripwire <root> --mcp` was started with (roots.size()>=2 = a multi-root workspace);
// both default empty for the pre-X7 "no startup root" mode, in which every request must still name its
// own `path` exactly as before. `root` mirrors `McpHttpConfig::root`; `roots` mirrors `::roots` — same
// plumbing as runMcpHttp(), just building McpDispatchPolicy::defaultRoot instead of ::pinnedRoot (D3/D4).
inline int runMcp( int topK, bool stable = false, bool noRedact = false,
                   const std::string& root = std::string(), const std::vector<std::string>& roots = {} )
{
    // MEASURE-FIRST instrumentation (RIPWIRE_MCP_TIMINGS, off by default → byte-identical + silent server, same
    // discipline as ingest.cpp's RIPWIRE_CACHE_STATS). When set, emit ONE stderr TSV line per handled request:
    //   ripwire-timing verb=<v> wall_ms=<f> rebuilt=<0|1>
    // stderr only, so the JSON-RPC stdout stream is untouched and every determinism/protocol gate is unaffected.
    // NOTE: the design specified a `--mcp-timings` CLI flag; cli.h/main.cpp are owned by a concurrent agent this
    // round, so we use the env var instead (recorded in bench/PROFILE.md's appendix) — same zero-cost-off contract.
    const bool timingsOn = std::getenv( "RIPWIRE_MCP_TIMINGS" ) != nullptr;

    // X7 (D3/D4): resolve the SOFT stdio default root, same shape as runMcpHttp()'s pinnedRoot resolution
    // (mcpWorkspaceKey for 2+ roots, else a plain mcpCanonRoot) but never refuses to start — a malformed
    // multi-root set just leaves defaultRoot empty (falls back to the pre-X7 "every request names its own
    // path" behavior) rather than exiting, since stdio has no analogous "refuse to bind" moment.
    std::string defaultRoot;
    if( roots.size() >= 2 )
    {
        std::string wsErr;
        const std::string key = mcpWorkspaceKey( roots, wsErr );
        if( !key.empty() )
        {
            defaultRoot = mcpCanonRoot( key );
        }
    }
    else if( !root.empty() )
    {
        defaultRoot = mcpCanonRoot( root );
    }

    McpDispatchPolicy policy;      // stdio: no HARD workspace pinning (pinnedRoot stays ""), edit verbs allowed
    policy.defaultRoot = defaultRoot;   // "" unless a startup root was given — see the comment above

    // R2a (the 2026-08-12 usage mine): with NO startup root, resolve the launch cwd ONCE as the softest
    // default — see McpDispatchPolicy::assumedRoot for the full contract and mcpResolveAssumedRoot for
    // the guards ("/" and $HOME are nobody's workspace; getcwd failure degrades to the refusal).
    if( defaultRoot.empty() )
    {
        policy.assumedRoot = mcpResolveAssumedRoot();
    }

    // R4: readByteSafeLine, NOT std::getline( std::cin, ... ) — libc++'s getline narrows int_type→char on
    // every std::cin byte, so a single 0x80..0xFF request byte aborted the sanitizer build and left this
    // whole server surface dark for non-ASCII input. Same parity contract (see stdinline.h): grows
    // dynamically — a >1MB request is not split into garbage — delimiter consumed, trailing '\r' kept.
    std::string line;
    while( readByteSafeLine( stdin, line ) )
    {
        if( line.find_first_not_of( " \t\r\n" ) == std::string::npos )
        {
            continue;
        }

        // per-request timing capture (only when the env observable is on — zero clock/atomic work otherwise).
        const std::chrono::steady_clock::time_point t0 =
            timingsOn ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
        const std::uint64_t rebuildAtStart = timingsOn ? mcpRebuildCounter().load( std::memory_order_relaxed ) : 0;

        const McpDispatchResult r = dispatchMcpLine( line, topK, stable, noRedact, policy );
        if( r.isNotification )
        {
            continue;
        }

        std::fputs( r.resp.c_str(), stdout );
        std::fputc( '\n', stdout );
        std::fflush( stdout );

        // MEASURE-FIRST per-request timing line (stderr only, env-gated). Emitted AFTER the protocol response is
        // flushed so it can never interleave into the JSON-RPC stdout stream. rebuilt=1 iff a full getIndex()
        // rebuild fired somewhere in this request's handling (staleness / post-edit path).
        if( timingsOn )
        {
            const double wallMs = std::chrono::duration< double, std::milli >(
                                      std::chrono::steady_clock::now() - t0 ).count();
            const unsigned rebuilt = ( mcpRebuildCounter().load( std::memory_order_relaxed ) != rebuildAtStart ) ? 1u : 0u;
            std::fprintf( stderr, "ripwire-timing verb=%s wall_ms=%.3f rebuilt=%u\n",
                          r.timingVerb.c_str(), wallMs, rebuilt );
            std::fflush( stderr );
        }
    }
    return 0;
}

}   // namespace rw
