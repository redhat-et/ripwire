#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings
#include "gitcmd.h"         // rw::gitCmd — every git child starts with --no-optional-locks -c core.fsmonitor=false


// crossref.h — the CROSS-BRANCH CONTENT INDEX: --whereis=SYM and --stray-content.
// Evidence: a completed, soak-verified canyon fix sat UNMERGED on 1 of
// 30 branches for two days while a ledger claim said "ported" — `git cherry` answers commit ANCESTRY, and
// every other ripwire verb indexes ONE worktree, so nothing could answer "where does this CONTENT live?".
//
// SCOPE, once, for both verbs (§B12.2): "every ref" here has always meant `refs/heads` — every LOCAL branch,
// worktree branches included — and never `refs/remotes/*`; see enumerateRefs for why (they mirror the local
// ones in the usual checkout and would double every row). That is a real limit, not a detail: on a FRESH
// CLONE, the standard CI/agent shape, the work is all on `refs/remotes/origin/*` and only the checked-out
// branch has a local head, so both verbs cover ~nothing. Only `--help` used to say "local"; both payload
// legends now carry the clause, with refs_scanned=/refs= named as the number that shows it.
//
// The two questions:
//   --whereis=SYM      — every local ref whose tree DEFINES or MENTIONS SYM, and whether HEAD has it. Scans each
//                        ref's FULL tree (that is the question), so a symbol a branch merely inherited is
//                        still found. Trees only, though: content that NO ref still carries is invisible to
//                        a tree scan however loudly history remembers it, which is why --with-history adds
//                        the gitoracle.h lane — one `git log` pass that says whether HEAD's own history ever
//                        removed the name, and in which commit. hits="0" then separates "never existed here"
//                        from "deleted in commit X on DATE", which is the difference between a typo and rot.
//                        HEAD's side is the CHECKOUT: a path the working tree changed is read from disk
//                        (scanWorktree), so an uncommitted edit is never answered from the commit it left.
//   --stray-content   — per ref: the content the ref's own divergent work AUTHORED that the live line does
//                        NOT have, plus a verdict (merged / superseded / unmerged).
//
// ── the cost model: per-BLOB, keyed by blob sha ───────────────────────────────────────────────────────────
// Git is content-addressed, so 30 branches off one trunk share ~99% of their blobs. EVERY byte-level fact
// this module needs (a blob's line multiset, its shingle sketch, whether SYM occurs in it) is a pure
// function of the blob's CONTENT — therefore of its sha — so it is computed ONCE per distinct blob and
// reused by every ref that references it. A blob sha is immutable by construction, so the memo can never go
// stale (the same reasoning quality.h's per-sha ingest caches rest on). Blobs are streamed through ONE
// `git cat-file --batch` for the whole run (not one process per file), and reduced to fixed-size facts as
// they arrive — raw bytes are never retained, so peak memory is bounded by the facts, not by the trees.
// Net effect: indexing all N refs costs barely more than indexing one.
//
// ── what "stray content" means, precisely ─────────────────────────────────────────────────────────────────
// For ref R with base B = merge-base(R, HEAD):
//     authored(R,P) = lines ADDED by R vs B in path P        (R's OWN work — not what it inherited)
//     stray(R,P)    = authored(R,P) lines absent from HEAD's blob at P
// Restricting to AUTHORED lines is load-bearing and was the bug in the hand-rolled sweep this verb replaces:
// a plain "lines R has that HEAD lacks" also counts BASE content that HEAD itself later deleted — the live
// line's own decision, not the branch's work — which buried 194 real stray lines under ~800 phantom ones on
// the motivating repo. Deletions on either side are handled by MULTISET arithmetic over line hashes, so
// removing one of two identical lines registers (a set would silently drop it).
//
// ── supersession: the case `git cherry` structurally cannot see ───────────────────────────────────────────
// A branch fix that the live line RE-IMPLEMENTED differently is still an unmerged commit to `git cherry`,
// forever. The evidence that separates it is the DELETION SITE: both sides diff against the SAME base, so
// "R deleted base line L" and "HEAD deleted base line L" are exactly comparable with no fuzzy matching at
// all. When the live line removed the very base code the branch removed, it has demonstrably revisited that
// site on its own — the branch's copy is a variant, not a missing feature:
//     redoDel(R,P) = |del(B→R,P) ∩ del(B→HEAD,P)| / |del(B→R,P)|        (multiset)
// A file with redoDel ≥ kRedoDelMin is SUPERSEDED; a file whose stray content is a PURE ADDITION (nothing
// deleted, so no site to compare) can only be superseded through the minhash lane below. The ref-level
// verdict is the stray-LINE-weighted majority, so one coincidentally-shared deleted line can never vouch for
// a few hundred added ones.
//
// The minhash lane (bottom-k sketch over normalized token shingles) covers the pure-addition case: content
// the branch added that the live line holds in some rewritten/relocated form. It is deliberately held to a
// HIGH bar (kSimSupersede, and a minimum stray size) because containment alone is a weak signal — measured
// on the motivating repo it ran HIGHER for genuinely-unmerged branches than for superseded ones, so it
// corroborates the deletion-site evidence rather than competing with it. Every file row reports its raw
// del=/redo=/sim= numbers so the verdict is auditable, never a black box.
//
// ── ANCHORING, per verb, stated rather than assumed (r26 merge-base audit) ────────────────────────────────
// --stray-content is a HYBRID, deliberately, and the split is the whole point:
//   SCOPE (which lines are even considered)  — BASE-anchored. authored(R,P) is `diff base..R`, never
//        `diff HEAD..R`. This is the §"what stray content means" rule above; getting it wrong is what buried
//        194 real stray lines under ~800 phantom ones, and it is the same correction --abi later needed.
//   ABSENCE (the test each authored line then faces) — HEAD-anchored, ON PURPOSE. "Does the live line have
//        this content TODAY" is literally the user's question ("is my fix in?"), and it is only answerable
//        against live HEAD; anchoring the absence test at the merge base would compare the branch to a tree
//        neither side has cared about for weeks and would call every landed fix "stray". A HEAD-anchored
//        comparison is correct here for the same reason it is wrong for scope: the question is about now.
// --whereis has NO diff and therefore no anchor at all. It is a TREE SCAN of every ref (plus the gitoracle
//        history lane), which is what makes it able to find content a branch merely INHERITED — precisely
//        what a base-anchored diff would exclude. Nothing here can fire "because HEAD moved"; the only
//        HEAD-relative fact it reports is on-head=, which is a statement about HEAD by construction.
//
// Read-only, always: `git cat-file`, `git diff --raw`, `git merge-base` and `git for-each-ref` only. This
// module never checks out, never writes a ref, never touches the working tree. Determinism: refs are sorted
// by name, files by path, every hash is FNV-1a over trimmed bytes, and no wall clock is ever consulted (ref
// dates come from git's committer clock) — a fixed repo state gives byte-identical output.

#include "model.h"
#include "quality.h"            // gitOneLine / gitHeadSha / gitRepoHasHistory / popenTrimmed
#include "pathguard.h"          // readRegularFileNoFollow — the worktree overlay reads a changed path regular-file-only, no-follow
#include "gitstamp.h"           // stampAt — the at="<sha>[+dirty]" anchor (M10: --stray-content had head= with no dirty bit)
#include "gitoracle.h"          // the SHARED name-history oracle — the deleted-from-every-tree lane for whereis
#include "arch.h"               // fnv1a64
#include "infra/hashutil.h"     // fnv1aMultiply — the sanitizer-safe wrapping multiply (G1 runs -fsanitize=integer)
#include "infra/jsonesc.h"      // shSingleQuote
#include "serialize.h"          // escapeXml
#include "pageview.h"           // §P8: pageWindow / pageDisclosure — the shared --limit/--offset contract
#include "nextverb.h"           // nextAttrXml / nextFlag — the <refs next=> follow-up of the default listing
#include "compactlegend.h"      // compactDeliveredBytesOrWritten — the default listing is chosen on the bytes the compact dialect delivers
#include "workspace.h"          // wsdetail::segmentsOf
#include "filter.h"             // §P11.5: rw::pathTierOf — the shared source/test/doc ORDERING tier
#include "infra/Diagnostics.h"  // ASSUME / DISCLOSE
#include "infra/sortutil.h"    // svLess — the rename probe orders names in byte order, never via string_view operator<
#include "ingest.h"             // definitionLinesInBlobs — the tags path over another ref's blob (labelBranchRowsByParse)

#include "btree.hpp"      // gtl::btree_map — sorted iteration (house rule: never std::map)

#include <algorithm>
#include <atomic>       // the git-spawn pool's work index
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <filesystem>   // the worktree overlay: symlink_status / read_symlink / file_size on a changed path
#include <functional>
#include <mutex>        // labelBranchRowsByParse holds quality::headSnapshotIngestMutex around the blob parse
#include <optional>
#include <string>
#include <string_view>
#include <thread>       // the git-spawn pool (fork/exec is the cost, not compute)
#include "infra/os.h"   // rw::os::getpid / unlink / popen — the blob-batch temp list and its git reader
#include <utility>
#include <vector>

namespace rw
{
namespace crossref
{

// ── tuning constants (every threshold the verdict rests on, in one place) ────────────────────────────────

constexpr std::size_t   kShingleTokens   = 5;        // tokens per shingle for the minhash sketch
constexpr std::size_t   kSketchSize      = 128;      // bottom-k minhash sketch width (fixed per blob)
constexpr std::size_t   kMaxBlobBytes    = 2u << 20; // 2 MB — above this a blob is data, not content worth diffing
constexpr std::size_t   kBinaryProbe     = 8192;     // NUL within this prefix ⇒ binary, skipped
constexpr float         kRedoDelMin      = 0.60f;    // deletion-site overlap that marks a file superseded
constexpr float         kSimSupersede    = 0.90f;    // minhash containment bar for the PURE-ADDITION lane
constexpr std::uint32_t kSimMinStray     = 8;        // …and its minimum stray size (tiny bodies match by luck)
constexpr float         kRefSupersedeMin = 0.60f;    // stray-line-weighted share that marks a whole ref superseded
constexpr std::uint32_t kMaxRefs         = 512;      // refusal bound — a sweep, not a fork-network crawl

// Display caps (--detail lifts both): the ranked head is the answer, and a 30-branch sweep would otherwise
// bury it under thousands of rows. What is dropped is always COUNTED in a <more/> element, never silently.
constexpr std::size_t   kStrayFilesPerRef = 12;
constexpr std::size_t   kWhereisHits      = 60;

// --whereis: the RUNAWAY GUARD on the tags parse of other refs' blobs (labelBranchRowsByParse; --detail=N lifts it). Only a
// blob holding a parse-worthy row (parseWorthyLine) is parsed, one parse per distinct (blob, path): ripwire's own most-called helper
// across 162 refs needs 104 parses and 43 MB (~1.7 s at load 20 on an M2 Pro); a typical name, a handful. Hitting
// either bound is disclosed on the answer (<unparsed next=>), and the blobs it leaves confirm no definition.
constexpr std::size_t   kWhereisParseMaxBlobs = 256;
constexpr std::size_t   kWhereisParseMaxBytes = std::size_t( 64 ) << 20;

// WHICH ROWS a --whereis answer lists (--whereis-listing=, MCP `listing`). A where-defined question is answered by
// the kind="def" rows; the kind="ref" rows (8-59 per answer on the comparison-table cells, ~8 KB) supplied no gold
// item there. So the default lists the definitions and COUNTS the references in one <refs count= next=> element whose
// next= lists exactly those rows (Refs). All is the whole hit list, the pre-listing answer and the uncapped variant
// a lean answer is graded against (owner rule: a capped variant is graded against the uncapped one).
//   Defs  every kind="def" row; the kind="ref" rows counted. Degrades to All (no listing=, no <refs>) when the hit
//         list holds no ref row (nothing to elide) or no def row (the mentions ARE the answer then).
//   Refs  the kind="ref" rows only, in the hit list's order: the <refs next=> page.
//   All   every row.
//   ShorterOfDefsAll  the DEFAULT (no flag, no MCP `listing`): complete answers first. The Defs page when it SHOWS MORE
//         definitions than the All page under the shared row cap (a capped All page can list fewer: HEAD's references fill
//         the cap before the branch definitions arrive; review D1), whatever its bytes; when both pages show the same
//         definitions, the Defs page only when it is STRICTLY shorter in bytes (review B1: on a symbol with one or two
//         refs the Defs page pays more for its <refs> element, listing= and their legend readings than the ref rows it
//         elides), else the All page. Measured, never guessed: whereisServedListing renders both. An explicit defs is
//         served as asked.
enum class WhereisListing : std::uint8_t { Defs, Refs, All, ShorterOfDefsAll };

// ── blob facts (the per-sha memo payload) ────────────────────────────────────────────────────────────────

// Everything this module needs to know about one blob, reduced from its bytes as they stream past and kept
// instead of them. `lineHashes` is SORTED so the multiset ops below are linear merges.
struct BlobFacts
{
    std::vector<std::uint64_t> lineHashes;      // FNV-1a of each trimmed, non-blank line — sorted, DUPLICATES KEPT
    std::vector<std::uint64_t> sketch;          // bottom-k minhash of kShingleTokens-token shingles — sorted, unique
    std::uint32_t              lineCount = 0;
    bool                       isText    = true;   // false ⇒ binary/oversized: facts are empty, rows say so
};

// ── content-preserving normalization (deliberately NOT clones.h's) ───────────────────────────────────────
// clones.h maps every identifier to `$I` so two DIFFERENT functions with the same shape collide — exactly
// right for clone detection and exactly wrong here, where the identifiers ARE the signal that two spellings
// of a fix are the same fix. So: identifiers kept verbatim, numbers → $N and strings → $S (a re-implementation
// that changes a literal is still the same work), comments dropped, punctuation kept.
inline bool isIdentByte( unsigned char c ) noexcept { return std::isalnum( c ) || c == '_'; }

// Append the next normalized token starting at src[i] to `out`, returning the index just past it. A comment
// or whitespace run emits nothing (out unchanged) — the caller loops until the end of the buffer.
inline std::size_t nextNormToken( std::string_view src, std::size_t i, std::vector<std::string_view>& out )
{
    static constexpr std::string_view kNum = "$N", kStr = "$S";
    const std::size_t n = src.size();

    if( std::isspace( (unsigned char)src[i] ) )
    {
        return i + 1;
    }
    if( src[i] == '/' && i + 1 < n && src[i + 1] == '/' )
    {
        i += 2;
        while( i < n && src[i] != '\n' )
        {
            ++i;
        }
        return i;
    }
    if( src[i] == '/' && i + 1 < n && src[i + 1] == '*' )
    {
        i += 2;
        while( i + 1 < n && !( src[i] == '*' && src[i + 1] == '/' ) )
        {
            ++i;
        }
        return std::min( n, i + 2 );
    }
    if( src[i] == '"' || src[i] == '\'' )
    {
        const char q = src[i];
        std::size_t j = i + 1;
        while( j < n && src[j] != q )
        {
            if( src[j] == '\\' )
            {
                ++j;
            }
            ++j;
        }
        out.push_back( kStr );
        return std::min( n, j + 1 );
    }
    if( std::isdigit( (unsigned char)src[i] ) )
    {
        std::size_t j = i;
        while( j < n && ( isIdentByte( (unsigned char)src[j] ) || src[j] == '.' ) )
        {
            ++j;
        }
        out.push_back( kNum );
        return j;
    }
    if( std::isalpha( (unsigned char)src[i] ) || src[i] == '_' )
    {
        std::size_t j = i;
        while( j < n && isIdentByte( (unsigned char)src[j] ) )
        {
            ++j;
        }
        out.push_back( src.substr( i, j - i ) );      // identifier KEPT — the semantic fingerprint
        return j;
    }
    out.push_back( src.substr( i, 1 ) );              // operator / punctuation
    return i + 1;
}

inline std::vector<std::string_view> normalizeTokens( std::string_view src )
{
    std::vector<std::string_view> out;
    out.reserve( src.size() / 4 + 1 );
    for( std::size_t i = 0; i < src.size(); )
    {
        i = nextNormToken( src, i, out );
    }
    return out;
}

// Bottom-k minhash over kShingleTokens-token shingles of the normalized stream. Bottom-k (the k smallest
// distinct shingle hashes) is a fixed-width, order-free, deterministic sketch: containment between two
// sketches estimates containment between the full shingle sets, and two identical bodies always produce the
// identical sketch. A body shorter than one shingle degrades to its bare token hashes (still comparable).
inline std::vector<std::uint64_t> minhashSketch( std::string_view src )
{
    const std::vector<std::string_view> tok = normalizeTokens( src );
    std::vector<std::uint64_t>          all;

    if( tok.size() < kShingleTokens )
    {
        all.reserve( tok.size() );
        for( std::string_view t : tok )
        {
            all.push_back( fnv1a64( t ) );
        }
    }
    else
    {
        all.reserve( tok.size() - kShingleTokens + 1 );
        for( std::size_t i = 0; i + kShingleTokens <= tok.size(); ++i )
        {
            // FNV-1a over the shingle's per-token hashes. The multiply MUST wrap — that is the algorithm —
            // so it goes through hashutil::fnv1aMultiply (a widened multiply masked back to 64 bits) rather
            // than a bare `*`: the G1 stack runs -fsanitize=integer -fno-sanitize-recover=all, under which a
            // plain unsigned overflow aborts the process. (Caught by that gate, not by inspection.)
            std::uint64_t h = 14695981039346656037ull;                       // FNV-1a 64 offset basis
            for( std::size_t k = 0; k < kShingleTokens; ++k )
            {
                h ^= fnv1a64( tok[ i + k ] );
                h  = hashutil::fnv1aMultiply( h );
            }
            all.push_back( h );
        }
    }

    std::sort( all.begin(), all.end() );
    all.erase( std::unique( all.begin(), all.end() ), all.end() );
    if( all.size() > kSketchSize )
    {
        all.resize( kSketchSize ); // bottom-k
    }
    return all;
}

// ── sorted-sequence set algebra (shared by the sketch lane and the line-multiset lane) ──────────────────

// |a ∩ b| over two SORTED sequences. Duplicates are consumed pairwise, so this is a MULTISET intersection
// on the line lane (where a line repeated twice on one side and once on the other must count once) and a
// plain set intersection on the sketch lane (whose sketches are unique by construction).
inline std::size_t sortedIntersectSize( const std::vector<std::uint64_t>& a, const std::vector<std::uint64_t>& b )
{
    // SORTEDNESS is this whole family's precondition — an unsorted input does not fail loudly, it silently
    // under-counts the intersection and quietly shifts a verdict. Free in release (__builtin_assume).
    ASSUME( std::is_sorted( a.begin(), a.end() ) );
    ASSUME( std::is_sorted( b.begin(), b.end() ) );
    std::size_t hit = 0, i = 0, j = 0;
    while( i < a.size() && j < b.size() )
    {
        if( a[i] < b[j] )
        {
            ++i;
        }
        else if( b[j] < a[i] )
        {
            ++j;
        }
        else
        {
            ++hit;
            ++i;
            ++j;
        }
    }
    return hit;
}

// Containment of `a` in `b`: |a ∩ b| / |a| over two SORTED unique sketches. Containment, not Jaccard —
// HEAD's file is typically far larger than a branch's added region, and Jaccard would punish that size gap
// for no reason. Empty `a` ⇒ 0 (nothing to be contained; never a divide-by-zero).
inline float sketchContainment( const std::vector<std::uint64_t>& a, const std::vector<std::uint64_t>& b )
{
    if( a.empty() || b.empty() )
    {
        return 0.0f;
    }
    return float( sortedIntersectSize( a, b ) ) / float( a.size() );
}

// ── line multisets ───────────────────────────────────────────────────────────────────────────────────────

// Hash every trimmed, non-blank line of `src` into a SORTED vector (duplicates kept — this is a multiset).
// Blank/whitespace-only lines carry no content and would otherwise dominate every intersection.
inline std::vector<std::uint64_t> lineMultiset( std::string_view src )
{
    std::vector<std::uint64_t> out;
    std::size_t                i = 0;
    while( i < src.size() )
    {
        std::size_t e = src.find( '\n', i );
        if( e == std::string_view::npos )
        {
            e = src.size();
        }
        std::size_t a = i, b = e;
        while( a < b && std::isspace( (unsigned char)src[a] ) )
        {
            ++a;
        }
        while( b > a && std::isspace( (unsigned char)src[b - 1] ) )
        {
            --b;
        }
        if( b > a )
        {
            out.push_back( fnv1a64( src.substr( a, b - a ) ) );
        }
        i = e + 1;
    }
    std::sort( out.begin(), out.end() );
    return out;
}

// Multiset difference a \ b over two SORTED multisets (an element present twice in `a` and once in `b`
// survives once). The linear merge that makes "what did this side ADD / REMOVE" exact under duplicates.
inline std::vector<std::uint64_t> msetDiff( const std::vector<std::uint64_t>& a, const std::vector<std::uint64_t>& b )
{
    ASSUME( std::is_sorted( a.begin(), a.end() ) );
    ASSUME( std::is_sorted( b.begin(), b.end() ) );
    std::vector<std::uint64_t> out;
    std::size_t                i = 0, j = 0;
    while( i < a.size() )
    {
        if( j >= b.size() || a[i] < b[j] )
        {
            out.push_back( a[i++] );
        }
        else if( b[j] < a[i] )
        {
            ++j;
        }
        else
        {
            ++i;
            ++j;
        }
    }
    return out;
}

// Count members of the SORTED multiset `a` that are absent from the SORTED multiset `b` (b treated as a SET:
// "does the live line have this line ANYWHERE in the file"). This is the stray-line count — a line the branch
// authored that simply does not occur in HEAD's version, wherever it might have moved to.
inline std::size_t countAbsent( const std::vector<std::uint64_t>& a, const std::vector<std::uint64_t>& b )
{
    std::size_t miss = 0;
    for( std::uint64_t h : a )
    {
        if( !std::binary_search( b.begin(), b.end(), h ) )
        {
            ++miss;
        }
    }
    return miss;
}

// ── the streaming blob reader (ONE `git cat-file --batch` for the whole run) ─────────────────────────────

// A blob sha is 40 hex bytes (SHA-1) or 64 (SHA-256). Anything else came from a malformed diff line and is
// refused before it reaches the batch, so a corrupt line can never be spliced into the command.
// Byte-for-byte the same predicate as quality::isBareCommitSha — an object name is an object name, blob or
// commit — so it delegates rather than keeping a second copy that could drift when SHA-256 rules change.
inline bool isBlobSha( std::string_view s ) noexcept
{
    return quality::isBareCommitSha( s );
}

// An all-zero sha is git's "this side does not exist" marker in `diff --raw` (an add or a delete).
inline bool isNullSha( std::string_view s ) noexcept
{
    return !s.empty() && s.find_first_not_of( '0' ) == std::string_view::npos;
}

// Is `s` safe to hand to git as a REVISION argument? Same 40/64-hex shape as a blob name, but the property
// being asserted is different and worth its own name: a resolved object name cannot be mistaken for an OPTION
// word, so it can never become `--output=FILE`.
//
// That is not hypothetical. `git diff` — the verb diffRaw uses — honours `--output=FILE`, and the round that
// found this bug demonstrated a file OUTSIDE the repo being truncated and overwritten at exit 0 by a sibling
// verb that passed an unvalidated ref through. Every revision token here is git's OWN output today (an
// objectname from for-each-ref, a sha from merge-base), so the exposure is latent rather than live — but
// "the input happens to be trustworthy" is an invariant nothing was enforcing, and it is one careless caller
// from being false. Enforce it at the seam instead, where it costs a comparison.
//
// NOTE for anyone hardening a sibling: the resolve/validate IS the defense. A `--` placed BEFORE the revision
// makes it a pathspec and breaks the command; the separator belongs at the END, after the revisions.
inline bool isRevisionToken( std::string_view s ) noexcept
{
    return isBlobSha( s );
}

// Stream every sha in `shas` through one `git cat-file --batch`, invoking `onBlob( sha, bytes )` per blob in
// request order. Oversized/binary blobs invoke the callback with an EMPTY view and `isText=false` so the
// caller can record the honest "not diffable" fact rather than silently omitting the path.
//
// The sha list goes in through a TEMP FILE rather than the command line: 30 refs' worth of changed blobs is
// tens of thousands of shas, far past ARG_MAX, and popen is read-only so stdin cannot be fed directly. The
// temp file lives under the same hardened cache dir the rest of the tool uses and is unlinked on every exit
// path (including the early returns below).
//
// T1 (completeness claims): `stats`, when supplied, records the degrade shapes this streamer previously
// swallowed — a caller that wants to CLAIM its scan was exhaustive (whereis' complete=) needs to know
// whether any blob went unread. `binary` is counted separately from the failure shapes on purpose: a
// binary blob cannot carry a text symbol, so it does not defeat a text-scoped claim, while an OVERSIZED
// text blob genuinely could and must.
struct StreamBlobStats
{
    std::uint32_t missing    = 0;      // "<oid> missing" / malformed header — the object could not be read
    std::uint32_t nonBlob    = 0;      // wrong object type or negative size — never scanned
    std::uint32_t oversized  = 0;      // > kMaxBlobBytes, consumed but DISCARDED unread
    std::uint32_t binary     = 0;      // NUL in the probe window — outside a text-scoped claim, not a failure
    bool          endedEarly = false;  // the batch pipe died before serving every sha
    bool          startFailed = false; // the batch never started (list file / popen failure)
    // The DISCLOSE sink for the batch's own failures: both flags withhold every completeness claim built on the stream.
    enum class DisclosureWhy : std::uint8_t
    {
        ListUnwritable,       // the blob-batch list could not be written
        BatchNotStarted,      // git cat-file --batch did not start
        StreamEndedMidBlob,   // the pipe died part-way through a blob
    };
    void disclose( DisclosureWhy why ) noexcept
    {
        switch( why )
        {
            case DisclosureWhy::ListUnwritable:
            case DisclosureWhy::BatchNotStarted:    startFailed = true; break;
            case DisclosureWhy::StreamEndedMidBlob: endedEarly  = true; break;
        }
    }

