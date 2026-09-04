#pragma once

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
//   --stray-content    — per ref: the content the ref's own divergent work AUTHORED that the live line does
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
#include "gitoracle.h"          // the SHARED name-history oracle — the deleted-from-every-tree lane for whereis
#include "arch.h"               // fnv1a64
#include "infra/hashutil.h"     // fnv1aMultiply — the sanitizer-safe wrapping multiply (G1 runs -fsanitize=integer)
#include "infra/jsonesc.h"      // shSingleQuote
#include "serialize.h"          // escapeXml
#include "pageview.h"           // §P8: pageWindow / pageDisclosure — the shared --limit/--offset contract
#include "workspace.h"          // wsdetail::segmentsOf
#include "filter.h"             // §P11.5: rw::pathTierOf — the shared source/test/doc ORDERING tier
#include "infra/Diagnostics.h"  // VERIFY / DEGRADED_PATH_ALERT

#include "btree.hpp"      // gtl::btree_map — sorted iteration (house rule: never std::map)

#include <algorithm>
#include <atomic>       // the git-spawn pool's work index
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <string>
#include <string_view>
#include <thread>       // the git-spawn pool (fork/exec is the cost, not compute)
#include <unistd.h>     // getpid / unlink — the blob-batch temp list
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
    VERIFY( std::is_sorted( a.begin(), a.end() ) );
    VERIFY( std::is_sorted( b.begin(), b.end() ) );
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
    VERIFY( std::is_sorted( a.begin(), a.end() ) );
    VERIFY( std::is_sorted( b.begin(), b.end() ) );
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

    const std::string listPath = quality::cacheDirLadder() + "/ripwire-crossref-" + std::to_string( ::getpid() ) + ".shas";
    {
        std::FILE* lf = std::fopen( listPath.c_str(), "wb" );
        if( !lf )
        {
            st.startFailed = true;
            DEGRADED_PATH_ALERT( "crossref: cannot write the blob-batch list — cross-branch content unavailable" );
            return;
        }
        for( const std::string& s : shas )
        {
            std::fprintf( lf, "%s\n", s.c_str() );
        }
        std::fclose( lf );
    }

    const std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root )
                          + " cat-file --batch < " + shSingleQuote( listPath ) + " 2>/dev/null";
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        ::unlink( listPath.c_str() );
        st.startFailed = true;
        DEGRADED_PATH_ALERT( "crossref: git cat-file --batch failed to start — cross-branch content unavailable" );
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
            st.endedEarly = true;
            onBlob( shas[ served ], std::string_view{}, false );
            DEGRADED_PATH_ALERT( "crossref: git cat-file stream ended mid-blob — stopping the batch rather than risk misattributing content" );
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

    pclose( pipe );
    ::unlink( listPath.c_str() );
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

