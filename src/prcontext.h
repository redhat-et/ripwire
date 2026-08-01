#pragma once

// prcontext.h — Wave-4 feature: --pr-context[=BASEREF]. The no-LLM review-evidence bundle: for the
// current working-tree diff (default) or a diff vs BASEREF, emit ONE deterministic XML section per
// changed file carrying everything a reviewer (human or agent) needs to reason about the change —
//   • the file's defined symbols
//   • their callers (1-hop in-edges)                    ← reuses the in-edge CSR (like --callers)
//   • the blast radius (transitive reverse reachability) ← reuses transitiveCallers (like --impact/--affected)
//   • the affected TEST files among that blast radius    ← reuses isTestPath (like --affected)
//   • co-change partners not in the diff                 ← reuses cochangePartners (gitmine)
//   • the file's owners                                  ← reuses gitFileAuthors (gitmine)
//
// This header COMPOSES existing analysis; it re-implements none of it. Output is the existing terse-
// attribute XML style, everything through escapeXml, deterministic (sorted paths, symbol id order).
// A non-git dir, git-unavailable, or a clean tree degrades to a single explanatory comment node and
// the caller exits 0. A BASEREF that does not resolve to a commit is the one case that does NOT degrade:
// it REFUSES with exit 1 (PrContextMask::badRef) — both because a silent empty bundle is indistinguishable
// from a clean tree in CI (P2.8), and because the raw token must never reach a git argv at all (P0.1).
//
// The changed-file mask (both the working-tree default and the BASEREF form) is built from
// `git diff --numstat`, NOT `--name-only` (A3-F10): numstat's 0-added/0-deleted rows are content-
// identical entries (pure mode flips, e.g. a chmod) and are excluded from the changed set — a raw
// `--name-only` mask can't tell those apart from a real edit, and a mass chmod (a real incident: 272
// files) turned into a 272-file "evidence bundle" of pure noise. The excluded count is still surfaced,
// as the `skipped_mode_only` attribute on <pr-context>, so the information isn't silently lost.
//
// ── ANCHORING: the BASEREF form is MERGE-BASE anchored, never two-dot (r26 merge-base audit) ─────────────
// The two anchors this verb can pick from, and why only one of them answers a reviewer's question:
//   default (no BASEREF)  `git diff HEAD` — the working tree against ITS OWN parent commit. There is no
//                         anchoring question here at all: HEAD is not a diverged line, it is this work's
//                         own base. Kept exactly as it was.
//   BASEREF form          `git diff merge-base(BASEREF, HEAD)`, NOT `git diff BASEREF`. A plain two-dot
//                         `diff BASEREF` answers "how do these two trees differ TODAY", which is not the
//                         review question ("what did this work change") the moment BASEREF has moved since
//                         this branch forked — exactly the failure abicheck.h §AUTHORSHIP documents for
//                         --abi, and crossref.h §"what stray content means" for --stray-content. Same bug,
//                         third verb. It cuts BOTH ways, and the second cut is the worse one:
//                           phantom  a file only BASEREF touched is content-different from our tree, so
//                                    two-dot lists it — and the bundle spends a full evidence section
//                                    (symbols, callers, blast radius, co-change, owners) on a file this
//                                    work never opened. Measured on a live 36-ref C++ tree: 38 such files.
//                           MISSED   a file BOTH sides changed to the SAME content is invisible to two-dot
//                                    (the trees agree) even though this work really did change it — a
//                                    changed file the reviewer never sees. Same tree: 33 such files.
// The excluded class is COUNTED, never silently filtered: `base_moved=` on the <pr-context> header is the
// number of paths BASEREF changed since the fork that this work did not touch — the same row class --abi
// names head-moved (the OTHER line moved; this work did not author the difference). `anchor=` states which
// anchor was actually used, so an unrelated-history degrade (no merge-base ⇒ two-dot fallback) is legible
// rather than silent.

#include "model.h"
#include "graph.h"
#include "filter.h"      // isTestPath
#include "gitmine.h"     // shSingleQuote, cochangePartners, gitFileAuthors, FileOwnership
#include "quality.h"     // gitOneLine — the SAME one-line git primitive crossref/abicheck/mergescout resolve their merge-base with
#include "serialize.h"   // escapeXml
#include "Diagnostics.h" // DEGRADED_PATH_ALERT — the unrelated-history (no merge-base) degrade
#include "gitstamp.h"    // gitstamp::atAttr — the at="<sha>[+dirty]" root anchor
#include "graphlegend.h" // §H4 §3.4 / V4 MED-3: the shared counts_floor= marker + graph-count legend clauses
#include "testmap.h"     // §A9.5 / §P11.4: TestRunnerIndex / runAttr — the run= hint on a named test row

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// result of a --numstat-based diff mask build: the mask itself, whether git ran cleanly, and how many
// entries were dropped for being content-identical (mode-only flips, e.g. chmod 644→755) — see
// PrContextMask::skippedModeOnly below. A3-F10.
struct PrContextMask
{
    std::vector<char> mask;             // parallel to ing.files
    bool              ok = false;       // false ⇒ git failed, non-git root, or an unresolvable ref (see badRef)
    std::uint32_t     skippedModeOnly = 0;   // entries git reported changed but with 0/0 numstat lines (mode-only)

    // ── anchoring (r26 merge-base audit; see the ANCHORING section of this file's header comment) ────────
    std::string       baseSha;               // merge-base(BASEREF, HEAD) — the anchor actually diffed against.
                                             // Empty for the working-tree default AND for the unrelated-history
                                             // degrade, which `baseAnchored` tells apart.
    bool              baseRefGiven = false;  // true ⇒ the BASEREF form (vs the working-tree default) — the two
                                             // cases `baseAnchored == false` would otherwise conflate
    bool              baseAnchored = false;  // true ⇒ a merge-base was resolved and used (the BASEREF form's
                                             // normal path); false ⇒ working-tree default, or the two-dot fallback
    bool              refHasNoWork = false;  // §A9.2: BASEREF's tip IS the merge-base — the ref has no divergent
                                             // commits of its own, so every row below is HEAD's work. Carried so
                                             // the bundle can SAY so instead of leaving the reader to caption an
                                             // empty-looking ref as "the ref changed nothing".
    std::uint32_t     baseMoved    = 0;      // paths BASEREF changed since the fork that this work never touched —
                                             // the rows base-anchoring EXCLUDES. Counted, never silently filtered
                                             // (the class --abi names head-moved: the other line moved, not us).

    // ── refusal (P0.1 security + P2.8 honesty) ───────────────────────────────────────────────────────────
    bool              badRef = false;        // a BASEREF was given, the root HAS git history, and the ref does not
                                             // resolve to a commit. `ok` is false, but this is NOT the non-git
                                             // degrade: the caller must REFUSE with exit 1 and name the ref (the
                                             // same loud refusal every sibling ref-taking verb gives). Kept apart
                                             // from plain `ok=false` because a non-git root must still exit 0.
};