    bool exhaustiveOverText() const noexcept
    {
        return !startFailed && !endedEarly && missing == 0 && nonBlob == 0 && oversized == 0;
    }
};

template<class OnBlob>
inline void streamBlobs( const std::string& root, const std::vector<std::string>& shas, OnBlob onBlob,
                         StreamBlobStats* stats = nullptr )
{
    // Null-object: count unconditionally into a local sink when the caller did not ask, so the body below
    // carries no per-site null test (the branch count stays what the streaming logic needs, nothing more).
    StreamBlobStats  localStats;
    StreamBlobStats& st = stats != nullptr ? *stats : localStats;

    if( shas.empty() )
    {
        return;
    }

    static std::atomic<std::uint64_t> listSeq{ 0 };   // concurrent batches (streamBlobsInSlices) each own their list file
    const std::string listPath = quality::cacheDirLadder() + "/ripwire-crossref-" + std::to_string( os::getpid() ) + "-"
                               + std::to_string( listSeq.fetch_add( 1, std::memory_order_relaxed ) ) + ".shas";
    {
        std::FILE* lf = std::fopen( listPath.c_str(), "wb" );
        if( !lf )
        {
            DISCLOSE( st, StreamBlobStats::DisclosureWhy::ListUnwritable, "crossref: cannot write the blob-batch list — cross-branch content unavailable" );
            return;
        }
        for( const std::string& s : shas )
        {
            rw::emitTo( lf, "{}\n", s.c_str() );
        }
        std::fclose( lf );
    }

    const std::string cmd = gitCmd( " -c core.quotepath=false -C " ) + shSingleQuote( root )
                          + " cat-file --batch < " + shSingleQuote( listPath ) + " 2>/dev/null";
    std::FILE* pipe = os::popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        os::unlink( listPath.c_str() );
        DISCLOSE( st, StreamBlobStats::DisclosureWhy::BatchNotStarted, "crossref: git cat-file --batch failed to start — cross-branch content unavailable" );
        return;
    }

    std::vector<char> body;
    std::string       header;
    for( std::size_t served = 0; served < shas.size(); ++served )
    {
        // header: "<oid> <type> <size>\n", or "<oid> missing\n" for an unreadable object
        header.clear();
        for( int c = std::fgetc( pipe ); c != EOF && c != '\n'; c = std::fgetc( pipe ) )
        {
            header.push_back( char( c ) );
        }
        if( header.empty() )
        {
            st.endedEarly = true;
            break; // pipe ended early — degrade quietly
        }

        const std::size_t sp2 = header.rfind( ' ' );
        const std::size_t sp1 = ( sp2 == std::string::npos ) ? std::string::npos : header.rfind( ' ', sp2 - 1 );
        if( sp1 == std::string::npos ) { ++st.missing;  onBlob( shas[ served ], std::string_view{}, false ); continue; }

        const std::string_view type( header.data() + sp1 + 1, sp2 - sp1 - 1 );
        const long long        size = std::strtoll( header.c_str() + sp2 + 1, nullptr, 10 );
        if( type != "blob" || size < 0 ) { ++st.nonBlob;  onBlob( shas[ served ], std::string_view{}, false ); continue; }

        // The payload must be CONSUMED whatever its size — the stream is framed, so skipping bytes would
        // desync every subsequent header and start attributing content to the wrong sha. But an oversized
        // blob is DISCARDED as it is consumed rather than buffered: a repo can hold a 500 MB object, and
        // resizing to it just to throw it away would spike RSS by that much for a blob we never look at.
        const bool        tooBig = std::size_t( size ) > kMaxBlobBytes;
        std::size_t       got    = 0;
        if( tooBig )
        {
            char        sink[ 65536 ];
            std::size_t left = std::size_t( size );
            while( left > 0 )
            {
                const std::size_t n = std::fread( sink, 1, std::min( left, sizeof( sink ) ), pipe );
                if( n == 0 )
                {
                    break;
                }
                left -= n;
                got  += n;
            }
        }
        else
        {
            body.resize( std::size_t( size ) );
            got = ( size > 0 ) ? std::fread( body.data(), 1, std::size_t( size ), pipe ) : 0;
        }
        (void)std::fgetc( pipe );                                            // the framing LF after the payload

        // A SHORT read means the pipe died mid-payload (git killed, disk error). The stream can no longer be
        // trusted to be framed, and continuing would pair later headers with the wrong sha — a silently
        // WRONG answer, which is worse than a short one. Report this blob as unreadable and stop.
        if( got != std::size_t( size ) )
        {
            DISCLOSE( st, StreamBlobStats::DisclosureWhy::StreamEndedMidBlob,
                      "crossref: git cat-file stream ended mid-blob — stopping the batch rather than risk misattributing content" );
            onBlob( shas[ served ], std::string_view{}, false );
            break;
        }

        const std::string_view bytes( body.data(), tooBig ? 0 : got );
        const bool             binary = bytes.substr( 0, std::min( bytes.size(), kBinaryProbe ) ).find( '\0' ) != std::string_view::npos;
        if( tooBig || binary )
        {
            if( tooBig ) { ++st.oversized; } else { ++st.binary; }
            onBlob( shas[served], std::string_view {}, false );
        }
        else
        {
            onBlob( shas[served], bytes, true );
        }
    }

    os::pclose( pipe );
    os::unlink( listPath.c_str() );
}

// The per-sha memo. `want()` registers a sha; `fill()` streams every not-yet-known sha through ONE batch and
// reduces it to BlobFacts. Calling fill() again after more want()s only fetches the NEW shas — the whole
// point of content-addressing: a blob shared by 25 refs is read and reduced exactly once.
class BlobStore
{
public:
    explicit BlobStore( std::string root ) : root_( std::move( root ) ) {}

    void want( const std::string& sha )
    {
        if( sha.empty() || isNullSha( sha ) || !isBlobSha( sha ) )
        {
            return;
        }
        if( facts_.find( sha ) != facts_.end() )
        {
            return;
        }
        pending_.push_back( sha );
    }

    void fill()
    {
        if( pending_.empty() )
        {
            return;
        }
        std::sort( pending_.begin(), pending_.end() );                       // determinism: batch order is sha order
        pending_.erase( std::unique( pending_.begin(), pending_.end() ), pending_.end() );

        std::vector<std::string> todo;
        todo.reserve( pending_.size() );
        for( const std::string& s : pending_ )
        {
            if( facts_.find( s ) == facts_.end() )
            {
                todo.push_back( s );
            }
        }
        pending_.clear();

        streamBlobs( root_, todo, [ & ]( const std::string& sha, std::string_view bytes, bool isText )
        {
            BlobFacts f;
            f.isText = isText;
            if( isText )
            {
                f.lineHashes = lineMultiset( bytes );
                f.sketch     = minhashSketch( bytes );
                f.lineCount  = std::uint32_t( f.lineHashes.size() );
            }
            facts_.emplace( sha, std::move( f ) );
            ++fetched_;
        } );
    }

    // The facts for `sha`, or a shared empty (non-text) record for an absent side — so a caller can treat
    // "this path did not exist on that side" as "it contributed no lines" without a null check.
    const BlobFacts& get( const std::string& sha ) const
    {
        static const BlobFacts kEmpty{};
        const auto it = facts_.find( sha );
        return ( it == facts_.end() ) ? kEmpty : it->second;
    }

    std::size_t distinctBlobs() const noexcept { return facts_.size(); }
    std::size_t fetched()       const noexcept { return fetched_; }

private:
    std::string                              root_;
    gtl::btree_map<std::string, BlobFacts>   facts_;
    std::vector<std::string>                 pending_;
    std::size_t                              fetched_ = 0;
};

// ── git plumbing (read-only) ─────────────────────────────────────────────────────────────────────────────

// Capture a git command's FULL multi-line stdout ("" on failure). This is exactly quality::gitOneLine's
// read-only `git -C <root> <tail>` shape (popenTrimmed keeps internal newlines, trimming only trailing
// whitespace), so it delegates rather than re-spelling the same hardened prefix and popen-and-trim call.
inline std::string gitCapture( const std::string& root, const std::string& tail )
{
    return quality::gitOneLine( root, tail );
}

inline std::vector<std::string_view> splitLines( std::string_view s )
{
    return wsdetail::segmentsOf( s, '\n' );
}

// One ref in the sweep: its name, tip sha, and committer date (git's clock — never the wall clock).
struct RefInfo
{
    std::string name;
    std::string tip;
    std::string date;      // YYYY-MM-DD
};

// Every local branch plus every worktree branch, sorted by name (determinism), excluding the ref HEAD is
// currently on (a branch cannot be stray from itself). `filter` (from --stray-content=SUBSTR) keeps only
// refs whose name contains it. Remote-tracking refs are deliberately EXCLUDED: they mirror local ones and
// would double every row.
// `filterNameHits` (optional out): how many refs/heads names CONTAIN the filter, counted before the
// "a branch cannot be stray from itself" exclusion of HEAD's own ref. H7 needs that number and not
// out.size(): a filter matching only the checked-out branch has SELECTED something (the answer is "nothing
// but the ref you are on"), while a filter matching no branch name at all has selected nothing and must
// refuse rather than report refs="0" — which reads as "no branch carries stray work".
//
// `enumeration` (optional out) is the DISCLOSE sink for a ref DROPPED here (a tip that is not an object name): it is
// in no count the caller prints, so a caller that claims completeness must read refsDropped — --whereis withholds
// complete= on it. A caller passing none has no such claim to withhold.
struct RefEnumeration
{
    enum class DisclosureWhy : std::uint8_t
    {
        TipNotObjectName,
    };
    std::uint32_t refsDropped = 0;
    void disclose( DisclosureWhy ) noexcept   // every reason records the same fact
    {
        ++refsDropped;
    }
};

inline std::vector<RefInfo> enumerateRefs( const std::string& root, std::string_view filter, const std::string& headSha,
                                           std::size_t* filterNameHits = nullptr, RefEnumeration* enumeration = nullptr )
{
    RefEnumeration  unread;   // the sink when the caller keeps none
    RefEnumeration& dropSink = enumeration != nullptr ? *enumeration : unread;
    const std::string raw = gitCapture( root, "for-each-ref --sort=refname --format='%(refname:short)|%(objectname)|%(committerdate:short)' refs/heads 2>/dev/null" );
    std::vector<RefInfo> out;
    for( std::string_view line : splitLines( raw ) )
    {
        // Parse from the RIGHT, not by splitting left-to-right: '|' is a LEGAL byte in a git ref name (git
        // forbids space, ~ ^ : ? * [ \ and control bytes — not the pipe), so a branch named `feat|x` split
        // into four fields and handed `x` back as the tip sha. That ref then failed merge-base and landed in
        // the degraded path, i.e. a legally-named branch silently became unanalysable. The two TRAILING
        // fields are git-generated and pipe-free by construction (an object name is hex, a short committer
        // date is YYYY-MM-DD), so everything before the second-to-last '|' is the name, whatever it contains.
        const std::size_t lastPipe = line.rfind( '|' );
        if( lastPipe == std::string_view::npos || lastPipe == 0 )
        {
            continue;
        }
        const std::size_t firstPipe = line.rfind( '|', lastPipe - 1 );
        if( firstPipe == std::string_view::npos || firstPipe >= lastPipe )
        {
            continue;
        }

        const std::string_view name = line.substr( 0, firstPipe );
        const std::string_view tip  = line.substr( firstPipe + 1, lastPipe - firstPipe - 1 );
        const std::string_view date = line.substr( lastPipe + 1 );
        if( filterNameHits != nullptr && !name.empty() && ( filter.empty() || name.find( filter ) != std::string_view::npos ) )
        {
            ++*filterNameHits;
        }
        if( name.empty() || tip == headSha )
        {
            continue; // the ref HEAD is on
        }
        if( !isRevisionToken( tip ) )
        {
            // %(objectname) is always a full object name, so this cannot fire on well-formed output — which
            // is exactly why it is checked HERE, at the one place ref tips enter the module. Every git
            // command downstream takes this value as a revision argument.
            DISCLOSE( dropSink, RefEnumeration::DisclosureWhy::TipNotObjectName, "crossref: for-each-ref yielded a ref whose tip is not an object name — skipping it" );
            continue;
        }
        if( !filter.empty() && name.find( filter ) == std::string_view::npos )
        {
            continue;
        }
        out.push_back( RefInfo{ std::string( name ), std::string( tip ), std::string( date ) } );
    }
    return out;
}

// One `diff --raw` row: both sides' blob shas for one path. `git diff --raw` is the ONE call that yields
// the changed path set AND both blob shas together — no follow-up ls-tree per file.
struct RawRow
{
    std::string path;
    std::string aSha;      // base side ("000…" ⇒ added)
    std::string bSha;      // ref  side ("000…" ⇒ deleted)
};

// Parse `git diff --raw --no-renames A B`:  ":<modeA> <modeB> <shaA> <shaB> <status>\t<path>"
//
// --no-abbrev is load-bearing, not cosmetic: `diff --raw` abbreviates object names to ~8 hex by default, and
// an abbreviated name is NOT a key — it cannot be handed to cat-file as a stable identity, and two blobs can
// share a prefix. The full name is what makes the per-sha memo sound.
inline std::vector<RawRow> diffRaw( const std::string& root, const std::string& a, const std::string& b )
{
    // Both sides must be RESOLVED object names before they reach `git diff`, which honours --output=FILE.
    // Degrade to an empty diff rather than spawn a command whose arguments were never checked.
    if( !isRevisionToken( a ) || !isRevisionToken( b ) )
    {
        DISCLOSE( "crossref: refusing a diff whose revision arguments are not resolved object names" );
        return {};
    }
    const std::string raw = gitCapture( root, "diff --raw --no-abbrev --no-renames " + shSingleQuote( a ) + " " + shSingleQuote( b ) + " -- 2>/dev/null" );
    std::vector<RawRow> out;
    for( std::string_view line : splitLines( raw ) )
    {
        if( line.empty() || line[0] != ':' )
        {
            continue;
        }
        const std::size_t tab = line.find( '\t' );
        if( tab == std::string_view::npos )
        {
            continue;
        }
        const std::vector<std::string_view> f = wsdetail::segmentsOf( line.substr( 1, tab - 1 ), ' ' );
        if( f.size() < 4 )
        {
            continue;
        }
        if( !isBlobSha( f[2] ) || !isBlobSha( f[3] ) )
        {
            continue; // malformed row — skip, never splice
        }
        out.push_back( RawRow{ std::string( line.substr( tab + 1 ) ), std::string( f[2] ), std::string( f[3] ) } );
    }
    std::sort( out.begin(), out.end(), []( const RawRow& x, const RawRow& y ) { return x.path < y.path; } );
    return out;
}

// ── the git-spawn pool, and the distinct-diff table it feeds ─────────────────────────────────────────────
//
// Each `git` invocation here is a PROCESS (~8 ms on the measured repo), and a 35-ref sweep asked for 128 of
// them strictly in sequence — ~1.1 s of pure fork/exec on a 1.65 s wall. Every one of those calls is
// read-only and independent of the others, so the fix is two-sided and needs no new git knowledge at all:
// ask for FEWER (skip the provably-empty ones, and never ask the same question twice), and ask in PARALLEL.

constexpr std::size_t   kMaxGitWorkers = 12;          // matches the ingest pool's measured ~12-way; these are
                                                      // processes, so more workers stops paying well before this
constexpr std::uint32_t kNoPair        = 0xFFFFFFFFu; // "this ref needs no diff" (see RefPlumbing::isAncestor)

// Run `body( i )` for every i in [0,count), across a small pool. DETERMINISM: every body writes only to the
// slot its OWN index owns and reads nothing another body writes, so the result is identical to the serial
// order by construction — the parallelism is in the fork/exec wait, never in the answer.
//
// A worker that throws abandons the indices it had not reached, and a slot nobody wrote holds its DEFAULT — which for a
// RefPlumbing reads ok=true, base="" and rendered as Merged. So the pool reports which indices finished through
// `sweep`, the DISCLOSE sink of its one degrade: each caller marks every unfinished slot as a failed analysis
// (ok="0" v="unknown" in the document) instead of reading a default as an answer.
struct ParallelSweep
{
    enum class DisclosureWhy : std::uint8_t
    {
        WorkerThrew,   // a worker's loop threw: the indices it had not reached were never run
    };
    std::vector<char> done;                     // done[i] = 1 once body( i ) returned; one writer per slot
    std::atomic<bool> isIncomplete{ false };
    void disclose( DisclosureWhy ) noexcept   // every reason records the same fact
    {
        isIncomplete.store( true, std::memory_order_relaxed );
    }
    bool isDone( std::size_t i ) const noexcept { return !isIncomplete.load( std::memory_order_relaxed ) || ( i < done.size() && done[ i ] != 0 ); }
};

template<class Body>
inline void parallelIndexed( std::size_t count, Body body, ParallelSweep& sweep )
{
    sweep.done.assign( count, 0 );
    if( count == 0 )
    {
        return;
    }

    std::size_t hwThreadCount = std::thread::hardware_concurrency();
    if( hwThreadCount == 0 )
    {
        hwThreadCount = 1;
    }
    const std::size_t workerCount = std::min( { hwThreadCount, count, kMaxGitWorkers } );
    if( workerCount <= 1 )
    {
        for( std::size_t i = 0; i < count; ++i )
        {
            body( i );
            sweep.done[ i ] = 1;
        }
        return;
    }

    std::atomic<std::size_t> nextIndex{ 0 };
    const auto               worker = [ & ]() noexcept
    {
        // A throw escaping a std::thread entry is std::terminate — degrade to partial coverage instead. Only
        // the allocation seam can throw here (popen/parse), and a short answer beats killing the process.
        try
        {
            for( std::size_t i = nextIndex.fetch_add( 1 ); i < count; i = nextIndex.fetch_add( 1 ) )
            {
                body( i );
                sweep.done[ i ] = 1;
            }
        }
        catch( ... ) { DISCLOSE( sweep, ParallelSweep::DisclosureWhy::WorkerThrew, "crossref: a git worker threw — this shard of the sweep is incomplete" ); }
    };

    {   // symmetric bare scope: the workers live exactly as long as the pass they serve
        std::vector<std::thread> workers;
        workers.reserve( workerCount );
        for( std::size_t w = 0; w < workerCount; ++w )
        {
            workers.emplace_back( worker );
        }
        for( std::thread& worker_ : workers )
        {
            worker_.join();
        }
    }
}

// ── one blob stream through several git processes (streamBlobsInSlices) ──────────────────────────────────────
// streamBlobs reads every blob through ONE `git cat-file --batch` pipe. On ripwire's 162 refs that is ~900 MB, and under
// load the pipe's ping-pong, not git's decompression, was the larger cost: 1.9 s for git writing to /dev/null against
// 5.9 s through `| cat` at load 28, and ~9 s of a --whereis at load 20-25 spent waiting in fread. This reads `slices`
// contiguous slices of the sha list through as many processes at once (parallelIndexed's pool). `onBlob( index, sha,
// bytes, isText )` runs on the slice's worker thread, once per served sha, so it may write only slot `index` of its own
// storage. The stats merge as one batch's would: counts add, and a slice that failed, was cut short or was never reached
// withholds every completeness claim.
constexpr std::size_t kWhereisStreamSlices = 4;

template<class OnBlob>
inline void streamBlobsInSlices( const std::string& root, const std::vector<std::string>& shas, std::size_t slices, OnBlob onBlob,
                                 StreamBlobStats& stats )
{
    slices = std::max<std::size_t>( 1, std::min( slices, shas.size() ) );
    std::vector<StreamBlobStats> sliceStats( slices );
    ParallelSweep                sweep;
    parallelIndexed( slices, [ & ]( std::size_t t )
    {
        const std::size_t              begin = shas.size() * t / slices;
        const std::size_t              end   = shas.size() * ( t + 1 ) / slices;
        const std::vector<std::string> part( shas.begin() + std::ptrdiff_t( begin ), shas.begin() + std::ptrdiff_t( end ) );
        std::size_t                    next = begin;   // streamBlobs serves its list in order, one call per served sha
        streamBlobs( root, part, [ & ]( const std::string& sha, std::string_view bytes, bool isText ) { onBlob( next++, sha, bytes, isText ); },
                     &sliceStats[ t ] );
    }, sweep );
    for( std::size_t t = 0; t < slices; ++t )
    {
        const StreamBlobStats& st = sliceStats[ t ];
        stats.missing    += st.missing;
        stats.nonBlob    += st.nonBlob;
        stats.oversized  += st.oversized;
        stats.binary     += st.binary;
        stats.endedEarly  = stats.endedEarly || st.endedEarly;
        stats.startFailed = stats.startFailed || st.startFailed;
        if( !sweep.isDone( t ) )
        {
            DISCLOSE( stats, StreamBlobStats::DisclosureWhy::BatchNotStarted, "crossref: a blob-stream slice was never read — completeness is withheld" );
        }
    }
}

// The DISTINCT (a,b) object-name pairs the sweep needs diffed, and their rows. Same reasoning the BlobStore
// rests on: a diff between two IMMUTABLE object names is a pure function of that pair, so asking twice can
// only ever spend a process for an answer already held. It pays because the sweep genuinely repeats itself —
// diff(base, HEAD) is re-derived once per ref and refs sharing a merge-base (N branches off one trunk commit)
// share that pair verbatim. Measured on a 35-ref repo: 72 diffRaw calls for only 66 distinct pairs.
//
// Registration (`want`) is SERIAL by contract and `run()` is the only parallel part, so there is no lock
// anywhere: pairs are addressed by a 32-bit index into storage that is fully sized before any worker starts,
// and each worker writes exactly one slot.
class DiffPairTable
{
public:
    // Register a pair, returning its stable index. Serial by contract — planning pass only.
    std::uint32_t want( const std::string& a, const std::string& b )
    {
        const std::string key = a + ' ' + b;
        const auto        it  = index_.find( key );
        if( it != index_.end() ) { ++reuseCount_; return it->second; }

        const std::uint32_t pairIndex = std::uint32_t( pairs_.size() );
        pairs_.push_back( DiffPair{ a, b } );
        index_.emplace( key, pairIndex );
        return pairIndex;
    }

    // One `git diff --raw` per DISTINCT registered pair, across the pool.
    void run( const std::string& root )
    {
        rows_.resize( pairs_.size() );
        ParallelSweep sweep;
        parallelIndexed( pairs_.size(), [ & ]( std::size_t i ) { rows_[i] = diffRaw( root, pairs_[i].a, pairs_[i].b ); }, sweep );
        unfinished_.assign( pairs_.size(), 0 );
        for( std::size_t i = 0; i < pairs_.size(); ++i )
        {
            unfinished_[ i ] = sweep.isDone( i ) ? 0 : 1;
        }
    }

    // Was this pair's diff actually RUN? An empty row list is also what a diff nobody ran holds, and it reads as "no
    // change"; a pair a thrown worker never reached is not an answer. kNoPair (no diff needed) is finished.
    bool isFinished( std::uint32_t pairIndex ) const noexcept
    {
        return pairIndex == kNoPair || std::size_t( pairIndex ) >= unfinished_.size() || unfinished_[ pairIndex ] == 0;
    }

    const std::vector<RawRow>& rows( std::uint32_t pairIndex ) const
    {
        static const std::vector<RawRow> kEmpty{};
        if( pairIndex == kNoPair || std::size_t( pairIndex ) >= rows_.size() )
        {
            return kEmpty;
        }
        return rows_[ pairIndex ];
    }

    std::size_t pairCount()  const noexcept { return pairs_.size(); }
    std::size_t reuseCount() const noexcept { return reuseCount_; }

private:
    struct DiffPair { std::string a, b; };