// Capture a git command's FULL multi-line stdout ("" on failure). quality::popenTrimmed already owns the
// popen-and-trim shape; this is the same call with the trim kept to trailing newlines only.
inline std::string gitCapture( const std::string& root, const std::string& tail )
{
    return quality::popenTrimmed( "git -c core.quotepath=false -C " + shSingleQuote( root ) + " " + tail );
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
inline std::vector<RefInfo> enumerateRefs( const std::string& root, std::string_view filter, const std::string& headSha,
                                           std::size_t* filterNameHits = nullptr )
{
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
            DEGRADED_PATH_ALERT( "crossref: for-each-ref yielded a ref whose tip is not an object name — skipping it" );
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
        DEGRADED_PATH_ALERT( "crossref: refusing a diff whose revision arguments are not resolved object names" );
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
template<class Body>
inline void parallelIndexed( std::size_t count, Body body )
{
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
        }
        return;
    }

    std::atomic<std::size_t> nextIndex{ 0 };
    const auto               worker = [ & ]()
    {
        // A throw escaping a std::thread entry is std::terminate — degrade to partial coverage instead. Only
        // the allocation seam can throw here (popen/parse), and a short answer beats killing the process.
        try
        {
            for( std::size_t i = nextIndex.fetch_add( 1 ); i < count; i = nextIndex.fetch_add( 1 ) )
            {
                body( i );
            }
        }
        catch( ... ) { DEGRADED_PATH_ALERT( "crossref: a git worker threw — this shard of the sweep is incomplete" ); }
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
        parallelIndexed( pairs_.size(), [ & ]( std::size_t i ) { rows_[i] = diffRaw( root, pairs_[i].a, pairs_[i].b ); } );
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

inline const char* verdictTag( Verdict v ) noexcept
{
    static const char* kTag[ kVerdictCount ] = { "merged", "superseded", "unmerged", "unknown" };
    static_assert( sizeof( kTag ) / sizeof( kTag[0] ) == kVerdictCount, "verdictTag table must cover every Verdict" );
    VERIFY( std::size_t( v ) < kVerdictCount );
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
    std::string          headSha;
    std::string          headRef;
    std::size_t          distinctBlobs = 0;
    std::size_t          refsScanned   = 0;
    std::uint32_t        mergedRefs    = 0;   // scanned, found fully present on the live line, and OMITTED below
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
    VERIFY( r.redone <= r.deleted );

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
};

// The merge-base probe — the one git call that must happen before the diff pairs are even known, and the
// only one in this phase. Runs on the pool: refs are independent and each writes its own slot.
inline RefPlumbing probeRefBase( const std::string& root, const RefInfo& ref, const std::string& headSha )
{
    RefPlumbing plumb;
    if( !isRevisionToken( ref.tip ) || !isRevisionToken( headSha ) )
    {
        plumb.ok = false;
        DEGRADED_PATH_ALERT( "crossref: ref tip or HEAD is not a resolved object name — refusing to probe, verdict is unknown" );
        return plumb;
    }

    plumb.base = quality::gitOneLine( root, "merge-base " + shSingleQuote( ref.tip ) + " " + shSingleQuote( headSha ) + " -- 2>/dev/null" );

    // The ANSWER is validated too, not just the question. It is git's own output today and therefore
    // well-formed — but that is an assumption, and this sha goes straight back out as the revision argument
    // to two more git commands. Anything that is not an object name is treated exactly like no merge-base.
    if( !plumb.base.empty() && !isRevisionToken( plumb.base ) )
    {
        DEGRADED_PATH_ALERT( "crossref: merge-base returned something that is not an object name — discarding it" );
        plumb.base.clear();
    }
    if( plumb.base.empty() )
    {
        // No merge-base: a SHALLOW clone (actions/checkout is shallow by default, so this is the CI default,
        // not an exotic case) or genuinely unrelated histories. Degrade, never crash — and the verdict this
        // produces is Unknown, never Merged: see writeStrayRef and Verdict's own comment.
        plumb.ok = false;
        DEGRADED_PATH_ALERT( "crossref: no merge-base for ref (shallow clone or unrelated history?) — verdict is unknown, not merged" );
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
    VERIFY( plumbing.size() == refs.size() );

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
    if( !quality::gitRepoHasHistory( root ) ) { result.ok = false; result.nonGitRoot = true; return result; }

    result.headSha = quality::gitHeadSha( root );
    result.headRef = quality::gitOneLine( root, "rev-parse --abbrev-ref HEAD 2>/dev/null" );

    std::size_t                filterNameHits = 0;
    const std::vector<RefInfo> refs = enumerateRefs( root, filter, result.headSha, &filterNameHits );
    result.filterMatchedNothing = !filter.empty() && filterNameHits == 0;
    if( result.filterMatchedNothing ) { result.ok = false; return result; }
    if( refs.size() > kMaxRefs ) { result.ok = false; result.tooManyRefs = true; return result; }

    // ── phase 1: the merge-base probe, one git call per ref, ACROSS THE POOL ────────────────────────────
    // Refs are independent and each worker writes only its own slot, so this is the serial answer computed
    // in parallel — not a different answer.
    std::vector<RefPlumbing> plumbing( refs.size() );
    parallelIndexed( refs.size(), [ & ]( std::size_t i ) { plumbing[i] = probeRefBase( root, refs[i], result.headSha ); } );

    // ── phases 2-4: the distinct diffs, then ONE batched blob read for the whole sweep ───────────────────
    const DiffPairTable diffs = gatherRefDiffs( root, refs, result.headSha, plumbing );

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
    bool          isDef = false;      // LEXICAL definition heuristic — see definitionShaped()
    std::string   text;               // the trimmed source line (evidence, so the caller can judge)
};

// §A7: where the parsed INDEX says SYM is defined — supplied by the caller (the CLI holds the IngestResult;
// the MCP verb deliberately holds no index and passes none). `path` is spelled ROOT-RELATIVE, the way git
// spells a tree entry; `line` is the index's 1-based def line.
struct IndexDefSite
{
    std::string   path;
    std::uint32_t line = 0;
};

// The optional EVIDENCE a caller can hand the tree scan — both members are "extra knowledge this surface
// happens to hold", both default to "not supplied", and both only ever ADD a lane, so they travel as one
// parameter rather than growing computeWhereis' argument list once per lane.
struct WhereisEvidence
{
    const gitoracle::HistoryIndex* history   = nullptr;   // --with-history: the name-history oracle (nullptr ⇒ not asked for)
    std::span<const IndexDefSite>  indexDefs = {};        // §A7: where the parsed index defines SYM (empty ⇒ label HEAD lexically)
};

struct WhereResult
{
    bool                  ok = true;
    bool                  nonGitRoot = false;
    std::string           sym;
    std::string           headSha;
    bool                  onHead = false;     // SYM occurs in HEAD's tree
    bool                  headLabelsFromIndex = false;   // §A7: HEAD rows' kind= came from the index, not the shape test
    std::size_t           refsScanned = 0;
    std::size_t           distinctBlobs = 0;
    std::vector<WhereHit> hits;

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

// Is this line SHAPED like a definition of `sym`? Declarative marker table over the languages ripwire indexes
// — deliberately LEXICAL, not AST-parsed: this is the REF-BLOB side, raw text that was never ingested, and
// paying a tree-sitter parse per candidate blob to sharpen a hint would cost more than the hint is worth. HEAD
// rows do NOT come here at all when the caller supplies the index's def sites (see relabelHeadHitsFromIndex):
// the honest split documented in --help is HEAD = parsed, refs = lexical, and this function is the lexical half.
// False positives here cost a `kind="def"` that should have read `kind="ref"`, never a missed hit.
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
        out.push_back( WhereHit{ ref.name, ref.tip, ref.date, path, lineNo,
                                 definitionShaped( line, sym, at ), std::string( line.substr( a, b - a ) ) } );
        return;                                                               // one hit per line — the line IS the evidence
    }
}

// Record every whole-word occurrence of `sym` in one blob's bytes, as (line number, trimmed line).
//
// The walk is driven by the SEGMENT, not by the terminator: a blob whose last line has no trailing '\n' is
// perfectly legal git content, and evaluating only on '\n' silently skipped it. A symbol defined on that
// final line then reported hits="0" — which this verb's own help text tells the reader means "this repo
// never had the name", the single most misleading answer it can give.
inline void scanBlobForSymbol( std::string_view bytes, std::string_view sym,
                               const RefInfo& ref, const std::string& path, std::vector<WhereHit>& out )
{
    std::size_t   lineStart = 0;
    std::uint32_t lineNo    = 1;
    while( lineStart <= bytes.size() )
    {
        std::size_t  end     = bytes.find( '\n', lineStart );
        const bool   isFinal = ( end == std::string_view::npos );
        if( isFinal )
        {
            end = bytes.size();
        }

        scanLineForSymbol( bytes.substr( lineStart, end - lineStart ), sym, ref, path, lineNo, out );

        if( isFinal )
        {
            break;
        }
        lineStart = end + 1;
        ++lineNo;
    }
}

// Every (path, blob) in one ref's tree. `git ls-tree -r` is one process per ref and the ONLY tree-wide call
// --whereis makes; the blobs behind it are shared across refs and reduced once each.
inline std::vector<RawRow> lsTree( const std::string& root, const std::string& rev )
{
    if( !isRevisionToken( rev ) )
    {
        DEGRADED_PATH_ALERT( "crossref: refusing to list a tree whose revision argument is not a resolved object name" );
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
//   • the caller supplied no def sites (no index — the MCP verb), or the index knows no def of this name (the
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

    std::vector<char> promoted( hits.size(), 0 );
    for( const IndexDefSite& def : indexDefs )
    {
        std::size_t   bestHit  = hits.size();
        std::uint32_t bestDist = 0;
        for( std::size_t hitIndex = 0; hitIndex < hits.size(); ++hitIndex )
        {
            const WhereHit& h = hits[ hitIndex ];
            if( h.ref != "HEAD" || !sameTreePath( h.path, def.path ) )
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
            promoted[bestHit] = 1;
        }
    }

    const bool anyPromoted = std::find( promoted.begin(), promoted.end(), 1 ) != promoted.end();
    if( !anyPromoted )
    {
        DEGRADED_PATH_ALERT( "whereis: the index's def sites match no HEAD row (working tree drifted from HEAD?) — keeping the lexical labels" );
        return false;
    }
    for( std::size_t hitIndex = 0; hitIndex < hits.size(); ++hitIndex )
    {
        if( hits[hitIndex].ref == "HEAD" )
        {
            hits[hitIndex].isDef = promoted[hitIndex] != 0;
        }
    }
    return true;
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
                                   WhereisEvidence evidence = {} )
{
    WhereResult result;
    result.sym = std::string( sym );
    if( !quality::gitRepoHasHistory( root ) ) { result.ok = false; result.nonGitRoot = true; return result; }

    result.headSha = quality::gitHeadSha( root );
    result.history = evidence.history;
    if( evidence.history != nullptr )
    {
        result.fate = evidence.history->fateOf( result.sym );
    }

    std::vector<RefInfo> refs = enumerateRefs( root, filter, result.headSha );
    refs.insert( refs.begin(), RefInfo{ "HEAD", result.headSha, quality::gitCommitterDateIso( root ) } );
    if( refs.size() > kMaxRefs ) { result.ok = false; return result; }

    // blob sha → every (ref index, path) that points at it, in a deterministic order.
    struct Site { std::uint32_t refIndex; std::string path; };
    bool anyEmptyTree = false;   // T1: a zero-row ls-tree could be a FAILED listing — it forfeits complete=
    gtl::btree_map<std::string, std::vector<Site>> sites;
    for( std::uint32_t i = 0; i < refs.size(); ++i )
    {
        const std::vector<RawRow> rows = lsTree( root, refs[i].tip );
        if( rows.empty() )
        {
            anyEmptyTree = true;
        }
        for( const RawRow& r : rows )
        {
            sites[ r.bSha ].push_back( Site{ i, r.path } );
        }
    }

    std::vector<std::string> shas;
    shas.reserve( sites.size() );
    for( const auto& [ sha, s ] : sites ) { (void)s; shas.push_back( sha ); }

    result.distinctBlobs = shas.size();
    result.refsScanned   = refs.size() - 1;                                   // HEAD is not one of the swept refs

    StreamBlobStats blobStats;   // T1: the degrade census that decides whether this scan may claim complete=
    streamBlobs( root, shas, [ & ]( const std::string& sha, std::string_view bytes, bool isText )
                 {
        if( !isText || bytes.find( sym ) == std::string_view::npos ) { return;   // cheap reject before the line walk
}
        const auto it = sites.find( sha );
        if( it == sites.end() ) { return;
}
        for( const Site& s : it->second )
        {
            if( refs[ s.refIndex ].name == "HEAD" ) { result.onHead = true;
}
            scanBlobForSymbol( bytes, sym, refs[ s.refIndex ], s.path, result.hits );
        } }, &blobStats );

    // T1: exhaustive-over-text iff every sha streamed clean AND no ref's tree listing was suspect. An empty
    // sha list (every scanned tree empty, or none) trivially streamed clean — anyEmptyTree covers that shape.
    result.scanExhaustive = blobStats.exhaustiveOverText() && !anyEmptyTree;

    // §A7: HEAD's rows are the INDEX's answer, not the shape test's — before the sort, because "definitions
    // before references" is a sort key and a wrong label re-orders the first screen.
    result.headLabelsFromIndex = relabelHeadHitsFromIndex( result.hits, evidence.indexDefs );

    // HEAD first, then refs by name; within a ref, SOURCE before test before docs (§P11.5, see this
    // function's header), then definitions before references, then path/line.
    std::sort( result.hits.begin(), result.hits.end(), []( const WhereHit& a, const WhereHit& b )
    {
        const bool ah = a.ref == "HEAD", bh = b.ref == "HEAD";
        if( ah != bh )
        {
            return ah;
        }
        if( a.ref != b.ref )
        {
            return a.ref < b.ref;
        }
        const PathTier at = pathTierOf( a.path ), bt = pathTierOf( b.path );
        if( at != bt )
        {
            return at < bt;
        }
        if( a.isDef != b.isDef )
        {
            return a.isDef;
        }
        if( a.path != b.path )
        {
            return a.path < b.path;
        }
        return a.line < b.line;
    } );
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
    std::fprintf( out, "<!-- ripwire stray-content eval: labelled verdict accuracy. Each row is one branch whose "
                       "true state was established by hand; want= is the label, got= is what the classifier said. "
                       "A branch absent from the report scores as merged ONLY when it is a real ref this repo has "
                       "(merged refs are omitted by design); a label naming a ref that does not exist is refused, "
                       "not scored (see badRefs on refusal). unknown= on the root counts cases whose verdict "
                       "is unknown (no merge-base / unrelated history); its own bucket, never folded into merged. "
                       "Use this to MEASURE a threshold change instead of eyeballing it. -->" );
    std::fprintf( out, "<stray-eval cases=\"%zu\" correct=\"%u\" unknown=\"%u\" accuracy=\"%.1f\">", n, rep.correct, rep.unknownCount, acc );
    for( const EvalCase& c : rep.cases )
    {
        std::fprintf( out, "<case ref=\"%s\" want=\"%s\" got=\"%s\" hit=\"%d\" reported=\"%d\"/>",
                      ex( c.ref ).c_str(), verdictTag( c.expected ), verdictTag( c.got ),
                      c.got == c.expected ? 1 : 0, c.found ? 1 : 0 );
    }
    std::fprintf( out, "</stray-eval>" );
}

// ── XML emission (G4: minified, xmllint-clean; no `\n` outside CDATA) ────────────────────────────────────

using XmlEscaper = std::function<std::string( std::string_view )>;

inline void writeStrayFile( std::FILE* out, const FileRow& f, const XmlEscaper& ex )
{
    std::fprintf( out, "<file p=\"%s\" v=\"%s\" stray=\"%u\" authored=\"%u\" del=\"%u\" redone=\"%u\" sim=\"%.2f\" head-touched=\"%d\"%s/>",
                  ex( f.path ).c_str(), verdictTag( f.verdict ), f.strayLines, f.authored, f.deleted, f.redone,
                  double( f.sim ), f.headTouched ? 1 : 0, f.diffable ? "" : " diffable=\"0\"" );
}

inline void writeStrayRef( std::FILE* out, const RefRow& r, const XmlEscaper& ex, std::size_t maxFiles )
{
    // ok="0" ALWAYS renders v="unknown". computeStrayContent already sets Unknown at the degrade site, so
    // this is a belt-and-braces coercion at the one place the claim is actually made to the reader: no future
    // degrade path can reintroduce "the analysis failed, so let us print the reassuring answer".
    const Verdict shownVerdict = r.ok ? r.verdict : Verdict::Unknown;
    VERIFY( r.ok || shownVerdict == Verdict::Unknown );

    std::fprintf( out, "<ref name=\"%s\" tip=\"%.9s\" date=\"%s\" base=\"%.9s\" ok=\"%d\" v=\"%s\" stray=\"%u\" files=\"%u\" superseded=\"%u\">",
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
    VERIFY( shownCount == std::min( r.files.size(), maxFiles ) );
    if( r.files.size() > maxFiles )
    {
        std::fprintf( out, "<more files=\"%zu\"/>", r.files.size() - maxFiles );
    }
    std::fprintf( out, "</ref>" );
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
    VERIFY( std::size_t( unmerged ) + superseded + unknown + res.mergedRefs == res.refsScanned );

    // G4: an XML comment may not contain a double hyphen, so this text (and writeWhereis's) names flags and
    // git subcommands WITHOUT their leading dashes. Keep it that way when editing.
    std::fprintf( out, "<!-- ripwire stray-content: per ref, the lines its own divergent work AUTHORED (vs its merge-base "
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
                       "by limit / offset, which page the OUTER ref listing and report their own shown= / capped=. -->" );
    // §P8: shipped as `head-ref=` while its own --abi sibling (abicheck.h's `<abi head_ref=>`, over the SAME
    // field, reached by the SAME command line) shipped `head_ref=` — the tool's only kebab/snake pair, so a
    // parser written against one half read nothing from the other. Unified onto snake_case: it is the
    // majority (41 vs 8) and the spelling README.md documents. Kebab survives only in docs/captures/*.
    const PageWindow  refPage = pageWindow( res.refs.size(), pageLimit, pageOffset );
    char              srab[ kPageDisclosureCap ];
    std::fprintf( out, "<stray-content head=\"%.9s\" head_ref=\"%s\" refs=\"%zu\" blobs=\"%zu\" unmerged=\"%u\" superseded=\"%u\" merged=\"%u\" unknown=\"%u\"%s>",
                  res.headSha.c_str(), ex( res.headRef ).c_str(), res.refsScanned, res.distinctBlobs, unmerged, superseded, res.mergedRefs, unknown,
                  pageDisclosure( srab, sizeof( srab ), refPage.end - refPage.begin, res.refs.size(), refPage.end, pageLimit, pageOffset, false ) );
    for( std::size_t refIndex = refPage.begin; refIndex < refPage.end; ++refIndex )
    {
        writeStrayRef( out, res.refs[refIndex], ex, maxFiles );
    }
    std::fprintf( out, "</stray-content>" );
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
    VERIFY( lastColon != std::string_view::npos && lastColon + 1 < spec.size() );
    return spec.substr( lastColon + 1 );
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
inline void writeWhereisPage( std::FILE* out, const WhereResult& res, std::size_t maxHits, int pageLimit, int pageOffset )
{
    std::vector<char> esc;
    const XmlEscaper  ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };

    // The emitted window. An explicit --limit overrides maxHits (the caller's 60-hit display default, or
    // SIZE_MAX under --detail); --offset skips whole rows and clamps at the end, so offset-past-the-end is
    // an empty page rather than an out-of-range read. maxHits can be SIZE_MAX, which pageWindow's int limit
    // cannot carry — clamp the "no explicit --limit" arm to the row count instead of overflowing it.
    const int        rowCap  = pageLimit > 0 ? pageLimit
                             : ( maxHits >= res.hits.size() ? int( res.hits.size() ) : int( maxHits ) );
    const PageWindow hitPage = pageWindow( res.hits.size(), rowCap, pageOffset );

    std::fprintf( out, "<!-- ripwire whereis: every LOCAL ref whose TREE contains this symbol, HEAD first, and within a ref "
                       "SOURCE files before test files before docs, then definitions before references, then path and line. "
                       "The doc demotion is ORDER ONLY: a doc line that quotes a signature still reads as a definition to "
                       "the heuristic below and still says kind=\"def\", it is simply printed after the code. kind= is answered "
                       "by TWO different mechanisms, and head_labels= says which one answered for HEAD: with head_labels=\"index\" "
                       "a HEAD row is kind=\"def\" iff the PARSED index puts a definition there (one row per index def site), "
                       "while every NON-HEAD row — and every row when head_labels=\"lexical\" (no index was supplied, the index "
                       "knows no def of this name, or the working tree has drifted from HEAD) — is a LEXICAL shape heuristic over "
                       "raw blob text that was never ingested: it reads a quoted signature in a doc as a definition and can miss "
                       "an unusual declarator. refs_scanned= is the SCAN DENOMINATOR (how many refs besides HEAD were read), NOT a "
                       "count of refs that matched — hits= and the rows are the matched set. on-head=\"0\" alongside ref hits is the case this verb exists "
                       "for: content that lives only on a branch. A TREE scan can only find content some ref still carries, "
                       "so hits=\"0\" on its own does not distinguish a name this repo never had from one it deleted; run "
                       "with the with_history flag and the fate row says which, naming the commit that removed it. "
                       "ANCHORING: none, by design. This verb runs no diff at all — it scans each ref's FULL tree, which is "
                       "what lets it find content a branch merely INHERITED (exactly what a merge base anchored diff would "
                       "exclude), so nothing here can fire merely because HEAD moved. at= is sha-only here (never +dirty): "
                       "a tree scan reads committed blobs, so the working tree's cleanliness does not enter the answer. "
                       // §B11.2 — the one zero this verb prints that is NOT a measurement, named in the legend.
                       "SELECTOR: this verb takes a BARE symbol name, not the file:name spelling that callers, uses, "
                       "impact, around, lego and edit_check accept. A file:name spelling is searched as a LITERAL "
                       "string, no tree contains it, and the result is a true but useless hits=\"0\" shaped exactly "
                       "like a name this repo never had. When that is what happened, a selector-note element says so "
                       "and its retry= is the bare name to re-run with. That element has three reasons, and r= names which: "
                       "qualified-selector (a file:name spelling was searched literally), line-seed (an @FILE:LINE selector "
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
                       // T1 — the completeness claim, the mirror of the truncation vocabulary, defined where it appears.
                       "COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not "
                       "re-derive it: every occurrence of the symbol in every TEXT blob of every scanned ref's full tree is printed "
                       "above — nothing was capped or paged out, and no blob was oversized (over the 2 MB blob ceiling), missing or "
                       "cut short by the stream. The denominator is refs_scanned= plus HEAD, under SCOPE above (local heads only), "
                       "so with complete= present a ref absent from the rows genuinely lacks the symbol in its committed tree. "
                       "Binary blobs are outside the claim (a text symbol cannot occur in one); an oversized TEXT blob suppresses "
                       "the claim instead of being silently skipped. Its ABSENCE claims nothing. "
                       "raise the default cap with limit=N (offset=M pages; a cut listing carries total=/has_more=/next_offset= so a paging loop can continue from it) -->" );
    char pab[ kPageDisclosureCap ];
    // §A7(iii): refs_scanned=, not refs=. --stray-content and --abi both spell the MATCHED set refs=; this one
    // counted every branch the sweep READ (73 here, matched or not) under the same attribute name — one noun,
    // two meanings, across sibling verbs an agent reads together.
    // T1: the claim is scan-exhaustiveness AND listing-wholeness — an uncut page over a clean scan. Appended
    // LAST (after at=) so no existing attribute-adjacency assertion can break on it, the same placement rule
    // the graph verbs' floor marker follows. When either half fails, NOTHING is added: the truncation
    // vocabulary above already covers every partial shape, and complete-equals-zero would be noise.
    const bool completeClaim = res.scanExhaustive && hitPage.begin == 0 && hitPage.end == res.hits.size();
    std::fprintf( out, "<whereis sym=\"%s\" on-head=\"%d\" refs_scanned=\"%zu\" blobs=\"%zu\" hits=\"%zu\" head_labels=\"%s\"%s at=\"%.9s\"%s>",
                  ex( res.sym ).c_str(), res.onHead ? 1 : 0, res.refsScanned, res.distinctBlobs, res.hits.size(),
                  res.headLabelsFromIndex ? "index" : "lexical",
                  pageDisclosure( pab, sizeof( pab ), hitPage.end - hitPage.begin, res.hits.size(), hitPage.end,
                                  pageLimit, pageOffset, true ),
                  res.headSha.c_str(),
                  completeClaim ? " complete=\"1\"" : "" );

    // §B11.2 — a zero that is a SPELLING fact, not a repository fact, says so. Emitted first, before the
    // history lane, so it is the first thing after the root on the one shape where it fires: hits="0" AND a
    // file-qualified selector. It never appears beside a nonzero hit list, so it cannot dilute a real answer.
    if( res.hits.empty() && whereisSpecIsFileQualified( res.sym ) )
    {
        std::fprintf( out, "<selector-note r=\"qualified-selector\" spec=\"%s\" retry=\"%s\"/>",
                      ex( res.sym ).c_str(), ex( whereisBareNameOf( res.sym ) ).c_str() );
    }
    // H7: the same element, two more reasons — the line seed that was RESOLVED before the scan (so sym= is a
    // name and not the raw @spec), and the near-miss beside a zero the index can explain.
    if( !res.seedSpec.empty() )
    {
        std::fprintf( out, "<selector-note r=\"line-seed\" spec=\"%s\" retry=\"%s\"/>",
                      ex( res.seedSpec ).c_str(), ex( res.sym ).c_str() );
    }
    if( res.hits.empty() && !res.nearMiss.empty() )
    {
        std::fprintf( out, "<selector-note r=\"near-miss\" spec=\"%s\" retry=\"%s\"/>",
                      ex( res.sym ).c_str(), ex( res.nearMiss ).c_str() );
    }

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
    if( res.history != nullptr )
    {
        gitoracle::writeHistoryProbe( out, *res.history, ex );
        if( res.history->ok && !( res.onHead && res.headLabelsFromIndex ) )
        {
            gitoracle::writeNameFate( out, res.sym, res.fate, ex );
        }
    }

    // The <more/> contract, restated because it was false here: shown + dropped == hits=, ALWAYS. The count
    // must be taken against the CAP, not against a loop variable `shown++ >= cap` has already pushed to
    // cap+1 — that off-by-one under-reported every drop by exactly one row (81 hits, 60 shown, "20" dropped),
    // and at exactly cap+1 hits `size > shown` went false, so the element vanished and a row disappeared
    // unmarked. Nothing is dropped without a number is a headline claim; keep it arithmetically true.
    std::size_t shownCount = 0;
    for( std::size_t hitIndex = hitPage.begin; hitIndex < hitPage.end; ++hitIndex )
    {
        const WhereHit& h = res.hits[ hitIndex ];
        ++shownCount;
        std::fprintf( out, "<hit ref=\"%s\" tip=\"%.9s\" date=\"%s\" p=\"%s\" l=\"%u\" kind=\"%s\" t=\"%s\"/>",
                      ex( h.ref ).c_str(), h.tip.c_str(), ex( h.date ).c_str(), ex( h.path ).c_str(),
                      h.line, h.isDef ? "def" : "ref", ex( h.text ).c_str() );
    }
    VERIFY( shownCount == hitPage.end - hitPage.begin );
    // <more hits="N"/> = the rows AFTER this page, so shown + more == the rows from this page's offset on.
    // Un-paginated that is the historic "hits= minus the 60 printed"; paged it is what the NEXT page holds
    // (and next_offset= on the root says where to ask for it).
    if( hitPage.end < res.hits.size() )
    {
        std::fprintf( out, "<more hits=\"%zu\"/>", res.hits.size() - hitPage.end );
    }
    std::fprintf( out, "</whereis>" );
}

// The un-paginated form — unchanged contract, for callers that want the whole (capped) listing.
inline void writeWhereis( std::FILE* out, const WhereResult& res, std::size_t maxHits )
{
    writeWhereisPage( out, res, maxHits, 0, 0 );
}

}}   // namespace rw::crossref