// Resolve the path column of a `git diff --numstat` row to the file's CURRENT (new) on-disk path. Two things
// must happen before it can suffix-match an ingested path (A4-F3 + A4-F13):
//   • A rename row renders as `pre{old => new}post` (common prefix/suffix factored out) or, with nothing in
//     common, the bare form `old => new`. Taken verbatim, that column matches no ingested file, so a
//     renamed+edited file — exactly the change a reviewer most needs — silently vanishes from --pr-context.
//     Resolve to the NEW path: brace form ⇒ prefix + new-mid + suffix; bare form ⇒ the text after " => ".
//   • git C-quotes a path containing a quote/backslash/control byte (even with core.quotepath=false), so
//     unquote first (gitUnquotePath, from gitmine.h) — otherwise such files drop too.
// Deterministic, pure. Non-rename rows pass through unchanged (after unquoting).
inline std::string resolveNumstatPath( std::string col )
{
    col = gitUnquotePath( col );
    const std::size_t arrow = col.find( " => " );
    if( arrow == std::string::npos ) return col;                     // not a rename row

    const std::size_t lb = col.rfind( '{', arrow );
    const std::size_t rb = col.find( '}', arrow );
    if( lb != std::string::npos && rb != std::string::npos && lb < arrow && rb > arrow )
        return col.substr( 0, lb ) + col.substr( arrow + 4, rb - ( arrow + 4 ) ) + col.substr( rb + 1 );   // pre{old => new}post
    return col.substr( arrow + 4 );                                 // bare "old => new" → new
}

// git-diff (working tree vs HEAD, or vs a named BASEREF) via `--numstat` rather than `--name-only`: numstat
// gives one line per changed path as "added<TAB>deleted<TAB>path", where a PURE mode flip (content
// identical, e.g. a chmod) reports "0\t0\tpath" — no content hunk at all. Binary files report "-\t-\tpath"
// (added/deleted are meaningless for them) and MUST still count as changed. So: skip only the 0/0 rows,
// keep everything else (including "-"/"-"). A3-F10: --name-only alone can't tell a mode flip from a real
// edit, which turned a 272-file chmod into a 272-file "evidence bundle" of pure noise.
// One such pass, reduced to its changed-path list. Split out (r26) so the base-moved probe below reuses
// this parser VERBATIM instead of growing a second copy of the same tab-splitting loop. `revArgs` is the
// already-shell-quoted revision tail handed to `git diff --numstat` ("HEAD", one sha, or "<sha> <ref>");
// `ok=false` means git failed outright (non-zero exit AND nothing parsed).
struct NumstatDiff
{
    std::vector<std::string> paths;              // one per changed path, rename-resolved to the NEW spelling
    bool                     ok = false;
    std::uint32_t            skippedModeOnly = 0;
};

// One parsed "<added>\t<deleted>\t<path>" row. An empty `path` with isModeOnly=false is a row carrying
// nothing (a blank line); an empty `path` with isModeOnly=true is the 0/0 content-identical case the caller
// must COUNT rather than drop.
struct NumstatRow
{
    std::string path;
    bool        isModeOnly = false;
};

// added/deleted are '-' for a binary file, which MUST still count as changed; an unparseable row degrades
// to "changed" (its raw text) rather than vanishing.
//
// §B13.2 — 0/0 is NOT synonymous with "mode-only". A PURE RENAME (100% similarity) is content-identical too,
// so git reports it with the same two zeros: `0\t0\tsrc/{util.h => renamed.h}`. Classed as mode-only, a
// whole pure-refactor / file-move PR reviewed as an EMPTY bundle — measured on a two-file fixture,
// `--pr-context` gave files="0" skipped_mode_only="2" with zero <file> rows at exit 0, while `--test-gate`
// on the identical tree gave changed="2" impacted="1" untested="1" and exit 4. The only signal a reviewer
// got was an attribute named after file MODES, whose legend example ("e.g. chmod") points away from renames.
// The path column is what separates the two: a rename/copy row carries the " => " marker (brace form or
// bare), a mode flip never does. So a 0/0 row WITH the marker is a changed file at its new spelling —
// resolved exactly like the renamed-and-edited row one line below, which was never in doubt — and only a 0/0
// row WITHOUT it is the content-identical flip that skipped_mode_only counts.
// (Residual, pre-existing and shared with resolveNumstatPath: a file whose own NAME contains " => " reads as
// a rename. Nothing in this parser can tell those apart, and the alternative — dropping the file silently —
// is the defect being fixed.)
inline NumstatRow numstatRowPath( std::string row )
{
    while( !row.empty() && ( row.back() == '\n' || row.back() == '\r' ) ) row.pop_back();
    if( row.empty() ) return {};

    const std::size_t t1 = row.find( '\t' );
    const std::size_t t2 = ( t1 == std::string::npos ) ? std::string::npos : row.find( '\t', t1 + 1 );
    if( t1 == std::string::npos || t2 == std::string::npos ) return NumstatRow{ std::move( row ), false };

    const std::string_view added( row.data(), t1 );
    const std::string_view deleted( row.data() + t1 + 1, t2 - t1 - 1 );
    std::string            pathCol = row.substr( t2 + 1 );
    if( added == "0" && deleted == "0" && pathCol.find( " => " ) == std::string::npos )
        return NumstatRow{ std::string{}, true };

    return NumstatRow{ resolveNumstatPath( std::move( pathCol ) ), false };
}

inline NumstatDiff numstatChangedPaths( const std::string& root, const std::string& revArgs )
{
    NumstatDiff out;

    // P0.1: the trailing `--` closes the argument list — every token before it is a REVISION (and every
    // revision this file builds is a rev-parse-resolved sha, see resolveDiffAnchor), so nothing downstream
    // can be re-read as an option or as an ambiguous pathspec. Belt to the resolver's braces; an empty
    // pathspec list after `--` means "all paths", so the diff itself is unchanged.
    const std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root ) + " diff --numstat "
                          + revArgs + " -- 2>/dev/null";

    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe ) return out;

    char line[ 4096 ];
    while( std::fgets( line, sizeof( line ), pipe ) )
    {
        auto [ path, isModeOnly ] = numstatRowPath( std::string( line ) );

        if( isModeOnly )         ++out.skippedModeOnly;
        else if( !path.empty() ) out.paths.push_back( std::move( path ) );
    }
    const int rc = pclose( pipe );
    if( rc != 0 && out.paths.empty() && out.skippedModeOnly == 0 ) return out;   // git failed outright
    out.ok = true;
    return out;
}

// Pick the revision this diff is ANCHORED at, and record which anchor was used (r26 merge-base audit — see
// this file's header §ANCHORING for the full reasoning and the measured cost of getting it wrong).
//   baseRef empty  ⇒ "HEAD": the working tree against its own parent. No divergence, no anchoring question.
//   baseRef given  ⇒ merge-base(baseRef, HEAD): what THIS work changed since it forked, not how the two
//                    trees happen to differ today.
// No merge-base (unrelated histories) ⇒ degrade to the two-dot diff against the ref's own RESOLVED tip
// rather than refuse; `baseAnchored` stays false so the emitted anchor= says which view the reader got.
//
// ── P0.1: the ref is RESOLVED before it is ever a git argument (arbitrary-file-overwrite) ────────────────
// The unrelated-history fallback used to hand the RAW user ref back as the revision token. shSingleQuote
// stops SHELL injection, but the token still arrives at git as its own argv entry — and `git diff` honors
// `--output=FILE`, which TRUNCATES and rewrites FILE. A ref beginning with `-` fails merge-base first,
// which is *exactly* what routed it into that fallback: `--pr-context=--output=/etc/x` clobbered a file
// outside the repo and exited 0. So: resolve through `rev-parse --verify ...^{commit}` FIRST (the same
// probe mergescout.h:resolveCommittish uses) and diff the resulting 40-hex sha, which can never begin
// with `-`. An unresolvable ref is a REFUSAL (`badRef`), never a fallback — the caller exits 1 (P2.8).
struct DiffAnchor
{
    std::string revArgs;               // the already-shell-quoted revision tail for `git diff --numstat`
    std::string baseSha;               // the resolved merge-base, or "" (default form / unrelated history)
    std::string refSha;                // BASEREF resolved to a commit sha — the ONLY spelling of the ref that
                                       // reaches a git argv (see the base-moved probe below)
    bool        baseRefGiven = false;
    bool        baseAnchored = false;
    bool        refHasNoWork = false;  // §A9.2: merge-base == the ref's own tip ⇒ the ref is an ancestor of HEAD
                                       // and has NO divergent work (what --merge-scout reports as changed="0")
    bool        badRef       = false;  // ref given, root has git history, ref does not resolve ⇒ refuse (exit 1)
    bool        gitUnusable  = false;  // no HEAD at all (non-git root / git unavailable) ⇒ the exit-0 degrade
};