    std::vector<DiffPair>                     pairs_;
    std::vector<std::vector<RawRow>>          rows_;        // sized once in run(), one owner per slot
    std::vector<char>                         unfinished_;  // 1 ⇒ a thrown worker never ran that pair's diff
    gtl::btree_map<std::string, std::uint32_t> index_;
    std::size_t                               reuseCount_ = 0;
};

// ── the stray-content analysis ───────────────────────────────────────────────────────────────────────────

// `Unknown` is the verdict for a ref whose ANALYSIS FAILED (no merge-base: a shallow clone, or genuinely
// unrelated histories) — deliberately its own value rather than a fallback onto `Merged`. A failed analysis
// must never render as the reassuring answer: "merged" on a ref nobody could analyse reads as "this branch
// holds nothing you need", which is exactly the claim the evidence does NOT support. It sits LAST so the
// three real verdicts keep their existing numeric values.
enum class Verdict : std::uint8_t { Merged = 0, Superseded, Unmerged, Unknown };

constexpr std::size_t kVerdictCount = 4;
static_assert( enumCountIsExact<Verdict, kVerdictCount>(), "kVerdictCount must equal the Verdict count — raise it with the append" );

inline const char* verdictTag( Verdict v ) noexcept
{
    // The extent is DEDUCED: the old `kTag[ kVerdictCount ]` made the size assert below restate its own declaration, and
    // a missing tag would have zero-filled into a null pointer instead of failing.
    static constexpr const char* kTag[] = { "merged", "superseded", "unmerged", "unknown" };
    static_assert( std::size( kTag ) == kVerdictCount, "verdictTag table must cover every Verdict" );
    ASSUME( std::size_t( v ) < kVerdictCount );
    return kTag[ std::size_t( v ) ];
}

// One path's answer within one ref.
struct FileRow
{
    std::string   path;
    std::uint32_t strayLines = 0;      // lines the ref AUTHORED that HEAD does not have
    std::uint32_t authored   = 0;      // lines the ref authored vs its base (the denominator for context)
    std::uint32_t deleted    = 0;      // base lines the ref removed  (0 ⇒ pure addition, no deletion site)
    std::uint32_t redone     = 0;      // …of which HEAD removed too  (the supersession evidence)
    float         sim        = 0.0f;   // minhash containment of the ref's blob in HEAD's blob
    bool          headTouched = false; // did the live line change this path at all since the base?
    bool          diffable    = true;  // false ⇒ binary/oversized on some side; counts are not meaningful
    Verdict       verdict     = Verdict::Merged;
};

struct RefRow
{
    RefInfo                ref;
    std::string            base;             // merge-base(ref, HEAD)
    bool                   ok = true;        // false ⇒ no merge-base (shallow clone / unrelated history) — reported,
                                             //          never dropped, and verdict is forced to Unknown, never Merged
    std::uint32_t          strayLines = 0;
    std::uint32_t          strayFiles = 0;
    std::uint32_t          supersededLines = 0;
    Verdict                verdict = Verdict::Merged;
    std::vector<FileRow>   files;            // stray/superseded files only, sorted by strayLines desc then path
};

struct StrayResult
{
    bool                 ok = true;
    bool                 nonGitRoot = false;
    bool                 tooManyRefs = false;
    // H7 (capture-audit 2026-09-04): the --stray-content=SUBSTR filter named no local ref at all. refs="0"
    // unknown="0" at exit 0 reads as "no branch carries stray work" — the most reassuring possible answer,
    // from a sweep that never happened. ok=false, so the caller refuses in the --doc-drift/--dead-code words.
    bool                 filterMatchedNothing = false;
    std::string          filter;                // H14/M6: the --stray-content=SUBSTR this sweep was narrowed by ("" = none)
    std::string          headSha;
    std::string          headRef;
    std::string          atStamp;               // M10: gitstamp::stampAt(root) — head= above stays a bare 9-hex sha
                                                  // (gitstampcheck.sh's --abi/landing-plan arms pin that spelling);
                                                  // at= is the new attribute carrying the dirty bit.
    std::size_t          distinctBlobs = 0;
    std::size_t          refsScanned   = 0;
    std::uint32_t        mergedRefs    = 0;   // scanned, found fully present on the live line, and OMITTED below
    // refs for-each-ref listed that enumerateRefs DROPPED (a tip that is not an object name): in none of the counts
    // above, so while it is non-zero refs= and the four buckets describe a sweep that skipped them — refs_dropped= says so.
    std::uint32_t        refsDropped   = 0;
    std::vector<RefRow>  refs;                // only refs with stray content — merged ones are noise in a 30-ref sweep
};

// Per-file verdict from the two evidences. Split out of analyzeRef so the rule is one readable expression
// that a test can pin directly, and so the ordering of the lanes (deletion-site FIRST, minhash only as the
// pure-addition fallback) is visible rather than buried in a chain of ifs.
inline Verdict classifyFile( const FileRow& r )
{
    // `redone` counts a SUBSET of `deleted` (base lines this ref removed that HEAD removed too), so a
    // redone > deleted would mean the intersection out-counted one of its own operands — a corrupt
    // multiset walk, and it would push redoDel above 1.0 and silently mark the file superseded.
    ASSUME( r.redone <= r.deleted );

    if( r.strayLines == 0 )
    {
        return Verdict::Merged;
    }

    if( r.deleted > 0 )
    {
        const float redoDel = float( r.redone ) / float( r.deleted );
        return ( redoDel >= kRedoDelMin ) ? Verdict::Superseded : Verdict::Unmerged;
    }

    // Pure addition: no deletion site to compare, so the only remaining evidence that the live line already
    // holds this content is a HIGH minhash containment over a body big enough for that to mean something.
    if( r.headTouched && r.sim >= kSimSupersede && r.strayLines >= kSimMinStray )
    {
        return Verdict::Superseded;
    }
    return Verdict::Unmerged;
}

// Everything one ref's analysis needs FROM GIT, gathered before any blob is reduced. Splitting this out of
// the analysis proper is what lets the expensive, perfectly-parallel part (fork/exec) and the part that must
// stay deterministic and serial (the multiset arithmetic) stop interleaving — and it is what collapses the
// per-ref `git cat-file --batch` into ONE batch for the whole sweep.
struct RefPlumbing
{
    std::string   base;                        // merge-base(ref, HEAD); empty ⇒ analysis failed
    bool          ok           = true;
    bool          isAncestor   = false;        // ref.tip == base: the ref is fully on the live line already
    std::uint32_t refDiffPair  = kNoPair;      // DiffPairTable index for diff(base, ref.tip)
    std::uint32_t headDiffPair = kNoPair;      // DiffPairTable index for diff(base, HEAD)

    gtl::btree_map<std::string, std::string> headBlobAt;   // path → HEAD's blob, for the paths HEAD changed

    // The DISCLOSE sink for the probe's degrades: a failed probe renders ok="0" v="unknown", never a verdict.
    enum class DisclosureWhy : std::uint8_t
    {
        RevisionNotObjectName,    // the ref tip or HEAD is not a resolved object name: not probed
        MergeBaseNotObjectName,   // git's merge-base answer is not an object name: discarded, read as no merge-base
        NoMergeBase,              // shallow clone or unrelated history
    };
    void disclose( DisclosureWhy why ) noexcept
    {
        switch( why )
        {
            case DisclosureWhy::RevisionNotObjectName:
            case DisclosureWhy::NoMergeBase:            ok = false; break;
            case DisclosureWhy::MergeBaseNotObjectName: base.clear(); break;
        }
    }
};

// The merge-base probe — the one git call that must happen before the diff pairs are even known, and the
// only one in this phase. Runs on the pool: refs are independent and each writes its own slot.
inline RefPlumbing probeRefBase( const std::string& root, const RefInfo& ref, const std::string& headSha )
{
    RefPlumbing plumb;
    if( !isRevisionToken( ref.tip ) || !isRevisionToken( headSha ) )
    {
        DISCLOSE( plumb, RefPlumbing::DisclosureWhy::RevisionNotObjectName, "crossref: ref tip or HEAD is not a resolved object name — refusing to probe, verdict is unknown" );
        return plumb;
    }

    plumb.base = quality::gitOneLine( root, "merge-base " + shSingleQuote( ref.tip ) + " " + shSingleQuote( headSha ) + " -- 2>/dev/null" );

    // The ANSWER is validated too, not just the question. It is git's own output today and therefore
    // well-formed — but that is an assumption, and this sha goes straight back out as the revision argument
    // to two more git commands. Anything that is not an object name is treated exactly like no merge-base.
    if( !plumb.base.empty() && !isRevisionToken( plumb.base ) )
    {
        DISCLOSE( plumb, RefPlumbing::DisclosureWhy::MergeBaseNotObjectName, "crossref: merge-base returned something that is not an object name — discarding it" );
    }
    if( plumb.base.empty() )
    {
        // No merge-base: a SHALLOW clone (actions/checkout is shallow by default, so this is the CI default,
        // not an exotic case) or genuinely unrelated histories. Degrade, never crash — and the verdict this
        // produces is Unknown, never Merged: see writeStrayRef and Verdict's own comment.
        DISCLOSE( plumb, RefPlumbing::DisclosureWhy::NoMergeBase, "crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged" );
        return plumb;
    }
    // ref.tip == base ⇒ the ref is an ANCESTOR of HEAD, so diff(base, ref.tip) is a diff of a tree against
    // itself: provably empty, hence nothing authored, hence merged. Both of this ref's diffs are skipped —
    // 20 of the measured repo's 72 `diff --raw` calls were exactly this `diff A A`.
    plumb.isAncestor = ( ref.tip == plumb.base );
    return plumb;
}

// One ref's whole answer, computed from ALREADY-FETCHED plumbing and an ALREADY-FILLED blob store. Pure:
// no git call, no I/O, no shared mutable state — so the verdict is a function of the evidence and nothing
// else. `plumb.headBlobAt` is diff(base, HEAD) indexed by path — the live line's own change over the SAME
// base, which is what makes the deletion sets directly comparable.
inline RefRow analyzeRef( const RefInfo& ref, const RefPlumbing& plumb, const std::vector<RawRow>& refDiff,
                          const BlobStore& blobs )
{
    RefRow row;
    row.ref  = ref;
    row.base = plumb.base;
    if( !plumb.ok )
    {
        row.ok      = false;
        row.verdict = Verdict::Unknown;      // NEVER Merged — a failed analysis is not a reassuring answer
        return row;
    }

    const gtl::btree_map<std::string, std::string>& headBlobAt = plumb.headBlobAt;

    for( const RawRow& r : refDiff )
    {
        const auto        hIt        = headBlobAt.find( r.path );
        const bool        headTouched = hIt != headBlobAt.end();
        const std::string headSide   = headTouched ? hIt->second : r.aSha;    // unchanged by HEAD ⇒ still the base blob
        if( r.bSha == headSide )
        {
            continue; // byte-identical on the live line
        }

        const BlobFacts& base = blobs.get( r.aSha );
        const BlobFacts& mine = blobs.get( r.bSha );
        const BlobFacts& live = blobs.get( headSide );

        FileRow f;
        f.path        = r.path;
        f.headTouched = headTouched;
        f.diffable    = mine.isText && base.isText && live.isText;
        if( !f.diffable )
        {
            // A binary/oversized side cannot be line-diffed. Report the path with counts zeroed and
            // diffable="0" rather than dropping it — an unreported path reads as "nothing here".
            f.verdict = isNullSha( headSide ) ? Verdict::Unmerged : Verdict::Merged;
            if( f.verdict == Verdict::Unmerged ) { row.files.push_back( std::move( f ) ); ++row.strayFiles; }
            continue;
        }

        const std::vector<std::uint64_t> authored = msetDiff( mine.lineHashes, base.lineHashes );
        const std::vector<std::uint64_t> removed  = msetDiff( base.lineHashes, mine.lineHashes );
        const std::vector<std::uint64_t> headGone = msetDiff( base.lineHashes, live.lineHashes );

        f.authored   = std::uint32_t( authored.size() );
        f.deleted    = std::uint32_t( removed.size() );
        f.redone     = std::uint32_t( sortedIntersectSize( removed, headGone ) );
        f.strayLines = std::uint32_t( countAbsent( authored, live.lineHashes ) );
        f.sim        = sketchContainment( mine.sketch, live.sketch );
        f.verdict    = classifyFile( f );

        if( f.verdict == Verdict::Merged )
        {
            continue; // the live line has this work
        }

        row.strayLines += f.strayLines;
        if( f.verdict == Verdict::Superseded )
        {
            row.supersededLines += f.strayLines;
        }
        ++row.strayFiles;
        row.files.push_back( std::move( f ) );
    }

    std::sort( row.files.begin(), row.files.end(), []( const FileRow& a, const FileRow& b )
               { return a.strayLines != b.strayLines ? a.strayLines > b.strayLines : a.path < b.path; } );

    // Ref verdict: the stray-LINE-weighted share that the live line has demonstrably revisited. Weighting by
    // lines (not by file count) is what stops one coincidentally-shared deleted line in a mostly-additive
    // file from vouching for the hundreds of added lines around it.
    if( row.strayLines == 0 )
    {
        row.verdict = Verdict::Merged;
    }
    else if( float( row.supersededLines ) / float( row.strayLines ) >= kRefSupersedeMin )
    {
        row.verdict = Verdict::Superseded;
    }
    else
    {
        row.verdict = Verdict::Unmerged;
    }
    return row;
}

// Phases 2-3 of the sweep: plan the DISTINCT diffs it needs, then run them across the pool. A provably-empty
// diff is never asked for (isAncestor) and a pair two refs share is asked for once, so the process count is
// the number of distinct QUESTIONS, not the number of refs times two.
inline DiffPairTable gatherRefDiffs( const std::string& root, const std::vector<RefInfo>& refs,
                                     const std::string& headSha, std::vector<RefPlumbing>& plumbing )
{
    ASSUME( plumbing.size() == refs.size() );

    DiffPairTable diffs;
    for( std::size_t i = 0; i < refs.size(); ++i )
    {
        if( !plumbing[i].ok || plumbing[i].isAncestor )
        {
            continue;
        }
        plumbing[i].refDiffPair  = diffs.want( plumbing[i].base, refs[i].tip );
        plumbing[i].headDiffPair = diffs.want( plumbing[i].base, headSha );
    }
    diffs.run( root );
    return diffs;
}

// Phase 4: index HEAD's side per ref, then register every blob the WHOLE sweep needs so they all ride ONE
// `git cat-file --batch`. This is the batching the BlobStore was built for and the old per-ref loop quietly
// defeated — it called fill() inside each ref's analysis, so a 35-ref sweep paid 16 separate batch processes.
inline void registerSweepBlobs( const DiffPairTable& diffs, std::vector<RefPlumbing>& plumbing, BlobStore& blobs )
{
    for( RefPlumbing& plumb : plumbing )
    {
        if( !plumb.ok || plumb.isAncestor )
        {
            continue;
        }

        for( const RawRow& h : diffs.rows( plumb.headDiffPair ) )
        {
            plumb.headBlobAt.emplace( h.path, h.bSha );
        }
        for( const RawRow& r : diffs.rows( plumb.refDiffPair ) )
        {
            blobs.want( r.aSha );
            blobs.want( r.bSha );
            const auto h = plumb.headBlobAt.find( r.path );
            blobs.want( ( h != plumb.headBlobAt.end() ) ? h->second : r.aSha );   // HEAD's blob == base's unless HEAD touched it
        }
    }
    blobs.fill();
}

inline StrayResult computeStrayContent( const std::string& root, std::string_view filter )
{
    StrayResult result;
    result.filter = std::string( filter );   // H14/M6: echoed on the root — a count under a filter is not a repo total
    if( !quality::gitRepoHasHistory( root ) ) { result.ok = false; result.nonGitRoot = true; return result; }

    result.headSha = quality::gitHeadSha( root );
    result.atStamp = gitstamp::stampAt( root );   // M10: same anchor as every other repo-reading root, dirty bit included
    result.headRef = quality::gitOneLine( root, "rev-parse --abbrev-ref HEAD 2>/dev/null" );

    std::size_t                filterNameHits = 0;
    RefEnumeration             enumeration;   // a dropped ref is in no count below, so the root discloses it (refs_dropped=)
    const std::vector<RefInfo> refs = enumerateRefs( root, filter, result.headSha, &filterNameHits, &enumeration );
    result.refsDropped = enumeration.refsDropped;
    result.filterMatchedNothing = !filter.empty() && filterNameHits == 0;
    if( result.filterMatchedNothing ) { result.ok = false; return result; }
    if( refs.size() > kMaxRefs ) { result.ok = false; result.tooManyRefs = true; return result; }

    // ── phase 1: the merge-base probe, one git call per ref, ACROSS THE POOL ────────────────────────────
    // Refs are independent and each worker writes only its own slot, so this is the serial answer computed
    // in parallel — not a different answer.
    std::vector<RefPlumbing> plumbing( refs.size() );
    ParallelSweep            probeSweep;
    parallelIndexed( refs.size(), [ & ]( std::size_t i ) { plumbing[i] = probeRefBase( root, refs[i], result.headSha ); }, probeSweep );
    for( std::size_t i = 0; i < refs.size(); ++i )
    {
        plumbing[ i ].ok = plumbing[ i ].ok && probeSweep.isDone( i );   // a probe never run is a failed analysis, not a default
    }

    // ── phases 2-4: the distinct diffs, then ONE batched blob read for the whole sweep ───────────────────
    const DiffPairTable diffs = gatherRefDiffs( root, refs, result.headSha, plumbing );
    for( RefPlumbing& plumb : plumbing )
    {
        plumb.ok = plumb.ok && diffs.isFinished( plumb.refDiffPair ) && diffs.isFinished( plumb.headDiffPair );
    }

    BlobStore blobs( root );
    registerSweepBlobs( diffs, plumbing, blobs );

    // ── phase 5: the analysis proper — pure, serial, deterministic ──────────────────────────────────────
    // A ref whose work is entirely on the live line is the boring, common case — in a 30-branch sweep it is
    // most of them, and printing a row per ref would bury the handful that matter. Omit them from the body
    // but COUNT them in the header (merged=) so the sweep's coverage is still stated, never implied. A ref
    // whose analysis FAILED is never omitted: it is not known to be merged, which is the whole point.
    for( std::size_t i = 0; i < refs.size(); ++i )
    {
        RefRow row = analyzeRef( refs[i], plumbing[i], diffs.rows( plumbing[i].refDiffPair ), blobs );
        if( row.ok && row.verdict == Verdict::Merged ) { ++result.mergedRefs; continue; }
        result.refs.push_back( std::move( row ) );
    }

    result.refsScanned   = refs.size();
    result.distinctBlobs = blobs.distinctBlobs();

    // Report order: most stray content first (that is the queue the owner works), ties by ref name.
    std::sort( result.refs.begin(), result.refs.end(), []( const RefRow& a, const RefRow& b )
               { return a.strayLines != b.strayLines ? a.strayLines > b.strayLines : a.ref.name < b.ref.name; } );
    return result;
}

// ── --whereis=SYM ────────────────────────────────────────────────────────────────────────────────────────

// One occurrence of SYM in one ref's tree.
struct WhereHit
{
    std::string   ref;
    std::string   tip;
    std::string   date;
    std::string   path;
    std::uint32_t line = 0;
    bool          isDef = false;      // kind="def": HEAD's from the index (or, head_labels="lexical", definitionShaped); another
                                      //   ref's from the tags parse of its blob (labelBranchRowsByParse)
    std::string   text;               // the trimmed source line (evidence, so the caller can judge)
    bool          fromWorktree = false;   // read from the WORKING-TREE copy of a path that differs from HEAD (ref="worktree")
    bool          testLocal    = false;   // a TEST-LOCAL definition, demoted below the production ones (test_local="1")
    bool          unconfirmed  = false;   // kind="text": another ref's PARSE-WORTHY row whose blob was not parsed (the
                                          //   runaway guard, or a parse that could not finish) — never kind="def", never a ref
    bool          parseWorthy  = false;   // parseWorthyLine(): this line makes its blob worth a tags parse (another ref's rows)
    // foldSharedBranchDefs: a kind="def" row outside the checkout whose (path, line text) other refs hold too is ONE
    // definition held by N refs. The first row of such a group (lowest ref name) is its representative and carries
    // defRefs = N (1 = this ref alone); every later row of the group is foldedDef and the definitions page skips it
    // (listing=all still prints it). 0 = not a branch definition row.
    std::uint32_t defRefs   = 0;
    bool          foldedDef = false;

    // The CHECKOUT is HEAD's tree overlaid with the working copy of every path that differs from it: those rows
    // sort, label and count as one group, ahead of the other refs. Keyed on the flag, never on the ref name, so a
    // local branch that happens to be NAMED "worktree" is still an ordinary ref.
    bool inCheckout() const noexcept { return fromWorktree || ref == "HEAD"; }
};

// §A7: where the parsed INDEX says SYM is defined — supplied by the caller (both surfaces hold an IngestResult
// and pass whereisIndexDefSites below). `path` is spelled ROOT-RELATIVE, the way git
// spells a tree entry; `line` is the index's 1-based def line.
struct IndexDefSite
{
    std::string   path;
    std::uint32_t line = 0;
    bool          testLocal = false;   // filter.h isTestSymbol: in a test file, or in a test scope of any file
};

// The optional EVIDENCE a caller can hand the tree scan — both members are "extra knowledge this surface
// happens to hold", both default to "not supplied", and both only ever ADD a lane, so they travel as one
// parameter rather than growing computeWhereis' argument list once per lane.
struct WhereisEvidence
{
    const gitoracle::HistoryIndex* history   = nullptr;   // --with-history: the name-history oracle (nullptr ⇒ not asked for)
    std::span<const IndexDefSite>  indexDefs = {};        // §A7: where the parsed index defines SYM (empty ⇒ label HEAD lexically)
};

// §A7: every place the parsed index defines `name`, keyed the way git spells a tree entry (model.h::relForHash
// — the SAME root-relative join --abi uses to match ing.files against git paths). This is what lets whereis
// stop GUESSING on HEAD rows: the tree scan reads committed blobs, the index knows where the definitions are,
// and the join is a single pass over the symbol table with no extra I/O. ONE helper for both surfaces: the MCP
// twin used to pass none, and labelled a wrapped call site kind="def" where the CLI said "ref" (0.6.6 sweep).
inline std::vector<IndexDefSite> whereisIndexDefSites( const IngestResult& ing, std::string_view name, const std::string& root )
{
    std::vector<IndexDefSite> sites;
    for( const Symbol& s : ing.symbols )
    {
        if( s.name == name )
        {
            sites.push_back( IndexDefSite{ std::string( relForHash( ing.files[ s.fileId ], root ) ), s.line,
                                           isTestSymbol( ing, std::size_t( &s - ing.symbols.data() ) ) } );
        }
    }
    return sites;
}

// What the scan learned about the WORKING TREE under the root (the 2026-10-01 freshness fix). The answer used
// to read committed trees only and still claimed complete= on a dirty checkout, so a just-added function read
// hits="0" and a just-deleted one kept its HEAD lines. Now every path that differs from HEAD is read from disk.
// The ORDER is load-bearing: computeWhereis reads `state <= Read` as "every HEAD row kept is the checkout's content".
//   Clean     nothing under the root differs from HEAD — the committed scan IS the checkout (byte-identical output)
//   Read      every differing path was read (or is gone); its rows are ref="worktree" and replace HEAD's
//   Partial   some differing path could not be read; ITS HEAD rows stand and may be stale — complete= is withheld
//   Unlisted  git could not list what differs; every HEAD row may be stale — complete= is withheld
enum class WorktreeOverlay : std::uint8_t { Clean, Read, Partial, Unlisted };

// How the OTHER refs' rows got their kind= (labelBranchRowsByParse), counted per distinct (blob, path) — the unit one
// parse answers. `leftByGuard` and `failed` are the pairs that confirm nothing: their parse-worthy rows are the
// `textRows` (kind="text"), and the page discloses all three in one <unparsed> element.
struct BranchLabelCensus
{
    std::size_t parsed      = 0;   // parsed by the tags path (definitionLinesInBlobs)
    std::size_t mirrored    = 0;   // HEAD's own blob at the same path: HEAD's index labels, line for line
    std::size_t leftByGuard = 0;   // parse-worthy, but past kWhereisParseMaxBlobs / kWhereisParseMaxBytes
    std::size_t failed      = 0;   // parse-worthy, but the parser could not finish (BlobDefsStatus::Failed)
    std::size_t textRows    = 0;   // rows of those two that read kind="text"
};

struct WhereResult
{
    bool                  ok = true;
    bool                  nonGitRoot = false;
    std::string           sym;
    std::string           headSha;
    bool                  onHead = false;     // SYM occurs in HEAD's tree
    bool                  headLabelsFromIndex = false;   // §A7: HEAD rows' kind= came from the index, not the shape test
    BranchLabelCensus     branchLabels;      // how the OTHER refs' rows got kind= (labelBranchRowsByParse; <unparsed> on the page)
    std::size_t           refsScanned = 0;
    std::size_t           distinctBlobs = 0;
    std::string           filter;             // H14/M6: the --stray-filter SUBSTR this scan was narrowed by ("" = none)
    std::vector<WhereHit> hits;
    WorktreeOverlay       worktree = WorktreeOverlay::Clean;   // what the overlay did (worktree= on the root, +dirty on at=)
    bool                  headHolds = false;   // HEAD's COMMITTED tree holds SYM (on-head= reads the CHECKOUT on a dirty tree)
    std::string           dottedRetry;         // a Class.method spelling whose method the INDEX defines: the bare name (caller-set)
    std::string           renamedTo;           // the working tree renamed SYM to this definition (caller-set, on a zero)

    // T1 (completeness claims): true iff the scan PROVABLY covered every text blob of every scanned ref's
    // full tree — no missing/oversized/short-read blob, the batch served every sha, and no ref's tree
    // listing came back empty (an empty listing from a non-empty repo is indistinguishable from a failed
    // `git ls-tree`, so it forfeits the claim rather than risk a false one). Binary blobs do NOT forfeit
    // it: the claim is text-scoped, and a text symbol cannot occur in one. The writer ANDs this with
    // "every hit printed" before emitting complete= on the root.
    bool                  scanExhaustive = false;

    // H7 / lens 6 F5 — the two SELECTOR facts this verb used to swallow, both filled by the caller (they are
    // index questions, and this module is deliberately index-free: it reads git trees, not symbols).
    //   seedSpec  the raw @FILE:LINE spelling, when the selector was a line seed. `--whereis=@src/graph.h:2500`
    //             used to be searched as the LITERAL string "@src/graph.h:2500" across every blob, giving a
    //             true and useless hits="0" shaped exactly like a name this repo never had — while
    //             --owners/--mentions/--edit-check resolve that same grammar. The seed is now resolved to the
    //             enclosing definition's name BEFORE the scan; this echoes what was typed so the answer can
    //             still be tied to the command.
    //   nearMiss  the nearest indexed name, when the scan found nothing and the index knows one. The lexical
    //             zero stays a measurement (a name this repo never had is a real answer); the near-miss is
    //             what tells the reader which of the two zeros they are holding.
    std::string           seedSpec;
    std::string           nearMiss;

    // The --with-history lane: a non-owning view of the caller's oracle index (nullptr ⇒ not asked for) plus
    // THIS symbol's verdict, resolved once at compute time so emission stays a pure print. Views at the seam:
    // the caller owns the index and outlives both calls.
    const gitoracle::HistoryIndex* history = nullptr;
    gitoracle::NameFate            fate;
};

// Whole-word occurrence: SYM not flanked by identifier bytes (so `foo` never matches `foobar`/`myfoo`).
inline bool wholeWordAt( std::string_view hay, std::size_t at, std::size_t len ) noexcept
{
    if( at > 0 && isIdentByte( (unsigned char)hay[at - 1] ) )
    {
        return false;
    }
    if( at + len < hay.size() && isIdentByte( (unsigned char)hay[at + len] ) )
    {
        return false;
    }
    return true;
}

// The declarator END of a definition line, with trailing SPECIFIERS stripped: `noexcept`, cv/ref qualifiers,
// the virtual-override words, a pure/defaulted/deleted tail, and a trailing-return arrow. Returns the index one
// past the last byte that the terminator test below should look at.
//
// §A7 — this is not cosmetic. The house style of this very repo ends nearly every definition in `noexcept`,
// and the terminator test accepted only `{ } ) :`, so `inline Config parseArgs( … ) noexcept` — the real
// definition — read as kind="ref" while 3385 mention-rows outranked it. A shape test that rejects the
// dominant shape of the corpus it runs on is worse than no test.
inline std::size_t declaratorEnd( std::string_view line ) noexcept
{
    static constexpr std::string_view kTrailingSpecifiers[] = {
        "noexcept", "const", "override", "final", "mutable", "volatile", "&&", "&", "= 0", "=0",
        "= default", "= delete",
    };
    std::size_t e = line.size();
    while( e > 0 && std::isspace( (unsigned char)line[e - 1] ) )
    {
        --e;
    }

    for( bool stripped = true; stripped; )                                    // several may stack: `) const noexcept override`
    {
        stripped = false;
        for( std::string_view sp : kTrailingSpecifiers )
        {
            if( e < sp.size() || line.compare( e - sp.size(), sp.size(), sp ) != 0 )
            {
                continue;
            }
            const std::size_t before = e - sp.size();
            // a whole WORD only, so `myconst` / `isFinal` never lose their tail (the operator forms are
            // punctuation and need no boundary).
            if( isIdentByte( (unsigned char)sp.front() ) && before > 0 && isIdentByte( (unsigned char)line[before - 1] ) )
            {
                continue;
            }
            e = before;
            while( e > 0 && std::isspace( (unsigned char)line[e - 1] ) )
            {
                --e;
            }
            stripped = true;
        }
    }

    // a trailing return type (`) -> Result`): cut at the arrow when what precedes it closes the parameter list.
    if( const std::size_t arrow = line.rfind( "->", e ); arrow != std::string_view::npos )
    {
        std::size_t beforeArrow = arrow;
        while( beforeArrow > 0 && std::isspace( (unsigned char)line[beforeArrow - 1] ) )
        {
            --beforeArrow;
        }
        if( beforeArrow > 0 && line[beforeArrow - 1] == ')' )
        {
            e = beforeArrow;
        }
    }
    return e;
}

// Is the occurrence at `at` nested inside a parenthesised ARGUMENT LIST? A definition's own name is always at
// paren depth 0 on its line (`inline T f( … )`); `w.write( escapeXml( s, esc ) );` puts the name at depth 1,
// which is the false-positive class that gave a defs="1" symbol seventeen kind="def" rows.
inline bool insideArgumentList( std::string_view line, std::size_t at ) noexcept
{
    int depth = 0;
    for( std::size_t i = 0; i < at; ++i )
    {
        if( line[i] == '(' )
        {
            ++depth;
        }
        else if( line[i] == ')' && depth > 0 )
        {
            --depth;
        }
    }
    return depth > 0;
}

// Is this line SHAPED like a definition of `sym`? A declarative marker table over the languages ripwire indexes,
// read LEXICALLY over raw text. It labels NO row on another ref: there parseWorthyLine, a looser superset of it, only
// CHOOSES which blobs the tags path parses (labelBranchRowsByParse — a blob with no such row is not parsed, and its rows
// read kind="ref"). Its one
// remaining LABELLING role is HEAD's fallback, head_labels="lexical" (no index def of the name, or a working tree that
// drifted from HEAD). It errs in BOTH directions, and each costs something different in each role:
//   * a quoted signature in a doc, a call on a line ending in `}` or `)` (`if( x ) { f( a ); }`), `go f(a)`, `@f(1)`,
//     `f( a, [&]( int x ) {` read as definition-shaped: a false kind="def" on the HEAD fallback (as a chooser, one
//     wasted parse that then labels the row a reference);
//   * a definition it does not shape — a signature wrapped before its `)` or ending in `,`, a declarator followed by a
//     comment, `fun f(x) = x + 1`, `export const f = (a) =>`, a `name() {` at column 0 — reads as a reference: on the
//     HEAD fallback a definition missing from the definitions page (counted among the refs). parseWorthyLine takes the
//     cheap ones of these back in for the chooser; the rest stay a disclosed floor there too.
// A stricter reading of the line only trades one error for the other (the round-1 prefix and tail rules lost
// `#define NAME(`, `decltype(auto) NAME(`, `@Test(…) public void NAME()` …): the parser is the fix, not the line.
inline bool definitionShaped( std::string_view line, std::string_view sym, std::size_t at )
{
    static constexpr std::string_view kDeclMarkers[] = {
        "class ", "struct ", "enum ", "union ", "interface ", "namespace ", "trait ", "impl ", "protocol ",
        "def ", "func ", "fn ", "function ", "type ", "typedef ", "using ", "template", "extension ",
    };
    for( std::string_view m : kDeclMarkers )
    {
        if( line.find( m ) != std::string_view::npos && line.find( m ) < at )
        {
            return true;
        }
    }

    // A C-family definition: the name is immediately followed by '(', something precedes it on the line (the
    // return type / qualified scope), it is not a member call on a receiver, it is not itself an ARGUMENT
    // (§A7), and the line does NOT end in ';' — a trailing ';' is a prototype or a call statement, both of
    // which are references, not definitions. The accepted terminators are '{' (body opens here), '}' (whole
    // one-line body), ')' (signature wraps to the next line) and ':' (a constructor's init list follows),
    // tested AFTER declaratorEnd() has stripped any trailing specifier tail.
    const std::size_t after = at + sym.size();
    if( after < line.size() && line[ after ] == '(' )
    {
        const std::size_t e = declaratorEnd( line );
        const char last     = ( e > 0 ) ? line[ e - 1 ] : ';';
        const bool endsDecl = last == '{' || last == '}' || last == ')' || last == ':';
        const bool isCall   = at >= 1 && ( line[ at - 1 ] == '.' || ( at >= 2 && line[ at - 2 ] == '-' && line[ at - 1 ] == '>' ) );
        return endsDecl && !isCall && at > 0 && !insideArgumentList( line, at );
    }
    // ObjC method: "- (ret) sym" / "+ (ret) sym"
    if( !line.empty() && ( line[0] == '-' || line[0] == '+' ) && line.find( ')' ) < at )
    {
        return true;
    }
    return false;
}

// Does this line make its blob worth a tags PARSE (labelBranchRowsByParse)? A deliberately LOOSE superset of
// definitionShaped(), because the two errors cost different things here: a wrong "yes" costs one parse, which then
// labels the row a reference; a wrong "no" leaves a definition unparsed when it is the only such line of its blob, and
// that definition reads kind="ref". So the shape test's own misses that are cheap to take in are taken in:
//   * a comment after the declarator (`int f( int a ) { // note`, `#define f( a ) ( a ) /* note */`): retried without it;
//   * the name opening the line (`f() {` in a shell script, a GNU-style C signature `f (int a)` under its return type);
//   * the name bound by `=` to a function, an arrow or a lambda (`export const f = (a) =>`, `f = function (`, `f = lambda`);
//   * Kotlin's `fun ` marker (`fun f(x) = x + 1`);
//   * a markdown heading that opens with the name (`## f`): the index makes a section symbol of it.
// What is still missed is named in definitionShaped's header (a signature wrapped before its parameter list closes, a
// name alone on a line with only a type above it…); those definitions stay counted refs when nothing else in their
// blob earns it a parse.
inline bool parseWorthyLine( std::string_view line, std::string_view sym, std::size_t at )
{
    if( at == 0 || definitionShaped( line, sym, at ) )
    {
        return true;
    }
    const std::size_t after = at + sym.size();
    for( const std::string_view opener : { std::string_view( "//" ), std::string_view( "/*" ), std::string_view( " #" ) } )
    {
        const std::size_t c = line.find( opener, after );
        if( c != std::string_view::npos && definitionShaped( line.substr( 0, c ), sym, at ) )
        {
            return true;
        }
    }
    std::size_t k = after;
    while( k < line.size() && std::isspace( (unsigned char)line[ k ] ) )
    {
        ++k;
    }
    if( k + 1 < line.size() && line[ k ] == '=' && line[ k + 1 ] != '=' && line[ k + 1 ] != '>' )
    {
        std::size_t v = k + 1;
        while( v < line.size() && std::isspace( (unsigned char)line[ v ] ) )
        {
            ++v;
        }
        const std::string_view rhs = line.substr( v );
        if( rhs.starts_with( "(" ) || rhs.starts_with( "function" ) || rhs.starts_with( "async" ) || rhs.starts_with( "lambda" ) )
        {
            return true;
        }
    }
    const std::size_t fun = line.find( "fun " );
    if( fun != std::string_view::npos && fun < at )
    {
        return true;
    }
    const std::size_t hashes = line.find_first_not_of( " \t" );   // `#`s, then spaces, then the name: a heading
    std::size_t       h      = hashes;
    while( h < at && line[ h ] == '#' )
    {
        ++h;
    }
    return hashes != std::string_view::npos && h > hashes && h < at && line.find_first_not_of( " \t", h ) == at;
}

// Record every whole-word occurrence of `sym` in one blob's bytes, as (line number, trimmed line).
// One line's worth of the scan, split out so the line WALK below can stay a plain segmentation with no
// duplicated body — the duplication is what let the final-line case drift out of sync in the first place.
inline void scanLineForSymbol( std::string_view line, std::string_view sym, const RefInfo& ref,
                               const std::string& path, std::uint32_t lineNo, std::vector<WhereHit>& out )
{
    for( std::size_t at = line.find( sym ); at != std::string_view::npos; at = line.find( sym, at + 1 ) )
    {
        if( !wholeWordAt( line, at, sym.size() ) )
        {
            continue;
        }
        std::size_t a = 0, b = line.size();
        while( a < b && std::isspace( (unsigned char)line[a] ) )
        {
            ++a;
        }
        while( b > a && std::isspace( (unsigned char)line[b - 1] ) )
        {
            --b;
        }
        WhereHit& h   = out.emplace_back( WhereHit{ ref.name, ref.tip, ref.date, path, lineNo,
                                                    definitionShaped( line, sym, at ), std::string( line.substr( a, b - a ) ), false } );
        h.parseWorthy = parseWorthyLine( line, sym, at );
        return;                                                               // one hit per line — the line IS the evidence
    }
}

// Record every whole-word occurrence of `sym` in one blob's bytes, as (line number, trimmed line).
//
// The walk is driven by the SEGMENT, not by the terminator: a blob whose last line has no trailing '\n' is
// perfectly legal git content, and evaluating only on '\n' silently skipped it. A symbol defined on that
// final line then reported hits="0" — which this verb's own help text tells the reader means "this repo
// never had the name", the single most misleading answer it can give.
//
// The walk is OCCURRENCE-driven, not line-driven: one search finds the next occurrence of `sym` anywhere in the
// blob, the newlines skipped over are counted (the line number) and only the line holding the occurrence is handed
// to scanLineForSymbol — a line without the symbol is never visited on its own. The line-by-line walk this replaces
// paid two searches per line (the newline, then the symbol) over every line of every blob that held the symbol at
// all, and on a 153-ref repo that was the larger half of a 22 s --whereis. Same hits, same order, one per line.
inline void scanBlobForSymbol( std::string_view bytes, std::string_view sym,
                               const RefInfo& ref, const std::string& path, std::vector<WhereHit>& out )
{
    std::size_t   lineStart = 0;   // the first byte of the line that holds `counted`
    std::size_t   counted   = 0;   // every newline before this offset is in lineNo
    std::uint32_t lineNo    = 1;
    for( std::size_t pos = bytes.find( sym ); pos != std::string_view::npos; pos = bytes.find( sym, lineStart ) )
    {
        lineNo += std::uint32_t( std::count( bytes.begin() + std::ptrdiff_t( counted ), bytes.begin() + std::ptrdiff_t( pos ), '\n' ) );
        if( const std::size_t nl = bytes.rfind( '\n', pos ); nl != std::string_view::npos && nl >= counted )
        {
            lineStart = nl + 1;
        }
        std::size_t end = bytes.find( '\n', pos );
        if( end == std::string_view::npos )
        {
            end = bytes.size();   // a final line with no trailing '\n' is legal git content and is scanned like any other
        }
        scanLineForSymbol( bytes.substr( lineStart, end - lineStart ), sym, ref, path, lineNo, out );
        if( end >= bytes.size() )
        {
            break;
        }
        ++lineNo;                                                             // the line is done: one hit per line
        lineStart = end + 1;
        counted   = lineStart;
    }
}

// Every (path, blob) in one ref's tree. `git ls-tree -r` is one process per ref and the ONLY tree-wide call
// --whereis makes; the blobs behind it are shared across refs and reduced once each.
inline std::vector<RawRow> lsTree( const std::string& root, const std::string& rev )
{
    if( !isRevisionToken( rev ) )
    {
        DISCLOSE( "crossref: refusing to list a tree whose revision argument is not a resolved object name" );
        return {};
    }
    const std::string raw = gitCapture( root, "ls-tree -r " + shSingleQuote( rev ) + " -- 2>/dev/null" );
    std::vector<RawRow> out;
    for( std::string_view line : splitLines( raw ) )
    {
        const std::size_t tab = line.find( '\t' );
        if( tab == std::string_view::npos )
        {
            continue;
        }
        const std::vector<std::string_view> f = wsdetail::segmentsOf( line.substr( 0, tab ), ' ' );
        if( f.size() < 3 || f[1] != "blob" || !isBlobSha( f[2] ) )
        {
            continue;
        }
        out.push_back( RawRow{ std::string( line.substr( tab + 1 ) ), std::string{}, std::string( f[2] ) } );
    }
    return out;
}

// ── every ref's full tree from content-addressed tree objects (listTreesOfRefs) ───────────────────────────
//
// lsTree above spawns one `git ls-tree -r` per ref. Measured on ripwire's 162 local refs at load 25: that phase was
// 16.5 s of a 31 s --whereis (process start-up under load, each process re-listing subtrees most refs share). Trees are
// content-addressed, so a level-order walk reads each DISTINCT tree object ONCE — all of one level through one
// `git cat-file --batch` — and every ref's listing is rebuilt from those objects in ls-tree's own order (a tree's
// stored entry order, recursing in place) and spelling (gitQuotedPath: core.quotepath=false, as gitCapture runs it).
// Anything this walk cannot read exactly — a root that is not the top of the work tree, an object git does not
// serve, a malformed tree — returns nullopt and the caller lists with lsTree instead: the same rows, only slower.
struct GitTreeEntry
{
    std::string name;
    std::string sha;
    bool        isTree = false;   // a subtree; otherwise a blob of any mode (file, executable, symlink) — ls-tree's "blob"
};

// ls-tree's path spelling under core.quotepath=false: a path holding a control byte, `"` or `\` is written as a C
// string — quoted, with \a \b \t \n \v \f \r \" \\ and three-digit octal for the other control bytes and DEL — and every
// other path (bytes >= 0x80 included) is written as is (git quote.c, cq_lookup).
inline std::string gitQuotedPath( std::string_view path )
{
    const auto needs = []( unsigned char c ) noexcept { return c < 0x20 || c == '"' || c == '\\' || c == 0x7f; };
    if( std::none_of( path.begin(), path.end(), [ & ]( char c ) { return needs( (unsigned char)c ); } ) )
    {
        return std::string( path );
    }
    std::string out = "\"";
    for( const char ch : path )
    {
        const unsigned char c = (unsigned char)ch;
        static constexpr std::string_view kLetters = "abtnvfr";   // \a \b \t \n \v \f \r for bytes 7..13
        if( c >= 7 && c <= 13 )
        {
            out += '\\';
            out += kLetters[ c - 7 ];
        }
        else if( c == '"' || c == '\\' )
        {
            out += '\\';
            out += ch;
        }
        else if( needs( c ) )
        {
            const char oct[] = { '\\', char( '0' + ( c >> 6 ) ), char( '0' + ( ( c >> 3 ) & 7 ) ), char( '0' + ( c & 7 ) ) };
            out.append( oct, sizeof( oct ) );
        }
        else
        {
            out += ch;
        }
    }
    out += '"';
    return out;
}

// Parse one tree object: `<octal mode> <name>\0<raw id>` repeated. The raw id is 20 bytes for a SHA-1 repository and
// 32 for SHA-256; `idBytes` comes from the hex length of the tree's own name. False on any malformed entry (external
// input: VALIDATEd, never assumed). Gitlinks (mode 160000, a submodule's commit) are skipped, as ls-tree's blob filter does.
inline bool parseGitTree( std::string_view bytes, std::size_t idBytes, std::vector<GitTreeEntry>& out )
{
    static constexpr std::string_view kHex = "0123456789abcdef";
    std::size_t pos = 0;
    while( pos < bytes.size() )
    {
        const std::size_t sp  = bytes.find( ' ', pos );
        const std::size_t nul = sp == std::string_view::npos ? sp : bytes.find( '\0', sp + 1 );
        if( !VALIDATE( nul != std::string_view::npos && nul + 1 + idBytes <= bytes.size() ) )   // an entry cut short: not a tree we can read
        {
            return false;
        }
        const std::string_view mode = bytes.substr( pos, sp - pos );
        GitTreeEntry           e;
        e.name.assign( bytes.substr( sp + 1, nul - sp - 1 ) );
        e.isTree = mode == "40000";
        e.sha.reserve( idBytes * 2 );
        for( std::size_t k = 0; k < idBytes; ++k )
        {
            const unsigned char b = (unsigned char)bytes[ nul + 1 + k ];
            e.sha += kHex[ b >> 4 ];
            e.sha += kHex[ b & 15 ];
        }
        pos = nul + 1 + idBytes;
        if( mode != "160000" )
        {
            out.push_back( std::move( e ) );
        }
    }
    return true;
}

// One `git cat-file --batch` over `shas` (in order): onObject( sha, type, bytes ) per object. False when the batch did not
// serve every object in full (a start failure, a missing object, a short read): the caller then cannot trust its walk.
template<class OnObject>
inline bool catFileBatch( const std::string& root, const std::vector<std::string>& shas, OnObject onObject )
{
    if( shas.empty() )
    {
        return true;
    }
    static std::atomic<std::uint64_t> listSeq{ 0 };
    const std::string listPath = quality::cacheDirLadder() + "/ripwire-crossref-trees-" + std::to_string( os::getpid() ) + "-"
                               + std::to_string( listSeq.fetch_add( 1, std::memory_order_relaxed ) ) + ".shas";
    {
        std::FILE* lf = std::fopen( listPath.c_str(), "wb" );
        if( !lf )
        {
            return false;
        }
        for( const std::string& s : shas )
        {
            rw::emitTo( lf, "{}\n", s.c_str() );
        }
        std::fclose( lf );
    }
    const std::string cmd  = gitCmd( " -C " ) + shSingleQuote( root ) + " cat-file --batch < " + shSingleQuote( listPath ) + " 2>/dev/null";
    std::FILE*        pipe = os::popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        os::unlink( listPath.c_str() );
        return false;
    }
    bool              ok = true;
    std::string       header;
    std::vector<char> body;
    for( std::size_t served = 0; served < shas.size() && ok; ++served )
    {
        header.clear();
        for( int c = std::fgetc( pipe ); c != EOF && c != '\n'; c = std::fgetc( pipe ) )
        {
            header.push_back( char( c ) );
        }
        const std::size_t sp2 = header.rfind( ' ' );
        const std::size_t sp1 = sp2 == std::string::npos || sp2 == 0 ? std::string::npos : header.rfind( ' ', sp2 - 1 );
        const long long   size = sp1 == std::string::npos ? -1 : std::strtoll( header.c_str() + sp2 + 1, nullptr, 10 );
        if( size < 0 || header.compare( 0, sp1, shas[ served ] ) != 0 )
        {
            ok = false;   // "<sha> missing", an empty header (the pipe ended), or an answer for another object
            break;
        }
        body.resize( std::size_t( size ) );
        const std::size_t got = size > 0 ? std::fread( body.data(), 1, std::size_t( size ), pipe ) : 0;
        (void)std::fgetc( pipe );   // the framing LF after the payload
        ok = got == std::size_t( size ) && onObject( shas[ served ], std::string_view( header ).substr( sp1 + 1, sp2 - sp1 - 1 ),
                                                     std::string_view( body.data(), got ) );
    }
    os::pclose( pipe );
    os::unlink( listPath.c_str() );
    return ok;
}

// Every ref's `ls-tree -r` rows, by the level-order walk above; nullopt when the walk cannot answer exactly.
inline std::optional<std::vector<std::vector<RawRow>>> listTreesOfRefs( const std::string& root, const std::vector<RefInfo>& refs )
{
    // ls-tree lists the CURRENT DIRECTORY's subtree, relative to it: from a root below the top of the work tree the walk
    // would have to start one subtree down and re-spell every path. That case keeps lsTree.
    if( !gitCapture( root, "rev-parse --show-prefix 2>/dev/null" ).empty() )
    {
        return std::nullopt;
    }
    std::vector<std::string> tips;
    for( const RefInfo& r : refs )
    {
        tips.push_back( r.tip );
    }
    std::sort( tips.begin(), tips.end() );
    tips.erase( std::unique( tips.begin(), tips.end() ), tips.end() );

    gtl::btree_map<std::string, std::string> rootOf;   // commit → its tree
    const bool commitsRead = catFileBatch( root, tips, [ & ]( const std::string& sha, std::string_view type, std::string_view bytes )
    {
        const bool shaped = type == "commit" && bytes.starts_with( "tree " ) && bytes.find( '\n' ) != std::string_view::npos;
        if( !VALIDATE( shaped ) )
        {
            return false;
        }
        rootOf[ sha ] = std::string( bytes.substr( 5, bytes.find( '\n' ) - 5 ) );
        return isBlobSha( rootOf[ sha ] );
    } );
    if( !commitsRead )
    {
        return std::nullopt;
    }

    gtl::btree_map<std::string, std::vector<GitTreeEntry>> trees;   // every distinct tree object any ref reaches
    std::vector<std::string>                               level;
    for( const auto& [ commit, tree ] : rootOf )
    {
        (void)commit;
        level.push_back( tree );
    }
    while( !level.empty() )
    {
        std::sort( level.begin(), level.end() );
        level.erase( std::unique( level.begin(), level.end() ), level.end() );
        std::vector<std::string> next;
        const bool               read = catFileBatch( root, level, [ & ]( const std::string& sha, std::string_view type, std::string_view bytes )
        {
            std::vector<GitTreeEntry> entries;
            if( type != "tree" || !parseGitTree( bytes, sha.size() / 2, entries ) )
            {
                return false;
            }
            for( const GitTreeEntry& e : entries )
            {
                if( e.isTree && trees.find( e.sha ) == trees.end() )
                {
                    next.push_back( e.sha );
                }
            }
            trees.emplace( sha, std::move( entries ) );
            return true;
        } );
        if( !read )
        {
            return std::nullopt;
        }
        level.clear();
        for( std::string& s : next )
        {
            if( trees.find( s ) == trees.end() )
            {
                level.push_back( std::move( s ) );
            }
        }
    }

    std::vector<std::vector<RawRow>> out( refs.size() );
    for( std::size_t i = 0; i < refs.size(); ++i )
    {
        // depth-first in stored order, a subtree listed where it stands: ls-tree -r's own order
        struct Frame { const std::vector<GitTreeEntry>* entries; std::size_t next; std::size_t prefixLen; };
        std::string        prefix;
        std::vector<Frame> stack{ Frame{ &trees.at( rootOf.at( refs[ i ].tip ) ), 0, 0 } };
        while( !stack.empty() )
        {
            Frame& f = stack.back();
            if( f.next == f.entries->size() )
            {
                stack.pop_back();
                continue;
            }
            const GitTreeEntry& e = ( *f.entries )[ f.next++ ];
            prefix.resize( f.prefixLen );
            prefix += e.name;
            if( e.isTree )
            {
                const std::size_t childPrefix = prefix.size() + 1;
                prefix += '/';
                stack.push_back( Frame{ &trees.at( e.sha ), 0, childPrefix } );
                continue;
            }
            out[ i ].push_back( RawRow{ gitQuotedPath( prefix ), std::string{}, e.sha } );
        }
    }
    ENSURES( out.size() == refs.size(), "one listing per ref, in the refs' order (computeWhereis reads slot i as refs[i])" );
    return out;
}

// A git tree path ("src/graph.h") against an index path relativised to the ingest ROOT ("graph.h" when the
// tree was ingested as `ripwire src`): equal, or the git path ends with the index path on a component
// boundary. Never a realpath (determinism, same reasoning as arch.h::relForHash).
inline bool sameTreePath( std::string_view gitPath, std::string_view indexRelPath ) noexcept
{
    return rw::samePathTail( gitPath, indexRelPath );   // the rule lives ONCE, in arch.h
}

// §A7 — HEAD rows are documented as the PARSED answer, so stop guessing on them: the index knows where SYM is
// defined, and a HEAD row is kind="def" iff the index puts a definition of SYM there. Exactly ONE row is
// promoted per index def site — the closest occurrence inside the window — so a doc comment that names the
// symbol one line above its definition cannot become a second "definition", and the arithmetic is checkable
// (HEAD def rows == index defs in the scanned tree).
//
// The window is asymmetric on purpose: a multi-LINE signature puts the name BELOW the def's start line (the
// index records the start), while the text above a definition is comment prose that merely mentions the name.
//
// Two degrade paths, both alerted rather than silent, because both would otherwise reproduce the very failure
// this fixes ("0 def rows for a symbol that is plainly defined on HEAD"):
//   • the caller supplied no def sites (no index was passed), or the index knows no def of this name (the
//     symbol lives only on a branch, or outside the ingest root) ⇒ keep the lexical labels.
//   • def sites exist but NO HEAD row landed in any window ⇒ the working tree the index was built from has
//     drifted from HEAD's committed blob (uncommitted edits above the definition) ⇒ keep the lexical labels.
// Both leave head_labels="lexical" on the root, so the reader is told which half answered.
constexpr std::uint32_t kHeadDefLineAbove = 1;    // lines ABOVE the index's def line still counted as the def
constexpr std::uint32_t kHeadDefLineBelow = 3;    // …and below it (a signature wrapping over several lines)

inline bool relabelHeadHitsFromIndex( std::vector<WhereHit>& hits, std::span<const IndexDefSite> indexDefs )
{
    if( indexDefs.empty() )
    {
        return false;
    }

    std::vector<char> promoted( hits.size(), 0 );   // 1 = a production def site, 2 = a test-local one
    for( const IndexDefSite& def : indexDefs )
    {
        std::size_t   bestHit  = hits.size();
        std::uint32_t bestDist = 0;
        for( std::size_t hitIndex = 0; hitIndex < hits.size(); ++hitIndex )
        {
            const WhereHit& h = hits[ hitIndex ];
            if( !h.inCheckout() || !sameTreePath( h.path, def.path ) )
            {
                continue;
            }
            if( h.line + kHeadDefLineAbove < def.line || h.line > def.line + kHeadDefLineBelow )
            {
                continue;
            }
            const std::uint32_t dist = ( h.line > def.line ) ? h.line - def.line : def.line - h.line;
            if( bestHit == hits.size() || dist < bestDist ) { bestHit = hitIndex; bestDist = dist; }
        }
        if( bestHit != hits.size() )
        {
            promoted[bestHit] = def.testLocal ? 2 : 1;
        }
    }

    const bool anyPromoted = std::any_of( promoted.begin(), promoted.end(), []( char p ) { return p != 0; } );
    if( !anyPromoted )
    {
        DISCLOSE( "whereis: the index's def sites match no HEAD row (working tree drifted from HEAD?) — keeping the lexical labels" );
        return false;
    }
    for( std::size_t hitIndex = 0; hitIndex < hits.size(); ++hitIndex )
    {
        if( hits[hitIndex].inCheckout() )
        {
            hits[hitIndex].isDef     = promoted[hitIndex] != 0;
            hits[hitIndex].testLocal = promoted[hitIndex] == 2;
        }
    }
    return true;
}