// A git object name is 40 (sha-1) or 64 (sha-256) lowercase hex characters. Checked explicitly rather than
// assumed so "the revision token can never look like an option" is a property this file PROVES rather than
// inherits from git's output format — a non-hex answer degrades to a refusal, never to a raw-token diff.
inline bool isCommitSha( std::string_view s )
{
    if( s.size() != 40 && s.size() != 64 ) return false;
    for( const char c : s )
        if( !( ( c >= '0' && c <= '9' ) || ( c >= 'a' && c <= 'f' ) ) ) return false;
    return true;
}

// Resolve REF to a commit sha. `^{commit}` peels — so a blob/tree hash or a malformed ref answers "" — and
// mirrors mergescout.h:resolveCommittish verbatim rather than growing a second dialect of the same probe.
inline std::string resolveBaseRefSha( const std::string& root, std::string_view ref )
{
    const std::string sha = quality::gitOneLine( root, "rev-parse --verify --quiet "
                                                       + shSingleQuote( std::string( ref ) + "^{commit}" ) + " 2>/dev/null" );
    return isCommitSha( sha ) ? sha : std::string{};
}

inline DiffAnchor resolveDiffAnchor( const std::string& root, std::string_view baseRef )
{
    DiffAnchor out;
    if( baseRef.empty() ) { out.revArgs = "HEAD"; return out; }

    out.baseRefGiven = true;

    // no HEAD at all ⇒ not a git root (or git unavailable). NOT a bad ref: there is no ref to blame, and the
    // caller's contract for that case is the exit-0 explanatory degrade, not a refusal.
    const std::string headSha = quality::gitOneLine( root, "rev-parse --verify --quiet HEAD 2>/dev/null" );
    if( headSha.empty() ) { out.gitUnusable = true; return out; }

    // P0.1 + P2.8: an unresolvable ref REFUSES. It is never handed to `git diff` as a token.
    out.refSha = resolveBaseRefSha( root, baseRef );
    if( out.refSha.empty() )
    {
        DEGRADED_PATH_ALERT( "pr-context: the base ref does not resolve to a commit — refusing rather than handing the raw token to git" );
        out.badRef = true;
        return out;
    }

    const std::string base = quality::gitOneLine( root, "merge-base " + shSingleQuote( out.refSha )
                                                        + " " + shSingleQuote( headSha ) + " 2>/dev/null" );
    if( base.empty() )
    {
        DEGRADED_PATH_ALERT( "pr-context: no merge-base with the base ref (unrelated history?) — falling back to a two-dot diff against its tip" );
        out.revArgs = shSingleQuote( out.refSha );   // the RESOLVED sha, never the raw ref
        return out;
    }

    out.revArgs      = shSingleQuote( base );
    out.baseSha      = base;
    out.baseAnchored = true;
    out.refHasNoWork = ( base == out.refSha );   // §A9.2: the ref IS the fork point — no divergent commits of its own
    return out;
}

// §H6b — the changed-path → ingested-file join used to live HERE, privately, as an anchored pass plus a
// suffix fallback that marked EVERY match. That is the exact shape §H6 removed from gitmine.h, kept alive in
// a third copy because this file resolved its own paths. Both halves were wrong in opposite directions:
//   • the ANCHORED pass only fires when the crawl root IS the repo toplevel — it rebuilds git's spelling as
//     `<root>/<git path>` and nothing else — so running the verb from a SUBDIR fell through to the fallback;
//   • the FALLBACK marked every boundary-suffix match, so a changed root-level `util.cpp` marked every
//     `*/util.cpp` in the tree and the bundle spent a full evidence section on a file the diff never touched.
// And when the fallback found nothing the verb SAID something false. Measured, `src/util.h` edited, from
// `<repo>/src`: `--pr-context` → files="0" + "no changed files in the index (clean tree, or the diff touched
// only non-indexed files)" — while the same tree's already-fixed seam answered correctly from the same cwd
// (`--for` churn="2", `--owners` files="2"). The file IS indexed, as `./util.h`, and it DID change.
//
// So the join is DELETED rather than patched (wave 1's lesson: deleting the guess deletes the class).
// rw::markChangedFilesFromGitPaths derives the git-root→index-root offset once per root and binds each
// changed path to the ONE file whose own derived git spelling it is, or to nothing — which also makes this
// verb inherit gitmine.h's three honest-failure disclosures instead of failing silently. `root` is no longer
// a parameter of the join at all: the offset comes from the ingest, not from the string the user typed.

// `baseRef` empty ⇒ working-tree diff vs HEAD (the --pr-context default); non-empty ⇒ diff vs
// merge-base(baseRef, HEAD), NOT vs baseRef's tip (§ANCHORING). Returns {mask, ok, skippedModeOnly,
// baseSha, baseAnchored, baseMoved}; ok=false ⇒ git failed / bad ref (non-zero exit + no output).
// ok=true + empty mask = no changes.
inline PrContextMask gitDiffChangedMaskNumstat( const std::string& root, const IngestResult& ing,
                                                 std::string_view baseRef,
                                                 std::uint32_t onlyRoot = UINT32_MAX )   // multi-root §5: mark ONLY files of that root
{
    PrContextMask result;
    result.mask.assign( ing.files.size(), 0 );

    // this work's own changed set, anchored per resolveDiffAnchor
    const DiffAnchor anchor = resolveDiffAnchor( root, baseRef );
    result.baseSha      = anchor.baseSha;
    result.baseRefGiven = anchor.baseRefGiven;
    result.baseAnchored = anchor.baseAnchored;
    result.refHasNoWork = anchor.refHasNoWork;
    result.badRef       = anchor.badRef;

    // P0.1: an unresolvable ref never reaches `git diff` — and a root with no git history has nothing to
    // diff either. Both leave `ok` false; `badRef` is what tells the caller to REFUSE rather than degrade.
    if( anchor.badRef || anchor.gitUnusable ) return result;

    const NumstatDiff mine = numstatChangedPaths( root, anchor.revArgs );
    if( !mine.ok ) return result;

    const std::vector<std::string>& changed = mine.paths;
    result.skippedModeOnly = mine.skippedModeOnly;
    result.ok              = true;

    // the excluded class, counted not filtered: paths the BASE REF moved since the fork that we never opened.
    // One extra numstat pass (base..baseRef), negligible next to the ingest this bundle already paid for, and
    // it is the only thing that keeps the narrowing auditable instead of silent.
    if( result.baseAnchored )
    {
        // P0.1: the RESOLVED sha, not the raw ref — this probe builds a git argv exactly like the one above.
        const NumstatDiff moved = numstatChangedPaths( root, shSingleQuote( result.baseSha ) + " "
                                                             + shSingleQuote( anchor.refSha ) );
        for( const std::string& p : moved.paths )
            if( std::find( changed.begin(), changed.end(), p ) == changed.end() ) ++result.baseMoved;
    }

    markChangedFilesFromGitPaths( changed, ing, result.mask, onlyRoot );   // §H6b — the ONE join (gitmine.h)
    return result;
}