// ── the OTHER refs' rows: kind= from a parser, never from a reading of the line ───────────────────────────
//
// A row on another ref comes from a blob the index never read, and one line read lexically cannot tell a definition
// from a call in every language (rv-whereis-defs-fix: a stricter reading lost `#define NAME(`, `decltype(auto) NAME(`,
// `@Test(…) public void NAME()`, `#[derive(Debug)] struct NAME`; a looser one keeps `go NAME(a)`, `@NAME(1)`,
// `NAME( a, [&]( int x ) {`). So each distinct (blob, path) behind such rows is labelled the way HEAD's rows are:
//   * HEAD's OWN blob at the same path (a ref that never touched the file), when HEAD's rows came from the index
//     (head_labels="index"): HEAD's labels, line for line — the same bytes, the same answer, no parse;
//   * otherwise the index's extraction runs over the blob (definitionLinesInBlobs, ingest.h) and every definition the
//     tags query captures for the name promotes the nearest row within [line - kHeadDefLineAbove, line +
//     kHeadDefLineBelow], exactly relabelHeadHitsFromIndex's rule; every other row of the blob is a reference.
// WHICH blobs are parsed: only those holding a row parseWorthyLine() accepts (a loose superset of definitionShaped).
// Parsing every blob that mentions the name cost 15-40 s on ripwire's most-called helper (1140 blobs, 467 MB) against a
// 12 s answer; the chooser cuts that to ~100 blobs, ~43 MB. It CHOOSES, it never labels: a blob it rejects holds no
// parse-worthy row, and its rows read kind="ref" (the floor parseWorthyLine's header names). A parsed blob is labelled whole.
// The batch is bounded by the runaway guard (kWhereisParseMaxBlobs / kWhereisParseMaxBytes; WhereisParseBudget),
// filled most-rows-first. A blob the guard leaves, or one the parser could not finish, confirms NOTHING: its
// parse-worthy rows read kind="text", never kind="def", its other rows kind="ref", and <unparsed> counts them.
// A path in no indexed language, or one the crawl would skip (binary, oversized, a nesting refusal), is labelled as
// the index labels such a file on HEAD: no definition.
struct WhereisParseBudget
{
    std::size_t maxBlobs = kWhereisParseMaxBlobs;
    std::size_t maxBytes = kWhereisParseMaxBytes;
};

struct BranchParseJob
{
    std::string                sha;          // the blob (with `path`, the unit one parse answers)
    std::string                path;         // the tree path: its extension picks the grammar
    std::string                bytes;        // the blob, kept only when it holds a parse-worthy row
    std::vector<std::uint32_t> hitLines;     // the blob's hit lines, ascending (one hit per line)
    std::vector<std::size_t>   rows;         // every WhereHit this (blob, path) produced on a non-HEAD ref
    std::size_t                headFirst = 0, headEnd = 0;   // HEAD's rows of this same (blob, path), when HEAD holds it
    bool                       shaped    = false;            // some row is parse-worthy (parseWorthyLine): worth a parse
};

// The hit lines a parse's definition lines promote: per definition line, the nearest hit line in its window (the lower
// line on a tie — relabelHeadHitsFromIndex walks HEAD's rows in ascending line order with the same strict `<`).
inline std::vector<std::uint32_t> promotedHitLines( std::span<const std::uint32_t> hitLines, std::span<const std::uint32_t> defLines )
{
    EXPECTS( std::is_sorted( hitLines.begin(), hitLines.end() ), "one blob's hit lines, in the scan's ascending order (the tie rule reads them so)" );
    std::vector<std::uint32_t> promoted;
    for( const std::uint32_t defLine : defLines )
    {
        std::size_t   best     = hitLines.size();
        std::uint32_t bestDist = 0;
        for( std::size_t i = 0; i < hitLines.size(); ++i )
        {
            const std::uint32_t h = hitLines[ i ];
            if( h + kHeadDefLineAbove < defLine || h > defLine + kHeadDefLineBelow )
            {
                continue;
            }
            const std::uint32_t dist = ( h > defLine ) ? h - defLine : defLine - h;
            if( best == hitLines.size() || dist < bestDist ) { best = i; bestDist = dist; }
        }
        if( best != hitLines.size() )
        {
            promoted.push_back( hitLines[ best ] );
        }
    }
    std::sort( promoted.begin(), promoted.end() );
    return promoted;
}

// Label one job's rows: kind="def" exactly on `defLines` (sorted), else kind="ref" — or, when the job confirmed nothing
// (`confirmed` false), kind="text" on its parse-worthy rows (parseWorthyLine), the lines that asked for the parse.
inline void labelJobRows( WhereResult& result, const BranchParseJob& job, std::span<const std::uint32_t> defLines, bool confirmed )
{
    EXPECTS( std::all_of( job.rows.begin(), job.rows.end(), [ & ]( std::size_t r ) { return r < result.hits.size() && !result.hits[ r ].inCheckout(); } ),
             "a job's rows are rows of other refs this scan produced (HEAD's are the index's to label)" );
    for( const std::size_t r : job.rows )
    {
        WhereHit& h = result.hits[ r ];
        if( !confirmed )
        {
            h.unconfirmed = h.parseWorthy;
            result.branchLabels.textRows += h.parseWorthy ? 1 : 0;
        }
        h.isDef = confirmed && std::binary_search( defLines.begin(), defLines.end(), h.line );
    }
}

// The parse batch: the parse-worthy jobs no mirror answered, most rows first (then path, then blob — a fact of the
// answer, never of thread timing), up to the guard. Returns the jobs it parsed, in batch order.
inline std::vector<std::size_t> branchParseBatch( const std::vector<BranchParseJob>& jobs, std::span<const char> answered,
                                                  const WhereisParseBudget& budget, BranchLabelCensus& census )
{
    std::vector<std::size_t> want;
    for( std::size_t j = 0; j < jobs.size(); ++j )
    {
        if( answered[ j ] == 0 && jobs[ j ].shaped )
        {
            want.push_back( j );
        }
    }
    std::sort( want.begin(), want.end(), [ & ]( std::size_t a, std::size_t b )
               {
                   const BranchParseJob& x = jobs[ a ];
                   const BranchParseJob& y = jobs[ b ];
                   if( x.rows.size() != y.rows.size() ) { return x.rows.size() > y.rows.size(); }
                   if( x.path != y.path ) { return x.path < y.path; }
                   return x.sha < y.sha;
               } );
    std::vector<std::size_t> batch;
    std::size_t              bytes = 0;
    for( const std::size_t j : want )
    {
        const std::size_t size = jobs[ j ].bytes.size();
        if( batch.size() >= budget.maxBlobs || size > budget.maxBytes - bytes )
        {
            break;   // the guard: this job and every later one confirm nothing (counted below by the caller)
        }
        batch.push_back( j );
        bytes += size;
    }
    census.leftByGuard = want.size() - batch.size();
    ENSURES( batch.size() <= budget.maxBlobs && bytes <= budget.maxBytes, "the batch stays inside the runaway guard" );
    return batch;
}

inline void labelBranchRowsByParse( WhereResult& result, std::vector<BranchParseJob>& jobs, const WhereisParseBudget& budget )
{
    std::vector<char> answered( jobs.size(), 0 );
    for( std::size_t j = 0; j < jobs.size(); ++j )
    {
        BranchParseJob& job = jobs[ j ];
        if( job.headEnd > job.headFirst && result.headLabelsFromIndex )
        {
            std::vector<std::uint32_t> headDefs;   // HEAD's rows are ascending by line: one blob, one scan
            for( std::size_t r = job.headFirst; r < job.headEnd; ++r )
            {
                if( result.hits[ r ].isDef ) { headDefs.push_back( result.hits[ r ].line ); }
            }
            labelJobRows( result, job, headDefs, true );
            ++result.branchLabels.mirrored;
            answered[ j ] = 1;
        }
        else if( !job.shaped || sliceGrammarForFile( job.path ) == nullptr )
        {
            labelJobRows( result, job, {}, true );   // nothing parse-worthy, or no indexed language: as the index would say
            answered[ j ] = 1;
        }
    }
    const std::vector<std::size_t> batch = branchParseBatch( jobs, answered, budget, result.branchLabels );
    std::vector<BlobText>          blobs;
    blobs.reserve( batch.size() );
    for( const std::size_t j : batch )
    {
        blobs.push_back( BlobText{ jobs[ j ].path, jobs[ j ].bytes } );
    }
    std::vector<BlobDefinitions> parsed;
    if( !blobs.empty() )
    {
        // the tags queries live in a process-global, single-writer cache: a long-lived server serializes every ingest on this lock
        std::lock_guard<std::mutex> ingestLk( quality::headSnapshotIngestMutex() );
        parsed = definitionLinesInBlobs( blobs, result.sym );
    }
    ENSURES( parsed.size() == batch.size(), "one answer per (blob, path) handed to the parser" );
    for( std::size_t k = 0; k < batch.size(); ++k )
    {
        const std::size_t j = batch[ k ];
        answered[ j ]       = 1;
        switch( parsed[ k ].status )
        {
            case BlobDefsStatus::Parsed:
                labelJobRows( result, jobs[ j ], promotedHitLines( jobs[ j ].hitLines, parsed[ k ].lines ), true );
                ++result.branchLabels.parsed;
                break;
            case BlobDefsStatus::NoGrammar:
            case BlobDefsStatus::Unread:
                labelJobRows( result, jobs[ j ], {}, true );   // the crawl defines nothing in such a file on HEAD either
                break;
            case BlobDefsStatus::Failed:
                labelJobRows( result, jobs[ j ], {}, false );
                ++result.branchLabels.failed;
                break;
        }
    }
    for( std::size_t j = 0; j < jobs.size(); ++j )
    {
        if( answered[ j ] == 0 )
        {
            labelJobRows( result, jobs[ j ], {}, false );   // left by the guard: confirms nothing
        }
    }
}

// ── the working-tree overlay (2026-10-01 freshness fix) ──────────────────────────────────────────────────
//
// A git listing whose SUCCESS is known. gitOneLine answers "" both for "nothing to list" and for "git failed",
// and the overlay must not read a failed `git diff` as a clean checkout — that is the silent stale answer this
// fix exists to remove. gitmine.h's gitCommandLines reads the lines and keeps pclose's status; same command
// prefix as gitOneLine (core.quotepath=false, -C root), so the paths are spelled exactly as lsTree spells
// them: cwd-relative to the root, git-quoted only when a byte forces it.
struct GitListing
{
    std::vector<std::string> lines;
    bool                     ok = false;
};

inline GitListing gitListChecked( const std::string& root, const std::string& tail )
{
    GitCommandLines res = gitCommandLines( gitCmd( " -c core.quotepath=false -C " ) + shSingleQuote( root ) + " " + tail + " 2>/dev/null" );
    return GitListing{ std::move( res.lines ), res.isStarted && WIFEXITED( res.status ) && WEXITSTATUS( res.status ) == 0 };
}

// Every path under the root whose working copy differs from HEAD: tracked paths modified, staged, or deleted
// (`diff HEAD`, renames split into their two sides) plus untracked, not-ignored files. Sorted and de-duplicated
// (determinism). ok=false when either listing failed — the caller then cannot vouch for any HEAD row.
inline GitListing worktreeChangedPaths( const std::string& root, const std::string& headSha )
{
    if( !isRevisionToken( headSha ) )
    {
        return {};
    }
    GitListing changed = gitListChecked( root, "diff --name-only --no-renames --relative " + shSingleQuote( headSha ) + " --" );
    GitListing others  = gitListChecked( root, "ls-files --others --exclude-standard" );
    changed.ok         = changed.ok && others.ok;
    changed.lines.insert( changed.lines.end(), others.lines.begin(), others.lines.end() );
    std::sort( changed.lines.begin(), changed.lines.end() );
    changed.lines.erase( std::unique( changed.lines.begin(), changed.lines.end() ), changed.lines.end() );
    return changed;
}

// A cap on how many changed paths one answer reads from disk. Past it the rest keep their HEAD rows and the
// answer says worktree="partial" — a checkout with this many uncommitted paths is a generated tree, not an edit.
constexpr std::size_t kMaxWorktreePaths = 8192;

// One changed path's working copy, as the overlay sees it.
enum class WorktreeCopy : std::uint8_t
{
    Text,      // read: scan it, and it REPLACES HEAD's blob for this path
    Gone,      // absent from disk (deleted): no rows, and HEAD's rows for it are dropped
    NotText,   // binary, or a non-file that is not a directory (a FIFO, a socket): no text symbol can occur, HEAD's rows dropped
    Unread,    // exists but could not be read (permission, oversized, a git-quoted name), or a DIRECTORY — an untracked
               // nested repository or a submodule, whose files are another repository's and are not read here: HEAD's
               // rows STAND and the answer is worktree="partial", never a complete claim over files it never opened
};

// Whether a PARENT component of `relPath` is a symbolic link. A path beyond one is not in the working tree at all
// (git: "beyond a symbolic link" — it lists the tracked path as deleted and the link itself as untracked), so the
// overlay treats it as gone; reading through it would answer with a file outside the root.
inline bool beyondSymlinkedDir( const std::string& root, const std::string& relPath )
{
    std::error_code ec;
    for( std::size_t slash = relPath.find( '/' ); slash != std::string::npos; slash = relPath.find( '/', slash + 1 ) )
    {
        if( std::filesystem::symlink_status( std::filesystem::path( root ) / relPath.substr( 0, slash ), ec ).type() == std::filesystem::file_type::symlink )
        {
            return true;
        }
    }
    return false;
}

// The bytes git would store for this path: a regular file's contents, or a symbolic link's target text (git
// stores the link, not what it points at). Mirrors streamBlobs' rules: over kMaxBlobBytes is UNREAD (it could
// hold the symbol, so it forfeits the claim), a NUL in the probe window is binary (it cannot).
inline WorktreeCopy readWorktreeCopy( const std::string& root, const std::string& relPath, std::string& bytes )
{
    bytes.clear();
    if( relPath.empty() || relPath.front() == '"' )
    {
        return WorktreeCopy::Unread;   // git quoted a byte it would not print raw — this spelling is not the file's name
    }
    const std::string trimmed = relPath.back() == '/' ? relPath.substr( 0, relPath.size() - 1 ) : relPath;
    if( beyondSymlinkedDir( root, trimmed ) )
    {
        return WorktreeCopy::Gone;   // review S1: never read through the link to a file outside the root
    }
    std::error_code             ec;
    const std::filesystem::path p  = std::filesystem::path( root ) / trimmed;
    const auto                  st = std::filesystem::symlink_status( p, ec );
    if( st.type() == std::filesystem::file_type::not_found )
    {
        return WorktreeCopy::Gone;
    }
    if( ec )
    {
        return WorktreeCopy::Unread;
    }
    if( st.type() == std::filesystem::file_type::symlink )
    {
        const std::filesystem::path target = std::filesystem::read_symlink( p, ec );
        if( ec )
        {
            return WorktreeCopy::Unread;
        }
        bytes = target.string();
        return WorktreeCopy::Text;
    }
    if( st.type() == std::filesystem::file_type::directory )
    {
        return WorktreeCopy::Unread;   // a nested repository (`inner/` in the untracked listing) or a submodule: not read
    }
    if( st.type() != std::filesystem::file_type::regular )
    {
        return WorktreeCopy::NotText;
    }
    const std::uintmax_t size = std::filesystem::file_size( p, ec );
    if( ec || size > kMaxBlobBytes )
    {
        return WorktreeCopy::Unread;
    }
    std::optional<std::string> got = pathguard::readRegularFileNoFollow( p.string() );
    if( !got )
    {
        return WorktreeCopy::Unread;
    }
    bytes = std::move( *got );
    if( bytes.size() > kMaxBlobBytes )
    {
        bytes.clear();
        return WorktreeCopy::Unread;   // grew between the size probe and the read
    }
    if( std::string_view( bytes ).substr( 0, std::min( bytes.size(), kBinaryProbe ) ).find( '\0' ) != std::string_view::npos )
    {
        bytes.clear();
        return WorktreeCopy::NotText;
    }
    return WorktreeCopy::Text;
}

// The overlay's yield: the paths whose HEAD rows it REPLACED (sorted — the HEAD-site filter binary-searches it),
// the rows it found, and whether HEAD's own tree text held the name in a replaced copy (on-head=).
struct WorktreeScan
{
    WorktreeOverlay          state = WorktreeOverlay::Clean;
    std::vector<std::string> replaced;
    std::vector<WhereHit>    hits;
    bool                     mentions = false;
    enum class DisclosureWhy : std::uint8_t
    {
        ListingFailed,   // git diff / ls-files failed: nothing can be vouched for
        CopyUnread,      // a changed path could not be read: its HEAD rows stand
        OverPathCap,     // more changed paths than kMaxWorktreePaths: the rest keep their HEAD rows
    };
    // What each disclosure leaves the overlay able to vouch for, indexed by DisclosureWhy.
    static constexpr WorktreeOverlay kStateAfter[] = { WorktreeOverlay::Unlisted, WorktreeOverlay::Partial, WorktreeOverlay::Partial };
    void disclose( DisclosureWhy why ) noexcept { state = kStateAfter[ std::size_t( why ) ]; }
};

// Read the working copy of every path under the root that differs from HEAD and scan it for SYM. A row found
// here is ref="worktree" (tip=/date= the HEAD commit it overlays); a path read here (or gone) has its HEAD rows
// dropped by the caller, so a deleted or renamed definition stops answering from a commit the checkout left.
inline WorktreeScan scanWorktree( const std::string& root, std::string_view sym, const RefInfo& head )
{
    WorktreeScan     scan;
    const GitListing changed = worktreeChangedPaths( root, head.tip );
    if( !changed.ok )
    {
        DISCLOSE( scan, WorktreeScan::DisclosureWhy::ListingFailed, "whereis: git could not list the working tree's changes — HEAD rows may be stale, complete= withheld" );
        return scan;
    }
    if( changed.lines.empty() )
    {
        return scan;   // a clean checkout: the committed scan is the whole answer, byte-identical to before
    }
    scan.state = WorktreeOverlay::Read;
    if( changed.lines.size() > kMaxWorktreePaths )
    {
        DISCLOSE( scan, WorktreeScan::DisclosureWhy::OverPathCap, "whereis: more changed paths than the overlay reads — the rest keep their HEAD rows, complete= withheld" );
    }
    const RefInfo worktreeRef{ "worktree", head.tip, head.date };
    const std::size_t readCount = std::min( changed.lines.size(), kMaxWorktreePaths );
    std::string bytes;
    for( std::size_t pathIndex = 0; pathIndex < readCount; ++pathIndex )
    {
        const std::string& relPath = changed.lines[ pathIndex ];
        const WorktreeCopy copy    = readWorktreeCopy( root, relPath, bytes );
        if( copy == WorktreeCopy::Unread )
        {
            DISCLOSE( scan, WorktreeScan::DisclosureWhy::CopyUnread, "whereis: a changed path could not be read from the working tree — its HEAD rows stand, complete= withheld" );
            continue;
        }
        scan.replaced.push_back( relPath );
        if( copy != WorktreeCopy::Text || bytes.find( sym ) == std::string::npos )
        {
            continue;
        }
        scan.mentions = true;
        const std::size_t first = scan.hits.size();
        scanBlobForSymbol( bytes, sym, worktreeRef, relPath, scan.hits );
        for( std::size_t hitIndex = first; hitIndex < scan.hits.size(); ++hitIndex )
        {
            scan.hits[ hitIndex ].fromWorktree = true;
        }
    }
    // computeWhereis binary-searches `replaced`: a subsequence of the sorted, de-duplicated listing, so sorted too.
    ENSURES( std::is_sorted( scan.replaced.begin(), scan.replaced.end() ), "whereis: the overlay's replaced paths must stay sorted for the HEAD-site filter" );
    return scan;
}

// ── the working-tree RENAME behind a "not found" (2026-10-01, the comparison table's F-textual-2b) ─────────────
//
// `--callers=line_trim` after the working tree renamed it to `trim_line` refused with "did you mean 'line_type'?":
// the edit-distance suggester ranks names by spelling, and a token swap is far from its source by spelling. The
// working tree holds better evidence than spelling. A name the index lacks but HEAD's copy of a CHANGED file has,
// beside a definition in that file's working copy that HEAD's copy lacks, is a rename in progress. This finds the
// best such definition, so the not-found answers can offer it first. Read-only, git plumbing only, and it runs only
// on a refusal path.

// The lower-cased identifier words of a name: split at '_', '-', digits-to-letters and lower-to-upper case changes.
inline std::vector<std::string> identWordsOf( std::string_view name )
{
    std::vector<std::string> words;
    std::string              cur;
    for( std::size_t i = 0; i < name.size(); ++i )
    {
        const unsigned char c        = static_cast<unsigned char>( name[ i ] );
        const bool          boundary = i > 0 && std::isupper( c ) && std::islower( static_cast<unsigned char>( name[ i - 1 ] ) );
        if( !std::isalnum( c ) || boundary )
        {
            if( !cur.empty() ) { words.push_back( std::move( cur ) ); cur.clear(); }
            if( !std::isalnum( c ) ) { continue; }
        }
        cur.push_back( static_cast<char>( std::tolower( c ) ) );
    }
    if( !cur.empty() ) { words.push_back( std::move( cur ) ); }
    std::sort( words.begin(), words.end() );
    words.erase( std::unique( words.begin(), words.end() ), words.end() );
    return words;
}

// Whether `word` occurs in `bytes` as a whole identifier: the whereis row scan itself, so the rule cannot drift.
inline bool hasWholeWord( std::string_view bytes, std::string_view word )
{
    std::vector<WhereHit> rows;
    scanBlobForSymbol( bytes, word, RefInfo{}, std::string(), rows );
    return !rows.empty();
}

constexpr std::size_t kMaxRenameProbeFiles = 32;   // HEAD copies one rename probe reads; past it the probe stops (a hint, never a claim)

// One possible rename target: an indexed definition in a changed path, and how many identifier words it shares.
struct RenameCandidate
{
    std::string      path;
    std::string_view name;
    std::size_t      shared = 0;
};

// The candidates for `missing`, best first: definitions in `changedPaths` (sorted) sharing a STRICT MAJORITY of the
// larger identifier-word set. line_trim/trim_line (2 of 2) and getUserName/fetchUserName (2 of 3) qualify; a shared
// project prefix alone (zqDoomed/zqFresh, 1 of 2) does not, so a deletion is not read as a rename. Order: most
// shared words, then the closest length, then name and path (determinism).
inline std::vector<RenameCandidate> renameCandidatesOf( const IngestResult& ing, std::string_view missing,
                                                        const std::vector<std::string>& changedPaths, const std::string& root )
{
    const std::vector<std::string> missingWords = identWordsOf( missing );
    std::vector<RenameCandidate>   candidates;
    for( const Symbol& s : ing.symbols )
    {
        const std::string path( relForHash( ing.files[ s.fileId ], root ) );
        if( s.kind == SymKind::Section || s.name == missing || !std::binary_search( changedPaths.begin(), changedPaths.end(), path ) )
        {
            continue;
        }
        const std::vector<std::string> words  = identWordsOf( s.name );
        const std::size_t              shared = std::count_if( words.begin(), words.end(), [ & ]( const std::string& w )
                                                               { return std::binary_search( missingWords.begin(), missingWords.end(), w ); } );
        if( shared * 2 > std::max( words.size(), missingWords.size() ) )
        {
            candidates.push_back( RenameCandidate{ path, s.name, shared } );
        }
    }
    const auto lengthGap = [ & ]( std::string_view n ) { return n.size() > missing.size() ? n.size() - missing.size() : missing.size() - n.size(); };
    std::sort( candidates.begin(), candidates.end(), [ & ]( const RenameCandidate& a, const RenameCandidate& b )
    {
        if( a.shared != b.shared )
        {
            return a.shared > b.shared;
        }
        const std::size_t gapA = lengthGap( a.name ), gapB = lengthGap( b.name );
        if( gapA != gapB )
        {
            return gapA < gapB;
        }
        // byte order through svLess, never string_view's operator< (libstdc++'s _S_compare wraps under -fsanitize=integer)
        return a.name != b.name ? sortutil::svLess( a.name, b.name ) : sortutil::svLess( a.path, b.path );
    } );
    return candidates;
}

// Whether a DEFINITION of `name` left this file: HEAD's copy has a definition-shaped line naming it (the same lexical
// test every whereis row uses) that the working copy no longer contains verbatim. A mention alone (an import, a call,
// a comment) is not a rename, and neither is a definition-shaped line the working copy still carries — the review's
// two false positives (an external name still imported and called; a name only a TODO comment ever mentioned).
inline bool definitionLeftCopy( std::string_view headCopy, std::string_view workCopy, std::string_view name )
{
    std::vector<WhereHit> rows;
    scanBlobForSymbol( headCopy, name, RefInfo{}, std::string(), rows );
    std::vector<std::string_view> workLines;
    for( std::string_view line : splitLines( workCopy ) )
    {
        const std::size_t a = line.find_first_not_of( " \t\r" );
        workLines.push_back( a == std::string_view::npos ? std::string_view{} : line.substr( a, line.find_last_not_of( " \t\r" ) + 1 - a ) );
    }
    std::sort( workLines.begin(), workLines.end(), sortutil::svLess );
    return std::any_of( rows.begin(), rows.end(), [ & ]( const WhereHit& row )
                        { return row.isDef && !std::binary_search( workLines.begin(), workLines.end(), std::string_view( row.text ), sortutil::svLess ); } );
}

// One changed file's rename evidence, gathered once: its HEAD copy, and whether a definition of the missing name
// left it (definitionLeftCopy against the working copy; a file gone from disk lost every line).
struct RenameEvidence
{
    std::string path;
    std::string headCopy;
    bool        definitionLeft = false;
};

inline RenameEvidence renameEvidenceOf( const std::string& root, const std::string& path, std::string_view missing )
{
    RenameEvidence ev{ path, {}, false };
    if( path.front() == '"' )
    {
        return ev;   // a git-quoted spelling is not the path's name: no evidence either way
    }
    ev.headCopy = gitCapture( root, "show " + shSingleQuote( "HEAD:./" + path ) + " 2>/dev/null" );
    std::string        work;
    const WorktreeCopy copy = readWorktreeCopy( root, path, work );
    ev.definitionLeft       = ( copy == WorktreeCopy::Text || copy == WorktreeCopy::Gone ) && definitionLeftCopy( ev.headCopy, work, missing );
    return ev;
}