// R4 / RESEARCH_outputEconomy lever 4: the per-file DETAIL trim ladder for --pr-context under a token budget.
// The bundle's cost is entirely diff-size-driven and was unbounded (26.3K tokens on a 15-file diff; a 213-file
// diff is far worse). Under a budget the graceful move is NOT to drop changed files — a reviewer needs to know
// EVERY file that changed — but to degrade the DEPTH per file, deepest (most nested/expensive) detail first,
// while keeping the cheap structural facts (blast-radius / test / caller / co-change COUNTS + owner flags) for
// ALL files at every level. Each level is a strictly cheaper superset-of-facts of the one below; the emitter
// picks the LEAST-trimmed level whose est_tokens fits, and names what it dropped in truncated=.
//   • listCap fields at 0  ⇒ the container element is emitted with its count attrs but NO child rows.
//   • emitSymbolRows=false ⇒ <changed-symbols count="K"/> (self-closing) — the per-symbol caller anchor is gone.
// Level 0 reproduces the pre-budget output byte-for-byte (caps 20/40/12/12/5, symbol rows on), so a run with
// no budget is unchanged.
struct PrTrim
{
    int         impactCap;        // <impact> child <f> rows (0 = counts only)
    int         testCap;          // <tests> child <test> rows
    int         callerCap;        // per-symbol <caller> children (0 = the <s> row carries only its callers= count)
    bool        emitSymbolRows;   // false ⇒ <changed-symbols count=K/> with no <s> children at all
    int         cochangeCap;      // <cochange> child <partner> rows
    int         ownerCap;         // <owners> child <author> rows
    const char* dropped;          // honest, cumulative summary of what a consumer is NOT seeing at this level
};

inline constexpr PrTrim kPrTrims[] = {
    { 20, 40, 12, true,  12, 5, "none" },                                                        // L0 = pre-budget output (byte-identical)
    {  8, 12,  4, true,   4, 3, "list-caps-reduced" },                                            // L1
    {  4,  6,  0, true,   2, 2, "caller-lists+list-caps-reduced" },                               // L2
    {  2,  3,  0, false,  0, 0, "per-symbol-rows+cochange-list+owner-list-dropped" },             // L3
    {  0,  0,  0, false,  0, 0, "all-nested-lists-dropped(structural-counts-only)" },             // L4 = floor (counts survive for every file)
};

// Rough header/comment/wrapper overhead (bytes) folded into the est_tokens estimate so the budget decision
// accounts for the non-per-file envelope, not just the <file> body.
inline constexpr std::size_t kPrHeaderOverheadBytes = 560;

// The <pr-context> header's anchoring attributes (r26), or "" for the working-tree default — which has no
// anchoring question at all and therefore renders a byte-identical header to the pre-r26 output. Two states
// otherwise: anchor="merge-base" (the normal BASEREF path, with the anchor sha and the excluded base-moved
// count) and anchor="ref-tip-two-dot" (no merge-base at all — unrelated history — so the reader is told
// which view they actually got instead of being left to assume).
template< typename Escaper >
inline std::string prAnchorAttr( const PrContextMask& anchor, const Escaper& ex )
{
    if( anchor.baseAnchored )
        return std::string( " anchor=\"merge-base\" base_sha=\"" ) + ex( std::string_view( anchor.baseSha ).substr( 0, 9 ) )
             + "\" base_moved=\"" + std::to_string( anchor.baseMoved ) + "\"";
    if( anchor.baseRefGiven ) return std::string( " anchor=\"ref-tip-two-dot\" base_moved=\"0\"" );
    return {};
}

// §A9.2 — WHICH SIDE this bundle reviews, stated on the root, always. The BASEREF form's rows are HEAD's
// work since the fork; when the ref carries no divergent commits of its own (its tip IS the merge base —
// the changed="0" --merge-scout reports for it) that is exactly the moment a reader captions the bundle
// backwards, as "the ref's diff". direction= names the side unconditionally so the caption never has to be
// inferred from the presence of rows, and the three values map 1:1 to the three anchors the verb has:
//   worktree-since-head   the working-tree default (no BASEREF) — uncommitted work vs HEAD
//   head-since-fork       the normal BASEREF form — merge-base anchored (see prAnchorAttr's anchor=)
//   head-since-ref-tip    the unrelated-history degrade — no merge base exists, so the ref's tip is the anchor
// The protected anchor=/base_moved= disclosures are untouched: this answers a different question (which
// SIDE), and anchor= answers WHERE the diff is anchored.
inline std::string prDirectionAttr( const PrContextMask& anchor )
{
    if( !anchor.baseRefGiven )  return " direction=\"worktree-since-head\"";   // uncommitted work vs HEAD
    if( !anchor.baseAnchored )  return " direction=\"head-since-ref-tip\"";    // unrelated history: no merge base exists
    return " direction=\"head-since-fork\"";
}

// §B3: the shown=/capped= pair every capped nested list in <file> emits (impact <f>, per-symbol <caller>,
// cochange <partner>, tests <test>, owners <author>) — S = min(total, cap), capped = S < total. cap<=0 (a
// trim level that drops the list entirely, e.g. L2's callerCap=0) naturally yields shown=0, capped=(total
// > 0) — the SAME formula serves both "list present, maybe truncated" and "list dropped entirely", so one
// function replaces five duplicated ternary pairs at the five call sites below.
struct PrShownCap { std::size_t shown; unsigned capped; };
inline PrShownCap prShownCap( std::size_t total, int cap ) noexcept
{
    const std::size_t shown = cap > 0 ? std::min( total, std::size_t( cap ) ) : 0;
    return { shown, shown < total ? 1u : 0u };
}

// The one row that fires exactly when the ref's tip == the merge base. Emitted as an element (not another
// root attribute) because it is a REMARK about the whole bundle, and because the reader it is written for
// is the one who stopped reading at the first screen.
// ── the --max-tokens trim ladder, as its own decision ────────────────────────────────────────────────
// "Pick the LEAST-trimmed level whose estimated tokens fit" is one named choice with one answer, and it was
// spelled inline inside a 274-line emitter. Render each candidate level to a memstream, estimate tokens from
// its byte size at the densest-language rate (kMinBytesPerToken, the same conservative constant --max-tokens
// uses, so the estimate is a real ceiling), and stop at the first fit. If even the FLOOR exceeds the budget,
// keep the floor (files are never dropped) and mark it — an honest "this is as small as it gets and it is
// still over". `truncated` is computed here too, because it is a statement ABOUT the chosen level: "none"
// only when nothing was trimmed, else the cumulative drop summary plus the floor-exceeded note.
struct PrTrimRender
{
    std::string body;
    std::size_t estTokens   = 0;
    std::size_t level       = 0;
    std::string truncated   = "none";
};