// The definition the working tree most likely renamed `missing` to, or "" when the evidence names none: the best
// candidate in a changed file from which a DEFINITION of `missing` left (definitionLeftCopy), and whose HEAD copy does
// NOT hold the candidate's own name (it is new there).
inline std::string worktreeRenameOf( const IngestResult& ing, std::string_view missing, const std::string& root )
{
    if( missing.empty() || identWordsOf( missing ).empty() || !quality::gitRepoHasHistory( root ) )
    {
        return {};
    }
    const GitListing changed = worktreeChangedPaths( root, quality::gitHeadSha( root ) );
    if( !changed.ok || changed.lines.empty() )
    {
        return {};
    }
    std::vector<RenameEvidence> probed;   // one evidence record per changed file, read at most once
    for( const RenameCandidate& c : renameCandidatesOf( ing, missing, changed.lines, root ) )
    {
        auto ev = std::find_if( probed.begin(), probed.end(), [ & ]( const RenameEvidence& e ) { return e.path == c.path; } );
        if( ev == probed.end() && probed.size() >= kMaxRenameProbeFiles )
        {
            break;
        }
        if( ev == probed.end() )
        {
            probed.push_back( renameEvidenceOf( root, c.path, missing ) );
            ev = std::prev( probed.end() );
        }
        if( ev->definitionLeft && !hasWholeWord( ev->headCopy, c.name ) )
        {
            return std::string( c.name );
        }
    }
    return {};
}

// The comparison table's hono-05 row: a test file's local `const serveStatic = …` read as a definition beside the
// real one, and a reader takes the first kind="def" row. A definition is TEST-LOCAL when the index says so
// (isTestSymbol: a test file or a test scope), or, on a lexical row, when its path is in the test tier. Only when
// the answer holds BOTH kinds are the test-local rows marked (test_local="1") and ordered after the production ones;
// nothing is dropped. An answer with one kind keeps its rows, its order and its bytes. True when it marked any.
inline bool demoteTestLocalDefs( std::vector<WhereHit>& hits )
{
    for( WhereHit& h : hits )
    {
        h.testLocal = h.isDef && ( h.testLocal || pathTierOf( h.path ) == PathTier::TestOrBench );
    }
    const bool anyProduction = std::any_of( hits.begin(), hits.end(), []( const WhereHit& h ) { return h.isDef && !h.testLocal; } );
    const bool anyTestLocal  = std::any_of( hits.begin(), hits.end(), []( const WhereHit& h ) { return h.testLocal; } );
    if( anyProduction && anyTestLocal )
    {
        return true;
    }
    for( WhereHit& h : hits )
    {
        h.testLocal = false;
    }
    return false;
}

// The 26b sweep's definitions page: a defs="1" symbol listed 2113 "definitions", because every one of 153 refs holds
// its own copy of the same `inline … escapeXml( … )` line and each copy was a row. Identical definition lines across
// the OTHER refs — the same path, the same line text, kind="def", outside the checkout — are ONE definition held by
// N refs. In the sorted order (refs by name) the first row of such a group is its representative: it carries
// defRefs = N and the definitions page prints it once with refs="N"; every later row of the group is foldedDef and
// that page skips it. Nothing is erased: hits= still counts every row and listing=all prints each ref's own row.
// A ref that holds the same text at TWO lines of one path (a macro twin, a copy in a #if branch) is two groups —
// the k-th such line of a ref joins the k-th group — so N is exactly the number of refs holding the row, never more.
// The checkout's rows (HEAD and worktree=) are the parsed answer and never fold; nor does any kind="ref" row. A
// kind="text" row (a parse-worthy line whose blob was not parsed, see labelBranchRowsByParse) folds the same way,
// in groups of its own: the same line on N refs is one unconfirmed row with refs="N", never merged into a definition.
inline void foldSharedBranchDefs( std::vector<WhereHit>& hits )
{
    struct Group
    {
        std::string              lastRef;        // the ref whose rows were last seen for this (path, text)
        std::size_t              ordinalInRef = 0;   // how many rows of that ref this key has had so far
        std::vector<std::size_t> representatives;   // one per ordinal: the hit index that stands for it
    };
    gtl::btree_map<std::string, Group> groups;
    std::string                        key;
    std::size_t                        branchDefs = 0, represented = 0;   // every branch def row is one representative's count
    for( std::size_t i = 0; i < hits.size(); ++i )
    {
        WhereHit& h = hits[ i ];
        if( ( !h.isDef && !h.unconfirmed ) || h.inCheckout() )
        {
            continue;
        }
        ++branchDefs;
        key.assign( h.unconfirmed ? "text\n" : "def\n" );   // a confirmed and an unconfirmed copy of a line never share a group
        key += h.path;
        key += '\n';   // a path never holds a newline, and text is one trimmed line: the join is unambiguous
        key += h.text;
        Group& g = groups[ key ];
        if( g.lastRef != h.ref )
        {
            g.lastRef      = h.ref;
            g.ordinalInRef = 0;
        }
        else
        {
            ++g.ordinalInRef;
        }
        if( g.ordinalInRef < g.representatives.size() )
        {
            WhereHit& rep = hits[ g.representatives[ g.ordinalInRef ] ];
            ++rep.defRefs;
            h.foldedDef = true;
        }
        else
        {
            g.representatives.push_back( i );
            h.defRefs = 1;
        }
    }
    for( const WhereHit& h : hits )
    {
        represented += h.foldedDef ? 0 : h.defRefs;
    }
    ENSURES( represented == branchDefs, "the representatives' refs= counts add up to every branch definition row: nothing is dropped, only counted" );
}

// The emitted ORDER of --whereis rows (see computeWhereis' header): the checkout (HEAD plus its worktree rows) first
// as ONE group — a definition the edit just added sorts among HEAD's definitions, not after them; the two never
// share a path, so the group needs no ref order inside it — then the other refs by name; within a group SOURCE
// before test before docs (§P11.5), then definitions before references, then path and line.
inline bool whereHitBefore( const WhereHit& a, const WhereHit& b )
{
    const bool ah = a.inCheckout(), bh = b.inCheckout();
    if( ah != bh )
    {
        return ah;
    }
    if( !ah && a.ref != b.ref )
    {
        return a.ref < b.ref;
    }
    const PathTier at = pathTierOf( a.path ), bt = pathTierOf( b.path );
    if( at != bt )
    {
        return at < bt;
    }
    // Production definitions, then test-local ones (test_local="1", see demoteTestLocalDefs), then the unconfirmed
    // parse-worthy rows (kind="text", labelBranchRowsByParse), then references.
    const auto defRank = []( const WhereHit& h ) { return h.isDef ? ( h.testLocal ? 1 : 0 ) : ( h.unconfirmed ? 2 : 3 ); };
    if( defRank( a ) != defRank( b ) )
    {
        return defRank( a ) < defRank( b );
    }
    if( a.path != b.path )
    {
        return a.path < b.path;
    }
    if( a.line != b.line )
    {
        return a.line < b.line;
    }
    return a.fromWorktree < b.fromWorktree;
}

// The whole --whereis computation. Every ref's FULL tree is enumerated, but each distinct blob is READ once:
// a `(blob sha → the paths/refs that point at it)` fan-out map is built first, then one streaming pass scans
// each blob's bytes and attributes its hits to every (ref, path) that shares it. That is the content-addressed
// economy the whole module rests on — 30 branches of a shared trunk cost ~one tree's worth of reading.
//
// §P11.5 — the emitted ORDER carries a path tier, and that is the fix for a first screen that put doc-QUOTED
// code above the real definition: `--whereis=rankGraphTeleport` opened with three kind="def" rows into
// docs/captures/*.md CDATA and only reached src/graph.h:1148 on row four. Any repo whose docs quote code hits
// it, so it is not specific to this tree's capture files.
//
// This does NOT sharpen definitionShaped() and must not be read as doing so. That heuristic's documented
// residual stands exactly as written above it: ref blobs are raw text that was never ingested, so a doc line
// quoting a signature still LOOKS like a definition and still reports kind="def". The tier only decides where
// such a row is PRINTED — a doc row claiming kind="def" is still a doc row claiming kind="def", now below the
// code. Nothing is dropped and no row's attributes change; a reader who wants the doc evidence still gets
// every row of it.
inline WhereResult computeWhereis( const std::string& root, std::string_view sym, std::string_view filter,
                                   WhereisEvidence evidence = {}, const WhereisParseBudget& budget = {} )
{
    WhereResult result;
    result.sym    = std::string( sym );
    result.filter = std::string( filter );   // H14/M6: echoed on the root beside refs_scanned=, which it bounds
    if( !quality::gitRepoHasHistory( root ) ) { result.ok = false; result.nonGitRoot = true; return result; }

    result.headSha = quality::gitHeadSha( root );
    result.history = evidence.history;
    if( evidence.history != nullptr )
    {
        result.fate = evidence.history->fateOf( result.sym );
    }

    RefEnumeration       enumeration;   // a dropped ref is searched nowhere, so it forfeits complete= like an empty tree
    std::vector<RefInfo> refs = enumerateRefs( root, filter, result.headSha, nullptr, &enumeration );
    refs.insert( refs.begin(), RefInfo{ "HEAD", result.headSha, quality::gitCommitterDateIso( root ) } );
    if( refs.size() > kMaxRefs ) { result.ok = false; return result; }

    // The CHECKOUT, not just HEAD's commit: every path that differs from HEAD is read from the working tree, and
    // HEAD's rows for exactly those paths are dropped below — the stale-and-silent answer the comparison table
    // caught 12 times (an added function at hits="0", a deleted one at its old lines, both complete="1").
    WorktreeScan worktree = scanWorktree( root, sym, refs.front() );
    result.worktree       = worktree.state;
    result.onHead         = worktree.mentions;

    // blob sha → every (ref index, path) that points at it, in a deterministic order. `replaced`: HEAD's blob for a
    // path the working tree changed — it prints no row (the overlay answers for that path), but it is still read for
    // ONE fact the fate lane needs: whether HEAD's COMMITTED tree holds the name (headHolds; review M8).
    struct Site { std::uint32_t refIndex; std::string path; bool replaced; };
    bool anyEmptyTree = false;   // T1: a zero-row ls-tree could be a FAILED listing — it forfeits complete=
    gtl::btree_map<std::string, std::vector<Site>> sites;
    {
        // One `git ls-tree -r` process per ref, run through the same pool the stray-content sweep uses: each worker
        // writes only its own slot, and the fan-out below reads the slots in ref order, so the map (and the answer)
        // is the serial one by construction. Measured on a 153-ref repo: 7.0 s of serial ls-tree wall → 2.1 s.
        std::vector<std::vector<RawRow>> trees( refs.size() );
        ParallelSweep                    treeSweep;
        if( std::optional<std::vector<std::vector<RawRow>>> walked = listTreesOfRefs( root, refs ) )
        {
            trees = std::move( *walked );   // every distinct tree object read once (listTreesOfRefs); treeSweep never ran, so isDone holds
        }
        else
        {
            DISCLOSE( Diagnostics::answerUnchanged, "lsTree lists the same rows per ref: only slower",
                      "crossref: the tree-object walk could not read every tree exactly — listing each ref with git ls-tree" );
            parallelIndexed( refs.size(), [ & ]( std::size_t i ) { trees[ i ] = lsTree( root, refs[ i ].tip ); }, treeSweep );
        }
        for( std::uint32_t i = 0; i < refs.size(); ++i )
        {
            const std::vector<RawRow>& rows = trees[ i ];
            if( rows.empty() || !treeSweep.isDone( i ) )
            {
                anyEmptyTree = true;   // a slot a worker never reached is an unlisted tree: it forfeits complete= like an empty one
            }
            for( const RawRow& r : rows )
            {
                sites[ r.bSha ].push_back( Site{ i, r.path, i == 0 && std::binary_search( worktree.replaced.begin(), worktree.replaced.end(), r.path ) } );
            }
        }
    }

    std::vector<std::string> shas;
    shas.reserve( sites.size() );
    for( const auto& [ sha, s ] : sites ) { (void)s; shas.push_back( sha ); }

    result.distinctBlobs = shas.size();
    result.refsScanned   = refs.size() - 1;                                   // HEAD is not one of the swept refs

    // The scan of every blob holding the name runs on the stream's own worker threads (streamBlobsInSlices): a pure
    // function of the bytes — its hit rows (stamped with no ref yet), and the bytes themselves only when some row is
    // parse-worthy. The loop after it walks the blobs in sha order on this thread, so the answer is the serial one.
    struct BlobScan
    {
        bool                  hasSym = false;   // a text blob holding the name's bytes (the cheap reject passed)
        std::vector<WhereHit> rows;             // its hits; empty ⇔ no whole-word occurrence (hasWholeWord)
        std::string           bytes;            // kept only for a parse-worthy blob (labelBranchRowsByParse)
    };
    std::vector<BlobScan>       scans( shas.size() );
    StreamBlobStats             blobStats;   // T1: the degrade census that decides whether this scan may claim complete=
    streamBlobsInSlices( root, shas, kWhereisStreamSlices, [ & ]( std::size_t i, const std::string&, std::string_view bytes, bool isText )
    {
        if( !isText || bytes.find( sym ) == std::string_view::npos )
        {
            return;   // cheap reject before the line walk
        }
        BlobScan& b = scans[ i ];
        b.hasSym    = true;
        scanBlobForSymbol( bytes, sym, RefInfo{}, std::string(), b.rows );
        if( std::any_of( b.rows.begin(), b.rows.end(), []( const WhereHit& h ) { return h.parseWorthy; } ) )
        {
            b.bytes.assign( bytes );
        }
    }, blobStats );
    std::vector<BranchParseJob> branchJobs;  // one per distinct (blob, path) behind a non-HEAD row: labelBranchRowsByParse
    for( std::size_t blobIndex = 0; blobIndex < shas.size(); ++blobIndex )
    {
        const BlobScan& scan = scans[ blobIndex ];
        if( !scan.hasSym )
        {
            continue;
        }
        const std::string& sha = shas[ blobIndex ];
        const auto it = sites.find( sha );
        if( it == sites.end() )
        {
            continue;
        }
        const std::vector<WhereHit>& blobRows = scan.rows;
        const std::size_t firstJobOfBlob = branchJobs.size();
        struct HeadRows { std::string_view path; std::size_t first, end; };
        std::vector<HeadRows> headRows;   // HEAD's rows of THIS blob, per path (HEAD is the first site: refs[0])
        for( const Site& s : it->second )
        {
            const bool head   = refs[ s.refIndex ].name == "HEAD";
            result.headHolds  = result.headHolds || ( head && ( !s.replaced || !blobRows.empty() ) );
            result.onHead     = result.onHead || ( head && !s.replaced );
            if( s.replaced )
            {
                continue;
            }
            const std::size_t firstRow = result.hits.size();
            for( const WhereHit& row : blobRows )
            {
                WhereHit& h = result.hits.emplace_back( row );
                h.ref       = refs[ s.refIndex ].name;
                h.tip       = refs[ s.refIndex ].tip;
                h.date      = refs[ s.refIndex ].date;
                h.path      = s.path;
            }
            if( head )
            {
                headRows.push_back( HeadRows{ s.path, firstRow, result.hits.size() } );   // the index labels these (relabelHeadHitsFromIndex)
                continue;
            }
            if( firstRow == result.hits.size() )
            {
                continue;
            }
            auto job = std::find_if( branchJobs.begin() + std::ptrdiff_t( firstJobOfBlob ), branchJobs.end(),
                                     [ & ]( const BranchParseJob& j ) { return j.path == s.path; } );
            if( job == branchJobs.end() )
            {
                BranchParseJob fresh;
                fresh.sha  = sha;
                fresh.path = s.path;
                for( std::size_t r = firstRow; r < result.hits.size(); ++r )
                {
                    fresh.hitLines.push_back( result.hits[ r ].line );
                    fresh.shaped = fresh.shaped || result.hits[ r ].parseWorthy;   // parseWorthyLine(): worth a parse
                }
                const auto headCopy = std::find_if( headRows.begin(), headRows.end(), [ & ]( const HeadRows& h ) { return h.path == s.path; } );
                if( headCopy != headRows.end() )
                {
                    fresh.headFirst = headCopy->first;
                    fresh.headEnd   = headCopy->end;
                }
                if( fresh.shaped )
                {
                    fresh.bytes = scan.bytes;   // kept for the parse batch (a mirror of HEAD's labels may yet make it unneeded)
                }
                branchJobs.push_back( std::move( fresh ) );
                job = branchJobs.end() - 1;
            }
            for( std::size_t r = firstRow; r < result.hits.size(); ++r )
            {
                job->rows.push_back( r );
            }
        }
    }
    std::vector<BlobScan>().swap( scans );   // the rows are stamped and the parse-worthy bytes copied into their jobs

    // T1: exhaustive-over-text iff every sha streamed clean AND no ref's tree listing was suspect. An empty
    // sha list (every scanned tree empty, or none) trivially streamed clean — anyEmptyTree covers that shape.
    // The overlay's half: Clean or Read means every HEAD row kept is also the checkout's content (enum order).
    result.scanExhaustive = blobStats.exhaustiveOverText() && !anyEmptyTree && enumeration.refsDropped == 0 && worktree.state <= WorktreeOverlay::Read;
    result.hits.insert( result.hits.end(), std::make_move_iterator( worktree.hits.begin() ), std::make_move_iterator( worktree.hits.end() ) );

    // §A7: HEAD's rows are the INDEX's answer, not the shape test's — before the sort, because "definitions
    // before references" is a sort key and a wrong label re-orders the first screen.
    result.headLabelsFromIndex = relabelHeadHitsFromIndex( result.hits, evidence.indexDefs );
    // …and the other refs' rows are a PARSER's answer too, after HEAD's: a ref holding HEAD's own blob takes HEAD's labels.
    labelBranchRowsByParse( result, branchJobs, budget );
    demoteTestLocalDefs( result.hits );

    // The checkout first, then refs by name; within a group, SOURCE before test before docs (§P11.5, see this
    // function's header), then definitions before references, then path/line — whereHitBefore states it.
    std::sort( result.hits.begin(), result.hits.end(), []( const WhereHit& a, const WhereHit& b ) { return whereHitBefore( a, b ); } );
    foldSharedBranchDefs( result.hits );   // after the sort: the representative of a group is its first row in this order
    return result;
}

// ── the labelled-accuracy eval (--eval-stray=FILE) ───────────────────────────────────────────────────────
// The existing harness (--eval / --eval-retrieval / --eval-mined) scores RANKED SETS: recall@k over a
// retrieval. A verdict verb has no ranking to score — it emits a CLASSIFICATION, so its eval is a labelled
// confusion table, and it lives here (with the classifier) rather than in eval.h, which owns the retrieval
// metrics and would otherwise have to reach into StrayResult's internals.
//
// FILE is TSV: `<ref name>\t<expected verdict>`, one per line, `#` comments and blanks skipped. Expected is
// merged | superseded | unmerged. This exists because the thresholds in kRedoDelMin / kSimSupersede were
// chosen against real labelled branches, and a future change to them must be MEASURED against those labels
// rather than eyeballed — the whole reason the classifier is documented as auditable.

struct EvalCase   { std::string ref; Verdict expected; Verdict got; bool found = false; };
struct EvalReport
{
    std::vector<EvalCase>   cases;
    std::uint32_t           correct = 0;
    std::uint32_t           unknownCount = 0;   // H13: cases whose classifier verdict is Unknown — its own
                                                 // bucket, disclosed separately so it can never hide inside
                                                 // "correct" or "incorrect" the way it did when an absent,
                                                 // NONEXISTENT ref silently defaulted to Merged.
    std::vector<std::string> badRefs;           // labels naming a ref this git repo does not have at all —
                                                 // refused, never scored (see evalStray below)
    bool                     ok = true;
};

inline bool parseVerdict( std::string_view s, Verdict& out )
{
    if( s == "merged" )     { out = Verdict::Merged;     return true; }
    if( s == "superseded" ) { out = Verdict::Superseded; return true; }
    if( s == "unmerged" )   { out = Verdict::Unmerged;   return true; }
    if( s == "unknown" )    { out = Verdict::Unknown;    return true; }       // label a ref that CANNOT be analysed here
    return false;
}

inline EvalReport evalStray( const std::string& root, const std::string& labelsPath )
{
    EvalReport rep;

    std::string bytes;
    {
        std::FILE* fp = std::fopen( labelsPath.c_str(), "rb" );
        if( !fp ) { rep.ok = false; return rep; }
        char        buf[ 65536 ];
        std::size_t n = 0;
        while( ( n = std::fread( buf, 1, sizeof( buf ), fp ) ) > 0 )
        {
            bytes.append( buf, n );
        }
        std::fclose( fp );
    }

    const StrayResult res = computeStrayContent( root, {} );
    if( !res.ok ) { rep.ok = false; return rep; }

    // Reported refs carry their verdict; every ref NOT reported was scanned and found merged (writeStrayContent
    // omits those), so an absent ref scores as `merged` rather than as a miss.
    gtl::btree_map<std::string, Verdict> got;
    for( const RefRow& r : res.refs )
    {
        got.emplace( r.ref.name, r.verdict );
    }

    for( std::string_view line : splitLines( bytes ) )
    {
        if( line.empty() || line[0] == '#' )
        {
            continue;
        }
        const std::size_t tab = line.find( '\t' );
        if( tab == std::string_view::npos )
        {
            continue;
        }
        EvalCase c;
        c.ref = std::string( line.substr( 0, tab ) );
        if( !parseVerdict( line.substr( tab + 1 ), c.expected ) )
        {
            continue;
        }

        const auto it = got.find( c.ref );
        c.found = it != got.end();
        if( c.found )
        {
            c.got = it->second;
        }
        else
        {
            // H13: an absent ref scores as merged ONLY when it is a real ref that computeStrayContent
            // actually scanned and found fully present (writeStrayContentPage omits those by design). A
            // label naming a ref this repo does not have at all is a broken fixture, not a merged branch
            // — crediting it as a correct "merged" guess is exactly how a nonexistent ref reached
            // accuracy=100% here before this fix. Verify existence with the same rev-parse the rest of
            // the tool already uses (gitResolveCommitSha) rather than trusting the label.
            if( quality::gitResolveCommitSha( root, c.ref ).empty() )
            {
                rep.badRefs.push_back( c.ref );
                continue;   // refused, never scored — does not touch correct/unknownCount/cases
            }
            c.got = Verdict::Merged;
        }
        if( c.got == Verdict::Unknown )
        {
            // Its own bucket: an Unknown verdict (no merge-base / unrelated history — crossref's own
            // degrade path) must never be silently absorbed into "correct" against a "merged" expectation,
            // and this counter makes that visible on the root instead of only inside the per-case rows.
            ++rep.unknownCount;
        }
        if( c.got == c.expected )
        {
            ++rep.correct;
        }
        rep.cases.push_back( std::move( c ) );
    }
    if( !rep.badRefs.empty() )
    {
        rep.ok = false;   // refuse the whole run rather than silently scoring a fixture that names refs that do not exist
    }
    return rep;
}

inline void writeStrayEval( std::FILE* out, const EvalReport& rep )
{
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };

    const std::size_t n   = rep.cases.size();
    const double      acc = n ? ( 100.0 * double( rep.correct ) / double( n ) ) : 0.0;
    rw::emitRaw( out, "<!-- ripwire stray-content eval: labelled verdict accuracy. Each row is one branch whose "
                       "true state was established by hand; want= is the label, got= is what the classifier said. "
                       "A branch absent from the report scores as merged ONLY when it is a real ref this repo has "
                       "(merged refs are omitted by design); a label naming a ref that does not exist is refused, "
                       "not scored (see badRefs on refusal). unknown= on the root counts cases whose verdict "
                       "is unknown (no merge-base / unrelated history); its own bucket, never folded into merged. "
                       "Use this to MEASURE a threshold change instead of eyeballing it. -->" );
    rw::emitTo( out, "<stray-eval cases=\"{}\" correct=\"{}\" unknown=\"{}\" accuracy=\"{:.1f}\">", n, rep.correct, rep.unknownCount, acc );
    for( const EvalCase& c : rep.cases )
    {
        rw::emitTo( out, "<case ref=\"{}\" want=\"{}\" got=\"{}\" hit=\"{}\" reported=\"{}\"/>",
                      ex( c.ref ).c_str(), verdictTag( c.expected ), verdictTag( c.got ),
                      c.got == c.expected ? 1 : 0, c.found ? 1 : 0 );
    }
    rw::emitRaw( out, "</stray-eval>" );
}

// ── XML emission (G4: minified, xmllint-clean; no `\n` outside CDATA) ────────────────────────────────────

using XmlEscaper = std::function<std::string( std::string_view )>;

inline void writeStrayFile( std::FILE* out, const FileRow& f, const XmlEscaper& ex )
{
    rw::emitTo( out, "<file p=\"{}\" v=\"{}\" stray=\"{}\" authored=\"{}\" del=\"{}\" redone=\"{}\" sim=\"{:.2f}\" head-touched=\"{}\"{}/>",
                  ex( f.path ).c_str(), verdictTag( f.verdict ), f.strayLines, f.authored, f.deleted, f.redone,
                  double( f.sim ), f.headTouched ? 1 : 0, f.diffable ? "" : " diffable=\"0\"" );
}

inline void writeStrayRef( std::FILE* out, const RefRow& r, const XmlEscaper& ex, std::size_t maxFiles )
{
    // ok="0" ALWAYS renders v="unknown". computeStrayContent already sets Unknown at the degrade site, so
    // this is a belt-and-braces coercion at the one place the claim is actually made to the reader: no future
    // degrade path can reintroduce "the analysis failed, so let us print the reassuring answer".
    const Verdict shownVerdict = r.ok ? r.verdict : Verdict::Unknown;
    ASSUME( r.ok || shownVerdict == Verdict::Unknown );

    rw::emitTo( out, "<ref name=\"{}\" tip=\"{:.9}\" date=\"{}\" base=\"{:.9}\" ok=\"{}\" v=\"{}\" stray=\"{}\" files=\"{}\" superseded=\"{}\">",
                  ex( r.ref.name ).c_str(), r.ref.tip.c_str(), ex( r.ref.date ).c_str(), r.base.c_str(),
                  r.ok ? 1 : 0, verdictTag( shownVerdict ), r.strayLines, r.strayFiles, r.supersededLines );

    // The <more/> contract: shown + dropped == the total, always. Count against the CAP (maxFiles), never
    // against a loop variable the break has already incremented past it — that off-by-one is what made
    // whereis claim 20 dropped where 21 were, and it vanished entirely at exactly cap+1.
    std::size_t shownCount = 0;
    for( const FileRow& f : r.files )
    {
        if( shownCount >= maxFiles )
        {
            break;
        }
        ++shownCount;
        writeStrayFile( out, f, ex );
    }
    ASSUME( shownCount == std::min( r.files.size(), maxFiles ) );
    if( r.files.size() > maxFiles )
    {
        rw::emitTo( out, "<more files=\"{}\"/>", r.files.size() - maxFiles );
    }
    rw::emitRaw( out, "</ref>" );
}

// §P15/§P16: res.refs is already deterministic (strayLines desc, then ref.name asc — computeStrayContent's
// own sort) and used to print every stray ref unconditionally, with no historic display cap on the OUTER
// listing (only the per-ref <file> children were ever capped, at maxFiles, which stays untouched — a second,
// independent listing per rule 6). Paging mirrors writeWhereisPage: pageLimit/pageOffset default to 0 (no
// paging, the un-paginated three-argument writeStrayContent below keeps every existing caller byte-identical).
inline void writeStrayContentPage( std::FILE* out, const StrayResult& res, std::size_t maxFiles, int pageLimit, int pageOffset )
{
    std::vector<char> esc;
    const XmlEscaper  ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };

    // Every scanned ref lands in EXACTLY ONE bucket, so unmerged + superseded + merged + unknown == refs=.
    // Before the unknown bucket existed, a ref whose analysis failed landed in none of them and the header
    // silently failed to add up — the counters and refs= disagreeing was the first visible symptom.
    std::uint32_t unmerged = 0, superseded = 0, unknown = 0;
    for( const RefRow& r : res.refs )
    {
        if( !r.ok || r.verdict == Verdict::Unknown )
        {
            ++unknown;
        }
        else if( r.verdict == Verdict::Unmerged )
        {
            ++unmerged;
        }
        else if( r.verdict == Verdict::Superseded )
        {
            ++superseded;
        }
    }
    ASSUME( std::size_t( unmerged ) + superseded + unknown + res.mergedRefs == res.refsScanned );

    // G4: an XML comment may not contain a double hyphen, so this text (and writeWhereis's) names flags and
    // git subcommands WITHOUT their leading dashes. Keep it that way when editing.
    rw::emitRaw( out, "<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base "
                       "with HEAD) that the live line does NOT have. v=\"superseded\" means the live line removed the same "
                       "base code this ref removed (redone/del) — it re-implemented the work, the case `git cherry` cannot "
                       "see; v=\"unmerged\" means the work is genuinely absent; merged refs are omitted. Read-only: git "
                       "cat-file/diff/ls-tree only, one batched cat-file for the whole sweep, every blob reduced once per "
                       "sha. Line-granular, not semantic: see the ripwire help text for the limits. ANCHORING is a "
                       "deliberate hybrid: the SCOPE is base anchored (only lines the ref itself authored vs its merge base "
                       "are ever considered, so a file the ref never opened cannot appear because the live line moved), "
                       "while the ABSENCE test is HEAD anchored on purpose (does the live line have this content TODAY is "
                       "the question being asked, and it is only answerable against live HEAD). v=\"unknown\" with ok=\"0\" "
                       "means this ref could NOT be analysed at all because it has no merge base with HEAD, which on a "
                       "SHALLOW clone (the checkout default in CI) is every ref: it is not a claim that the ref is merged, "
                       "and the fix is to deepen the clone. The four buckets are exhaustive, so unmerged plus superseded "
                       "plus merged plus unknown always equals refs. "
                       "diffable=\"0\" on a file row (present only then) means a binary or oversized blob on some side: "
                       "the path is listed rather than dropped, but it cannot be line diffed, so its counts are 0, not measured. "
                       // §B12.2 — the same scope clause as whereis, in the same words, because the two verbs are read
                       // together and used to over claim in the same way ("across ALL branches").
                       "SCOPE: refs/heads only, which is every local branch (worktree branches included). Remote "
                       "tracking refs are NOT scanned: they mirror local ones in the usual checkout and would double "
                       "every row. The consequence on a FRESH CLONE, where the branches live under refs/remotes/origin "
                       "and only the checked out one has a local head, is that there is nothing here to be stray FROM; "
                       "refs= is that fact as a number. "
                       // §B8.2 — the per ref truncation vocabulary, defined where it is emitted.
                       "TRUNCATION: a ref row ends with a more element (more files=N) when its own file listing was "
                       "capped; shown plus that number equals the ref's files= total, always. That inner listing is a "
                       "SECONDARY listing (it repeats complete and identical on every page) and is capped by detail, not "
                       "by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. "
                       "at= is the git commit these numbers were computed at; a trailing +shallow means the clone's history is truncated (a depth-limited clone: churn counts only the commits present), and a trailing +dirty means the working tree "
                       "differed from that commit (head= is the same commit, bare sha, kept for compatibility). "
                       "refs_dropped= (present only when non-zero) is how many local branches git listed that this sweep "
                       "could NOT read (a tip that is not an object name): they are in none of the counts, so refs= and the "
                       "four buckets describe only the branches that were swept. -->" );
    // §P8: shipped as `head-ref=` while its own --abi sibling (abicheck.h's `<abi head_ref=>`, over the SAME
    // field, reached by the SAME command line) shipped `head_ref=` — the tool's only kebab/snake pair, so a
    // parser written against one half read nothing from the other. Unified onto snake_case: it is the
    // majority (41 vs 8) and the spelling README.md documents. Kebab survives only in docs/captures/*.
    const PageWindow  refPage = pageWindow( res.refs.size(), pageLimit, pageOffset );
    char              srab[ kPageDisclosureCap ];
    // M10: head= stays a bare 9-hex sha (gitstampcheck.sh's existing arm pins that spelling); at= is the
    // new attribute, carrying the dirty bit this document never disclosed before.
    const std::string atAttrStr = res.atStamp.empty() ? std::string() : ( " at=\"" + res.atStamp + "\"" );
    // H14/M6: refs="2" under a ref-name filter reads as "this repo has two branches" unless the filter is
    // named. --doc-drift already echoed its own filter=; this is the same attribute on a sibling that did not.
    const std::string filterAttr = res.filter.empty() ? std::string() : ( " filter=\"" + ex( res.filter ) + "\"" );
    const std::string droppedAttr = res.refsDropped == 0 ? std::string() : ( " refs_dropped=\"" + std::to_string( res.refsDropped ) + "\"" );
    rw::emitTo( out, "<stray-content head=\"{:.9}\" head_ref=\"{}\" refs=\"{}\" blobs=\"{}\" unmerged=\"{}\" superseded=\"{}\" merged=\"{}\" unknown=\"{}\"{}{}{}{}>",
                  res.headSha.c_str(), ex( res.headRef ).c_str(), res.refsScanned, res.distinctBlobs, unmerged, superseded, res.mergedRefs, unknown,
                  filterAttr.c_str(), droppedAttr.c_str(),
                  pageDisclosure( srab, sizeof( srab ), refPage.end - refPage.begin, res.refs.size(), refPage.end, pageLimit, pageOffset, false ),
                  atAttrStr.c_str() );
    for( std::size_t refIndex = refPage.begin; refIndex < refPage.end; ++refIndex )
    {
        writeStrayRef( out, res.refs[refIndex], ex, maxFiles );
    }
    rw::emitRaw( out, "</stray-content>" );
}

inline void writeStrayContent( std::FILE* out, const StrayResult& res, std::size_t maxFiles )
{
    writeStrayContentPage( out, res, maxFiles, 0, 0 );
}

// ── §B11.2: the qualified spelling this verb has no selector for ─────────────────────────────────────────
// --whereis matches a symbol NAME against ref-tree text. Handed a `file:name` spelling — the grammar nine
// other verbs DO accept, and the exact thing an agent pastes out of a `p="file:line"` row or a --uses retry
// example — it searched for that literal string, found it in no tree, and answered hits="0": true, useless,
// and BYTE-IDENTICAL to the answer for a name this repo never had. That is the V2-1 guard's uncovered arm
// (its `uses` twin was closed in §B6 M6). Every other zero this verb prints is a measurement; this one is a
// spelling error wearing a measurement's clothes.
//
// The test is SYNTACTIC and therefore index-free, which is what lets it hold on both surfaces: the MCP
// `whereis` verb deliberately never calls getIndex() (no rebuild, no staleness coupling), so a guard that
// needed an IngestResult could only ever have covered the CLI — the one-arm asymmetry this whole class is.
// Because it lives in the writer, both surfaces inherit it with no call-site change at all.
//
// Deliberately NOT a refusal: hits="0" here is a true statement, unlike `uses`' external="1" (a false claim
// about the indexed tree), so the proportionate fix is to make the zero legible, not to change an exit code.
// A `::` spelling is left alone — that is a canonical id or a C++/Ruby qualified name, not a path selector —
// and so is a file half with neither a path separator nor an extension shape, which keeps every ObjC selector
// (`doThing:withOther:`) and every unusual name answerable exactly as before.
inline bool whereisSpecIsFileQualified( std::string_view spec )
{
    if( spec.find( "::" ) != std::string_view::npos )
    {
        return false;
    }

    const std::size_t lastColon = spec.rfind( ':' );
    if( lastColon == std::string_view::npos || lastColon == 0 || lastColon + 1 >= spec.size() )
    {
        return false;
    }

    const std::string_view fileHalf = spec.substr( 0, lastColon );
    if( fileHalf.find( '/' ) != std::string_view::npos )
    {
        return true; // a path, unambiguously
    }

    // a bare file NAME with an extension ("engine.cpp:computeBudget"): the dot must sit inside the half and be
    // followed by a short all-alphanumeric run, so an ordinary identifier can never trip it.
    const std::size_t dot = fileHalf.rfind( '.' );
    if( dot == std::string_view::npos || dot == 0 || dot + 1 >= fileHalf.size() )
    {
        return false;
    }
    const std::string_view ext = fileHalf.substr( dot + 1 );
    if( ext.size() > 8 )
    {
        return false;
    }
    return std::all_of( ext.begin(), ext.end(), []( unsigned char c ) { return std::isalnum( c ) != 0; } );
}

// The bare-name half a caller should retype. Only meaningful when whereisSpecIsFileQualified( spec ).
inline std::string_view whereisBareNameOf( std::string_view spec )
{
    const std::size_t lastColon = spec.rfind( ':' );
    ASSUME( lastColon != std::string_view::npos && lastColon + 1 < spec.size() );
    return spec.substr( lastColon + 1 );
}

// A `Class.method` / `Class#method` spelling (2026-10-01, found by the edit-check lane): the way docs, Python, JS,
// Java and Ruby name a method. This verb searches its selector as a LITERAL, and no tree spells a method's
// definition that way (it is `def area` inside `class Shape`), so the scan answered hits="0" on-head="0"
// complete="1" with no note — a zero shaped exactly like a name this repo never had. The test is the shared
// resolver's dotted-scope tier condition (graph.h resolveAllByDottedScope on lane/editcheck-067: a '.' or '#', and
// no ':' or '/'), narrowed to identifier segments so a quoted literal with other punctuation is left alone.
inline bool whereisSpecIsDotted( std::string_view spec )
{
    if( spec.find_first_of( ".#" ) == std::string_view::npos || spec.find_first_of( ":/" ) != std::string_view::npos )
    {
        return false;
    }
    std::size_t segmentLen = 0;
    for( const char c : spec )
    {
        const bool separator = c == '.' || c == '#';
        if( separator && segmentLen == 0 )
        {
            return false;   // an empty segment: ".x", "a..b", "a#"
        }
        if( !separator && !isIdentByte( static_cast<unsigned char>( c ) ) )
        {
            return false;
        }
        segmentLen = separator ? 0 : segmentLen + 1;
    }
    return segmentLen > 0;
}

// The bare method name a caller should retype: the last segment. Only meaningful when whereisSpecIsDotted( spec ).
inline std::string_view whereisDottedNameOf( std::string_view spec )
{
    return spec.substr( spec.find_last_of( ".#" ) + 1 );
}

// The dotted-selector retry for `spec`, or "" when the note must not fire: a dotted spelling whose LAST SEGMENT the
// INDEX defines (so the offered retry finds a definition). `setup.py`, `os.path`, `README.txt` are literals a reader
// may legitimately ask this "defines or mentions" verb about, and their literal scan keeps its complete= (review M3).
// Once the shared dotted-scope resolver lands (graph.h resolveAllByDottedScope), this should ask it instead.
inline std::string whereisDottedRetryOf( const IngestResult& ing, std::string_view spec )
{
    if( !whereisSpecIsDotted( spec ) )
    {
        return {};
    }
    const std::string_view method = whereisDottedNameOf( spec );
    const bool defined = std::any_of( ing.symbols.begin(), ing.symbols.end(),
                                      [ & ]( const Symbol& s ) { return s.kind != SymKind::Section && s.name == method; } );
    return defined ? std::string( method ) : std::string();
}

// The legend's CONDITIONAL tail: each paragraph rides only an answer that carries what it defines, so a plain
// answer pays no bytes for the with_history lane, test-local rows or the worktree overlay. Split out of
// writeWhereisPage so the page writer stays a page writer.
// refs= on a hit rides only a definitions page that printed one (foldSharedBranchDefs), and so does its reading: the
// SHARED DEFINITIONS clause of the legend, spliced by writeWhereisListedPage beside the tail below.
inline constexpr char kWhereisSharedDefsLegend[] =
    "SHARED DEFINITIONS: refs=\"N\" on a kind=\"def\" row outside the checkout means N scanned refs hold this same "
    "definition line (the same path and the same line text; on a kind=\"text\" row, the same unparsed line, never merged "
    "with a confirmed one); the row is printed once, for the first of those "
    "refs by name, whose ref=, tip=, date= and l= it carries (another of the N may hold the line at a different "
    "line number). It appears only under listing=\"defs\" and only when N is at least 2: a definition one ref "
    "alone holds carries no refs=. hits= still counts every copy, and listing=all prints each ref's own row. ";

inline void writeWhereisLegendTail( std::FILE* out, const WhereResult& res )
{
    // §L10b: the with_history lane's own <history> element, previously undefined on this legend — shared
    // verbatim with --doc-drift's copy (gitoracle.h kHistoryProbeLegend) so the two cannot drift. Only
    // when res.history actually made that element reachable — an unconditional splice would cost every
    // plain --whereis run bytes describing an absent element.
    if( res.history != nullptr )
    {
        std::fputs( gitoracle::kHistoryProbeLegend, out );
    }
    // test_local= rides only an answer that holds both kinds of definition (demoteTestLocalDefs), and so does its reading.
    if( std::any_of( res.hits.begin(), res.hits.end(), []( const WhereHit& h ) { return h.testLocal; } ) )
    {
        rw::emitRaw( out, "TEST-LOCAL: test_local=\"1\" on a kind=\"def\" row marks a definition in a test scope (the index's test lens) "
                           "or under a test, bench or fixture path (test/, bench/, benches/, fixture/, fixtures/, testdata/ and the "
                           "test-file name patterns), on any row. It appears only when the same answer also "
                           "holds a production definition, and those rows are ordered after the production definitions and before "
                           "the references of their tier. Nothing is dropped. " );
    }
    // The unparsed element's vocabulary (writeWhereisUnparsed), only on an answer that carries the element. No literal
    // double dash inside this XML comment: the flag is spelled by name, the next= attribute carries its real spelling.
    if( res.branchLabels.leftByGuard + res.branchLabels.failed > 0 )
    {
        rw::emitTo( out, "UNPARSED: the unparsed element counts the blobs of other refs that hold a line worth parsing but that "
                           "no parse read: blobs= of them, either past the runaway guard on the parse batch ({} blobs or {} MB, filled "
                           "most rows first, then by path and blob) or a parse that could not finish; rows= is the kind=\"text\" rows they "
                           "gave. Those rows are neither a confirmed definition nor a confirmed reference, and the blobs' other rows read "
                           "kind=\"ref\". Its next= rides when the guard left some: the same question with the detail flag at 1, which "
                           "lifts the guard. ", kWhereisParseMaxBlobs, kWhereisParseMaxBytes >> 20 );
    }
    // The overlay's own vocabulary, only on an answer that carries it — a clean checkout pays no bytes for it.
    if( res.worktree != WorktreeOverlay::Clean )
    {
        rw::emitRaw( out, "WORKTREE: worktree= on the root means the checkout under this root differs from HEAD, so HEAD's "
                           "committed tree alone would be a stale answer. Every path that differs (modified, staged, deleted or "
                           "untracked and not ignored) is read from the working tree instead: its rows say ref=\"worktree\" (tip= "
                           "and date= name the HEAD commit it overlays) and REPLACE HEAD's rows for that path, so a definition the "
                           "edit added is listed and one it deleted or renamed is not. HEAD's rows stand only for paths the working "
                           "tree left alone. On such an answer on-head=, hits= and head_labels= read the CHECKOUT, HEAD plus those rows, not "
                           "HEAD's commit alone: on-head=\"0\" there means the checkout lacks the name, which HEAD's commit may still "
                           "hold. A path beyond a symbolic link to a directory is not in the checkout (git's own reading) and is never "
                           "read through the link. worktree=read: every differing path was read, and complete= keeps its meaning over "
                           "the checkout. worktree=partial: some differing path could not be read (permission, over the 2 MB ceiling, a "
                           "name git had to quote, a directory such as an untracked nested repository or a submodule, whose files are "
                           "another repository's, or more changed paths than one answer reads), so its HEAD rows stand and may be stale. worktree=unlisted: git "
                           "could not list the changes, so any HEAD row may be stale. Under partial or unlisted complete= is never "
                           "claimed. Other refs are always their committed trees. With the with_history lane, a name HEAD's commit holds "
                           "but the working tree removed gets fate v=\"uncommitted\" instead of the history oracle's never or removed. " );
    }
}

// The selector-note elements, first after the root: each says which KIND of zero (or of literal) the reader holds.
inline void writeWhereisSelectorNotes( std::FILE* out, const WhereResult& res, const XmlEscaper& ex )
{
    // §B11.2 — a zero that is a SPELLING fact, not a repository fact, says so. Emitted first, before the
    // history lane, so it is the first thing after the root on the one shape where it fires: hits="0" AND a
    // file-qualified selector. It never appears beside a nonzero hit list, so it cannot dilute a real answer.
    if( res.hits.empty() && whereisSpecIsFileQualified( res.sym ) )
    {
        rw::emitTo( out, "<selector-note r=\"qualified-selector\" spec=\"{}\" retry=\"{}\"/>",
                      ex( res.sym ).c_str(), ex( whereisBareNameOf( res.sym ) ).c_str() );
    }
    // The dotted spelling, on EVERY answer that carries one: a nonzero list is the literal's occurrences (call sites
    // like `Shape.area(…)`), never the definition, so the note rides beside it too. Only when the caller found that the
    // INDEX defines the last segment (dottedRetry) — `setup.py` or `os.path` is a literal, not a method (review M3).
    if( !res.dottedRetry.empty() )
    {
        rw::emitTo( out, "<selector-note r=\"dotted-selector\" spec=\"{}\" retry=\"{}\"/>",
                      ex( res.sym ).c_str(), ex( res.dottedRetry ).c_str() );
    }
    // H7: the same element, two more reasons — the line seed that was RESOLVED before the scan (so sym= is a
    // name and not the raw @spec), and the near-miss beside a zero the index can explain.
    if( !res.seedSpec.empty() )
    {
        rw::emitTo( out, "<selector-note r=\"line-seed\" spec=\"{}\" retry=\"{}\"/>",
                      ex( res.seedSpec ).c_str(), ex( res.sym ).c_str() );
    }
    // Review M7: a zero for a name the WORKING TREE renamed offers the new name (worktreeRenameOf's evidence: a
    // definition of SYM left a changed file that now defines this one), ahead of — and instead of — a spelling neighbour.
    if( res.hits.empty() && !res.renamedTo.empty() )
    {
        rw::emitTo( out, "<selector-note r=\"renamed\" spec=\"{}\" retry=\"{}\"/>",
                      ex( res.sym ).c_str(), ex( res.renamedTo ).c_str() );
    }
    else if( res.hits.empty() && !res.nearMiss.empty() )
    {
        rw::emitTo( out, "<selector-note r=\"near-miss\" spec=\"{}\" retry=\"{}\"/>",
                      ex( res.sym ).c_str(), ex( res.nearMiss ).c_str() );
    }
}

// The with_history lane, when it was asked for: what the probe did, then this symbol's own verdict (see the comment
// at the call site for why an index-confirmed HEAD definition suppresses the verdict). Review M8: on a dirty checkout
// a zero (on-head="0") may be a name HEAD's COMMITTED tree still holds and only the uncommitted working tree removed.
// The oracle's "never" / "removed" read a zero as "HEAD does not have it", which is false there, so that case gets
// its own verdict, v="uncommitted", naming what is true.
inline void writeWhereisFate( std::FILE* out, const WhereResult& res, const XmlEscaper& ex )
{
    if( res.history == nullptr )
    {
        return;
    }
    gitoracle::writeHistoryProbe( out, *res.history, ex );
    if( !res.history->ok || ( res.onHead && res.headLabelsFromIndex ) )
    {
        return;
    }
    if( res.headHolds && !res.onHead )
    {
        rw::emitTo( out, "<fate sym=\"{}\" v=\"uncommitted\" note=\"HEAD's commit still holds this name; only the uncommitted "
                         "working tree removed it\"/>", ex( res.sym ).c_str() );
        return;
    }
    gitoracle::writeNameFate( out, res.sym, res.fate, ex );
}

// ── the listing and the hoist (lean-answers lane) ────────────────────────────────────────────────────────

// The rows one --whereis answer lists (see WhereisListing): indices into WhereResult::hits in the list's own order,
// the root's listing= value ("" when every hit is listed), and how many kind="ref" rows the <refs count=> element
// stands for (0 = no such element).
struct ListedHits
{
    std::vector<std::size_t> rows;
    std::string_view         attr;
    std::size_t              refsElided = 0;
    std::size_t              defsFolded = 0;   // def rows of other refs a listed row's refs= stands for (folded="N" on the root)
};

// kind= of a row: "def" (a parser's definition), "text" (a parse-worthy line on another ref no parse confirmed,
// labelBranchRowsByParse) or "ref".
inline const char* whereisKindOf( const WhereHit& h ) noexcept
{
    return h.isDef ? "def" : ( h.unconfirmed ? "text" : "ref" );
}

// The ` refs="N"` a row carries, or "": it rides ONLY the definitions page (foldSharedBranchDefs), where the row stands
// for N refs' copies of the same definition line. listing=all prints each copy as its own row and never carries it; a
// lone copy carries none. The legend's SHARED DEFINITIONS clause rides exactly the pages where this is non-empty.
inline std::string whereisSharedAttr( const ListedHits& listed, const WhereHit& h )
{
    return ( listed.attr == "defs" && h.defRefs >= 2 ) ? ( " refs=\"" + std::to_string( h.defRefs ) + "\"" ) : std::string();
}

inline ListedHits listedHits( const WhereResult& res, WhereisListing listing )
{
    EXPECTS( listing != WhereisListing::ShorterOfDefsAll, "the default is resolved to Defs or All (whereisServedListing) before the rows are picked" );
    // The definitions page lists the kind="def" rows AND the kind="text" ones (parse-worthy lines on another ref
    // that no parse confirmed or refuted, labelBranchRowsByParse): a possible definition is printed, labelled, never
    // counted away among the references. listing=refs and <refs count=> are the kind="ref" rows exactly.
    const std::size_t defs = std::size_t( std::count_if( res.hits.begin(), res.hits.end(), []( const WhereHit& h ) { return h.isDef || h.unconfirmed; } ) );
    const std::size_t refs = res.hits.size() - defs;
    ListedHits out;
    // Defs with nothing to elide (no ref row) IS the whole list; Defs with no def row would list nothing but a count,
    // and then the mentions are the answer (a name the index does not define, a literal): both print every hit.
    const bool lean = listing == WhereisListing::Defs && defs > 0 && refs > 0;
    if( !lean && listing != WhereisListing::Refs )
    {
        out.rows.resize( res.hits.size() );
        for( std::size_t i = 0; i < res.hits.size(); ++i ) { out.rows[ i ] = i; }
        return out;
    }
    // The definitions page lists each shared branch definition ONCE (foldSharedBranchDefs): a folded row's line is
    // already on the page, on its representative, whose refs= counts it. The whole list (listing=all) keeps every row.
    const bool  wantDefs = lean;
    std::size_t folded   = 0;
    for( std::size_t i = 0; i < res.hits.size(); ++i )
    {
        const WhereHit& h = res.hits[ i ];
        if( ( h.isDef || h.unconfirmed ) != wantDefs ) { continue; }
        if( wantDefs && h.foldedDef ) { ++folded; continue; }
        out.rows.push_back( i );
    }
    out.attr       = wantDefs ? std::string_view( "defs" ) : std::string_view( "refs" );
    out.refsElided = wantDefs ? refs : 0;
    out.defsFolded = folded;
    ENSURES( out.rows.size() + folded == ( wantDefs ? defs : refs ), "a listing holds exactly the rows of its kind, a folded def on its representative" );
    return out;
}

// HEAD's committer date, read off the first row on HEAD's commit (every such row carries the same date: the scan
// stamps a ref's rows with its tip's date). "" when no row is on HEAD's commit (a branch-only answer, hits="0").
inline std::string whereisHeadDate( const WhereResult& res )
{
    const std::string_view head = std::string_view( res.headSha ).substr( 0, 9 );
    for( const WhereHit& h : res.hits )
    {
        if( !head.empty() && std::string_view( h.tip ).substr( 0, 9 ) == head )
        {
            return h.date;
        }
    }
    return {};
}

// Whether a row's tip= and date= are exactly the root's at= (as printed: 9 hex, without +dirty) and head_date=, so the
// row may omit both and a reader restores them losslessly. Compared on the PRINTED 9-hex spelling, the bytes a reader holds.
inline bool whereisRowOnHeadCommit( const WhereHit& h, std::string_view headSha, std::string_view headDate ) noexcept
{
    const std::string_view head = headSha.substr( 0, 9 );
    return !head.empty() && !headDate.empty() && std::string_view( h.tip ).substr( 0, 9 ) == head && h.date == headDate;
}