template< typename EmitFn >
inline PrTrimRender pickPrTrimLevel( const EmitFn& emitFiles, std::size_t budgetTokens )
{
    constexpr std::size_t nLevels = sizeof( kPrTrims ) / sizeof( kPrTrims[0] );
    PrTrimRender out;
    bool         isOverFloor = false;
    for( std::size_t li = 0; li < nLevels; ++li )
    {
        char*       buf = nullptr;
        std::size_t sz  = 0;
        std::string rendered;
        if( std::FILE* ms = open_memstream( &buf, &sz ) )
        {
            emitFiles( ms, kPrTrims[li] );
            std::fflush( ms );
            std::fclose( ms );
            if( buf ) rendered.assign( buf, sz );
        }
        std::free( buf );
        const std::size_t est = std::size_t( std::ceil( double( rendered.size() + kPrHeaderOverheadBytes ) / kMinBytesPerToken ) );
        out.level     = li;
        out.estTokens = est;
        out.body      = std::move( rendered );
        if( est <= budgetTokens ) break;
        if( li + 1 == nLevels ) isOverFloor = true;   // even the floor render is over budget
    }
    if( out.level > 0 ) out.truncated = kPrTrims[ out.level ].dropped;
    if( isOverFloor )   out.truncated += ";budget-floor-exceeded";
    return out;
}

// The budgeted root's site-specific attribute tail (the plain and empty forms build theirs inline — they
// are two attributes each).
inline std::string prBudgetTail( std::size_t changedFiles, std::uint32_t skippedModeOnly, std::size_t budgetTokens,
                                 const PrTrimRender& chosen, const std::string& truncatedEscaped )
{
    char tail[ 256 ];
    std::snprintf( tail, sizeof( tail ), " files=\"%zu\" skipped_mode_only=\"%u\" budget_tokens=\"%zu\" est_tokens=\"%zu\" trim_level=\"%zu\" truncated=\"%s\"",
                   changedFiles, skippedModeOnly, budgetTokens, chosen.estTokens, chosen.level, truncatedEscaped.c_str() );
    return tail;
}

// Open the <pr-context> root: the attributes EVERY form shares, this site's own tail, and the one remark row
// that may follow the opening tag. Three call sites (empty diff / plain / budgeted) which must not drift on
// which disclosures they carry — direction= and the no-ref-work row are exactly the kind of attribute that
// otherwise lands on two of three. G4: attribute text may not contain a double hyphen, so the note names
// the sibling verbs without their leading dashes.
inline void writePrRootOpen( std::FILE* out, const std::string& sharedAttrs, const std::string& tailAttrs,
                             const PrContextMask& anchor, const std::string& baseLabelEscaped )
{
    // §H4 §3.4 / V4 MED-3: the marker rides here, on the ONE root emitter all three forms (empty diff /
    // plain / budgeted) share — which is exactly the drift this helper exists to prevent, and the reason it
    // is appended LAST, past every caller-supplied tail attribute (same placement rule as gitstamp::atAttr).
    std::fprintf( out, "<pr-context%s%s%s>", sharedAttrs.c_str(), tailAttrs.c_str(), rw::kGraphCountFloorAttrXml );
    if( !anchor.refHasNoWork ) return;
    std::fprintf( out, "<no-ref-work note=\"%s tip == merge-base, so that ref has no divergent work of its own; this "
                       "bundle is HEAD's work since the fork. For the ref's OWN diff see merge-scout or stray-content\"/>",
                  baseLabelEscaped.c_str() );
}

// The reader-facing explanation of the anchoring attributes, emitted only when there ARE any (so the
// working-tree default's document is unchanged). G4: an XML comment may not contain a double hyphen, so
// this text names flags and attribute values WITHOUT their leading dashes — the same constraint crossref.h's
// own comments call out. Keep it that way when editing.
inline void writeAnchorNote( std::FILE* out, const std::string& anchorAttr )
{
    if( anchorAttr.empty() ) return;

    std::fprintf( out, "<!-- anchoring: a base ref was given, so this diff is anchored at merge base(BASEREF, HEAD), "
                       "NOT at the ref's tip — the bundle is what THIS work changed since it forked, not how the two "
                       "trees differ today. base_moved= counts paths the BASE REF moved since the fork that this work "
                       "never touched (excluded here, and the same row class the abi verb names head moved: the other "
                       "line moved, we did not author it). anchor=\"ref tip two dot\" instead means there was no merge "
                       "base at all (unrelated history) and the two dot view is what you are reading. -->" );
}

// §P11.7 — the FLAGSHIP review bundle led with its least reviewable file. Sections were emitted in path
// order, so on ripwire's own tree `CHANGELOG.md` came first and spent the reader's whole first screen on 31
// markdown headings rendered as callers="0" symbol rows, with the files something actually depends on below
// the fold. Re-key on the blast radius: transitive-dependent count DESC, path ASC to break ties, so the
// order is still a total, deterministic function of the corpus. Nothing is added or dropped — the same
// <file> sections in a different sequence, which is what a reviewer's scan order is for.
//
// The ordering is decided HERE, once, and not inside the per-file emitter: the budget path re-runs that
// emitter at several trim levels to measure, so deciding there would let a --max-tokens value reorder the
// bundle. The extra transitiveCallers pass is the deliberate price of that.
inline void orderChangedFilesByImpact( std::vector<std::uint32_t>& changed, const IngestResult& ing, const Graph& g,
                                       const std::vector<std::vector<NodeId>>& symsByFile )
{
    std::vector<std::size_t> dependentsByFile( ing.files.size(), 0 );
    for( std::uint32_t f : changed ) dependentsByFile[f] = transitiveCallers( g, symsByFile[f] ).size();
    orderIdsByKeyDescPathAsc( changed, dependentsByFile, ing.files );
}

// §P11.7 — a doc file's HEADINGS are not review evidence. A changed markdown file emitted one
// <s t="sec" callers="0"/> row per heading (31 of them for CHANGELOG.md), which is a table of contents
// wearing a symbol row's clothes: a section has no callers by construction, so every one of those rows
// carried the same zero. They collapse into a single sections= count on the enclosing element — the fact a
// reviewer can use ("this doc changed, N sections in it") without the rows that cannot say anything more.
//
// Returns { the rendered ATTRIBUTE, the symbols that still get a ROW }. The attribute is empty when the file
// has no section symbols at all, which is what keeps every code file's output byte-identical to before, and
// the row list is then the caller's whole list unchanged. count= on the element is untouched and still counts
// EVERY symbol, so count minus sections is exactly the number of rows that follow.
//
// Returning the filtered list rather than leaving the caller to skip sections mid-loop is deliberate: that
// skip would be an `if` four levels deep inside the per-file emitter lambda, and the split reads as what it
// is — this file's symbols are two different kinds of thing.
inline std::pair<std::string, std::vector<NodeId>> splitDocSections( const IngestResult& ing, const std::vector<NodeId>& fileSyms )
{
    std::size_t         sectionCount = 0;
    std::vector<NodeId> rowSyms;
    rowSyms.reserve( fileSyms.size() );
    for( NodeId s : fileSyms )
    {
        if( ing.symbols[s].kind == SymKind::Section ) ++sectionCount;
        else                                          rowSyms.push_back( s );
    }
    if( sectionCount == 0 ) return { std::string(), std::move( rowSyms ) };
    return { std::string( " sections=\"" ) + std::to_string( sectionCount ) + "\"", std::move( rowSyms ) };
}