// The listing a validated --whereis-listing= / MCP `listing` value names; "" (absent) is the default, defs when it
// lists more definitions than all, else the shorter of the two (WhereisListing::ShorterOfDefsAll). Both surfaces refuse any other value before they get here.
inline WhereisListing whereisListingOf( std::string_view v ) noexcept
{
    return v == "refs" ? WhereisListing::Refs : v == "all" ? WhereisListing::All
         : v == "defs" ? WhereisListing::Defs : WhereisListing::ShorterOfDefsAll;
}

// The <refs next=>: the same symbol, listing=refs — exactly the kind="ref" rows the default listing counted.
inline std::string whereisRefsNext( const WhereResult& res )
{
    return nextFlag( "--whereis=", res.sym ) + " --whereis-listing=refs";
}

// The page a --whereis answer prints: the listed rows and the window over them (writeWhereisPage's own reading of its
// arguments, handed to the two writers below so neither re-derives it).
struct WhereisPageView
{
    const ListedHits& listed;
    PageWindow        page;
    int               pageLimit  = 0;
    int               pageOffset = 0;
};

// The <whereis …> open tag (writeWhereisPage).
inline void writeWhereisRoot( std::FILE* out, const WhereResult& res, const WhereisPageView& v, const std::string& headDate,
                              const XmlEscaper& ex )
{
    const ListedHits& listed      = v.listed;
    const PageWindow& hitPage     = v.page;
    const std::size_t listedCount = listed.rows.size();
    const int         pageLimit   = v.pageLimit;
    const int         pageOffset  = v.pageOffset;
    char pab[ kPageDisclosureCap ];
    // §A7(iii): refs_scanned=, not refs=. --stray-content and --abi both spell the MATCHED set refs=; this one
    // counted every branch the sweep READ (73 here, matched or not) under the same attribute name — one noun,
    // two meanings, across sibling verbs an agent reads together.
    // T1: the claim is scan-exhaustiveness AND listing-wholeness — an uncut page over a clean scan. Appended
    // LAST (after at=) so no existing attribute-adjacency assertion can break on it, the same placement rule
    // the graph verbs' floor marker follows. When either half fails, NOTHING is added: the truncation
    // vocabulary above already covers every partial shape, and complete-equals-zero would be noise.
    // A dotted selector was searched as a literal the question did not mean: exhaustive over that literal, but not
    // an answer to "where is Class.method", so it never claims (its selector-note below says why).
    // listing= (WhereisListing): the claim reads the LISTED rows — under listing=defs every def row on this page (the
    // ref rows are counted exactly by <refs count=>, never silently gone); under listing=refs every ref row.
    const bool completeClaim = res.scanExhaustive && hitPage.begin == 0 && hitPage.end == listedCount && res.dottedRetry.empty();
    // H14/M6: refs_scanned="80" under a ref-name filter is a total for the FILTER, not for the repo (the
    // audit measured 80 filtered vs 189 unfiltered) — so the filter is named beside the number it bounds.
    const std::string whFilterAttr = res.filter.empty() ? std::string() : ( " filter=\"" + ex( res.filter ) + "\"" );
    // The overlay's two marks, both absent on a clean checkout (so its answer is byte-identical to before): +dirty
    // on the stamp whenever a differing path was seen, and worktree= naming what the overlay managed.
    static constexpr std::string_view kWorktreeAttr[] = { "", " worktree=\"read\"", " worktree=\"partial\"", " worktree=\"unlisted\"" };
    const bool dirty = res.worktree == WorktreeOverlay::Read || res.worktree == WorktreeOverlay::Partial;
    // THE HOIST (lossless): a checkout row on HEAD's own commit repeats tip= (= at= without +dirty) and date= (HEAD's
    // committer date) on every row. Those rows omit both, and the root says the date ONCE (head_date=) — only when a
    // printed row actually omitted it, so a page of branch rows alone is unchanged. Placed before at= so the at= /
    // worktree= / complete= adjacency every existing assertion reads stays byte-stable.
    bool              anyHoist  = false;
    for( std::size_t k = hitPage.begin; k < hitPage.end; ++k )
    {
        anyHoist = anyHoist || whereisRowOnHeadCommit( res.hits[ listed.rows[ k ] ], res.headSha, headDate );
    }
    // folded= (foldSharedBranchDefs): the def rows of other refs that a listed row's refs= stands for, so the root's
    // arithmetic stays checkable in one place: shown + more + folded + refs count = hits. Only when a row folded,
    // so an answer with no shared branch definition is byte-identical to before.
    // ref_labels="parsed": the answer holds rows of OTHER refs, whose kind= a parser gave (labelBranchRowsByParse). Only
    // then, so an answer with no branch row — a repo with no other ref — is byte-identical to before.
    const bool        anyBranchRow = std::any_of( res.hits.begin(), res.hits.end(), []( const WhereHit& h ) { return !h.inCheckout(); } );
    const std::string listingAttr  = ( listed.attr.empty() ? std::string() : ( " listing=\"" + std::string( listed.attr ) + "\"" ) )
                                   + ( listed.defsFolded > 0 ? ( " folded=\"" + std::to_string( listed.defsFolded ) + "\"" ) : std::string() )
                                   + ( anyBranchRow ? std::string( " ref_labels=\"parsed\"" ) : std::string() );
    const std::string headDateAttr = anyHoist ? ( " head_date=\"" + ex( headDate ) + "\"" ) : std::string();
    rw::emitTo( out, "<whereis sym=\"{}\" on-head=\"{}\" refs_scanned=\"{}\" blobs=\"{}\" hits=\"{}\" head_labels=\"{}\"{}{}{}{} at=\"{:.9}{}\"{}{}>",
                  ex( res.sym ).c_str(), res.onHead ? 1 : 0, res.refsScanned, res.distinctBlobs, res.hits.size(),
                  res.headLabelsFromIndex ? "index" : "lexical", whFilterAttr.c_str(),
                  pageDisclosure( pab, sizeof( pab ), hitPage.end - hitPage.begin, listedCount, hitPage.end,
                                  pageLimit, pageOffset, true ),
                  listingAttr.c_str(), headDateAttr.c_str(),
                  res.headSha.c_str(), dirty ? "+dirty" : "",
                  kWorktreeAttr[ std::size_t( res.worktree ) ],
                  completeClaim ? " complete=\"1\"" : "" );

}

// <unparsed blobs= rows= next=>: the other refs' (blob, path) pairs that held a parse-worthy row and confirm
// nothing — the runaway guard left them (WhereisParseBudget) or the parser could not finish — and the rows of theirs
// that read kind="text". next= rides only when the guard left some: --detail=1 lifts it. Absent when every
// parse-worthy blob was parsed (or mirrored HEAD's), so an answer the guard never touched is byte-identical.
inline void writeWhereisUnparsed( std::FILE* out, const WhereResult& res )
{
    const BranchLabelCensus& c = res.branchLabels;
    if( c.leftByGuard + c.failed == 0 )
    {
        return;
    }
    std::string next;
    if( c.leftByGuard > 0 )
    {
        std::string call = nextFlag( "--whereis=", res.sym );
        if( !res.filter.empty() )
        {
            call += " " + nextFlag( "--stray-content=", res.filter );   // the ref filter that made this page
        }
        next = nextAttrXml( call + " --detail=1" );
    }
    rw::emitTo( out, "<unparsed blobs=\"{}\" rows=\"{}\"{}/>", c.leftByGuard + c.failed, c.textRows, next.c_str() );
}

// The rows of the page, its <more hits=> remainder and the <refs count= next=> element (writeWhereisPage).
inline void writeWhereisRows( std::FILE* out, const WhereResult& res, const ListedHits& listed, const PageWindow& hitPage,
                              const std::string& headDate, const XmlEscaper& ex )
{
    const std::size_t listedCount = listed.rows.size();
    // The <more/> contract, restated because it was false here: shown + dropped == the listed rows, ALWAYS. The
    // count must be taken against the CAP, not against a loop variable `shown++ >= cap` has already pushed to
    // cap+1 — that off-by-one under-reported every drop by exactly one row (81 hits, 60 shown, "20" dropped),
    // and at exactly cap+1 hits `size > shown` went false, so the element vanished and a row disappeared
    // unmarked. Nothing is dropped without a number is a headline claim; keep it arithmetically true.
    std::size_t shownCount = 0;
    for( std::size_t k = hitPage.begin; k < hitPage.end; ++k )
    {
        const WhereHit& h = res.hits[ listed.rows[ k ] ];
        ++shownCount;
        if( whereisRowOnHeadCommit( h, res.headSha, headDate ) )
        {
            rw::emitTo( out, "<hit ref=\"{}\" p=\"{}\" l=\"{}\" kind=\"{}\"{} t=\"{}\"/>",
                          ex( h.ref ).c_str(), ex( h.path ).c_str(),
                          h.line, whereisKindOf( h ), h.testLocal ? " test_local=\"1\"" : "", ex( h.text ).c_str() );
            continue;
        }
        rw::emitTo( out, "<hit ref=\"{}\" tip=\"{:.9}\" date=\"{}\" p=\"{}\" l=\"{}\" kind=\"{}\"{}{} t=\"{}\"/>",
                      ex( h.ref ).c_str(), h.tip.c_str(), ex( h.date ).c_str(), ex( h.path ).c_str(),
                      h.line, whereisKindOf( h ), h.testLocal ? " test_local=\"1\"" : "", whereisSharedAttr( listed, h ).c_str(), ex( h.text ).c_str() );
    }
    ASSUME( shownCount == hitPage.end - hitPage.begin );
    // <more hits="N"/> = the LISTED rows AFTER this page, so shown + more == the listed rows from this page's offset
    // on. Un-paginated that is the historic "listed rows minus the 60 printed"; paged it is what the NEXT page holds
    // (and next_offset= on the root says where to ask for it).
    if( hitPage.end < listedCount )
    {
        rw::emitTo( out, "<more hits=\"{}\"/>", listedCount - hitPage.end );
    }
    // The elided ref rows, COUNTED and one pasteable call away: count= is exact (every kind="ref" row of the hit list,
    // whatever page this is), and next= lists exactly them. Not a <more> element: <more hits=> is this listing's own
    // page remainder, and a reader (or a gate) that reads "<more" as "this page was cut" must not see one here.
    if( listed.refsElided > 0 )
    {
        rw::emitTo( out, "<refs count=\"{}\"{}/>", listed.refsElided, nextAttrXml( whereisRefsNext( res ) ) );
    }
}

// Contract-level defect: this verb said hits="2560" and printed 60, and
// --limit/--offset were accepted and ignored, so a paging loop over it never advanced and never ended.
// `pageLimit`/`pageOffset` (0 = un-paginated) window the hit list, which is already deterministically
// ordered (HEAD first, then refs). The root gains shown= + capped= UNCONDITIONALLY — disclosing the silent
// cap is the point, so that one attribute pair is the deliberate break in the un-paginated byte shape.
// <more hits="N"/> stays: it is the same fact from the other end (what this page did NOT print), and its
// arithmetic contract (shown + dropped == the rows still ahead) is kept exact.
//
// Paging lives in its own entry point rather than as two defaulted parameters on writeWhereis() so the
// un-paginated contract — the one the MCP `whereis` verb calls — keeps its exact three-argument shape.
inline void writeWhereisListedPage( std::FILE* out, const WhereResult& res, std::size_t maxHits, int pageLimit, int pageOffset,
                                    const ListedHits& listed )
{
    std::vector<char> esc;
    const XmlEscaper  ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };

    // The emitted window. An explicit --limit overrides maxHits (the caller's 60-hit display default, or
    // SIZE_MAX under --detail); --offset skips whole rows and clamps at the end, so offset-past-the-end is
    // an empty page rather than an out-of-range read. maxHits can be SIZE_MAX, which pageWindow's int limit
    // cannot carry — clamp the "no explicit --limit" arm to the row count instead of overflowing it.
    const std::size_t listedCount = listed.rows.size();
    const int         rowCap  = pageLimit > 0 ? pageLimit
                              : ( maxHits >= listedCount ? int( listedCount ) : int( maxHits ) );
    const PageWindow  hitPage = pageWindow( listedCount, rowCap, pageOffset );

    rw::emitRaw( out, "<!-- ripwire whereis: every LOCAL ref whose TREE contains this symbol, HEAD first, and within a ref "
                       "SOURCE files before test files before docs, then definitions before references, then path and line. "
                       "The doc demotion is ORDER ONLY: it changes no label, it prints doc rows after the code. kind= is a PARSER's "
                       "answer: with head_labels=\"index\" a HEAD row is kind=\"def\" iff the PARSED index puts a definition there "
                       "(one row per index def site); a row of ANOTHER ref (ref_labels=\"parsed\") is kind=\"def\" iff the index's own "
                       "extraction, run over that ref's blob, captures a definition of the name there (once per distinct blob and path; "
                       "a ref holding HEAD's own blob of the path takes HEAD's labels). Only a blob holding a line a loose LEXICAL test calls "
                       "worth parsing is parsed: every row of a blob without one is kind=\"ref\", so a definition that test misses (a "
                       "signature wrapped before its parameter list closes, a name alone under its return type), alone in its blob, is "
                       "a counted ref. kind=\"text\" is a line worth parsing whose blob no parse read (the unparsed "
                       "element counts them and says why): not a confirmed definition, not a confirmed reference. With "
                       "head_labels=\"lexical\" (no index was supplied, the index knows no def of this name, or the working tree has "
                       "drifted from HEAD) HEAD's rows fall back to a stricter lexical shape test, which reads a quoted signature in a doc as a "
                       "definition and can miss an unusual declarator. refs_scanned= is the SCAN DENOMINATOR (how many refs besides HEAD were read), NOT a "
                       "count of refs that matched — hits= and the rows are the matched set. on-head=\"0\" alongside ref hits is the case this verb exists "
                       "for: content that lives only on a branch. A TREE scan can only find content some ref still carries, "
                       "so hits=\"0\" on its own does not distinguish a name this repo never had from one it deleted; run "
                       "with the with_history flag and the fate row says which, naming the commit that removed it. "
                       "ANCHORING: none, by design. This verb runs no diff at all — it scans each ref's FULL tree, which is "
                       "what lets it find content a branch merely INHERITED (exactly what a merge base anchored diff would "
                       "exclude), so nothing here can fire merely because HEAD moved. at= gains +dirty exactly when some path "
                       "under the root differs from HEAD, and then the answer reads that path's working copy (worktree= says how). "
                       // §B11.2 — the one zero this verb prints that is NOT a measurement, named in the legend.
                       "SELECTOR: this verb takes a BARE symbol name, not the file:name spelling that callers, uses, "
                       "impact, around, lego and edit_check accept. A file:name spelling is searched as a LITERAL "
                       "string, no tree contains it, and the result is a true but useless hits=\"0\" shaped exactly "
                       "like a name this repo never had. When that is what happened, a selector-note element says so "
                       "and its retry= is the bare name to re-run with. That element has five reasons, and r= names which: "
                       "qualified-selector (a file:name spelling was searched literally), dotted-selector (a Class.method or "
                       "Class#method spelling, whose last segment the INDEX defines, was searched literally, and no tree spells "
                       "a method's definition that way, so complete= is withheld and retry= is the bare method name, which lists "
                       "that name in every class; a dotted literal whose last segment the index does not define, such as a file "
                       "name, is an ordinary literal search with no note), renamed (the scan found nothing and the working tree "
                       "renamed the name: a definition of it left a changed file that now defines retry=), line-seed (an @FILE:LINE selector "
                       "was RESOLVED to the definition enclosing that line before the scan, so sym= is that definition's "
                       "name and spec= is what you typed), and near-miss (the scan found nothing and the INDEX holds a name "
                       "one or two edits away — the tree zero is still a measurement, the note only says which zero it is). "
                       "Its absence beside hits=\"0\" means the zero "
                       "IS a measurement. "
                       // §B12.2 — the SCOPE of "every ref", stated in the payload. Only the help text said "local".
                       "SCOPE: refs/heads only, which is every local branch (worktree branches included). "
                       "Remote tracking refs are NOT scanned: they mirror local ones in the usual checkout and would "
                       "double every row. The consequence on a FRESH CLONE, where the branches live under "
                       "refs/remotes/origin and only the checked out one has a local head, is that this verb sees "
                       "essentially one tree; refs_scanned= is that fact as a number, so read it before reading hits=. "
                       // §B8.2 — the truncation vocabulary this verb emits, defined where it is emitted.
                       "TRUNCATION: the trailing more element (more hits=N) is the rows AFTER this page, so shown plus "
                       "more equals the rows from this page's offset on. It is not a second cap, and not a second "
                       "vocabulary to page by: it is the SAME fact shown= / capped= / next_offset= carry, restated from "
                       "the other end (what this page did not print). Page with limit= and offset=; the more element is "
                       "absent exactly when this page reached the end of the hit list. "
                       // lean-answers lane — the default LISTING and the tip/date hoist, defined where they appear.
                       "LISTING: by default only the kind=\"def\" rows (and any kind=\"text\" row) are listed (listing=\"defs\" on the root) when that page lists "
                       "MORE definitions than the listing=all page lists under the same row cap (a capped all page can list fewer: "
                       "references can fill the cap before the branch definitions arrive), whatever its bytes, or, when both pages "
                       "list the same definitions, is STRICTLY shorter in bytes than the all page (both compared without limit= or "
                       "offset=, as written and in the compact dialect, so every page of one answer lists the same rows); "
                       "otherwise the default lists every hit. Under listing=\"defs\" the "
                       "kind=\"ref\" rows are COUNTED by the trailing refs element: count= is exactly the number of kind=\"ref\" "
                       "rows in the hit list, none of them printed here, and its next= lists exactly those rows (listing=\"refs\", "
                       "the same rows byte for byte that listing=all prints). listing= is absent when every hit is listed: the hit "
                       "list holds no kind=\"ref\" row, or no kind=\"def\" row (then the mentions are the answer), or the defs page "
                       "would neither list more definitions nor be shorter, or the whole list was asked for (the whereis-listing flag, value all; its value defs "
                       "lists the definitions whatever the size). Under listing=\"defs\" a definition line that several refs hold "
                       "(the same path and line text, outside the checkout) is one row with refs=\"N\", defined below when one rides, "
                       "and folded= on the root counts the rows so folded: on the first page, shown plus more plus folded plus the refs count equals hits. "
                       "kind=\"def\" on a HEAD row is the parser's label, not a proof: a "
                       "definition the parser does not model (a Ruby define_method, a setattr, a name bound by assignment such as an "
                       "alias in a class body) is a kind=\"ref\" row, so under listing=\"defs\" it is among the counted refs. "
                       "shown=, capped=, the paging attributes and the more "
                       "element window the LISTED rows; hits= still counts every row. "
                       "TIP AND DATE: a row whose commit is HEAD's omits tip= and date=: its tip is at= without +dirty and its "
                       "date is head_date= on the root. Every other row carries both. "
                       // T1 — the completeness claim, the mirror of the truncation vocabulary, defined where it appears.
                       "COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not "
                       "re-derive it: every occurrence of the symbol in every TEXT blob of every scanned ref's full tree is printed "
                       "above, or under listing=\"defs\" every such kind=\"def\" and kind=\"text\" row is printed and every kind=\"ref\" row counted "
                       "by the refs element (under listing=\"refs\", every kind=\"ref\" row) — nothing was capped or paged out, and "
                       "no blob was oversized (over the 2 MB blob ceiling), missing or cut short by the stream. The denominator is refs_scanned= plus HEAD, under SCOPE above (local heads only), "
                       "so with complete= present a ref absent from the rows genuinely lacks the symbol in its committed tree. "
                       "Binary blobs are outside the claim (a text symbol cannot occur in one); an oversized TEXT blob suppresses "
                       "the claim instead of being silently skipped. Its ABSENCE claims nothing. "
                       "raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it). " );
    if( std::any_of( listed.rows.begin() + std::ptrdiff_t( hitPage.begin ), listed.rows.begin() + std::ptrdiff_t( hitPage.end ),
                     [ & ]( std::size_t i ) { return !whereisSharedAttr( listed, res.hits[ i ] ).empty(); } ) )
    {
        rw::emitRaw( out, kWhereisSharedDefsLegend );
    }
    writeWhereisLegendTail( out, res );
    std::fputs( "-->", out );
    const std::string headDate = whereisHeadDate( res );
    writeWhereisRoot( out, res, WhereisPageView{ listed, hitPage, pageLimit, pageOffset }, headDate, ex );
    writeWhereisSelectorNotes( out, res, ex );

    // The history lane, when it was asked for: what the probe did, then this symbol's own verdict.
    // §L10: the oracle answers "did any line carrying this name ever leave the tree", and a doc that merely
    // QUOTED the symbol (a stale capture file, a plan) counts as a line carrying the name — so a symbol very
    // much alive on HEAD could still get v="removed", citing the doc's deletion rather than the symbol's.
    // The fix is narrower than "suppress whenever on-head=1": a doc-only mention (a design doc quoting a name
    // whose code WAS deleted) also sets on-head=1 lexically, and that IS real rot the fate row must still
    // name — suppressing on plain on-head= would silence exactly that true positive. What distinguishes the
    // two is head_labels=: "index" means the PARSED index confirmed a real definition on HEAD (not just a
    // text hit), which is a claim strong enough to override the line-removal oracle outright. So the fate
    // row is printed unless the index itself already proved the symbol is defined on HEAD.
    writeWhereisFate( out, res, ex );
    writeWhereisUnparsed( out, res );

    writeWhereisRows( out, res, listed, hitPage, headDate, ex );
    rw::emitRaw( out, "</whereis>" );
}

// THE DEFAULT, MEASURED (review B1, then D1). First the definitions: the Defs page is served whenever it SHOWS more
// definitions than the All page under the row cap (a capped All page can list fewer), whatever its bytes. Only when both
// pages show the same definitions do the bytes decide. The Defs page pays a fixed overhead — listing=, the <refs count= next=> element
// and, under the compact legend, their readings — that eliding one or two short ref rows does not repay: on 24 of 58
// sampled symbols the Defs page was LONGER than the All page while listing fewer rows. So both pages are rendered and
// Defs is served only when it is STRICTLY shorter both as written (the full legend, whose prose is the same text on
// both pages, so this compares the payload) and as the compact dialect delivers it (its per-answer readings ride only
// the page that carries their attribute, so a reading the All page's ref rows trigger can tip either way). A tie serves All: equal
// bytes, more rows. Both pages are rendered UNPAGED over the same row cap, so the choice is a fact of the answer, not
// of --limit/--offset: every page of one answer lists the same rows. A render that fails serves All (the whole answer).
inline ListedHits whereisServedListing( const WhereResult& res, std::size_t maxHits, WhereisListing listing )
{
    if( listing != WhereisListing::ShorterOfDefsAll )
    {
        return listedHits( res, listing );
    }
    ListedHits defs = listedHits( res, WhereisListing::Defs );
    if( defs.attr.empty() )
    {
        return defs;   // Defs already degraded to every hit (no ref row, or no def row): nothing to compare
    }
    ListedHits all = listedHits( res, WhereisListing::All );
    // COMPLETE ANSWERS FIRST (orchestrator ruling 2026-10-08, review D1). Under the shared row cap the All page can list
    // FEWER definitions than the Defs page: HEAD's ref rows fill the cap before the branch definitions arrive. Both
    // lists are in hit-list order and Defs is the def subsequence, so the definitions the All page shows are a PREFIX
    // of the Defs page's: comparing the counts compares the sets. More definitions wins whatever its bytes; only equal
    // sets fall to the bytes rule below.
    // Counted as DEFINITION ROWS OF THE WHOLE LIST: on the Defs page a representative row stands for defRefs rows
    // (foldSharedBranchDefs), on the All page every row is its own. The prefix argument still holds: each def row
    // the All page shows is either a representative (on the Defs page no later than its own def-subsequence
    // position, so within the first n) or folds into one that precedes it, and every (representative, ref) pair
    // is counted once in defRefs — so the Defs page's weighted count is at least the All page's.
    const auto defsShown = [ & ]( const ListedHits& l )
    {
        const std::size_t n        = std::min( l.rows.size(), maxHits );
        const bool        weighted = l.attr == "defs";
        std::size_t       shown    = 0;
        for( std::size_t k = 0; k < n; ++k )
        {
            const WhereHit& h = res.hits[ l.rows[ k ] ];
            shown += !h.isDef ? 0 : ( weighted ? std::max<std::size_t>( h.defRefs, 1 ) : 1 );
        }
        return shown;
    };
    const std::size_t defsOnDefsPage = defsShown( defs );
    const std::size_t defsOnAllPage  = defsShown( all );
    ENSURES( defsOnDefsPage >= defsOnAllPage, "the All page's shown definitions are a prefix of the Defs page's" );
    if( defsOnDefsPage > defsOnAllPage )
    {
        return defs;
    }
    const Rendered defsPage = renderToString( [ & ]( std::FILE* f ) { writeWhereisListedPage( f, res, maxHits, 0, 0, defs ); } );
    const Rendered allPage  = renderToString( [ & ]( std::FILE* f ) { writeWhereisListedPage( f, res, maxHits, 0, 0, all ); } );
    const bool     defsShorter = defsPage.ok && allPage.ok && defsPage.text.size() < allPage.text.size()
                              && compactDeliveredBytesOrWritten( defsPage.text, "whereis" )
                                     < compactDeliveredBytesOrWritten( allPage.text, "whereis" );
    return defsShorter ? std::move( defs ) : std::move( all );
}

// One --whereis answer page: the listing it serves (whereisServedListing), then that page.
inline void writeWhereisPage( std::FILE* out, const WhereResult& res, std::size_t maxHits, int pageLimit, int pageOffset,
                              WhereisListing listing )
{
    // The LISTED rows (WhereisListing): indices into res.hits, in the hit list's own order, so a listing is a
    // subsequence of the whole list and its rows print byte-identically to the same rows of listing=all.
    const ListedHits listed = whereisServedListing( res, maxHits, listing );
    writeWhereisListedPage( out, res, maxHits, pageLimit, pageOffset, listed );
}

// The un-paginated form — unchanged contract, for callers that want the whole (capped) listing.
inline void writeWhereis( std::FILE* out, const WhereResult& res, std::size_t maxHits )
{
    writeWhereisPage( out, res, maxHits, 0, 0, WhereisListing::All );
}

}}   // namespace rw::crossref