// Emit the full --pr-context bundle. `changedFile` is the diff mask (parallel to ing.files). `baseLabel`
// is a human label for the diff base ("working-tree" or the ref name), for the header attribute only.
// `skippedModeOnly` is the count of content-identical entries (mode-only flips) the mask builder dropped
// (A3-F10) — surfaced as an attribute so that information isn't silently lost even though those files
// never reach the per-file loop below. `budgetTokens` (0 = UNLIMITED, the default → byte-identical to the
// pre-budget output) caps the emitted est_tokens: the bundle degrades DEPTH-first per the trim ladder above,
// keeping every changed file present structurally. Deterministic: files emitted in path order; per-file
// symbols in id order; every list independently sorted; the chosen trim level is a pure function of the
// rendered byte size. Returns 0 always (a review evidence bundle never fails the pipeline).
// Multi-root (DESIGN_multiRoot.md §5/§7): `onlyRoot` (!= UINT32_MAX) isolates the git signals (co-change, owners)
// to that one repo's files — the changed-file mask is already per-root (built with the same onlyRoot), and the
// blast radius/tests/callers deliberately run on the WHOLE merged graph so cross-root evidence edges appear.
// `rootLabel` (non-empty) adds a `root="..."` attribute to the <pr-context> header so a per-root section in a
// <pr-context-workspace> wrapper self-identifies. Both default to the single-root sentinels, so a single-root
// call is BYTE-IDENTICAL to before (rootLabel empty ⇒ no attribute; onlyRoot=UINT32_MAX ⇒ mine all files).
// `anchor` (r26): the mask builder's PrContextMask, forwarded so the header can state which anchor the diff
// actually used and how many base-moved paths that excluded. A default-constructed value (baseAnchored
// false, baseMoved 0) means the working-tree default and emits NO extra attribute — so an unchanged caller
// still renders byte-identically.
inline int writePrContext( std::FILE* out, const std::string& root, const IngestResult& ing, const Graph& g,
                           const std::vector<char>& changedFile, std::string_view baseLabel,
                           std::uint32_t skippedModeOnly = 0, std::size_t budgetTokens = 0,
                           std::uint32_t onlyRoot = UINT32_MAX, std::string_view rootLabel = std::string_view(),
                           const PrContextMask& anchor = PrContextMask{} )
{
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    const std::uint32_t N = std::uint32_t( ing.symbols.size() );

    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    // multi-root §7: ` root="<label>"` on the header, or "" for a single-root run (⇒ byte-identical header).
    const std::string rootAttr = rootLabel.empty() ? std::string() : ( std::string( " root=\"" ) + ex( rootLabel ) + "\"" );
    // r26-stamp Task A: anchor these callers/blast-radius/tests numbers to the commit (+dirty state) they were
    // computed against — "" (omitted) on a non-git root, never a placeholder.
    const std::string atAttrStr = gitstamp::atAttr( root );

    // r26 anchoring attributes — emitted ONLY for the BASEREF form (the working-tree default has no anchoring
    // question, and stays byte-identical). anchor="merge-base" is the normal path; anchor="ref-tip-two-dot" is
    // the unrelated-history degrade, named so a reader is never left guessing which view they got.
    // §A9.2: direction= says which SIDE the bundle reviews; every root form carries the same shared prefix.
    const std::string escBase     = ex( baseLabel );
    const std::string anchorAttr  = prAnchorAttr( anchor, ex );
    const std::string sharedAttrs = " base=\"" + escBase + "\"" + rootAttr + anchorAttr + prDirectionAttr( anchor );

    // changed files, in path order (deterministic). Only files with ≥1 indexed symbol carry analysis;
    // a changed file with no indexed symbols still gets a section (so the reviewer sees it changed).
    std::vector<std::uint32_t> changed;
    for( std::uint32_t f = 0; f < F; ++f ) if( changedFile[f] ) changed.push_back( f );
    std::sort( changed.begin(), changed.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );

    std::fprintf( out, "<!-- ripwire pr-context: no-LLM review-evidence bundle per changed file — defined symbols, their callers, blast radius (transitive dependents), affected tests, co-change partners not in the diff, and owners. "
                 "base=%s. skipped_mode_only=diffs that changed a file's MODE and nothing else (e.g. chmod) excluded from the changed set; a pure RENAME is content-identical too but is NOT excluded — it is a changed file, listed at its new path. files= means two different things by DEPTH here and is deliberately not renamed (15 consumers read the root one): "
                 "on the ROOT it is the CHANGED file count; on each <impact/> child it is the distinct files dependents= reaches (changed + non-changed), so dependents=\"0\" implies files=\"0\" and vice versa — never an "
                 "impossible-looking dependents>0/files=0. files_other= on the same <impact/> is the non-changed subset (a changed file's dependents inside OTHER changed files have no <f> row of their own — they are already shown "
                 "as their own <file> section); it is NOT the <f> row count — see the row-cap sentence below. Files are ordered by BLAST RADIUS (transitive dependents descending, path breaking ties), not alphabetically. "
                 "sections= on changed-symbols counts a doc file's headings, collapsed into that number instead of one callers-zero row each; count= still counts every INDEXED symbol, sections included, so count minus sections is the number of rows that follow. "
                 "Every nested list below is a TOP-N subset of its element's own total, fixed per element (impact <f> at 20, per-symbol <caller> at 12, cochange <partner> at 12, tests <test> at 40, owners <author> at 5 — the L0 defaults; "
                 "max-tokens only lowers these further via the trim ladder, nothing raises them past L0): each capped element carries its own shown=/capped= pair so the cut is never silent — for the untrimmed list use impact=SYM/callers=SYM "
                 "(blast radius/callers), affected=FILE or situ (tests), cochange (partners), or owners (authors) instead. direction= names which SIDE this bundle reviews (worktree-since-head, head-since-fork, head-since-ref-tip); "
                 "a no-ref-work row says the base ref's tip IS the merge base, i.e. it carries no divergent work of its own. deterministic. "
                 // §H4 §3.4 / V4 MED-3: the SEVENTH graph-count surface. Every per-symbol callers= here is read
                 // from the in-edge CSR --callers reads, and <impact dependents=> is the same transitive reach
                 // --impact reports, so the same floor applies to hundreds of attributes in this one document.
                 // The shared constants, never a pr-context wording — that is the §B4 echo-site rule.
                 "%s-->", escBase.c_str(), rw::graphCountDisclosure().c_str() );

    writeAnchorNote( out, anchorAttr );

    if( changed.empty() )
    {
        writePrRootOpen( out, sharedAttrs, " files=\"0\" skipped_mode_only=\"" + std::to_string( skippedModeOnly ) + "\"" + atAttrStr, anchor, escBase );
        std::fprintf( out, "<!-- no changed files in the index (clean tree, or the diff touched only non-indexed files) -->" );
        std::fprintf( out, "</pr-context>" );
        return 0;
    }

    // in-edge CSR row offsets/columns = 1-hop callers (same source --callers reads).
    const auto* inRo = g.inEdges.rowOffsets();
    const auto* inCi = g.inEdges.colIndices();

    // A4-P10: mine the co-change file-sets ONCE for the whole bundle (was one `git log` popen PER changed
    // file — unbounded storm). Deterministic for a fixed HEAD, so every per-file probe below is identical.
    // Mined ONCE here even when the budget forces several render passes below (each pass is pure re-emission).
    const auto coSets = gitCommitFileSets( root, ing, "18 months ago", 30, nullptr, onlyRoot );

    // A4-P?: mine file OWNERSHIP ONCE too (was gitFileAuthors(root, ing, f) — one `git log` popen PER changed
    // file, the residual author-storm: a 213-file diff spawned 213 subprocesses). The whole-repo pass mines
    // every file's owners in ONE `git log --name-only`; each per-file lookup below (ownershipForFile) is a
    // pure binary search into it, byte-identical to the old single-file query per file.
    const auto allOwners = gitFileAuthors( root, ing, UINT32_MAX, 182.5, onlyRoot );

    // §A9.5 / §P11.4: run= on the named test rows, from the SAME index --affected/--situ/--test-gate read.
    const TestRunnerIndex prRunners( ing );   // built once, like coSets/allOwners — the bundle re-renders

    // One-time file→defined-symbols index (in id order == file/line order), so each changed file reads its
    // symbols in O(1) instead of re-scanning all N symbols (A4-P10). Buckets fill in ascending id order.
    std::vector<std::vector<NodeId>> symsByFile( F );
    for( NodeId i = 0; i < N; ++i ) symsByFile[ ing.symbols[i].fileId ].push_back( i );

    // §P11.7: files lead by BLAST RADIUS, not by path — see orderChangedFilesByImpact above.
    orderChangedFilesByImpact( changed, ing, g, symsByFile );

    // The per-file body emitter, parameterized by a trim level so the budget path can render it at several
    // depths into a memstream to measure, then re-render the chosen one to `out`. At the deepest trim it is
    // still one <file> element PER changed file (counts intact) — files are never dropped, only detail is.
    const auto emitFiles = [ & ]( std::FILE* o, const PrTrim& trim )
    {
        for( std::uint32_t f : changed )
        {
            // this file's defined symbols, in id order (== file/line order by the ingest sort).
            const std::vector<NodeId>& fileSyms = symsByFile[f];

            std::fprintf( o, "<file p=\"%s\" symbols=\"%zu\">", ex( ing.files[f] ).c_str(), fileSyms.size() );

            // (1) blast radius: transitive dependents of ALL this file's symbols. Reuse transitiveCallers.
            const std::vector<NodeId>  reach = transitiveCallers( g, fileSyms );

            // (2) affected test files among the blast radius (the --affected logic), path-sorted.
            std::vector<char>          fseen( F, 0 );
            std::vector<std::uint32_t> testFiles;
            for( NodeId n : reach ) { const std::uint32_t tf = ing.symbols[n].fileId; if( !fseen[tf] && isTestPath( ing.files[tf] ) ) { fseen[tf] = 1; testFiles.push_back( tf ); } }
            std::sort( testFiles.begin(), testFiles.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );

            // (3) blast-radius files (non-changed), ranked by # dependent symbols then path — the "what this
            //     change reaches" summary a reviewer scans first. Count kept for ALL levels; rows capped by trim.
            //
            // §P10.4: `dependents=` (reach.size()) counts every dependent SYMBOL regardless of which file it
            // lives in, but the old `files=` here counted only non-changed files — a changed file whose sole
            // dependents are OTHER changed files (common: two files in the same diff calling each other)
            // rendered the impossible-looking `dependents="1" files="0"`. `files=` is now the TOTAL distinct
            // files reached (changed + non-changed, i.e. every file `reach` touches); `files_other=` is the
            // non-changed subset — so dependents > 0 now implies files > 0. §B3: `files_other=` is NOT the
            // <f> row count (the <f> rows below are capped at trim.impactCap, 20 at L0); the ACTUAL row count
            // is disclosed exactly via the <impact>'s own shown=/capped= pair, which this claimed for free
            // and did not emit until §B3 added it — do not let this comment drift back to claiming
            // files_other= itself is the row count.
            std::vector<char>          reachFileSeen( F, 0 );
            std::vector<std::uint32_t> fileReachers( F, 0 );
            for( NodeId n : reach )
            {
                const std::uint32_t rf = ing.symbols[n].fileId;
                reachFileSeen[rf] = 1;
                if( !changedFile[rf] ) ++fileReachers[rf];
            }
            std::size_t                totalReachFiles = 0;
            for( std::uint32_t rf = 0; rf < F; ++rf ) if( reachFileSeen[rf] ) ++totalReachFiles;
            std::vector<std::uint32_t> radiusFiles;
            for( std::uint32_t rf = 0; rf < F; ++rf ) if( fileReachers[rf] ) radiusFiles.push_back( rf );
            std::sort( radiusFiles.begin(), radiusFiles.end(), [ & ]( std::uint32_t a, std::uint32_t b )
                       { return fileReachers[a] != fileReachers[b] ? fileReachers[a] > fileReachers[b] : ing.files[a] < ing.files[b]; } );

            // §B3: <f> is a TOP-N subset of files_other= (see prShownCap above) — no longer a silent cap.
            const PrShownCap fSc = prShownCap( radiusFiles.size(), trim.impactCap );
            if( trim.impactCap > 0 )
            {
                std::fprintf( o, "<impact dependents=\"%zu\" files=\"%zu\" files_other=\"%zu\" shown=\"%zu\" capped=\"%u\">",
                             reach.size(), totalReachFiles, radiusFiles.size(), fSc.shown, fSc.capped );
                for( std::size_t i = 0; i < fSc.shown; ++i )
                    std::fprintf( o, "<f p=\"%s\" deps=\"%u\"/>", ex( ing.files[ radiusFiles[i] ] ).c_str(), fileReachers[ radiusFiles[i] ] );
                std::fprintf( o, "</impact>" );
            }
            else
                std::fprintf( o, "<impact dependents=\"%zu\" files=\"%zu\" files_other=\"%zu\" shown=\"%zu\" capped=\"%u\"/>",
                             reach.size(), totalReachFiles, radiusFiles.size(), fSc.shown, fSc.capped );

            // (4) affected tests to run. §B3: same shown=/capped= disclosure on <tests>' count=.
            const PrShownCap tSc = prShownCap( testFiles.size(), trim.testCap );
            if( trim.testCap > 0 )
            {
                std::fprintf( o, "<tests count=\"%zu\" shown=\"%zu\" capped=\"%u\">", testFiles.size(), tSc.shown, tSc.capped );
                for( std::size_t i = 0; i < tSc.shown; ++i )
                    std::fprintf( o, "<test p=\"%s\"%s/>", ex( ing.files[ testFiles[i] ] ).c_str(), runAttr( prRunners, testFiles[i], ex ).c_str() );   // §A9.5
                std::fprintf( o, "</tests>" );
            }
            else
                std::fprintf( o, "<tests count=\"%zu\" shown=\"%zu\" capped=\"%u\"/>", testFiles.size(), tSc.shown, tSc.capped );

            // (5) per-symbol callers (1-hop in-edges) — the review anchor "who breaks if this symbol changes".
            //     Emit each changed symbol with its direct callers, in id order; cap callers per symbol. At the
            //     deepest trims the per-symbol rows themselves are dropped (the count on <changed-symbols> stays).
            // §P11.7: a doc file's headings become one sections= count — see splitDocSections above.
            const auto [ sectionsAttr, rowSyms ] = splitDocSections( ing, fileSyms );

            if( trim.emitSymbolRows )
            {
                std::fprintf( o, "<changed-symbols count=\"%zu\"%s>", fileSyms.size(), sectionsAttr.c_str() );
                for( NodeId s : rowSyms )
                {
                    const Symbol& sy = ing.symbols[s];
                    std::vector<NodeId> callers;
                    for( std::uint32_t k = inRo[s]; k < inRo[s + 1]; ++k )
                    { const NodeId c = inCi[k]; if( c < N ) callers.push_back( c ); }
                    std::sort( callers.begin(), callers.end() );
                    callers.erase( std::unique( callers.begin(), callers.end() ), callers.end() );
                    std::sort( callers.begin(), callers.end(), [ & ]( NodeId a, NodeId b )
                               { const Symbol& sa = ing.symbols[a]; const Symbol& sb = ing.symbols[b];
                                 if( sa.fileId != sb.fileId ) return ing.files[sa.fileId] < ing.files[sb.fileId];
                                 return sa.line != sb.line ? sa.line < sb.line : sa.name < sb.name; } );
                    // §B3: <caller> is a TOP-N subset of callers= — same shown=/capped= disclosure.
                    const PrShownCap cSc = prShownCap( callers.size(), trim.callerCap );
                    if( trim.callerCap > 0 )
                    {
                        std::fprintf( o, "<s t=\"%s\" n=\"%s\" p=\"%s:%u\" callers=\"%zu\" shown=\"%zu\" capped=\"%u\">",
                                     symTag( sy.kind ), ex( sy.name ).c_str(), ex( ing.files[ sy.fileId ] ).c_str(), sy.line, callers.size(), cSc.shown, cSc.capped );
                        for( std::size_t i = 0; i < cSc.shown; ++i )
                        {
                            const Symbol& cs = ing.symbols[ callers[i] ];
                            std::fprintf( o, "<caller t=\"%s\" n=\"%s\" p=\"%s:%u\"/>", symTag( cs.kind ), ex( cs.name ).c_str(), ex( ing.files[ cs.fileId ] ).c_str(), cs.line );
                        }
                        std::fprintf( o, "</s>" );
                    }
                    else   // keep the row + its callers COUNT (the cheap structural fact), drop the caller list
                        std::fprintf( o, "<s t=\"%s\" n=\"%s\" p=\"%s:%u\" callers=\"%zu\" shown=\"%zu\" capped=\"%u\"/>",
                                     symTag( sy.kind ), ex( sy.name ).c_str(), ex( ing.files[ sy.fileId ] ).c_str(), sy.line, callers.size(), cSc.shown, cSc.capped );
                }
                std::fprintf( o, "</changed-symbols>" );
            }
            else
                std::fprintf( o, "<changed-symbols count=\"%zu\"%s/>", fileSyms.size(), sectionsAttr.c_str() );

            // (6) co-change partners NOT in the diff (gitmine). Degrades to an empty list without git. A4-P10:
            // answered from the once-mined `coSets` (no per-file `git log` popen).
            std::uint32_t                commits = 0;
            const std::vector<CoPartner> partners = cochangePartners( ing, ing.files[f], commits, coSets );
            std::vector<const CoPartner*> outside;
            for( const CoPartner& p : partners ) if( !changedFile[ p.fileId ] ) outside.push_back( &p );
            // cochangePartners already returns deg-desc, path-asc order → keep it.
            // §B3: <partner> is a TOP-N subset of partners= — same shown=/capped= disclosure.
            const PrShownCap pSc = prShownCap( outside.size(), trim.cochangeCap );
            if( trim.cochangeCap > 0 )
            {
                std::fprintf( o, "<cochange commits=\"%u\" partners=\"%zu\" shown=\"%zu\" capped=\"%u\">", commits, outside.size(), pSc.shown, pSc.capped );
                for( std::size_t i = 0; i < pSc.shown; ++i )
                    std::fprintf( o, "<partner p=\"%s\" deg=\"%.2f\"%s/>", ex( ing.files[ outside[i]->fileId ] ).c_str(),
                                 outside[i]->deg, coPairAttr( *outside[i] ) );   // §A9.3: surprising= or dep_capable="0"
                std::fprintf( o, "</cochange>" );
            }
            else
                std::fprintf( o, "<cochange commits=\"%u\" partners=\"%zu\" shown=\"%zu\" capped=\"%u\"/>", commits, outside.size(), pSc.shown, pSc.capped );

            // (7) owners of this file (gitmine, recency-weighted). A4-P?: answered from the once-mined
            //     `allOwners` (no per-file `git log` popen) — ownershipForFile is a pure binary search,
            //     byte-identical to the old single-file gitFileAuthors(root, ing, f). Empty without git.
            const FileOwnership* ow = ownershipForFile( allOwners, f );
            // §B3: <author> is a TOP-N subset of authors= — same shown=/capped= disclosure.
            if( ow && trim.ownerCap > 0 )
            {
                const PrShownCap aSc = prShownCap( ow->authors.size(), trim.ownerCap );
                std::fprintf( o, "<owners authors=\"%u\" bf=\"%d\" shown=\"%zu\" capped=\"%u\">", ow->uniqueAuthors, ow->busFactor ? 1 : 0, aSc.shown, aSc.capped );
                for( std::size_t i = 0; i < aSc.shown; ++i )
                    std::fprintf( o, "<author email=\"%s\" share=\"%.2f\"/>", ex( ow->authors[i].email ).c_str(), ow->authors[i].share );
                std::fprintf( o, "</owners>" );
            }
            else if( ow )   // trimmed: keep the author COUNT + bus-factor flag (cheap structural facts), drop the list
                std::fprintf( o, "<owners authors=\"%u\" bf=\"%d\" shown=\"0\" capped=\"%u\"/>", ow->uniqueAuthors, ow->busFactor ? 1 : 0, ow->authors.empty() ? 0u : 1u );
            else
                std::fprintf( o, "<owners authors=\"0\" bf=\"0\"/>" );   // no git ownership data at all — not a capped listing, nothing to disclose

            std::fprintf( o, "</file>" );
        }
    };

    // NO budget (the default): emit at level 0 (byte-identical to the pre-budget output) with no est_tokens/
    // truncated attributes — every existing consumer and gate is unaffected.
    if( budgetTokens == 0 )
    {
        writePrRootOpen( out, sharedAttrs, " files=\"" + std::to_string( changed.size() ) + "\" skipped_mode_only=\"" + std::to_string( skippedModeOnly ) + "\"" + atAttrStr, anchor, escBase );
        emitFiles( out, kPrTrims[0] );
        std::fprintf( out, "</pr-context>" );
        return 0;
    }

    // BUDGETED (--max-tokens) — see pickPrTrimLevel: render each candidate level, keep the least-trimmed fit.
    const PrTrimRender chosen = pickPrTrimLevel( emitFiles, budgetTokens );
    writePrRootOpen( out, sharedAttrs, prBudgetTail( changed.size(), skippedModeOnly, budgetTokens, chosen, ex( chosen.truncated ) ) + atAttrStr, anchor, escBase );
    std::fwrite( chosen.body.data(), 1, chosen.body.size(), out );
    std::fprintf( out, "</pr-context>" );
    return 0;
}

}   // namespace rw
