#pragma once

// gitmine.h — git-history mining shared by the CLI (main.cpp) and the MCP server (mcp.h): shell-quoting,
// per-commit changed-file sets, and the co-change (logical-coupling) core. popen-based; no git library.

#include "model.h"
#include "graph.h"               // resolveIncludeAdj — for the "surprising" (changes together, no transitive static dep) flag
#include "mention.h"             // mention_detail::baseNameOf — the SAME "basename of a path" primitive binstale.h/docdrift.h reuse
#include "lintrules.h"           // §A9.3: langOfPath / dependencyCapable — the SAME predicate <health dep_files=> uses
#include "workspace.h"          // WorkspaceRoot — mineChurnPerFile's per-root merge (promoted from main.cpp, 2026-08-29 split)
#include "infra/profileScope.h"  // PROFILE_SCOPE self-profiling — gated by PROFILE_ENABLED (off unless -DRIPWIRE_PROFILE=ON)
#include "infra/Diagnostics.h"   // DEGRADED_PATH_ALERT — graceful-degrade on a bad/unresolvable --since value
#include "infra/stdinline.h"     // readByteSafeLine — THE line reader (R4); no fixed buffer to split a long path on
#include "infra/jsonesc.h"       // A4-F27 residual: rw::shSingleQuote lives here (lightest shared header) —
                                 // gitmine.h no longer carries its own copy; see jsonesc.h for the dedup rationale

#include <algorithm>
#include <atomic>       // the join's once-per-process disclosure flags
#include <bit>          // std::popcount — the recurrence mask's set-bit count (Clio sub-windows)
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <mutex>        // gitRepoToplevel's per-directory memo — one rev-parse probe per root, not per miner
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include <limits.h>    // PATH_MAX (hasEnclosingGitRepo realpath buffer)
#include <sys/stat.h>  // stat() — the zero-popen .git walk-up pre-check

namespace rw
{

// shSingleQuote (shell-escape a single-quoted arg) now lives in jsonesc.h — the canonical, lightest
// shared home for it (A4-F27 residual dedup with docparse::detail::shellQuote). It is defined directly
// in `namespace rw` there, so every existing `shSingleQuote(...)` call site in this file (and in
// main.cpp / prcontext.h / quality.h, which reach it transitively via this include) keeps working
// unqualified — same namespace, no `using` needed.

// ── time-window scope for the churn/co-change miners (--since=REV|DATE) ──────────────────────────

// The resolved form of a --since value: EITHER a revision boundary (git log REV.. — deterministic,
// used by the det-gate) OR a date passed straight through to `git log --since=DATE` (a git
// approxidate like "2 weeks ago" — NOT deterministic across wall-clock days, by construction; that
// is inherent to a relative-date window, not a bug here). `active=false` means "no scoping" — either
// the caller passed no --since at all, or the value didn't resolve to anything git accepts, in which
// case callers must fall back to their own default (all-history) window, unchanged from pre-flag
// behavior. Never crashes: an unresolvable value degrades to `active=false` + one stderr note.
struct SinceScope
{
    bool        active = false;   // false → caller uses its existing default window (degrade / no --since)
    bool        isRev  = true;    // true → `revBoundary` is a commit-ish; false → `sinceDate` is a git approxidate
    std::string revBoundary;      // e.g. "HEAD~20" or a tag — used as `git log <revBoundary>..`
    std::string sinceDate;        // e.g. "2 weeks ago" — used as `git log --since=<sinceDate>`
    // N4 (capture-audit verify-wave1 2026-09-04): the BASELINE COMMIT this value names — a revision is its own
    // sha, a date is the newest commit at or before it — EMPTY when the history never reaches it (a date before
    // the first commit). The window hosts (--hotspots/--cochange/--rank-by=churn) never read it: 1999.. is all
    // of history and an honest window. The baseline host (--slice compares against a commit) needs it, and the
    // decision that it is missing is made ONCE, in main.cpp beside the M8 validation, from this field — so a
    // fifth consumer cannot resolve the same value by a different rule (slicediff.h used to resolve it itself).
    std::string baselineSha;
};

// A --since value "looks like a date" only if EVERY alphabetic run in it is a date word (or an ISO
// designator) and the value carries a digit or at least one real date word. Deliberately a coarse
// allowlist, NOT a full approxidate re-implementation — git's parser is far more lenient than we need to
// replicate; the job is rejecting garbage before it silently becomes a window nobody asked for.
//
// §P0.5c tightened this. The old rule was "contains a digit OR contains a date word ANYWHERE", and its
// comment argued a false positive was safe. It is not: `notaref9z` contains a digit, so it sailed through
// as a date, git's approxidate turned it into some arbitrary timestamp, and --hotspots printed
// window="notaref9z" over a window nobody chose. Per-RUN matching rejects it (`notaref` is not a date
// word) while every real form still passes: "2 weeks ago", "5 days ago", "yesterday", "Jan 5, 2026",
// "2026-01-01", "2026-01-01T00:00:00Z" (t/z are the only single letters accepted, as ISO designators),
// "@1785219969". A value this rejects is one the caller must NOT silently scope by.
// Is a leading ISO-shaped calendar date REAL? `looksLikeDate` below is a SHAPE test — it accepts anything
// whose alphabetic runs are date words and which carries a digit — and a shape test cannot tell 2026-01-15
// from 2026-13-45. git's approxidate silently turns the impossible one into some timestamp, which
// --hotspots then stamped into window="2026-13-45" and reported as a legitimately empty window
// (commits="0", "not an error"). Month 13 and day 45 do not exist, so that is a caller error, not a
// measurement (M8, capture-audit 2026-09-04).
//
// Scope, deliberately narrow: ONLY a value that BEGINS with the numeric YYYY-MM[-DD] shape is range-checked.
// Everything else — "2 weeks ago", "yesterday", "Jan 5, 2026", "@1785219969" — is git's approxidate to
// parse, and re-implementing that grammar here is the mistake this file's header already warns against.
inline bool leadingIsoDateIsReal( std::string_view s )
{
    const auto digitsAt = []( std::string_view v, std::size_t at, std::size_t count ) -> bool
    {
        if( at + count > v.size() ) { return false; }
        for( std::size_t i = 0; i < count; ++i )
        {
            if( v[ at + i ] < '0' || v[ at + i ] > '9' ) { return false; }
        }
        return true;
    };
    const auto numberAt = []( std::string_view v, std::size_t at, std::size_t count ) -> int
    {
        int n = 0;
        for( std::size_t i = 0; i < count; ++i ) { n = n * 10 + ( v[ at + i ] - '0' ); }
        return n;
    };

    if( !digitsAt( s, 0, 4 ) || s.size() < 7 || s[4] != '-' || !digitsAt( s, 5, 2 ) )
    {
        return true;   // not the shape this check owns — leave the verdict to looksLikeDate + approxidate
    }
    const int year  = numberAt( s, 0, 4 );
    const int month = numberAt( s, 5, 2 );
    if( month < 1 || month > 12 )
    {
        return false;
    }
    if( s.size() < 10 || s[7] != '-' || !digitsAt( s, 8, 2 ) )
    {
        return true;   // YYYY-MM with no day half — the month check above is all there is to make
    }
    const bool leap   = ( year % 4 == 0 && year % 100 != 0 ) || year % 400 == 0;
    const int  inMonth[ 13 ] = { 0, 31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    const int  day    = numberAt( s, 8, 2 );
    return day >= 1 && day <= inMonth[ month ];
}

inline bool looksLikeDate( std::string_view s )
{
    static constexpr const char* kWords[] = {
        "ago", "day", "week", "month", "year", "hour", "min", "sec", "fortnight",
        "yesterday", "today", "tomorrow", "now", "midnight", "noon", "last", "next", "am", "pm", "utc", "gmt",
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
        "mon", "tue", "wed", "thu", "fri", "sat", "sun"
    };

    std::string lower( s );
    for( char& c : lower )
    {
        c = char( std::tolower( static_cast<unsigned char>( c ) ) );
    }

    bool hasDigit = false, hasDateWord = false;
    for( char c : lower )
    {
        if( c >= '0' && c <= '9' )
        {
            hasDigit = true;
        }
    }

    // Every alphabetic RUN must be date-shaped; one non-date word (`notaref`, `not`) disqualifies the value.
    for( std::size_t runBegin = 0; runBegin < lower.size(); )
    {
        if( !std::isalpha( static_cast<unsigned char>( lower[ runBegin ] ) ) ) { ++runBegin; continue; }
        std::size_t runEnd = runBegin;
        while( runEnd < lower.size() && std::isalpha( static_cast<unsigned char>( lower[runEnd] ) ) )
        {
            ++runEnd;
        }
        const std::string_view run( lower.data() + runBegin, runEnd - runBegin );

        bool runIsDateShaped = false;
        if( run.size() == 1 )
        {
            runIsDateShaped = ( run[0] == 't' || run[0] == 'z' ); // ISO 8601 designators only
        }
        else
        {
            for( const char* w : kWords )
            {
                if( run.size() >= std::string_view( w ).size() && run.compare( 0, std::string_view( w ).size(), w ) == 0 )
                { runIsDateShaped = true;  hasDateWord = true;  break; }
            }
        }

        if( !runIsDateShaped )
        {
            return false;
        }
        runBegin = runEnd;
    }
    return ( hasDigit || hasDateWord ) && leadingIsoDateIsReal( s );
}

// N4: THE ONE no-baseline refusal — a --since that is a real window but names no commit at or before it, on a
// host that compares against a commit. Spelled here alone (sincecheck.sh's N4 source arm counts the files);
// main.cpp decides it beside the M8 validation, slicediff.h prints the same sentence on its own degrade path.
inline std::string sinceNoBaselineRefusal( std::string_view value, const std::string& root )
{
    return "ripwire: --since=" + std::string( value ) + " resolves to no commit in '" + root
         + "' — beside --slice it names the revision to compare this variable's def-use slice against "
           "(e.g. --since=HEAD~1, --since=<sha>, --since=\"2 weeks ago\")";
}

// THE ONE unresolvable---since refusal, shared by every host (M8). Four verbs consume --since and the
// §P0.5c "a window nobody chose is not a measurement" fix landed on one of them; the other three either
// worded it themselves or did not refuse at all. Hosts print this; nobody re-words it.
inline std::string sinceUnresolvedRefusal( std::string_view value )
{
    return "ripwire: --since='" + std::string( value ) + "' is neither a git revision nor a real calendar date — refusing "
           "rather than measuring under a window nobody chose (a revision: HEAD~20, v1.2.0, a sha; a date: 2026-01-01, "
           "'2 weeks ago', yesterday)";
}

// Resolve a raw --since=VALUE into a SinceScope. Tries VALUE as a revision first (`git rev-parse
// --verify --quiet VALUE^{commit}` — the ^{commit} peel rejects anything that isn't a committish, e.g.
// a blob/tree hash or a malformed ref); a hit is unambiguous and deterministic, so it wins. Otherwise,
// if VALUE passes the coarse looksLikeDate() gate, pass it through verbatim as a `--since=DATE` (git's
// own approxidate does the real parsing — relative forms are inherently wall-clock-relative, which is
// expected and documented, not a determinism bug). Anything else (no git / not a repo / VALUE is
// neither a resolvable rev nor date-shaped) degrades to `active=false` + one stderr note; callers then
// fall back to their pre-flag default window, so a bad --since can never crash or silently scope to
// zero commits without explanation.
// popen a shell command and return its trimmed stdout ("" on any failure — never crashes). THE one copy of the
// popen-trim shape in the tool: the quality.h git one-liners, the doctor probes, crossref.h and binstale.h all
// reach it as quality::popenTrimmed (a using-declaration of this). It lives HERE — the lower header, which
// quality.h includes — because resolveSinceScope needed the same reader (N4, 2026-09-04) and a second copy in
// this file was a --quality-delta new-clone-of-reused-helper row. Built on readByteSafeLine (infra/stdinline.h),
// the G3 byte-safe line reader every git pipe in this header uses: no fixed buffer to split a long path on
// (churnjoincheck's G3 arm forbids fgets here), a high byte never sign-changed. Lines are re-joined with the
// '\n' the reader consumed, so multi-line callers (crossref.h, the rename map) read exactly what fgets gave them.
inline std::string popenTrimmed( const std::string& cmd )
{
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        return {};
    }
    std::string out;
    std::string line;
    while( readByteSafeLine( pipe, line ) )
    {
        out += line;
        out += '\n';
    }
    pclose( pipe );
    while( !out.empty() && ( out.back() == '\n' || out.back() == '\r' || out.back() == ' ' ) )
    {
        out.pop_back();
    }
    return out;
}

inline SinceScope resolveSinceScope( const std::string& root, std::string_view value )
{
    SinceScope scope;
    if( value.empty() )
    {
        return scope; // no --since given → inactive, caller uses its default
    }

    const std::string val( value );

    // 1) try as a revision boundary — deterministic, preferred when it resolves. The peeled sha rev-parse prints
    //    IS the baseline (N4); before N4 only its EXISTENCE was read. popenTrimmed is the G3 reader
    //    (readByteSafeLine) every git pipe in this header uses — gitCommandLines is defined further down.
    {
        const std::string sha = popenTrimmed( "git -C " + shSingleQuote( root )
                                              + " rev-parse --verify --quiet " + shSingleQuote( val + "^{commit}" ) + " 2>/dev/null" );
        if( !sha.empty() )
        {
            scope.active      = true;
            scope.isRev       = true;
            scope.revBoundary = val;
            scope.baselineSha = sha;
            return scope;
        }
    }

    // 2) not a resolvable rev — try as a date (git's approxidate), gated by looksLikeDate() to catch
    // obvious garbage before it silently becomes a 0-commit window. N4: the newest commit at or before the
    // date is the baseline a commit-comparing host needs — empty when the history never reaches the date
    // (the same `rev-list -1 --before` slicediff.h used to run itself).
    if( looksLikeDate( val ) )
    {
        scope.active      = true;
        scope.isRev       = false;
        scope.sinceDate   = val;
        scope.baselineSha = popenTrimmed( "git -C " + shSingleQuote( root ) + " rev-list -1 --before=" + shSingleQuote( val ) + " HEAD 2>/dev/null" );
        return scope;
    }

    // 3) neither. SILENT here, and both the alert and the stderr note that used to live on this line are
    // gone (M8 / lens 6 F7b). An unresolvable --since is refused by the caller now — main.cpp validates the
    // flag once, before any verb runs — so this path printed a "[math degraded] … ignoring it" alert and an
    // "ignoring it; the verb's own default window applies" note immediately ahead of the host's "refusing
    // rather than…". Three lines, and only the third was true. `active=false` remains the return contract
    // (sinceLogArgs then yields the caller's own fallback window verbatim), which is what keeps every
    // no---since call site byte-identical.
    return scope;   // active=false
}

// Build the `git log` window arguments for a SinceScope: either a `LOW..` revision-range prefix (REV
// form — deterministic) or a `--since=DATE ` flag (date form — wall-clock-relative by construction).
// `inactive` (scope.active==false) returns the caller-supplied fallback window verbatim, so every call
// site's pre-flag behavior is reproduced byte-for-byte when --since is absent or unresolvable.
inline std::string sinceLogArgs( const SinceScope& scope, const char* fallbackSince )
{
    if( !scope.active )
    {
        return "--since=" + shSingleQuote( fallbackSince ) + " ";
    }
    if( scope.isRev )
    {
        return shSingleQuote( scope.revBoundary + ".." ) + " ";   // positional rev-range, not a --since flag
    }
    return "--since=" + shSingleQuote( scope.sinceDate ) + " ";
}

// ── how a MERGE commit is diffed, for EVERY `--name-only` history walk in this file ──────────────────────
//
// `git log --name-only` prints NO paths at all for a merge commit: with no --diff-merges mode selected, git
// shows a merge's header and nothing else. So a file whose only history is a merge commit — content the merge
// ITSELF introduced (an "evil merge": a conflict resolved by writing something neither parent had, or a file
// added while resolving) — has zero history lines anywhere in the stream. It read churn=0, it was missing from
// --owners entirely, and NOTHING disclosed it: a measured-looking zero, which is the one shape this file's
// whole disclosure apparatus exists to prevent. Measured on the ripwire repo before this fix: 2 of 1028
// tracked paths had no --owners row at all while
// being ordinary, present, tracked files.
//
// `-c` (combined diff) lists, for a merge, exactly the files that differ from EVERY parent — precisely "what
// this merge itself did", and nothing else. The alternatives were MEASURED, not weighed by taste, on a fixture
// whose per-file truth is known by reading its history (test/mergechurncheck.sh builds it) and on this repo:
//
//   variant                      branchfile.cpp   mergeonly.cpp   shared.cpp   ripwire-repo path-lines
//                                (truth: 3)       (truth: 1)      (truth: 4)   (this file's own history)
//   ------------------------------------------------------------------------------------------------------
//   no flag (the defect)         3  ok            0  MISSING      3  MISSING   3618  — 1026 paths
//   -m                           4  DOUBLE        2  DOUBLE       5  DOUBLE    7026  (+94%)
//   --diff-merges=first-parent   4  DOUBLE        1  ok           4  ok        4811  (+33%)
//   --first-parent               1  LOST          1  ok           3  MISSING   3289  (-9%, 3 paths LOST)
//   -c  (this)                   3  ok            1  ok           4  ok        3817  (+5.5%) — 1028 paths
//
// Bare `-m` diffs the merge against EACH parent in turn, so every merged branch commit's work is counted a
// second time inside the merge; `--diff-merges=first-parent` does the same for the first parent's side;
// `--first-parent` stops walking branch commits altogether and DEFLATES them (and lost 3 paths outright here).
// Only `-c` recovers the merge's own content while leaving ordinary merged work at its true count: on this
// repo 43 of 1028 paths moved, ALL upward, none downward, and 2 appeared for the first time.
//
// Cost: 0.103 s → 0.148 s for the whole-history walk on this repo (1133 commits, 133 merges) — one popen,
// and the expensive walk is memoized (quality::gitCoChangeAndChurnCached; its cache SCHEME is bumped with
// this change, since a warm blob written by a merge-blind binary would otherwise keep serving the old stream).
//
// `-c` after `log` is git log's combined-diff option; it is NOT the `git -c core.quotepath=false` config
// override that opens every command here. Spelled as this one constant so the five walks cannot drift, and
// deliberately as `-c` rather than `--diff-merges=combined`: the long form arrived in git 2.31, and an
// unknown option would make `git log` fail outright, turning every churn number into a silent zero — exactly
// the failure this change exists to remove. `-c` has been git log's spelling since 1.5.
//
// What is STILL not mined, stated where the reader meets the flag: a merge that resolves a conflict by taking
// one parent's version verbatim adds nothing here (correct — the merge authored nothing for that file), and
// `git log` still walks only what is reachable from HEAD. gitoracle.h's removed-line pickaxe keeps its
// deliberate `--no-merges` — it asks a different question (which commit DELETED a name) and is unaffected.
inline constexpr const char* kMergeDiffArgs = "-c ";

// ── the git-history path → indexed-file join (shared by the churn / co-change / author / mask miners) ──
//
// THE INDEX, and there is only one kind: the git path each ingested file WOULD be spelled as, mapped to its
// fileId. A `git log --name-only` path is always relative to the repo TOPLEVEL; an ingested path is relative
// to the crawl root and wears whatever spelling the user passed. The difference between those two anchors is
// an OFFSET, and an offset is DERIVABLE once per root (GitPathOffset) — so the join is an exact string
// equality on a hash key, not a search.
//
// §H6 / F4 — why there is no fuzzy fallback any more. This used to be a basename index
// (basename → [(indexed path, fileId)]) plus a "which candidate leaves the least prefix unexplained?"
// tie-break, refusing only on an exact byte TIE. A tie is not the failure condition; an ABSENT better
// candidate is. When the file a git path really names is deleted / excluded / never ingested, its basename
// can still have exactly ONE surviving candidate — no tie — so the dead path's commit count was written onto
// that survivor with full confidence and no disclosure (measured: root `zeta.cpp` 5 edits + a delete,
// `a/zeta.cpp` 1 commit dated 2019, `--hotspots` → `ranked="1" ./a/zeta.cpp churn="6"`, empty stderr).
// Deriving the offset deletes the guess, and deleting the guess deletes the whole class: a git path that does
// not spell an indexed file's own repo-relative path binds to NOTHING.
using GitPathIndex = HashMap<std::string, std::uint32_t>;   // repo-relative git path → fileId (UINT32_MAX ⇒ refused, see gitPathIndexOfFiles)

// git C-quotes a path (wraps it in double quotes with backslash escapes) whenever it contains a byte git
// considers "unusual" — a double-quote, backslash, tab, newline, or other control byte — and it does so
// EVEN with core.quotepath=false (that flag only suppresses the octal-escaping of high-bit/UTF-8 bytes, it
// does NOT stop the quoting of control/quote/backslash bytes; verified). A quoted field starts and ends
// with '"'. Undo it: if `raw` is C-quoted, strip the enclosing quotes and decode \" \\ \a \b \f \n \r \t \v
// and \NNN (1–3 octal digits) back to raw bytes; otherwise return `raw` unchanged. Without this, such files
// never suffix-match an ingested path and silently drop from co-change / churn / ownership / diff masks
// (A4-F13). Shared here so every git-output resolver (co-change, churn, ownership, and prcontext's numstat
// mask, which includes this header) unquotes identically.
inline std::string gitUnquotePath( const std::string& raw )
{
    if( raw.size() < 2 || raw.front() != '"' || raw.back() != '"' )
    {
        return raw; // not C-quoted → verbatim
    }

    std::string out;
    out.reserve( raw.size() );
    const std::size_t contentEnd = raw.size() - 1;   // index of the closing quote — content is [1, contentEnd)
    for( std::size_t i = 1; i < contentEnd; ++i )
    {
        const char c = raw[i];
        if( c != '\\' ) { out += c; continue; }
        if( i + 1 >= contentEnd )
        {
            break; // trailing lone backslash (malformed) — drop it
        }
        const char e = raw[ ++i ];

        switch( e )
        {
            case 'a': out += '\a'; break;
            case 'b': out += '\b'; break;
            case 'f': out += '\f'; break;
            case 'n': out += '\n'; break;
            case 'r': out += '\r'; break;
            case 't': out += '\t'; break;
            case 'v': out += '\v'; break;
            case '"': out += '"';  break;
            case '\\': out += '\\'; break;
            default:
                if( e >= '0' && e <= '7' )            // \NNN octal escape (1–3 digits)
                {
                    int val = e - '0';
                    for( int k = 0; k < 2 && i + 1 < contentEnd && raw[ i + 1 ] >= '0' && raw[ i + 1 ] <= '7'; ++k )
                    {
                        val = val * 8 + ( raw[ ++i ] - '0' );
                    }
                    out += char( val );
                }
                else
                {
                    out += e; // unknown escape — keep the char literally
                }
                break;
        }
    }
    return out;
}

// Does `indexedPath` END with `gitRelPath` on a directory boundary (off==0 or the preceding byte is '/')?
// A plain suffix isn't enough — "bar.cpp" must not match "foobar.cpp". Pure, allocation-free.
inline bool isBoundarySuffix( std::string_view indexedPath, std::string_view gitRelPath ) noexcept
{
    if( indexedPath.size() < gitRelPath.size() )
    {
        return false;
    }
    const std::size_t off = indexedPath.size() - gitRelPath.size();
    return indexedPath.compare( off, gitRelPath.size(), gitRelPath ) == 0 && ( off == 0 || indexedPath[ off - 1 ] == '/' );
}

// ONE normalisation, applied to BOTH sides of the join before any byte comparison, and the only latitude the
// join has. Two rewrites, in ONE pass so there is no second place to keep in step:
//   * every `/./` seam collapses — workspace.h spelled a merged-root file `<label>/./<rel>` this way through
//     §P8.7 (2026-07-28; the `./` made a single-root id an exact suffix of the workspace id). M12
//     (capture-audit-2026-09-04) dropped that seam — workspace.h now spells plain `<label>/<rel>` — so this
//     rewrite is a LEGACY no-op on today's labeled spelling, kept rather than removed because it is still
//     correct (harmless) on any `/./` a path genuinely contains for an unrelated reason (a `..`-normalized
//     symlink target, say) and removing a working normalization on a hunch is not this round's job;
//   * a LEADING `./` is dropped, repeatedly — the INGEST-stored spelling `ripwire .` produces still carries
//     it (`./<rel>`; only the display-time emitters strip it, via rootRelativeUri) and git never does.
// The seam test goes first so `/./x` collapses to `/x` rather than losing its leading slash.
// Deliberately NOT case folding: this filesystem is case-insensitive, so a git path differing from an indexed
// path only in case means the committed spelling has DRIFTED from the on-disk spelling. That is a fact worth
// noticing, never a licence to bind — such a path resolves to nothing, like any other path naming no indexed
// file.
// G2 — the ONE thing normalizeJoinPath cannot equalise, named where the reader meets it: UNICODE
// NORMALIZATION. A filename created with a decomposed accent ("e" + U+0301) stays decomposed (NFD) on this
// filesystem, while git stores and prints the composed form (NFC) — `core.precomposeunicode` is ON by default
// on macOS. Those are DIFFERENT byte strings, and this join is byte-exact, so such a file is indexed, is
// never ranked by --hotspots, is missing from --owners' count, and every number about it reads as a measured
// zero. That is a SILENT TOTAL LOSS of one file's history, and it is not any of the five states the comment
// below rules deliberately silent (deleted / excluded / outside-root / renamed / case-drift).
//
// Composing NFD→NFC needs the Unicode decomposition tables, which this binary deliberately does not carry
// (zero dependencies, no ICU), so the class is DISCLOSED rather than fixed — see noteDecomposedIndexedFiles.
// Detection needs no tables: an NFD name is exactly a name that CONTAINS A COMBINING MARK, and the combining
// blocks are a handful of ranges. Confirmation needs no tables either — git is asked how IT spells the file,
// and the two spellings are compared as bytes (see confirmGitSpellingDiffers).
struct CodepointRange { std::uint32_t lo; std::uint32_t hi; };

// The combining/conjoining blocks a decomposed filename can be built from. Covers Latin/Greek/Cyrillic
// (U+0300..036F and the three supplements), the symbol marks, the half marks, Japanese voiced-sound marks,
// and the Hangul conjoining jamo Korean NFD decomposes into. A table, not a switch (house style).
inline constexpr CodepointRange kCombiningMarkRanges[] = {
    { 0x0300, 0x036F },   // Combining Diacritical Marks — the Latin NFD workhorse
    { 0x0483, 0x0489 },   // Cyrillic combining
    { 0x0591, 0x05BD },   // Hebrew points
    { 0x064B, 0x065F },   // Arabic marks
    { 0x093C, 0x094D },   // Devanagari signs/virama
    { 0x1100, 0x11FF },   // Hangul Jamo (conjoining) — Korean NFD
    { 0x1AB0, 0x1AFF },   // Combining Diacritical Marks Extended
    { 0x1DC0, 0x1DFF },   // Combining Diacritical Marks Supplement
    { 0x20D0, 0x20F0 },   // Combining Marks for Symbols
    { 0x3099, 0x309A },   // Japanese combining voiced/semi-voiced sound marks
    { 0xFE20, 0xFE2F },   // Combining Half Marks
};

// Does this UTF-8 path contain a combining mark, i.e. is it (at least partly) DECOMPOSED? Pure, allocation-
// free, and tolerant of invalid UTF-8 (a malformed byte is skipped, never read past the end) — a filename is
// arbitrary bytes and this must never be the thing that crashes on one.
inline bool hasCombiningMark( std::string_view path ) noexcept
{
    for( std::size_t i = 0; i < path.size(); )
    {
        const unsigned char b0 = static_cast<unsigned char>( path[i] );
        std::uint32_t       cp = 0;
        std::size_t         len = 1;

        if     ( b0 < 0x80 )                        { ++i; continue; }                       // ASCII can never be a mark
        else if( ( b0 & 0xE0 ) == 0xC0 ) { cp = b0 & 0x1Fu; len = 2; }
        else if( ( b0 & 0xF0 ) == 0xE0 ) { cp = b0 & 0x0Fu; len = 3; }
        else if( ( b0 & 0xF8 ) == 0xF0 ) { cp = b0 & 0x07u; len = 4; }
        else                                        { ++i; continue; }                       // stray continuation byte

        if( i + len > path.size() )
        {
            break;
        }
        bool isWellFormed = true;
        for( std::size_t k = 1; k < len; ++k )
        {
            const unsigned char bk = static_cast<unsigned char>( path[ i + k ] );
            if( ( bk & 0xC0 ) != 0x80 ) { isWellFormed = false; break; }
            cp = ( cp << 6 ) | ( bk & 0x3Fu );
        }
        if( !isWellFormed ) { ++i; continue; }

        for( const CodepointRange& r : kCombiningMarkRanges )
        {
            if( cp >= r.lo && cp <= r.hi )
            {
                return true;
            }
        }
        i += len;
    }
    return false;
}

inline std::string normalizeJoinPath( std::string_view path )
{
    std::string out;
    out.reserve( path.size() );
    for( std::size_t i = 0; i < path.size(); )
    {
        if( path.substr( i, 3 ) == "/./" )                      { out.push_back( '/' );      i += 3; continue; }
        if( out.empty() && path.substr( i, 2 ) == "./" )        {                            i += 2; continue; }
        out.push_back( path[i] );  ++i;
    }
    return out;
}

// Run a git command and hand back its stdout LINES with the CR/LF tail stripped and blank lines dropped —
// the read half every `--name-only`-shaped probe here spells identically. `isStarted` false ⇒ popen refused
// (no shell / no git); `status` is pclose's, so a caller can still tell "git ran and said nothing" from "git
// failed", which the two main.cpp probes decide differently. Extracted when the §H6 fix made those two
// probes' tails one shared call each and left this loop as the only thing they still cloned (216 tokens, and
// --quality-delta flagged it: the boilerplate had been duplicated all along, the fix merely exposed it).
struct GitCommandLines
{
    std::vector<std::string> lines;
    bool                     isStarted = false;
    int                      status    = 0;
};

inline GitCommandLines gitCommandLines( const std::string& cmd )
{
    GitCommandLines out;
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        return out;
    }
    out.isStarted = true;

    // R4's readByteSafeLine, not a `char line[4096]` + fgets — the rule for EVERY git-pipe reader in this file.
    // F6 found the claim applied at one of five readers; G3 found three MORE survivors after the fix that
    // recorded F6, in the same file in the same wave, so the claim is now re-derived the only way that works
    // (trap #10): by grepping this file for the OLD pattern's survivors, not the new one's adoptions.
    // As of G3 every hit for `fgets` / `char line[` / `char buf[` in this file is inside a COMMENT — there is
    // no such code left; every reader is this one, or gitCommandLines, which is this one. That is not a claim
    // to be trusted from here: churnjoincheck §9c re-derives it from the source on every run, because a
    // comment asserting a file-wide property is exactly what rotted twice.
    // It grows dynamically, so a path longer than the buffer arrives as
    // ONE line instead of two truncated ones, and it keeps an embedded NUL instead of ending the string there
    // (`std::string s( line )` on an fgets buffer stops at the first NUL). Under a fuzzy join a split tail
    // could bind to a real but WRONG file; under the exact join above it binds to nothing, so the residual cost
    // is a silently DROPPED commit rather than a fabricated one — still a number the reader would trust.
    // It leaves a trailing '\r' in place by contract, which is why the strip below still runs.
    std::string line;
    while( readByteSafeLine( pipe, line ) )
    {
        while( !line.empty() && ( line.back() == '\n' || line.back() == '\r' ) )
        {
            line.pop_back();
        }
        if( !line.empty() )
        {
            out.lines.push_back( line );
        }
    }
    out.status = pclose( pipe );
    return out;
}

// The repo TOPLEVEL enclosing `absDir` (absolute and already realpath'd), or empty when `absDir` is not inside
// a git repo at all. realpath'd on the way out so it compares byte-for-byte with a realpath'd file path — on
// this platform `/tmp` is a symlink to `/private/tmp`, and an unresolved toplevel would fail every prefix test
// it exists for. MEMOIZED per directory: a directory's toplevel cannot change under a running process, and up
// to six miners in this file each build their own index in one run.
inline std::string gitRepoToplevel( const std::string& absDir )
{
    static std::mutex                        toplevelMutex;
    static HashMap<std::string, std::string> toplevelByProbeDir;

    {
        const std::lock_guard<std::mutex> lock{ toplevelMutex };
        const auto                        it = toplevelByProbeDir.find( absDir );
        if( it != toplevelByProbeDir.end() )
        {
            return it->second;
        }
    }

    std::string top;
    {
        // the ONE git command in this file without `-c core.quotepath=false`, deliberately: that flag governs
        // how git renders PATHSPEC OUTPUT, and `rev-parse --show-toplevel` prints the directory verbatim —
        // measured on a root spelled "répo dïr", which comes back raw and joins correctly.
        const GitCommandLines probe = gitCommandLines( "git -C " + shSingleQuote( absDir ) + " rev-parse --show-toplevel 2>/dev/null" );
        if( probe.isStarted && probe.status == 0 && !probe.lines.empty() )
        {
            char resolved[ PATH_MAX ];
            top = ::realpath( probe.lines.front().c_str(), resolved ) ? std::string{ resolved } : probe.lines.front();
        }
    }

    const std::lock_guard<std::mutex> lock{ toplevelMutex };
    toplevelByProbeDir[ absDir ] = top;
    return top;
}

// How this ingest spells a path versus how GIT spells the same path, for ONE root. Git's `--name-only` paths
// are relative to the repo TOPLEVEL; `ing.files[f]` is the crawl root's spelling plus the file's path under it.
// So for every file of one root:
//
//     git path( f )  ==  gitPrefix + ing.files[f].substr( indexStripPrefix.size() )
//
// where `indexStripPrefix` is the root-spelling bytes git does not use ("./", "src/", "/abs/repo/",
// "<label>/" post-M12) and `gitPrefix` is the crawl root's own position INSIDE the repo when the root is a
// SUBDIRECTORY of it ("src/"), else empty. Both come from ONE probe file whose absolute path and whose repo
// toplevel are both known facts — the offset is DERIVED, never inferred from a name collision.
//
// Why any directory-aligned split of the probe works. Write the probe as `ing.files[p] == S + r` (root
// spelling + path under the root) and its git path as `P + r`. The longest directory-aligned tail the two
// spellings share is `q + r` for some boundary-aligned suffix `q` of BOTH `S` and `P`, so this derives
// (`S` minus `q`, `P` minus `q`) instead of (`S`, `P`). Those two answers agree on every file of the root,
// because every file of one root wears the same `S`: `(S∖q) + q + r_f == S + r_f`. So the split is free and
// the total transform is exact — which is why this can be one probe rather than a vote.
//
// `isDerived == false` with `isGitRepo == true` is the honest-failure state: a repo whose offset could not be
// worked out (probe outside its own toplevel, a spelling with no directory-aligned overlap). Nothing binds for
// that root and it is disclosed once — an honest "no churn evidence" beats a plausible wrong number.
// `isGitRepo == false` is not a failure: a non-git corpus has no history to attribute, which every miner here
// already degrades on quietly, so it says nothing.
struct GitPathOffset
{
    bool        isGitRepo = false;
    bool        isDerived = false;
    std::string indexStripPrefix;   // leading bytes of ing.files[f] that git does not spell
    std::string gitPrefix;          // "" or "<dir>/" — the crawl root's path inside the repo
    std::string probePath;          // the file the derivation was taken from (for the disclosure)
    std::string repoToplevel;       // G2: the repo this root's paths are spelled against — the -C for the
                                    // one confirmation probe the NFD disclosure runs (empty ⇒ no repo)
};

inline GitPathOffset deriveGitPathOffset( const IngestResult& ing, std::uint32_t onlyRoot )
{
    GitPathOffset offset;

    // Probe order: SHALLOWEST indexed path first, then by fileId. Depth is load-bearing, not tidiness — a
    // NESTED repo (submodule, vendored checkout) sits at least one directory below the crawl root, so a file at
    // the root's own top level cannot be inside one and its `rev-parse --show-toplevel` is the OUTER repo's.
    // Probing crawl order instead would let a single submodule file hand back the submodule's toplevel and take
    // the entire root's churn with it. Files that ARE inside a nested repo then get no history from this root,
    // which is the right answer: `git log` in the outer repo names a submodule by its gitlink, never by the
    // paths inside it. Deterministic: (depth, fileId) is a total order.
    std::vector<std::pair<std::uint32_t, std::uint32_t>> probeOrder;   // (directory depth, fileId)
    probeOrder.reserve( ing.files.size() );
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( onlyRoot != UINT32_MAX && ( f >= ing.fileRoot.size() || ing.fileRoot[f] != onlyRoot ) )
        {
            continue;
        }
        probeOrder.emplace_back( std::uint32_t( std::count( ing.files[f].begin(), ing.files[f].end(), '/' ) ), f );
    }
    std::sort( probeOrder.begin(), probeOrder.end() );

    for( const auto& [ probeDepth, f ] : probeOrder )
    {
        // The probe's ABSOLUTE path, resolved through its DIRECTORY rather than through the file itself: a
        // symlinked file inside a tree resolves to wherever it points (possibly another repo entirely), while
        // its directory is the tree's own. diskPath() is the disk spelling behind a labeled multi-root id.
        const std::string& disk     = diskPath( ing, f );
        const std::size_t  slash    = disk.rfind( '/' );
        const std::string  probeDir = ( slash == std::string::npos ) ? std::string{ "." } : ( slash == 0 ? std::string{ "/" } : disk.substr( 0, slash ) );
        char               resolvedDir[ PATH_MAX ];
        if( !::realpath( probeDir.c_str(), resolvedDir ) )
        {
            continue; // this probe is unreadable — try the next file
        }

        const std::string top = gitRepoToplevel( resolvedDir );
        if( top.empty() )
        {
            break; // not a git repo at all — no later file changes that
        }
        offset.isGitRepo    = true;
        offset.probePath    = ing.files[f];
        offset.repoToplevel = top;

        std::string topSlash{ top };
        if( topSlash.back() != '/' )
        {
            topSlash += '/';
        }

        std::string absProbe{ resolvedDir };
        if( absProbe.back() != '/' )
        {
            absProbe += '/';
        }
        absProbe += ( slash == std::string::npos ) ? disk : disk.substr( slash + 1 );
        if( absProbe.size() <= topSlash.size() || absProbe.compare( 0, topSlash.size(), topSlash ) != 0 )
        {
            break; // probe outside its own toplevel
        }

        const std::string  gitRelProbe = normalizeJoinPath( absProbe.substr( topSlash.size() ) );
        const std::string& indexProbe  = ing.files[f];

        // the longest DIRECTORY-ALIGNED tail the two spellings share (longest first: every boundary-aligned
        // start offset of the git spelling, in order)
        for( std::size_t tailStart = 0; ; )
        {
            const std::string_view tail( gitRelProbe.data() + tailStart, gitRelProbe.size() - tailStart );
            if( isBoundarySuffix( indexProbe, tail ) )
            {
                offset.isDerived        = true;
                offset.indexStripPrefix = indexProbe.substr( 0, indexProbe.size() - tail.size() );
                offset.gitPrefix        = gitRelProbe.substr( 0, tailStart );
                break;
            }
            const std::size_t nextSlash = gitRelProbe.find( '/', tailStart );
            if( nextSlash == std::string::npos )
            {
                break;
            }
            tailStart = nextSlash + 1;
        }
        break;   // ONE probe decides the root — see the split argument above
    }
    return offset;
}

// The join's DISCLOSURES (§H6 / F4). Each names a state where a number the reader is about to trust is
// SHRUNK rather than wrong, so each is stated instead of absorbed, on the two surfaces this codebase has for a
// degrade: one stderr line (which survives -DNDEBUG — the map's own `ambiguous=`/`unresolved=` gauges are
// reference-resolution counters and a churn fix must not move them) plus a DEGRADED_PATH_ALERT for the plain
// build that gates degrade paths. ONCE per process each, not once per occurrence.
//
// What is deliberately NOT disclosed: a git path that names no indexed file. That is the ordinary state of
// thousands of paths in any real history (deleted, excluded language, outside the crawl root, renamed away,
// or a case-only drift), and it is now the only thing the join does with a path it cannot spell — saying so
// per path would bury the states below in noise. Wave 1's per-path "ambiguous tie" line went with the
// tie-break that produced it: an EXACT join has no ties to break, so the tie state no longer exists to report.
//
// A SIXTH state used to hide behind that paragraph without belonging to it, and naming it is the point of this
// note: a file whose only history is a MERGE commit. Nothing about the join lost it — the join was never handed
// its path, because `git log --name-only` says nothing about a merge commit at all. So the reader of the list
// above could not have found it there: it is not a path that names no indexed file, it is an indexed file that
// no path ever named. That is a COMMAND-level loss, and it is fixed at the command (kMergeDiffArgs, top of this
// file) rather than disclosed here, because a fix beats a disclosure whenever one is available. What remains
// genuinely unmined by the walk — a merge that resolves a conflict by taking one parent's version verbatim
// (the merge authored nothing for that file), and anything unreachable from HEAD — is stated at that constant.
//
// G2 carved ONE state back out of that silence, and the carve is deliberate: a NORMALIZATION mismatch (an NFD
// filename against git's NFC) is none of those five. Every one of them is a file whose history genuinely does
// not belong to this index; a normalization mismatch is a file whose history DOES, lost entirely to a byte
// comparison, with a measured-looking zero left in its place. It is disclosed from the INDEX side (the
// decomposed name is the evidence) and confirmed against git once, so it cannot fire on a platform where the
// two spellings agree — which is what keeps it out of the noise class the paragraph above is about.
// ONE emitter, three sentences: the only thing the three states differ in is the wording, and three copies of
// "exchange the flag, print, alert" is exactly how a fourth state ends up disclosed differently from the first
// three (the clone-seam pattern this round keeps finding). `hasReported` is per-state, so each sentence is said
// once; DEGRADED_PATH_ALERT carries its OWN once-flag, and since that flag lives here it fires for the FIRST of
// these states in a process — the per-state surface is the stderr line, which is also the one that survives
// -DNDEBUG and is therefore what the gates read.
inline void noteGitJoinDegradeOnce( std::atomic<bool>& hasReported, const std::string& humanSentence )
{
    if( hasReported.exchange( true, std::memory_order_relaxed ) )
    {
        return;
    }
    std::fprintf( stderr, "ripwire: %s\n", humanSentence.c_str() );
    DEGRADED_PATH_ALERT( "gitmine: a git-history path join was left unmade — see the stderr line naming the state and the path" );
}

inline void noteUnderivableGitJoin( const std::string& probePath )
{
    static std::atomic<bool> hasReportedUnderivableJoin{ false };
    noteGitJoinDegradeOnce( hasReportedUnderivableJoin,
                            "cannot derive how git spells the paths of the tree holding '" + probePath + "' (its repo toplevel and its indexed spelling do not line up) — "
                            "NO git history is attributed to any file of that root, so churn / co-change / ownership read as EMPTY rather than guessed" );
}

inline void noteAmbiguousGitJoin( const std::string& gitRelPath, std::uint32_t candidateCount )
{
    static std::atomic<bool> hasReportedAmbiguousJoin{ false };
    noteGitJoinDegradeOnce( hasReportedAmbiguousJoin,
                            "git-history path '" + gitRelPath + "' is the derived spelling of " + std::to_string( candidateCount )
                            + " different indexed files (two crawl roots spell one repo-relative path) — leaving it AMBIGUOUS and unresolved "
                              "(its churn / co-change / ownership is omitted, not attributed to an arbitrary same-name file)" );
}

inline void noteUnspelledIndexedFiles( const std::string& firstPath, std::uint32_t fileCount )
{
    static std::atomic<bool> hasReportedUnspelledFiles{ false };
    noteGitJoinDegradeOnce( hasReportedUnspelledFiles,
                            std::to_string( fileCount ) + " indexed file(s) do not wear their own root's path spelling (first: '" + firstPath + "') — "
                            "no git history is attributed to them, so their churn / co-change / ownership read as EMPTY rather than guessed" );
}

// G2 — the FOURTH state: a decomposed (NFD) filename whose composed (NFC) spelling is what git records.
// Names BOTH spellings, because "these two look identical and one of them is invisible to git" is precisely
// the confusion this line exists to prevent; a reader who cannot see the difference cannot act on it.
inline void noteDecomposedIndexedFiles( const std::string& indexSpelling, const std::string& gitSpelling, std::uint32_t fileCount )
{
    static std::atomic<bool> hasReportedDecomposedFiles{ false };
    noteGitJoinDegradeOnce( hasReportedDecomposedFiles,
                            std::to_string( fileCount ) + " indexed file(s) carry a DECOMPOSED (NFD) filename that git records in its COMPOSED (NFC) form "
                            "(first: indexed as '" + indexSpelling + "', git spells it '" + gitSpelling + "' — the same name, different bytes) — "
                            "this join is byte-exact, so NO git history binds to them and their churn / co-change / ownership read as EMPTY rather than guessed" );
}

// The confirmation half of G2, and the reason the disclosure above states a FACT rather than a suspicion:
// a combining mark in an indexed name only MATTERS if git spells that same file differently. So git is asked.
// `git ls-files` prints the tracked spelling; on macOS `core.precomposeunicode` also composes the pathspec we
// hand it, so an NFD argument still finds its NFC-tracked file and prints the NFC form — a different byte
// string, which is the confirmation. On a platform that records NFD, the same probe prints back exactly what
// we passed and this returns "" — correctly silent. An untracked file also returns "" (no history to lose).
// Runs at most ONCE per index build, and only when a decomposed name actually exists, so the ordinary
// pure-ASCII repo pays nothing at all.
inline std::string gitSpellingOfPath( const std::string& repoToplevel, const std::string& gitRelPath )
{
    if( repoToplevel.empty() || gitRelPath.empty() )
    {
        return {};
    }

    const GitCommandLines out = gitCommandLines( "git -c core.quotepath=false -C " + shSingleQuote( repoToplevel )
                                               + " ls-files --full-name -- " + shSingleQuote( gitRelPath ) + " 2>/dev/null" );
    if( !out.isStarted || out.lines.empty() )
    {
        return {};
    }
    return gitUnquotePath( out.lines.front() );
}

// Build THE index the join reads: the git path each ingested file WOULD be spelled as → its fileId. One
// offset per root, because a workspace merges N checkouts and each has its own repo toplevel.
// `onlyRoot` != UINT32_MAX ⇒ index ONLY that root's files — one repo's history must
// never bind to a same-named file in another root. UINT32_MAX over a MERGED ingest covers every root, and the
// one thing that can then go wrong — two roots deriving the identical repo-relative path — is refused rather
// than arbitrated (UINT32_MAX stored in the map ⇒ bindGitPathToFile reports it ambiguous).
//
// Deterministic: files are visited in fileId order, so the refusal and both disclosures name the same file on
// every run regardless of hash order.
// What ONE root's pass found worth disclosing. Accumulated across roots and reported once at the end, so a
// workspace does not say the same sentence per checkout.
struct GitPathIndexNotes
{
    std::string   unspelledFirstPath;        // first indexed file that did not wear its root's spelling
    std::uint32_t unspelledFileCount     = 0;
    std::string   collidedFirstPath;         // first git path two indexed files both derive
    std::uint32_t collidedCandidateCount = 0;
    std::string   decomposedFirstKey;        // G2: first derived key carrying a combining mark (an NFD name)
    std::string   decomposedFirstToplevel;   //     the repo it belongs to — the -C for the confirmation probe
    std::uint32_t decomposedFileCount   = 0;
};

// Add ONE root's files to the index under that root's own derived offset. `rootId` == UINT32_MAX ⇒ every file
// (the single-root ingest, which carries no fileRoot at all).
inline void addRootFilesToGitPathIndex( const IngestResult& ing, std::uint32_t rootId, GitPathIndex& byGitPath, GitPathIndexNotes& notes )
{
    const GitPathOffset offset = deriveGitPathOffset( ing, rootId );
    if( !offset.isDerived )
    {
        if( offset.isGitRepo )
        {
            noteUnderivableGitJoin( offset.probePath ); // a repo we cannot spell ⇒ loud; a non-repo ⇒ nothing to say
        }
        return;
    }

    const std::size_t stripByteCount = offset.indexStripPrefix.size();
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( rootId != UINT32_MAX && ( f >= ing.fileRoot.size() || ing.fileRoot[f] != rootId ) )
        {
            continue;
        }

        const std::string& fp = ing.files[f];
        if( fp.size() <= stripByteCount || fp.compare( 0, stripByteCount, offset.indexStripPrefix ) != 0 )
        {
            if( notes.unspelledFileCount++ == 0 )
            {
                notes.unspelledFirstPath = fp;
            }
            continue;
        }

        const std::string key    = normalizeJoinPath( offset.gitPrefix + fp.substr( stripByteCount ) );

        // G2: an NFD name is a name containing a combining mark. Counted here, CONFIRMED against git once at
        // the end — the count is what makes "some of your files have no history" a number rather than a hunch.
        if( hasCombiningMark( key ) )
        {
            if( notes.decomposedFileCount++ == 0 ) { notes.decomposedFirstKey = key;  notes.decomposedFirstToplevel = offset.repoToplevel; }
        }

        const auto [ it, isNew ] = byGitPath.try_emplace( key, f );
        if( isNew || it->second == f )
        {
            continue;
        }

        it->second = UINT32_MAX;                                            // two indexed files, one git path ⇒ neither may claim it
        if( notes.collidedCandidateCount == 0 )     { notes.collidedFirstPath = key;  notes.collidedCandidateCount = 2; }
        else if( notes.collidedFirstPath == key )
        {
            ++notes.collidedCandidateCount;
        }
    }
}

inline GitPathIndex gitPathIndexOfFiles( const IngestResult& ing, std::uint32_t onlyRoot = UINT32_MAX )
{
    GitPathIndex      byGitPath;
    GitPathIndexNotes notes;
    byGitPath.reserve( ing.files.size() );

    if( onlyRoot != UINT32_MAX )
    {
        addRootFilesToGitPathIndex( ing, onlyRoot, byGitPath, notes );
    }
    else if( ing.rootLabels.empty() )
    {
        addRootFilesToGitPathIndex( ing, UINT32_MAX, byGitPath, notes ); // unmerged ingest: no fileRoot to filter on
    }
    else
    {
        for( std::uint32_t r = 0; r < std::uint32_t( ing.rootLabels.size() ); ++r )
        {
            addRootFilesToGitPathIndex( ing, r, byGitPath, notes );
        }
    }

    if( notes.unspelledFileCount )
    {
        noteUnspelledIndexedFiles( notes.unspelledFirstPath, notes.unspelledFileCount );
    }
    if( notes.collidedCandidateCount )
    {
        noteAmbiguousGitJoin( notes.collidedFirstPath, notes.collidedCandidateCount );
    }

    // G2: the ONE confirmation probe, and only when a decomposed name exists — a pure-ASCII repo never runs it.
    // Silence when git spells the file the way we do (a platform that records NFD) or when it does not track
    // the file at all (nothing to lose): a disclosure that fires on a state with no consequence is noise, and
    // noise is what made the other five states deliberately silent in the first place.
    if( notes.decomposedFileCount )
    {
        const std::string gitSpelling = gitSpellingOfPath( notes.decomposedFirstToplevel, notes.decomposedFirstKey );
        if( !gitSpelling.empty() && gitSpelling != notes.decomposedFirstKey )
        {
            noteDecomposedIndexedFiles( notes.decomposedFirstKey, gitSpelling, notes.decomposedFileCount );
        }
    }
    return byGitPath;
}

// What ONE git-history path binds to. EXACT: the path is C-unquoted, put through the one shared
// normalisation, and looked up. `fileId == UINT32_MAX` ⇒ nothing bound — either no indexed file spells this
// path (the ordinary case: deleted, excluded, outside the crawl root, renamed away, or a case-only drift) or
// two roots spell it identically, which `isAmbiguous()` distinguishes. There is no third answer and no fuzzy
// answer; that absence IS §H6's fix (see GitPathIndex).
//
// C-unquoting happens HERE rather than per caller. The churn tally and the changed mask used to skip it "for
// byte-identity", which under a fuzzy join merely meant such paths dropped silently; under an exact join it is
// the difference between a quoted path resolving and not, so the seam owns it and every caller gets it.
struct GitPathBinding
{
    std::uint32_t fileId             = UINT32_MAX;
    bool          isRefusedAmbiguous = false;   // the path is derived by 2+ indexed files ⇒ refused, and disclosed at index build

    bool isResolved()  const noexcept { return fileId != UINT32_MAX; }
    bool isAmbiguous() const noexcept { return isRefusedAmbiguous; }
};

inline GitPathBinding bindGitPathToFile( const GitPathIndex& byGitPath, const std::string& rawGitPath )
{
    GitPathBinding binding;
    const auto     it = byGitPath.find( normalizeJoinPath( gitUnquotePath( rawGitPath ) ) );
    if( it == byGitPath.end() )
    {
        return binding;
    }
    if( it->second == UINT32_MAX ) { binding.isRefusedAmbiguous = true;  return binding; }
    binding.fileId = it->second;
    return binding;
}

// Resolve `rawGp` (a git repo-relative path, possibly C-quoted) to one ingested fileId, or UINT32_MAX. A pure
// function of (byGitPath, rawGp) with no side effects: the three states worth disclosing are all properties of
// the INDEX and are disclosed once when it is built, not once per lookup — so this is the thin sugar the five
// stream miners share.
inline std::uint32_t resolveGitPath( const GitPathIndex& byGitPath, const std::string& rawGp )
{
    return bindGitPathToFile( byGitPath, rawGp ).fileId;
}

// Mark the ingested files a git CHANGED-PATH list names (§H6). A mask, not a tally, so the consequence of a
// wrong join differs and was just as wrong: the bare boundary-suffix test let a root-level `util.cpp` mark
// every `*/util.cpp` in the tree, and --map-diff reported changed="2" where git changed exactly ONE file —
// seeding its diff teleport from a file nobody touched. Each changed path now marks the ONE file whose own
// derived git spelling it is, or nothing.
//
// F4: the earlier fix kept a fuzzy fallback and marked ALL candidates of a TIE, arguing a mask should not drop
// a real change. That argument only holds for candidates the evidence actually implicates — and a bare
// basename implicates every deeper path, which is how the over-mark was born. With the offset derived there is
// nothing to arbitrate: an unresolvable changed path is a path outside the crawl root or absent from the index,
// and marking a same-named stranger for it is the defect, not the recall.
// `outMask` must already be sized to ing.files.size(); `onlyRoot` != UINT32_MAX ⇒ mark only that root's files.
// The walk both the mask and the tally are: build the index once, resolve every entry, hand the caller the ONE
// file each entry binds to. Spelled once because the two used to be the same twelve lines twice — which is how
// they came to carry the same "first match in the bucket wins" defect twice (§H6) — and because an empty input
// must skip the offset probe in BOTH, not just whichever one remembered to.
// `entries` is any range whose element is a git path (a changed-path list) or a (git path, value) pair (a churn
// tally); `apply( fileId, entry )` does the caller's one distinct thing with it.
inline const std::string& gitPathOfEntry( const std::string& gitRelPath ) noexcept { return gitRelPath; }
template<typename Key, typename Value>   // Key covers both pair<string,V> (unordered_dense) and pair<const string,V>
inline const std::string& gitPathOfEntry( const std::pair<Key, Value>& tallyEntry ) noexcept { return tallyEntry.first; }

template<typename Entries, typename Apply>
inline void forEachBoundGitPath( const Entries& entries, const IngestResult& ing, std::uint32_t onlyRoot, Apply&& apply )
{
    if( entries.empty() )
    {
        return; // nothing to join ⇒ do not even probe for the offset
    }

    const GitPathIndex byGitPath = gitPathIndexOfFiles( ing, onlyRoot );
    for( const auto& entry : entries )
    {
        const std::uint32_t fileId = resolveGitPath( byGitPath, gitPathOfEntry( entry ) );
        if( fileId != UINT32_MAX )
        {
            apply( fileId, entry );
        }
    }
}

inline void markChangedFilesFromGitPaths( const std::vector<std::string>& changedPaths, const IngestResult& ing,
                                          std::vector<char>& outMask, std::uint32_t onlyRoot = UINT32_MAX )
{
    VERIFY( outMask.size() == ing.files.size() );
    forEachBoundGitPath( changedPaths, ing, onlyRoot,
                         [ & ]( std::uint32_t fileId, const std::string& ) { outMask[ fileId ] = 1; } );
}

// Map a per-git-path churn tally onto ingested fileIds (§H6). THE ONE mapper: this file's
// resolveCommitStream (the --for / --metrics churn= lens) and main.cpp's gitChurnCounts (--hotspots) carried
// the same loop twice, and therefore the same "first match in the bucket wins" defect twice.
//
// Driven by the counted PATHS, not by the files. Each path's count goes to the ONE file whose own derived git
// spelling it is, so a path can never be counted twice AND a file can never receive a count that is not its
// own history: with the offset derived, "the file this path names" and "a file with the same basename" have
// stopped being the same question. The phantom that outlived the first fix — a DELETED root `zeta.cpp`'s 6
// commits landing on `a/zeta.cpp`, which had none in the window, because a deleted file leaves no TIE to
// refuse — cannot be spelled here any more: `zeta.cpp` is not `a/zeta.cpp`, and no candidate list exists to
// pick a runner-up from.
//
// `outChurn` must already be sized to ing.files.size(); a file with no in-window commit keeps its 0, and that 0
// is now a MEASURED zero rather than an absence of evidence — unless the whole root's join could not be made,
// which is the one state the index discloses and which surfaces as `window="… (no churn evidence)"`.
// `onlyRoot` != UINT32_MAX ⇒ write only files of that root (multi-root §5 per-root isolation).
// Deterministic despite the unordered tally: at most one KEY per file exists, and the max() guard makes the one
// pathological case (two raw spellings normalising to one key) order-independent instead of last-write-wins.
inline void mapChurnCountsOntoFiles( const HashMap<std::string, std::uint32_t>& churnCounts, const IngestResult& ing,
                                     std::vector<std::uint32_t>& outChurn, std::uint32_t onlyRoot = UINT32_MAX )
{
    VERIFY( outChurn.size() == ing.files.size() );
    forEachBoundGitPath( churnCounts, ing, onlyRoot,
                         [ & ]( std::uint32_t fileId, const auto& tallyEntry )
                         { outChurn[ fileId ] = std::max( outChurn[ fileId ], tallyEntry.second ); } );   // never a sum: two distinct git paths would invent commits
}

// Per-commit sets of changed files (resolved to ingested file ids), for co-change mining. Commits larger
// than maxFiles are dropped — bulk renames / reformats / license sweeps destroy the coupling signal.
// onlyRoot (multi-root): != UINT32_MAX ⇒ resolve this repo's paths ONLY against
// files of that root (ing.fileRoot) — one repo's history must never suffix-match a same-named file in
// another root. Default = all files (single-root behavior, byte-identical).
//
// Shared stream core for the per-commit changed-file-set miners: run `git log <windowArgs> --name-only`
// and resolve each commit's paths to ingested fileIds (the ONE exact git-path join), keeping sets of
// 1..maxFiles files. `windowArgs` is the caller-built window clause — "--since='DATE' ", "'REV..' ", or
// "-N " (trailing space required, exactly as sinceLogArgs emits). Extracted (B3) so gitCommitFileSets
// (date/rev windows) and gitRecentCommitFileSets (last-N-commits window) share ONE parser instead of
// cloning it; gitCommitFileSets' behavior is byte-identical to its pre-extraction form.
inline std::vector<std::vector<std::uint32_t>> gitLogFileSets( const std::string& root, const IngestResult& ing, const std::string& windowArgs, std::size_t maxFiles,
                                                               std::uint32_t onlyRoot = UINT32_MAX )
{
    std::vector<std::vector<std::uint32_t>> sets;

    // the index is built BEFORE the log pipe opens: it runs a git probe of its own, and nesting that inside an
    // open --name-only pipe would leave a filled pipe buffer waiting on us while we wait on the probe.
    const GitPathIndex byGitPath = gitPathIndexOfFiles( ing, onlyRoot );

    const std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root ) + " log " + kMergeDiffArgs + windowArgs + "--name-only --format=tformat:__C__ 2>/dev/null";
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        return sets;
    }

    std::vector<std::uint32_t> cur;
    const auto flush = [ & ]()
    {
        std::sort( cur.begin(), cur.end() );
        cur.erase( std::unique( cur.begin(), cur.end() ), cur.end() );
        if( cur.size() >= 1 && cur.size() <= maxFiles )
        {
            sets.push_back( cur ); // keep 1..max (freq needs size-1 too)
        }
        cur.clear();
    };
    std::string s;
    while( readByteSafeLine( pipe, s ) )   // F6: THE line reader, not a char[4096] a long path can be split across
    {
        while( !s.empty() && ( s.back() == '\n' || s.back() == '\r' ) )
        {
            s.pop_back();
        }
        if( s == "__C__" ) { flush(); continue; }
        if( s.empty() )
        {
            continue;
        }
        const std::uint32_t f = resolveGitPath( byGitPath, s );
        if( f != UINT32_MAX )
        {
            cur.push_back( f );
        }
    }
    flush();
    pclose( pipe );
    return sets;
}

// Per-commit sets of changed files over a --since window (see gitLogFileSets for the parsing contract).
// `scope`: nullptr (default) reproduces the pre-flag behavior byte-for-byte — `--since=<since>` (a fixed
// default date) is used exactly as before; a non-null *inactive* scope ALSO falls back to `<since>`; a
// non-null *active* scope overrides `since` with the resolved --since=REV|DATE window (sinceLogArgs).
inline std::vector<std::vector<std::uint32_t>> gitCommitFileSets( const std::string& root, const IngestResult& ing, const char* since, std::size_t maxFiles, const SinceScope* scope = nullptr,
                                                                  std::uint32_t onlyRoot = UINT32_MAX )
{
    PROFILE_SCOPE_DESCRIBE( "gitmine: gitCommitFileSets (git log --name-only popen)" );
    const std::string windowArgs = scope ? sinceLogArgs( *scope, since ) : ( "--since=" + shSingleQuote( since ) + " " );
    return gitLogFileSets( root, ing, windowArgs, maxFiles, onlyRoot );
}

// B3 (co-change prior boost): per-commit changed-file sets over the LAST `commitCount` commits reachable
// from HEAD — a commit-COUNT window, deliberately NOT a date window: (1) it is a pure function of the
// checked-out tree state (same repo@HEAD ⇒ same sets on any machine on any day — the det-gate posture;
// a "18 months ago" approxidate drifts with the wall clock), and (2) it stays meaningful on HISTORICAL
// checkouts (a repo pinned to a 2024 base commit has nothing inside a wall-clock window measured in 2026,
// which is exactly the LocBench-eval shape). Degrades to empty on no-git / no-history, like every miner here.
inline std::vector<std::vector<std::uint32_t>> gitRecentCommitFileSets( const std::string& root, const IngestResult& ing, std::uint32_t commitCount, std::size_t maxFiles,
                                                                        std::uint32_t onlyRoot = UINT32_MAX )
{
    PROFILE_SCOPE_DESCRIBE( "gitmine: gitRecentCommitFileSets (co-change boost window)" );
    return gitLogFileSets( root, ing, "-" + std::to_string( commitCount ) + " ", maxFiles, onlyRoot );
}

// git's approxidate for "<months> months ago" is calendar-month subtraction from the current local time
// (date.c: tm_mon -= months, normalize); mirror it with localtime/mktime so a self-computed churn cutoff
// tracks what `git log --since="<months> months ago"` would use, to within the (sub-second) gap between the
// two clock reads — far tighter than the minutes-to-hours spacing of real commits, so no commit is ever
// bucketed differently. Used by gitCoChangeAndChurn to slice the shorter churn window out of the longer
// co-change walk in ONE popen (A4-P6). NOT for the det-gate paths (those anchor on HEAD's committer epoch).
inline std::int64_t approxMonthsAgoEpoch( unsigned months )
{
    const std::time_t now = std::time( nullptr );
    std::tm           tmv{};
    localtime_r( &now, &tmv );
    tmv.tm_mon -= int( months );                   // calendar-month subtraction (git approxidate semantics)
    return std::int64_t( std::mktime( &tmv ) );    // mktime normalizes the month/year underflow, like git
}

// The RAW, per-commit (epoch, changed-paths) stream from ONE `git log --name-only` walk
// over `coSince`: the parsed-but-UNRESOLVED form gitCoChangeAndChurn needs. Split out of that function so
// it can be MEMOIZED (quality::gitCoChangeAndChurnCached) independent of any particular ingest's fileId
// space — paths stay raw repo-relative strings here; resolveCommitStream (below) resolves them against a
// CALLER-supplied `ing` fresh on every call. Committed-history-only by construction (git log never sees
// working-tree state), which is exactly what makes this cacheable: two calls with the SAME (repo, coSince)
// against a DIFFERENT current `ing` (a dirty file added/removed since the cache was written) still resolve
// correctly, because resolution — not this raw walk — is where `ing` enters.
struct RawCommitStream
{
    struct Commit { std::int64_t epoch = 0; std::vector<std::string> paths; };
    std::vector<Commit> commits;
};

inline RawCommitStream gitLogNameOnlyRaw( const std::string& root, const std::string& coSince )
{
    PROFILE_SCOPE_DESCRIBE( "gitmine: gitLogNameOnlyRaw (git log --name-only popen)" );
    RawCommitStream out;
    const std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root )
                          + " log " + kMergeDiffArgs + "--since=" + shSingleQuote( coSince )
                          + " --name-only --format=tformat:__C__%x20%ct 2>/dev/null";
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        return out;
    }

    std::string s;
    while( readByteSafeLine( pipe, s ) )   // F6: THE line reader, not a char[4096] a long path can be split across
    {
        while( !s.empty() && ( s.back() == '\n' || s.back() == '\r' ) )
        {
            s.pop_back();
        }
        if( s.rfind( "__C__", 0 ) == 0 )                       // new commit marker: "__C__ <epoch>"
        {
            const std::int64_t epoch = ( s.size() > 6 ) ? std::strtoll( s.c_str() + 6, nullptr, 10 ) : 0;
            out.commits.push_back( RawCommitStream::Commit{ epoch, {} } );
            continue;
        }
        if( s.empty() )
        {
            continue;
        }
        if( out.commits.empty() )
        {
            out.commits.push_back( RawCommitStream::Commit {} ); // defensive: tformat always emits the marker first, but never crash on a malformed stream
        }
        out.commits.back().paths.push_back( std::move( s ) );   // readByteSafeLine clear()s its buffer first, so moving out of it is safe
    }
    pclose( pipe );
    return out;
}

// Y2 — the cheap freshness PROBE for a wall-clock-relative `coSince` window (e.g. "18 months ago"): the sha
// of the OLDEST commit git currently considers inside that window. Unlike gitLogNameOnlyRaw this skips
// --name-only entirely (no per-commit diff/path listing — just commit shas), so it is a small fraction of
// the 431 ms walk it guards. `coSince` is resolved against WALL-CLOCK now() by git's own approxidate parser,
// so the window's boundary — and therefore this sha — silently drifts by one day at a time even with HEAD
// unchanged; probing it fresh on every call (cheaply) and folding it into the qchurn cache key is what lets
// that key be (repo, HEAD sha, coSince, boundarySha) instead of (repo, HEAD sha, coSince) alone, which would
// serve a yesterday-computed answer past the day it silently expired. Empty on no-git/empty window (that
// degrade is fine — an empty window has nothing to drift, and gitLogNameOnlyRaw degrades identically).
inline std::string gitWindowBoundarySha( const std::string& root, const std::string& coSince )
{
    PROFILE_SCOPE_DESCRIBE( "gitmine: gitWindowBoundarySha (cheap window-drift probe)" );
    // G3: the shared reader, not a private `char buf[128]` + fgets accumulate. `| tail -1` already reduces
    // the output to one line, so `.back()` is that line; gitCommandLines has already stripped its CR/LF tail.
    const std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root )
                          + " log --since=" + shSingleQuote( coSince ) + " --format=%H 2>/dev/null | tail -1";
    const GitCommandLines res = gitCommandLines( cmd );
    if( !res.isStarted || res.lines.empty() )
    {
        return {};
    }
    return res.lines.back();
}

// Resolve a RawCommitStream against the CURRENT `ing` (+ `onlyRoot`) into the same (sets, churn) shape
// gitCoChangeAndChurn has always returned — pure in-memory work (basename/suffix matching + a churn tally),
// no subprocess. Split out (Y2) so the cached path (quality::gitCoChangeAndChurnCached) and the uncached
// path (gitCoChangeAndChurn, below) share ONE resolver instead of two copies that could drift.
inline std::vector<std::vector<std::uint32_t>> resolveCommitStream(
    const RawCommitStream& raw, const IngestResult& ing, std::size_t maxFiles,
    unsigned churnMonths, std::vector<std::uint32_t>* outChurn, std::uint32_t onlyRoot = UINT32_MAX )
{
    std::vector<std::vector<std::uint32_t>> sets;
    if( outChurn )
    {
        outChurn->assign( ing.files.size(), 0u ); // always sized (even on an empty stream)
    }
    if( raw.commits.empty() )
    {
        return sets; // nothing to resolve ⇒ do not even probe for the offset
    }

    // the git-path index over ingested files → fileId — THE shared builder, so this miner and gitCommitFileSets
    // cannot drift on which files are indexable or on how a git path is spelled.
    const GitPathIndex byGitPath = gitPathIndexOfFiles( ing, onlyRoot );
    const auto         resolve   = [ & ]( const std::string& gp ) { return resolveGitPath( byGitPath, gp ); };

    // churn: raw repo-relative path → #in-window commits touching it (identical to gitChurnCounts' `counts`).
    const std::int64_t                  churnCutoff = ( outChurn && churnMonths ) ? approxMonthsAgoEpoch( churnMonths ) : 0;
    HashMap<std::string, std::uint32_t> churnCounts;

    for( const RawCommitStream::Commit& c : raw.commits )
    {
        const bool inChurnWindow = ( outChurn && c.epoch >= churnCutoff );   // slice the churn sub-window off the same stream
        std::vector<std::uint32_t> cur;
        for( const std::string& p : c.paths )
        {
            if( inChurnWindow )
            {
                ++churnCounts[p]; // churn tally: raw path (gitChurnCounts parity)
            }
            const std::uint32_t f = resolve( p );               // co-change: resolve to fileId
            if( f != UINT32_MAX )
            {
                cur.push_back( f );
            }
        }
        std::sort( cur.begin(), cur.end() );
        cur.erase( std::unique( cur.begin(), cur.end() ), cur.end() );
        if( cur.size() >= 1 && cur.size() <= maxFiles )
        {
            sets.push_back( std::move( cur ) ); // keep 1..max (freq needs size-1 too)
        }
    }

    // Map churn raw-path counts onto ingested fileIds — the SHARED specificity-ordered mapper (§H6), the same
    // one main.cpp's gitChurnCounts uses. Still no C-unquote on this side (gitChurnCounts does not either;
    // preserved for byte-identity — A4-F13 covers the co-change/ownership resolvers, not this tally).
    if( outChurn )
    {
        mapChurnCountsOntoFiles( churnCounts, ing, *outChurn, onlyRoot );
    }
    return sets;
}

// A4-P6: ONE `git log --name-only` popen yielding BOTH the per-commit co-change file-sets (over `coSince`,
// commits capped at `maxFiles` — BYTE-IDENTICAL to gitCommitFileSets(coSince, maxFiles) with no scope) AND,
// when `outChurn`!=null, per-file commit counts over the SHORTER `churnMonths`-month sub-window
// (BYTE-IDENTICAL to gitChurnCounts("<churnMonths> months ago")). The commit-file-sets walk already streams
// every path occurrence, so a per-file count over the same stream IS the churn — this folds the two
// subprocesses the --for path used to spawn (18-month sets + 12-month churn) into ONE 18-month walk, bucketed
// by each commit's committer epoch so each number keeps its OWN horizon. The stream carries `%ct` on the
// marker line ("__C__ <epoch>"); adding the epoch changes no file line, so the co-change sets are identical to
// gitCommitFileSets'. Churn counts raw repo-relative path occurrences of in-window commits and suffix-maps
// them to fileIds exactly as gitChurnCounts does (no C-unquote there either — same A4-F13 behavior, preserved
// for identity). Degrades cleanly: no git → empty sets + all-zero churn. Determinism note: `churnMonths`
// resolves through approxMonthsAgoEpoch (wall-clock-relative, same as the gitChurnCounts it replaces).
//
// This UNCACHED form is now a thin raw-walk + resolve composition (below) — kept as-is for
// any caller that doesn't want the memoized path. The two rich-verb call sites (main.cpp's --metrics/--for
// amp=/churn= computation) go through quality::gitCoChangeAndChurnCached instead, which memoizes exactly
// the expensive part (gitLogNameOnlyRaw) this function also calls.
inline std::vector<std::vector<std::uint32_t>> gitCoChangeAndChurn(
    const std::string& root, const IngestResult& ing, const char* coSince, std::size_t maxFiles,
    unsigned churnMonths = 0, std::vector<std::uint32_t>* outChurn = nullptr,
    std::uint32_t onlyRoot = UINT32_MAX )   // multi-root §5: resolve ONLY against files of that root
{
    PROFILE_SCOPE_DESCRIBE( "gitmine: gitCoChangeAndChurn (single git log --name-only popen)" );
    const RawCommitStream raw = gitLogNameOnlyRaw( root, coSince );
    return resolveCommitStream( raw, ing, maxFiles, churnMonths, outChurn, onlyRoot );
}

// ── short-horizon churn (GitClear 2026: +15% "new code rewritten within two weeks" in AI-authored code) ──
//
// Per-file commit count within a `days`-wide window measured DETERMINISTICALLY from git commit timestamps —
// specifically `HEAD_commit_epoch − commit_epoch ≤ days·86400`, NOT the system wall clock. Anchoring the
// window at HEAD's own commit time (git's committer epoch, %ct) keeps the result byte-stable for a fixed tree
// state (the det-gate requirement): the same repo at the same HEAD yields the same counts on every run and
// machine, unlike a `--since="2 weeks ago"` approxidate which drifts with today's date. Returns a per-fileId
// count vector sized to ing.files (0 for files with no in-window commit / unresolvable path).
//
// Deterministic + degrade-don't-throw: no git / no HEAD / popen failure → an all-zero vector (caller treats
// it as "no short-horizon signal", never a crash). `git log` file paths are resolved to fileIds by the same
// basename-suffix matcher gitCommitFileSets uses, so a moved-into-tree path resolves identically.
// HEAD's committer epoch — THE deterministic "now" every age-measuring miner here anchors on, in ONE place
// so two of them cannot disagree about what "today" means. 0 ⇒ no git / no HEAD / an unparseable stamp;
// every caller treats that as "no history signal" and degrades, never as epoch zero.
//
// Extracted (P0-4) from gitFileCommitCountsInDayWindow, whose behavior is unchanged — it was the only
// anchor reader until the decayed-churn prior needed the same number, and a second copy of this is exactly
// how one surface ends up measuring age from HEAD while its sibling measures it from the wall clock.
inline std::int64_t gitHeadCommitEpoch( const std::string& root )
{
    // G3: the shared reader. `log -1 --format=%ct` prints exactly one line, so the first is the whole
    // answer; gitCommandLines strips the CR/LF tail, and the trailing-space strip is kept for the value.
    const std::string     cmd = "git -c core.quotepath=false -C " + shSingleQuote( root ) + " log -1 --format=%ct HEAD 2>/dev/null";
    const GitCommandLines res = gitCommandLines( cmd );
    if( !res.isStarted || res.lines.empty() )
    {
        return 0;
    }
    std::string out = res.lines.front();
    while( !out.empty() && out.back() == ' ' )
    {
        out.pop_back();
    }
    if( out.empty() )
    {
        return 0;
    }
    const std::int64_t epoch = std::strtoll( out.c_str(), nullptr, 10 );
    return epoch > 0 ? epoch : 0;
}

inline std::vector<std::uint32_t> gitFileCommitCountsInDayWindow( const std::string& root, const IngestResult& ing, std::uint32_t days )
{
    PROFILE_SCOPE_DESCRIBE( "gitmine: gitFileCommitCountsInDayWindow (short-horizon churn)" );
    std::vector<std::uint32_t> counts( ing.files.size(), 0 );
    if( ing.files.empty() )
    {
        return counts;
    }

    // HEAD's committer epoch — the window anchor (deterministic; system now() is never consulted).
    const std::int64_t headEpoch = gitHeadCommitEpoch( root );
    if( headEpoch <= 0 )
    {
        return counts;
    }
    const std::int64_t cutoff = headEpoch - std::int64_t( days ) * 86400;   // window floor (inclusive)

    // the exact git-path resolver — the shared builder + the shared binding, same as every miner here.
    const GitPathIndex byGitPath = gitPathIndexOfFiles( ing );
    const auto         resolve   = [ & ]( const std::string& gp ) { return resolveGitPath( byGitPath, gp ); };

    // Stream `git log --name-only` with each commit's epoch on its __C__ marker line: "__C__ <epoch>".
    // A commit counts once per file it touches, iff its epoch is within [cutoff, headEpoch].
    const std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root )
                          + " log " + kMergeDiffArgs + "--name-only --format=tformat:__C__%x20%ct 2>/dev/null";
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        return counts;
    }

    bool                       inWindow = false;   // is the commit we are currently reading files for in-window?
    std::vector<std::uint32_t> cur;                // this commit's resolved fileIds (dedup before tally)
    const auto flush = [ & ]()
    {
        if( inWindow )
        {
            std::sort( cur.begin(), cur.end() );
            cur.erase( std::unique( cur.begin(), cur.end() ), cur.end() );
            for( std::uint32_t f : cur )
            {
                ++counts[f];
            }
        }
        cur.clear();
    };
    std::string s;
    while( readByteSafeLine( pipe, s ) )   // F6: THE line reader, not a char[4096] a long path can be split across
    {
        while( !s.empty() && ( s.back() == '\n' || s.back() == '\r' ) )
        {
            s.pop_back();
        }
        if( s.rfind( "__C__", 0 ) == 0 )                       // new commit marker: "__C__ <epoch>"
        {
            flush();
            const std::int64_t epoch = ( s.size() > 6 ) ? std::strtoll( s.c_str() + 6, nullptr, 10 ) : 0;
            inWindow = ( epoch >= cutoff && epoch <= headEpoch );
            continue;
        }
        if( s.empty() || !inWindow )
        {
            continue;
        }
        const std::uint32_t f = resolve( s );
        if( f != UINT32_MAX )
        {
            cur.push_back( f );
        }
    }
    flush();
    pclose( pipe );
    return counts;
}

// --rank-by=churn teleport: weight each symbol by its file's git change-frequency (commits touching it in
// the window), Laplace-smoothed (+1) so every symbol keeps positive mass. Frequently-edited code is a
// proven "what matters here" prior. No git / no history → uniform (degrades cleanly). Deterministic (for
// the default window, or an active REV `scope`; a date `scope` is wall-clock-relative by construction).
// shared Laplace-smoothed churn→teleport core: per-file commit frequency → a Σ=1-able symbol prior
// (+1 smoothing keeps every symbol positive). !anyHistory ⇒ uniform (the no-git degrade both callers share).
//
// §B2.2: "uniform" means the caller is handed the STRUCTURAL ranking under a churn label — the ranks come out
// byte-identical to --rank-by=pagerank. That is a legitimate degrade and a misleading answer at the same time,
// so it is disclosed at the seam that produces it (both callers inherit the alert) AND reported up through
// `outHasChurnEvidence`, so the emitting verb can put it in the stamp a reader actually sees — the alert alone
// is compiled out under -DNDEBUG.
inline std::vector<float> churnPriorFromFreq( const IngestResult& ing, const std::vector<std::uint32_t>& freq, bool anyHistory )
{
    const std::size_t N = ing.symbols.size();
    std::vector<float> p( N, N ? 1.0f / float( N ) : 0.f );
    if( N == 0 || !anyHistory )
    {
        if( !anyHistory )
        {
            DEGRADED_PATH_ALERT( "gitmine: the churn window mined no commits — the churn prior is UNIFORM, so the ranking is the structural one" );
        }
        return p;
    }
    double tot = 0.0;
    for( const Symbol& s : ing.symbols )
    {
        tot += double( freq[s.fileId] ) + 1.0;
    }
    if( tot <= 0.0 )
    {
        return p;
    }
    for( const Symbol& s : ing.symbols )
    {
        p[s.id] = float( ( double( freq[s.fileId] ) + 1.0 ) / tot );
    }
    return p;
}

// `outHasChurnEvidence` (§B2.2, optional): false ⇒ the window mined NOTHING and the returned prior is uniform,
// i.e. the caller's "churn-ranked" map is the structural one. The emitting verb needs that fact to stamp it
// (see churnWindowStamp); nullptr keeps every pre-existing call byte-identical.
inline std::vector<float> churnTeleport( const std::string& root, const IngestResult& ing, const char* since = "18 months ago", const SinceScope* scope = nullptr,
                                         bool* outHasChurnEvidence = nullptr )
{
    PROFILE_SCOPE_DESCRIBE( "gitmine: churnTeleport (rank-by=churn)" );
    std::vector<std::uint32_t> freq( ing.files.size(), 0 );
    const auto sets = gitCommitFileSets( root, ing, since, 100, scope );   // generous cap: keep refactors, drop merge-bombs
    for( const auto& set : sets )
    {
        for( const std::uint32_t f : set )
        {
            ++freq[f];
        }
    }
    if( outHasChurnEvidence )
    {
        *outHasChurnEvidence = !sets.empty();
    }
    return churnPriorFromFreq( ing, freq, !sets.empty() );
}

// Multi-root --rank-by=churn: mine each root's history AGAINST ITS OWN files
// (per-root isolation), accumulate ONE per-file frequency table, then apply the same Laplace-smoothed
// symbol weighting once — a joint prior over the merged graph without ever mixing repo histories.
// Caveat (documented at the emit site): commit-count scales are per-repo; the joint prior treats a
// commit in either repo as equal weight. No git anywhere → uniform (same degrade as churnTeleport).
inline std::vector<float> churnTeleportWorkspace( const std::vector<std::string>& rootDirs, const IngestResult& ing, const char* since = "18 months ago",
                                                  bool* outHasChurnEvidence = nullptr )   // §B2.2 — see churnTeleport
{
    PROFILE_SCOPE_DESCRIBE( "gitmine: churnTeleportWorkspace (multi-root rank-by=churn)" );
    std::vector<std::uint32_t> freq( ing.files.size(), 0 );
    bool anyHistory = false;
    for( std::uint32_t r = 0; r < rootDirs.size(); ++r )
    {
        const auto sets = gitCommitFileSets( rootDirs[r], ing, since, 100, nullptr, r );
        if( !sets.empty() )
        {
            anyHistory = true;
        }
        for( const auto& set : sets )
        {
            for( const std::uint32_t f : set )
            {
                ++freq[f];
            }
        }
    }
    if( outHasChurnEvidence )
    {
        *outHasChurnEvidence = anyHistory;
    }
    return churnPriorFromFreq( ing, freq, anyHistory );
}

// ── P0-4: TIME-DECAYED churn ─────────────────────────────────────────────────────────────────────────
//
// Raw churn counts every commit in its window EQUALLY, so a file rewritten fifteen times two years ago
// outranks one rewritten twice last week. That is the opposite of the prior an agent wants, and widening or
// narrowing the window only moves the cliff — a hard window is a step function over a quantity that decays
// smoothly. Exponential decay prices recency instead of thresholding it: a commit `age` days before HEAD
// contributes 0.5^(age / halfLife).
//
// HALF-LIFE = 90 days, the conventional default in the software-evolution literature's exponential-decay
// weightings; it is a CHOICE, not a measurement, which is why it is disclosed in the map's window= stamp and
// in the legend rather than buried here. At 90 days a commit from last week counts ~0.95, one from a year
// ago ~0.06, one from three years ago ~0.001 — recent history dominates without any commit ever being
// discarded, which is what lets the default mine the WHOLE history instead of a wall-clock window.
//
// DETERMINISM — the reason this is not just churnTeleport with weights. "Now" is HEAD's own committer epoch
// (gitHeadCommitEpoch), never std::time(). A wall-clock anchor would make this the one verb whose output
// changes overnight on an unchanged tree, which the determinism contract forbids; and because the decay
// makes an explicit window unnecessary, the DEFAULT path passes no --since at all and is therefore a pure
// function of (repo, HEAD). An explicit --since=DATE still scopes it, and that arm is wall-clock-relative by
// the user's own choice, exactly as it already is for --rank-by=churn.
//
// A commit dated AFTER HEAD (possible on a merged branch, or with a skewed committer clock) would decay to a
// weight above 1; the age is clamped at 0 so no commit can ever count for more than a commit made at HEAD.
inline constexpr double kChurnDecayHalfLifeDays = 90.0;

// Per-fileId decayed commit weight over `windowArgs` (the caller-built window clause, exactly as
// gitLogFileSets takes it — pass "" for the whole history). Mirrors gitLogFileSets' parse, plus the epoch on
// the marker line; a commit touching more than `maxFiles` files is skipped by the same merge-bomb rule.
// Degrades to an all-zero vector on no git / no HEAD / popen failure, and reports that through `outAnyHistory`.
inline std::vector<double> gitLogDecayedFileWeights( const std::string& root, const IngestResult& ing, const std::string& windowArgs,
                                                     std::size_t maxFiles, bool* outAnyHistory, std::uint32_t onlyRoot = UINT32_MAX )
{
    PROFILE_SCOPE_DESCRIBE( "gitmine: gitLogDecayedFileWeights (rank-by=churn-decay)" );
    std::vector<double> weights( ing.files.size(), 0.0 );
    if( outAnyHistory )
    {
        *outAnyHistory = false;
    }
    if( ing.files.empty() )
    {
        return weights;
    }

    // The anchor first: without it there is no age to measure, so there is no answer to degrade FROM.
    const std::int64_t headEpoch = gitHeadCommitEpoch( root );
    if( headEpoch <= 0 )
    {
        DEGRADED_PATH_ALERT( "gitmine: no HEAD committer epoch — the decayed-churn prior is UNIFORM" );
        return weights;
    }

    // built BEFORE the log pipe opens, for the reason gitLogFileSets states: it runs a git probe of its own.
    const GitPathIndex byGitPath = gitPathIndexOfFiles( ing, onlyRoot );

    const std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root ) + " log " + kMergeDiffArgs + windowArgs
                          + "--name-only --format=tformat:__C__%x20%ct 2>/dev/null";
    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        return weights;
    }

    bool                       anyCommit = false;
    double                     curWeight = 0.0;   // this commit's decayed weight
    std::vector<std::uint32_t> cur;               // this commit's resolved fileIds (dedup before tally)
    const auto flush = [ & ]()
    {
        std::sort( cur.begin(), cur.end() );
        cur.erase( std::unique( cur.begin(), cur.end() ), cur.end() );
        if( cur.size() >= 1 && cur.size() <= maxFiles )
        {
            for( std::uint32_t f : cur )
            {
                weights[f] += curWeight;
            }
        }
        cur.clear();
    };
    std::string s;
    while( readByteSafeLine( pipe, s ) )   // F6: THE line reader, not a char[4096] a long path can be split across
    {
        while( !s.empty() && ( s.back() == '\n' || s.back() == '\r' ) )
        {
            s.pop_back();
        }
        if( s.rfind( "__C__", 0 ) == 0 )   // new commit marker: "__C__ <epoch>"
        {
            flush();
            anyCommit                 = true;
            const std::int64_t epoch  = ( s.size() > 6 ) ? std::strtoll( s.c_str() + 6, nullptr, 10 ) : 0;
            const std::int64_t ageSec = ( epoch > 0 && headEpoch > epoch ) ? ( headEpoch - epoch ) : 0;   // clamped: never > 1
            curWeight                 = std::pow( 0.5, ( double( ageSec ) / 86400.0 ) / kChurnDecayHalfLifeDays );
            continue;
        }
        if( s.empty() )
        {
            continue;
        }
        const std::uint32_t f = resolveGitPath( byGitPath, s );
        if( f != UINT32_MAX )
        {
            cur.push_back( f );
        }
    }
    flush();
    pclose( pipe );
    if( outAnyHistory )
    {
        *outAnyHistory = anyCommit;
    }
    return weights;
}

// The decayed sibling of churnPriorFromFreq: same Laplace-smoothed (+1) shape, so every symbol keeps
// positive mass and the "no history ⇒ uniform" degrade is spelled once per family, not once per caller.
inline std::vector<float> churnPriorFromDecayed( const IngestResult& ing, const std::vector<double>& weights, bool anyHistory )
{
    const std::size_t  N = ing.symbols.size();
    std::vector<float> p( N, N ? 1.0f / float( N ) : 0.f );
    if( N == 0 || !anyHistory )
    {
        if( !anyHistory )
        {
            DEGRADED_PATH_ALERT( "gitmine: the decayed-churn walk mined no commits — the prior is UNIFORM, so the ranking is the structural one" );
        }
        return p;
    }
    double tot = 0.0;
    for( const Symbol& s : ing.symbols )
    {
        tot += weights[s.fileId] + 1.0;
    }
    if( tot <= 0.0 )
    {
        return p;
    }
    for( const Symbol& s : ing.symbols )
    {
        p[s.id] = float( ( weights[s.fileId] + 1.0 ) / tot );
    }
    return p;
}

// --rank-by=churn-decay's teleport. `scope`: nullptr or inactive ⇒ the WHOLE history (no --since clause at
// all — the decay is the window, and that keeps the default a pure function of the tree at HEAD); an ACTIVE
// scope narrows the walk exactly as it does for --rank-by=churn.
inline std::vector<float> churnDecayTeleport( const std::string& root, const IngestResult& ing, const SinceScope* scope = nullptr,
                                              bool* outHasChurnEvidence = nullptr )
{
    PROFILE_SCOPE_DESCRIBE( "gitmine: churnDecayTeleport (rank-by=churn-decay)" );
    const std::string windowArgs = ( scope && scope->active ) ? sinceLogArgs( *scope, "" ) : std::string{};
    bool              anyHistory = false;
    const std::vector<double> weights = gitLogDecayedFileWeights( root, ing, windowArgs, 100, &anyHistory );   // same merge-bomb cap as churnTeleport
    if( outHasChurnEvidence )
    {
        *outHasChurnEvidence = anyHistory;
    }
    return churnPriorFromDecayed( ing, weights, anyHistory );
}

// Multi-root --rank-by=churn-decay: mine each root's history AGAINST ITS OWN files, accumulate ONE weight
// table, apply the smoothing once — the churnTeleportWorkspace rule, with the same per-repo-scale caveat
// (a commit in either repo decays on ITS OWN HEAD's clock, so the two histories are never mixed).
inline std::vector<float> churnDecayTeleportWorkspace( const std::vector<std::string>& rootDirs, const IngestResult& ing,
                                                       bool* outHasChurnEvidence = nullptr )
{
    PROFILE_SCOPE_DESCRIBE( "gitmine: churnDecayTeleportWorkspace (multi-root rank-by=churn-decay)" );
    std::vector<double> weights( ing.files.size(), 0.0 );
    bool                anyHistory = false;
    for( std::uint32_t r = 0; r < rootDirs.size(); ++r )
    {
        bool                      rootHistory = false;
        const std::vector<double> w           = gitLogDecayedFileWeights( rootDirs[r], ing, std::string{}, 100, &rootHistory, r );
        if( rootHistory )
        {
            anyHistory = true;
        }
        for( std::size_t f = 0; f < weights.size(); ++f )
        {
            weights[f] += w[f];
        }
    }
    if( outHasChurnEvidence )
    {
        *outHasChurnEvidence = anyHistory;
    }
    return churnPriorFromDecayed( ing, weights, anyHistory );
}

// The window STAMP for a churn-ranked map (§B2.2): the window that was mined, plus — when it mined NOTHING —
// the fact that makes the rest of the header interpretable. Spelled ONCE here so the single-root and
// multi-root arms (and any later consumer of the prior) cannot disclose it two ways, in the house form for a
// qualified stamp value: `baseline="git-HEAD (stale sidecar removed)"`, one attribute over.
// Without it, `rank_by="churn" window="18mo"` sits over ranks byte-identical to pagerank — and --help sells
// that stamp as the thing that stops churn "passing for the structural one" (cli.h:1070-1071), which it cannot
// do while both cases are spelled the same.
inline std::string churnWindowStamp( std::string_view minedWindow, bool hasChurnEvidence )
{
    std::string stamp{ minedWindow };   // brace-init: stamp( minedWindow ) parses as a function declarator (the vexing-parse lookalike hasEnclosingGitRepo warns about) and pollutes the symbol map
    if( !hasChurnEvidence )
    {
        stamp += " (no churn evidence)";
    }
    return stamp;
}

// resolve a path substring (e.g. "canyon/foo.cpp" or "foo.cpp") to one ingested file id, or UINT32_MAX.
inline std::uint32_t resolveFileSuffix( const IngestResult& ing, std::string_view sub )
{
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string& fp = ing.files[f];
        if( fp.size() >= sub.size() )
        {
            const std::size_t off = fp.size() - sub.size();
            if( fp.compare( off, sub.size(), sub ) == 0 && ( off == 0 || fp[off - 1] == '/' ) )
            {
                return f;
            }
        }
    }
    return UINT32_MAX;
}

// ── S5-C: recency-weighted author ownership ───────────────────────────────────────────────────────

// Per-author ownership entry for one file.
struct AuthorScore
{
    std::string email;     // normalized author email (lowercase)
    double      score;     // Σ exp(-λ·age) over that author's commits
    double      share;     // score / totalScore (fraction of weighted commits)
};

// Ownership summary for one file.
struct FileOwnership
{
    std::uint32_t            fileId;
    std::vector<AuthorScore> authors;   // sorted: score desc, email asc (deterministic)
    std::uint32_t            uniqueAuthors;
    bool                     busFactor;  // top author holds > 80% of weighted commits
};

// Mine author ownership for every file in `ing` (or a single file if `onlyFileId != UINT32_MAX`).
// ONE subprocess for the whole repo: git log --name-only --format=tformat:__C__%ae|%at, mirroring
// gitCommitFileSets' single-pass-stream pattern (see top of file) instead of one popen per file — that
// was the entire cost (5.3s → ~0.1s on a 150-file repo). Weight each commit by exp(-λ·age) where
// λ = ln(2) / halfLifeSeconds (default half-life = 6 months).
// SEMANTIC DELTA vs the old per-file `git log --follow`: --follow tracks a file across renames; a single
// whole-repo `git log --name-only` cannot cheaply do that (per-file --follow *was* the O(files) cost we're
// removing). So a renamed file's mined history now starts at the rename — pre-rename commits are dropped.
// Given the 6-month half-life, pre-rename history is already decayed to near-zero for any rename older
// than a year or so, so this is a minor accuracy trade for a ~50x speedup, not a correctness regression.
// MERGE COMMITS: the walk carries kMergeDiffArgs, so a file introduced by a merge ITSELF gets an ownership
// row attributed to the merge's author. It previously got NO ROW AT ALL — the whole-repo walk named no paths
// for a merge, so such a file was simply absent from --owners while every other tracked file was listed, with
// no disclosure to tell the absence from "this file has no history". Measured on this repo: 2 of 1028 paths.
// The single-file query form below is fixed by the same flag: `git log -- <path>` already SELECTED the merge
// (history simplification keeps it — the merge is not TREESAME to any parent for that path), it just printed
// no path line for it, so the resolve() below never matched and the pathspec pass mirrored the whole-repo one.
// Determinism: parsed strictly in the single stream's order; output rows sorted by (fileId asc); within
// a file, authors by (score desc, email asc). Degrades cleanly when git is unavailable (empty result).
inline std::vector<FileOwnership> gitFileAuthors(
    const std::string& root,
    const IngestResult& ing,
    std::uint32_t onlyFileId = UINT32_MAX,
    double halfLifeDays = 182.5,   // 6 months ≈ 182.5 days
    std::uint32_t onlyRoot = UINT32_MAX   // multi-root §5: mine this repo ONLY against its own files
)
{
    PROFILE_SCOPE_DESCRIBE( "gitmine: gitFileAuthors (single-pass git log --name-only popen)" );
    // λ = ln(2) / half_life_seconds
    const double halfLifeSecs = halfLifeDays * 86400.0;
    const double lambda       = 0.6931471805599453 / halfLifeSecs;   // ln(2) / T½

    const std::size_t fileCount  = ing.files.size();
    const bool        singleFile = ( onlyFileId != UINT32_MAX );

    // Per-file accumulator: email → list of raw commit timestamps that touched that file. Filled in
    // one pass over the whole-repo log stream, then reduced to decay scores below.
    // N=2 on the inner timestamp list. An int64 is 8 bytes, so <int64,1> is 16 B and <int64,2> is 24 B —
    // exactly what the std::vector header already cost, which makes N=2 the free-relative-to-baseline step
    // rather than a growth. Coverage 84.9%/77.2% across the two census corpora against 73.0%/59.9% at N=1;
    // marginal coverage per byte then falls 2.16 → 0.70 going 2→4, so 2 is the knee. Most (file, author)
    // pairs are one commit — 1 613/3 002 inner lists on the two corpora, nearly all of them singletons.
    HashMap<std::uint32_t, HashMap<std::string, rw::SmallVec<std::int64_t, 2>>> perFile;
    HashMap<std::uint32_t, std::int64_t>                                        newestTsByFile;
    if( !singleFile )
    {
        perFile.reserve( fileCount );
        newestTsByFile.reserve( fileCount );
    }

    // F6 companion: this used to be a SIXTH hand-rolled index, and a DIVERGENT one — it keyed on the
    // root-stripped `relPath` where the shared builder keyed on the full ingested path, so the fit measure the
    // shared refusal machinery used was on a different scale here. Worse, root-stripped is the WRONG anchor for
    // this stream: `git log --name-only` prints paths relative to the repo TOPLEVEL, not to `-C <root>`, so a
    // crawl root inside a larger repo was matching on a spelling git never emits. The shared builder derives
    // that offset instead of assuming it away.
    const GitPathIndex byGitPath = gitPathIndexOfFiles( ing, onlyRoot );
    const auto         resolve   = [ & ]( const std::string& gp ) -> std::uint32_t
    {
        const std::uint32_t f = resolveGitPath( byGitPath, gp );
        return ( singleFile && f != onlyFileId ) ? UINT32_MAX : f;   // single-file query: the pathspec narrows git, this narrows us
    };
    const std::string rootSlash = root + "/";

    // git log -c --name-only --format=tformat:__C__%ae|%at 2>/dev/null  (optionally scoped to one path with
    // -- <relpath>): one "__C__email|unix-ts" header per commit, then its changed files, one per line,
    // until a blank line / the next header. Mirrors gitCommitFileSets' exact invocation style.
    std::string cmd = "git -c core.quotepath=false -C " + shSingleQuote( root )
                     + " log " + kMergeDiffArgs + "--name-only --format=tformat:__C__%ae\\|%at";
    if( singleFile )
    {
        const std::string& fp = ing.files[ onlyFileId ];
        std::string        relPath = fp;
        if( fp.size() > rootSlash.size() && fp.compare( 0, rootSlash.size(), rootSlash ) == 0 )
        {
            relPath = fp.substr( rootSlash.size() );
        }
        cmd += " -- " + shSingleQuote( relPath );
    }
    cmd += " 2>/dev/null";

    std::FILE* pipe = popen( cmd.c_str(), "r" );
    if( !pipe )
    {
        return {};
    }

    std::string  curEmail;
    std::int64_t curTs = 0;
    bool         haveCommit = false;
    std::string  s;
    while( readByteSafeLine( pipe, s ) )   // F6: THE line reader, not a char[4096] a long path can be split across
    {
        while( !s.empty() && ( s.back() == '\n' || s.back() == '\r' ) )
        {
            s.pop_back();
        }
        if( s.compare( 0, 5, "__C__" ) == 0 )
        {
            const std::string_view rest( s.data() + 5, s.size() - 5 );
            const std::size_t      pipePos = rest.find( '|' );
            if( pipePos == std::string_view::npos || pipePos == 0 || pipePos + 1 >= rest.size() )
            {
                haveCommit = false;
                continue;
            }
            curEmail = rest.substr( 0, pipePos );
            for( char& c : curEmail )
            {
                c = char( std::tolower( static_cast<unsigned char>( c ) ) );
            }
            const std::string tsStr( rest.substr( pipePos + 1 ) );
            char* end = nullptr;
            curTs = std::strtoll( tsStr.c_str(), &end, 10 );
            haveCommit = ( end != tsStr.c_str() );
            continue;
        }
        if( s.empty() || !haveCommit )
        {
            continue; // blank separator line, or malformed header — skip its files
        }

        const std::uint32_t f = resolve( s );
        if( f == UINT32_MAX )
        {
            continue;
        }

        perFile[ f ][ curEmail ].push_back( curTs );
        std::int64_t& newest = newestTsByFile[ f ];
        if( curTs > newest )
        {
            newest = curTs;
        }
    }
    pclose( pipe );

    std::vector<FileOwnership> result;
    result.reserve( perFile.size() );
    for( auto& [ fid, authorTs ] : perFile )
    {
        if( authorTs.empty() )
        {
            continue;
        }
        const std::int64_t newestTs = newestTsByFile[ fid ];

        // Compute decay scores
        double totalScore = 0.0;
        std::vector<AuthorScore> authors;
        authors.reserve( authorTs.size() );
        for( const auto& [ em, timestamps ] : authorTs )
        {
            double score = 0.0;
            for( const std::int64_t ts : timestamps )
            {
                const double ageSecs = double( newestTs - ts );
                score += std::exp( -lambda * ageSecs );
            }
            totalScore += score;
            authors.push_back( { em, score, 0.0 } );
        }

        // Fill shares + detect bus factor
        const bool topOver80 = [ & ]() -> bool
        {
            if( totalScore <= 0.0 )
            {
                return false;
            }
            double best = 0.0;
            for( auto& a : authors )
            {
                a.share = a.score / totalScore;
                if( a.score > best )
                {
                    best = a.score;
                }
            }
            return ( best / totalScore ) > 0.80;
        }();

        // Sort: score descending, then email ascending for ties (deterministic)
        std::sort( authors.begin(), authors.end(), []( const AuthorScore& x, const AuthorScore& y )
                   { return x.score != y.score ? x.score > y.score : x.email < y.email; } );

        result.push_back( { fid, std::move( authors ), std::uint32_t( authorTs.size() ), topOver80 } );
    }

    // Sort result by fileId for deterministic output (HashMap iteration order above is not stable)
    std::sort( result.begin(), result.end(), []( const FileOwnership& a, const FileOwnership& b )
               { return a.fileId < b.fileId; } );

    return result;
}

// Precomputed-ownership lookup (A4-P?): find `fileId`'s entry in an ALREADY-MINED whole-repo ownership
// vector, or nullptr if that file has no mined history. gitFileAuthors(root, ing) already mines EVERY
// file's ownership in ONE whole-repo `git log --name-only` pass; a multi-probe caller (--pr-context over a
// 213-file diff) that instead called gitFileAuthors(root, ing, f) once PER file spawned one `git log` popen
// per file — the residual O(files) subprocess storm this kills (mirroring the co-change dedup: mine once,
// share across every probe). This is BYTE-IDENTICAL to the single-file query per file: the whole-repo pass
// resolves the same repo-relative paths through the same byGitPath/resolveGitPath, accumulates the same
// per-file per-author timestamps, and reduces them with the same 6-month-half-life decay — verified equal
// on a large private C++ corpus across every multi-author file (authors/bf/share all match). The result is sorted by
// fileId (see the tail of gitFileAuthors), so this binary-searches. Pure: no git, no I/O.
inline const FileOwnership* ownershipForFile( const std::vector<FileOwnership>& all, std::uint32_t fileId )
{
    const auto it = std::lower_bound( all.begin(), all.end(), fileId,
                                      []( const FileOwnership& o, std::uint32_t id ) { return o.fileId < id; } );
    return ( it != all.end() && it->fileId == fileId ) ? &*it : nullptr;
}

// ─── static #include coupling (shared by BOTH cochange paths) ─────────────────────────────────────

// A4-F22 / P9.1: "surprising" must mean "no static #include coupling *either way, transitively*", not
// just a direct 1-hop include. A one-hop-indirect include (ingest.cpp→ingest.h→model.h on this very
// repo) is a real static dependency and must NOT read as hidden coupling. Built ONCE from
// resolveIncludeAdj(ing); isStaticallyCoupled(a,b) answers "is there a chain of #includes from a to b,
// or from b to a" by lazily memoizing each queried file's own forward transitive-include closure
// (visited-set BFS — complete and cycle-safe, no depth cap needed since the visited set already bounds
// it). Two forward closures cover BOTH directions: "b reachable from a" is a hit in closure(a); "a
// reachable from b" is a hit in closure(b) — no separate reverse graph needed. THE ONE PREDICATE shared
// by the per-file partner scan below (cochangePartners) and --cochange's repo-wide pair scan in
// main.cpp, so "surprising" cannot mean two different things depending on which path answered it (P9.1:
// it did — the repo-wide path used a 1-hop-only check and both src↔src rows in its top-30 were false
// positives as a result: ingest.cpp↔model.h and main.cpp↔notes.h, both genuinely transitively coupled).
//
// §P9.1 RESIDUE (2026-07-28) — the BARE-NAME FALLBACK (namesBaseNameOf). The closure is only ever as
// complete as resolveIncludeAdj, which cannot resolve a cross-directory `-I` include: the path-precise
// resolver walks includer-relative and root-relative candidates only, and a `-I` needs the build system's
// flags, which we deliberately do not read. So one false positive survived — and a repo-wide sweep found
// it was the ONLY one: `bench/bench_convergence.cpp:26` is literally `#include "infra/svector.h"`, resolved
// through `-Isrc`, and the pair shipped as `surprising="1"` on a plain `#include`.
//
// The rule: if either file's raw #include list names the OTHER's BASENAME, call the pair statically
// coupled. This can only ever SUPPRESS surprising="1", never produce one, so it cannot create a false
// positive of the flag — its only possible cost is hiding a genuinely-hidden coupling between two files
// whose basenames collide with something the includer already names, and for a flag whose entire value is
// precision that is the right trade. Deliberately NOT wired into resolveIncludeAdj or the include graph:
// ranking depends on those staying path-precise. It is also the CHEAPEST of the three tests (one hash
// probe over a short list, no BFS), so it runs first.
class StaticIncludeCoupling
{
public:
    explicit StaticIncludeCoupling( const IngestResult& ing ) : files_( ing.files ), adj_( resolveIncludeAdj( ing ) )
    {
        for( const Include& inc : ing.includes )
        { // §P9.1 fallback index
            if( inc.fileId < ing.files.size() && !inc.target.empty() )
            {
                includedBaseNames_[ inc.fileId ].emplace_back( mention_detail::baseNameOf( inc.target ) );
            }
        }
    }

    bool isStaticallyCoupled( std::uint32_t a, std::uint32_t b ) const
    {
        if( namesBaseNameOf( a, b ) || namesBaseNameOf( b, a ) )
        {
            return true; // §P9.1 bare-name fallback (cheapest test)
        }
        const std::vector<char>& fa = forwardClosure( a );
        if( b < fa.size() && fa[b] )
        {
            return true;
        }
        const std::vector<char>& fb = forwardClosure( b );
        return a < fb.size() && fb[a];
    }

private:
    // §P9.1 residue — the cross-directory-`-I` fallback the class header explains. SUPPRESS-only.
    bool namesBaseNameOf( std::uint32_t includer, std::uint32_t other ) const
    {
        const auto it = includedBaseNames_.find( includer );
        if( it == includedBaseNames_.end() || other >= files_.size() )
        {
            return false;
        }
        const std::string_view otherBase = mention_detail::baseNameOf( files_[ other ] );
        for( const std::string& target : it->second )
        {
            if( target == otherBase )
            {
                return true;
            }
        }
        return false;
    }

    const std::vector<char>& forwardClosure( std::uint32_t src ) const
    {
        const auto it = memo_.find( src );
        if( it != memo_.end() )
        {
            return it->second;
        }
        std::vector<char> seen( adj_.size(), 0 );
        if( src < adj_.size() )
        {
            std::vector<std::uint32_t> stack{ src };
            seen[src] = 1;                                      // self (harmless: callers never query a==b)
            while( !stack.empty() )
            {
                const std::uint32_t v = stack.back(); stack.pop_back();
                for( std::uint32_t w : adj_[v] )
                {
                    if( w < seen.size() && !seen[w] )
                    {
                        seen[w] = 1;
                        stack.push_back( w );
                    }
                }
            }
        }
        return memo_.emplace( src, std::move( seen ) ).first->second;
    }

    const std::vector<std::string>&                    files_;               // §P9.1 fallback: the OTHER file's basename
    std::vector<std::vector<std::uint32_t>>           adj_;
    HashMap<std::uint32_t, std::vector<std::string>>  includedBaseNames_;    // §P9.1 fallback: fileId → its raw #include basenames
    mutable HashMap<std::uint32_t, std::vector<char>>  memo_;
};

// ─── recurrence across sub-windows (Clio, ICSE 2011) ──────────────────────────────────────────────
//
// THE DEFECT THIS CLOSES. `--cochange` mined ONE window (18 months by default) and reported any pair
// that cleared `together>=3` inside it. In that view a one-off refactor sprint — two files touched
// together four times in one week, never again — is INDISTINGUISHABLE from a structural defect that
// has bled for eighteen months. Both score together=4, both score deg=1.00, and the row says nothing
// that separates them.
//
// Wong/Cai/Kim/Dalton's Clio (docs/LINEAGE.md §2) does not have that problem, because it does not
// report a discrepancy the first time it appears: it mines frequent patterns over the LAST FIVE
// RELEASES and reports only the ones that RECUR. Releases are not a concept this tool has — it reads
// `git log`, not a tag taxonomy, and inferring releases from tags would be a per-project convention
// dressed up as a measurement. The equivalent that IS derivable from the history alone is to cut the
// mined window into equal-commit-count sub-windows and ask in how many of them the pair actually
// co-changed. That is `recur=`.
//
// EQUAL COUNT, NOT EQUAL TIME, and the choice is load-bearing. A calendar third of an 18-month window
// can contain 400 commits or 4 (holidays, a release freeze, a job change), so a time cut makes
// recur= a function of when the team took time off. An equal-commit-count cut asks the question that
// was meant: "did this pair keep coming back as the project moved", where "moved" is measured in
// commits. It is also the deterministic choice — the chunk boundaries are a pure function of the
// commit list the miner already holds, with no second clock read.
//
// THREE, and why the number is disclosed rather than tuned. Three is the smallest cut that can tell
// "all in one place" from "spread out" at the support floor of 3 — with two sub-windows a genuinely
// clustered pair still has an even chance of straddling the boundary. It is NOT swept, calibrated or
// claimed optimal, which is exactly why every emitter publishes `sub_windows=` next to `recur=`: a
// recurrence of 1 is uninterpretable until the reader knows the denominator, and the honesty rule
// here is that a number mined over a partition names its partition.
inline constexpr std::uint32_t kCoRecurSubWindows = 3;

// The number of sub-windows actually used: fewer commits than sub-windows means the extra ones would
// be empty, and an empty sub-window a pair could never appear in is a denominator that lies. Emitters
// publish THIS, not the constant.
inline std::uint32_t coEffectiveSubWindows( std::size_t commitCount ) noexcept
{
    return std::uint32_t( std::min<std::size_t>( kCoRecurSubWindows, commitCount ) );
}

// Sub-window index of commit `commitIndex` of `commitCount`, in the miner's own commit order. The
// multiply-then-divide form spreads the remainder instead of piling it onto the last chunk, so with
// 25 commits the cut is 9/8/8 rather than 8/8/9 — and it never indexes past `windows-1`, which is
// what the mask below relies on. Order is git-log order (newest first); recur= counts DISTINCT
// sub-windows, so which end is which cannot change the number and is not part of the contract.
inline std::uint32_t coSubWindowOf( std::size_t commitIndex, std::size_t commitCount, std::uint32_t windows ) noexcept
{
    if( commitCount == 0 || windows == 0 )
    {
        return 0;
    }
    return std::uint32_t( ( commitIndex * windows ) / commitCount );
}

// recur= from the accumulated sub-window bitmask. A pair over the support floor has at least one
// joint commit, so a zero mask is unreachable from a real pair — but VERIFY would be wrong here (a
// caller may legitimately ask about a pair with no joint commit), so the clamp is silent and the
// callers below only ever build masks from commits they actually saw.
inline std::uint32_t coRecurrenceOf( std::uint32_t subWindowMask ) noexcept
{
    return std::uint32_t( std::popcount( subWindowMask ) );
}

// ─── directional (asymmetric) confidence — Clio's conf = frq(x1 U x2)/frq(x1) ──────────────────────
//
// `deg=` has always been support over the QUIETER of the two files, which is Code-Maat-shaped and is
// exactly max(conf(a=>b), conf(b=>a)) — the right magnitude with the direction thrown away. A reader
// met `deg="1.00"` and could not tell whether it meant "a never changes without b" or the reverse,
// which is the difference between "fix a" and "fix b".
//
// conf(a=>b) = together / commits(a): of the commits that touched a, the fraction that also touched
// b. The DRIVER is the antecedent of the stronger rule — the file whose changes most reliably imply
// the other's, i.e. the one that cannot move alone. A tie is reported as a tie: `driver=` is omitted
// rather than broken by an arbitrary rule a reader would take for a finding.
inline double coConfidence( std::uint32_t together, std::uint32_t antecedentCommits ) noexcept
{
    return antecedentCommits ? double( together ) / double( antecedentCommits ) : 0.0;
}

// ─── Modularity Violation Groups (Mo/Cai/Kazman, IEEE TSE 2019) ───────────────────────────────────
//
// A pair list answers "which pairs are violating"; an MVG answers "which FILE do I fix", which is the
// question the reader arrived with. Mo defines it as the MINIMAL SET OF GROUPS covering all violating
// pairs (f_core, f_j) — so "X co-changes with {A,B,C}, none of which it depends on" is one actionable
// row where three pair rows leave the actionable part implicit.
//
// Minimal cover is set cover, and set cover is NP-hard, so what ships is the textbook greedy
// approximation: repeatedly take the file incident to the most still-uncovered violating pairs, emit
// it as a core with exactly those partners, mark them covered. Every violating pair therefore lands
// in exactly ONE group and the membership total reconciles with the violation count — the arithmetic
// the emitter's legend promises. `groups.size()` is an UPPER BOUND on the minimum, never the minimum,
// and the emitter says `cover="greedy"` for that reason: honesty rule #3 forbids spelling a number
// that cannot be a minimum the way a minimum is spelled.
//
// DETERMINISM. Greedy has ties and a tie broken by hash order is a byte-unstable document. Degrees
// are counted into a dense per-fileId vector and the winner is the LOWEST fileId among the maxima;
// fileIds are assigned in sorted crawl order, so that is the lexicographically smallest path. The
// input is sorted on (a, b) first, which is a total order because a pair's two fileIds are distinct.
// The whole cover is thus a pure function of the violation set.
struct CoViolation { std::uint32_t a, b, together, recur; double confA, confB; };
struct CoGroup     { std::uint32_t core; std::vector<std::size_t> members; };   // members index into the input vector

inline std::vector<CoGroup> cochangeViolationGroups( std::vector<CoViolation>& viol, std::size_t fileCount )
{
    std::sort( viol.begin(), viol.end(), []( const CoViolation& x, const CoViolation& y )
               { return x.a != y.a ? x.a < y.a : x.b < y.b; } );

    std::vector<CoGroup>       groups;
    std::vector<char>          covered( viol.size(), 0 );
    std::vector<std::uint32_t> degree( fileCount, 0 );
    std::size_t                remaining = viol.size();
    while( remaining > 0 )
    {
        std::fill( degree.begin(), degree.end(), 0u );
        for( std::size_t vi = 0; vi < viol.size(); ++vi )
        {
            if( !covered[vi] )
            {
                ++degree[ viol[vi].a ];
                ++degree[ viol[vi].b ];
            }
        }
        std::uint32_t core = UINT32_MAX, best = 0;
        for( std::uint32_t f = 0; f < degree.size(); ++f )
        {   // strict > keeps the LOWEST fileId (= smallest path) among equal maxima
            if( degree[f] > best )
            {
                best = degree[f];
                core = f;
            }
        }
        if( core == UINT32_MAX )
        {   // unreachable while `remaining` counts the same set the degrees are built from — but a silent
            // infinite loop is the failure mode if it ever is, so degrade loudly and stop covering.
            DEGRADED_PATH_ALERT( "cochangeViolationGroups: uncovered pairs remain but no file carries one — cover abandoned" );
            break;
        }
        CoGroup g{ core, {} };
        for( std::size_t vi = 0; vi < viol.size(); ++vi )
        {
            if( !covered[vi] && ( viol[vi].a == core || viol[vi].b == core ) )
            {
                covered[vi] = 1;
                g.members.push_back( vi );
                --remaining;
            }
        }
        groups.push_back( std::move( g ) );
    }
    return groups;
}

// ─── co-change partner ────────────────────────────────────────────────────────────────────────────

// §A9.3 — surprising= means "changes together, yet NO static dependency explains it". For a pair where at
// least one side CANNOT carry a static dependency in the first place — a .sh gate, a .md doc, a .pdf, a
// .pptx — that sentence is vacuously true: no include edge could ever exist, so its absence is not
// evidence of hidden coupling. ~22 of the first 30 repo-wide rows were such pairs (a PDF↔PPTX build
// artifact pair rendered as "hidden architectural debt"; every gate↔subject pair rendered as surprising).
//
// The predicate is §P9.4's, verbatim — lintrules::dependencyCapable( langOfPath( path ) ), the same one
// <health dep_files=> uses for its denominator — so "dependency-capable" cannot mean two things in one
// binary. A pair with a dep-incapable side KEEPS its row (co-change is a real, mined fact about it) and
// carries dep_capable="0" in place of surprising=, which is the honest reading: the question surprising=
// answers is not defined for this pair.
inline bool coPairDependencyCapable( const IngestResult& ing, std::uint32_t a, std::uint32_t b )
{
    return dependencyCapable( langOfPath( ing.files[a] ) )
        && dependencyCapable( langOfPath( ing.files[b] ) );
}

// one co-change partner of a file (changes together in git history). `surprising` can only ever be true
// when `depCapable` is — see coPairDependencyCapable above.
//   deg     = conf(probed => partner): of the PROBED file's commits, the fraction the partner shares.
//   degRev  = conf(partner => probed): the other direction, over the PARTNER's own commit count.
//             The pair form's symmetric deg= is max(deg, degRev) — see coConfidence above.
//   recur   = how many of `subWindows` sub-windows contain a joint commit (Clio recurrence).
struct CoPartner { std::uint32_t fileId; std::uint32_t together; double deg; double degRev; std::uint32_t recur; bool surprising; bool depCapable; };

// The row's verdict attribute, rendered ONCE for all four emitters (--cochange repo-wide `<pair>`, its
// per-file `<f>`, --pr-context's `<partner>`, and — via the JSON pair below — the MCP verb). Three states,
// two spellings: hidden coupling ⇒ surprising="1"; coupled and explained ⇒ nothing (the quiet default);
// the question undefined for this pair ⇒ dep_capable="0". Spelled here so a later edit cannot teach one
// emitter a vocabulary the others do not speak — the §P9.1 defect, one attribute over.
inline const char* coPairAttr( bool isDepCapable, bool isSurprising ) noexcept
{
    if( !isDepCapable )
    {
        return " dep_capable=\"0\"";
    }
    return isSurprising ? " surprising=\"1\"" : "";
}
inline const char* coPairAttr( const CoPartner& p ) noexcept { return coPairAttr( p.depCapable, p.surprising ); }

// Partners of `fileSubstr`: files that historically change in the same commit. deg = fraction of the
// file's commits the partner also appears in; surprising = no transitive static #include either way (A4-F22:
// a one-hop-indirect include like A.cpp→A.h→B.h counts as a dependency, so is NOT surprising). Shared by the
// --cochange=FILE CLI mode and the MCP `cochange` verb. `scope`: nullptr (default, and the MCP verb's
// call) reproduces the pre-flag "18 months ago" window byte-for-byte; a non-null active scope (CLI
// --since=REV|DATE) overrides it — see gitCommitFileSets.
// Precomputed-sets overload (A4-P10): identical result to the git-driven form below, but answers from an
// ALREADY-MINED `sets` (gitCommitFileSets(root, ing, "18 months ago", 30) — or a scoped variant) instead of
// spawning its own `git log` popen. A --situ / --pr-context call probes MANY files; mining once and sharing
// `sets` across every probe kills the O(probes) subprocess storm (the same fix gitFileAuthors got). Pure: no
// git, no I/O. Callers that probe one file (the CLI --cochange / MCP verb) use the git-driven wrapper below.
// `outSubWindows` (optional): the recurrence denominator this call actually used, for the emitter's
// `sub_windows=` disclosure. Nobody may publish recur= without it — see kCoRecurSubWindows above.
inline std::vector<CoPartner> cochangePartners( const IngestResult& ing, std::string_view fileSubstr, std::uint32_t& outCommits,
                                                const std::vector<std::vector<std::uint32_t>>& sets, std::uint32_t* outSubWindows = nullptr )
{
    outCommits = 0;
    if( outSubWindows )
    {
        *outSubWindows = coEffectiveSubWindows( sets.size() );
    }
    std::vector<CoPartner> res;
    const std::uint32_t fid = resolveFileSuffix( ing, fileSubstr );
    if( fid == UINT32_MAX )
    {
        return res;
    }
    if( sets.empty() )
    {
        return res;
    }

    // Clio recurrence: the SAME partition the repo-wide scan uses, from the shared helpers above, so
    // the two paths cannot report different recur= for one pair (§P9.1's lesson, one attribute over).
    const std::uint32_t subWindows = coEffectiveSubWindows( sets.size() );

    std::vector<std::uint32_t>            freq( ing.files.size(), 0 );
    HashMap<std::uint32_t, std::uint32_t> together;                          // other file id → shared commits
    HashMap<std::uint32_t, std::uint32_t> recurMask;                         // other file id → sub-windows containing a joint commit
    for( std::size_t commitIndex = 0; commitIndex < sets.size(); ++commitIndex )
    {
        const std::vector<std::uint32_t>& cs = sets[ commitIndex ];
        const bool has = std::binary_search( cs.begin(), cs.end(), fid );    // cs is sorted+unique
        for( std::uint32_t f : cs )
        {
            ++freq[f];
        }
        if( !has )
        {
            continue;
        }
        const std::uint32_t bit = std::uint32_t( 1u ) << coSubWindowOf( commitIndex, sets.size(), subWindows );
        for( std::uint32_t f : cs )
        {
            if( f != fid )
            {
                ++together[f];
                recurMask[f] |= bit;
            }
        }
    }
    outCommits = freq[fid];

    // A4-F22 / P9.1: "surprising" must mean "no static #include coupling *either way, transitively*" —
    // see StaticIncludeCoupling above, the ONE predicate shared with --cochange's repo-wide pair scan
    // in main.cpp (P9.1 was the two paths disagreeing).
    const StaticIncludeCoupling coupling( ing );
    constexpr std::uint32_t kSupport = 3;
    for( const auto& [other, n] : together )
    {
        if( n >= kSupport )
        {
            // §A9.3: surprising= is gated on BOTH sides being dependency-capable — see coPairDependencyCapable.
            const bool isDepCapable = coPairDependencyCapable( ing, fid, other );
            const auto maskIt       = recurMask.find( other );
            res.push_back( { other, n, coConfidence( n, freq[fid] ), coConfidence( n, freq[other] ),
                             coRecurrenceOf( maskIt == recurMask.end() ? 0u : maskIt->second ),
                             isDepCapable && !coupling.isStaticallyCoupled( fid, other ), isDepCapable } );
        }
    }
    std::sort( res.begin(), res.end(), [ & ]( const CoPartner& x, const CoPartner& y )
               { return x.deg != y.deg ? x.deg > y.deg : ing.files[x.fileId] < ing.files[y.fileId]; } );
    return res;
}

// git-driven form: mine the co-change file-sets for THIS one probe, then delegate to the precomputed overload.
// The single-probe callers (CLI --cochange, MCP `cochange`) keep this signature. Multi-probe callers
// (--situ / --pr-context) must hoist gitCommitFileSets("18 months ago", 30, scope) out of their loop and use
// the overload above instead — see A4-P10.
inline std::vector<CoPartner> cochangePartners( const std::string& root, const IngestResult& ing, std::string_view fileSubstr, std::uint32_t& outCommits, const SinceScope* scope = nullptr,
                                                std::uint32_t onlyRoot = UINT32_MAX,   // multi-root §5: mine ONLY within that root
                                                std::uint32_t* outSubWindows = nullptr )
{
    PROFILE_SCOPE_DESCRIBE( "gitmine: cochangePartners (--cochange)" );
    outCommits = 0;
    if( outSubWindows )
    {
        *outSubWindows = 0;   // unknown file / no history ⇒ no partition was made, and the emitter must say 0, not 3
    }
    if( resolveFileSuffix( ing, fileSubstr ) == UINT32_MAX )
    {
        return {}; // unknown file → no git call, as before
    }
    const auto sets = gitCommitFileSets( root, ing, "18 months ago", 30, scope, onlyRoot );
    return cochangePartners( ing, fileSubstr, outCommits, sets, outSubWindows );
}

// B3: cheap "could there be ANY git history above this root?" pre-check — a stat() walk up the directory
// tree looking for a `.git` entry (dir OR file: worktrees and submodules use a gitfile). Lets the co-change
// boost skip its popen entirely on non-git corpora (bare fixture copies, generated perf corpora), so those
// paths pay literally zero added cost. A hit does NOT guarantee usable history (a fresh or depth-1 clone
// has none) — the support>=3 threshold in applyCoChangeBoost is the real inertness gate; this is only the
// no-subprocess fast path. Pure filesystem reads; never spawns anything.
inline bool hasEnclosingGitRepo( const std::string& root )
{
    char resolved[ PATH_MAX ];
    if( !::realpath( root.c_str(), resolved ) )
    {
        return false; // unresolvable root → treat as no repo (degrade)
    }
    std::string dir{ resolved };   // brace-init: dir( resolved ) parses as a function declarator (vexing-parse lookalike) and would pollute the symbol map

    // walk up at most 64 levels (any real path is far shallower; the bound is a hostile-symlink guard)
    for( int levelIndex = 0; levelIndex < 64 && !dir.empty(); ++levelIndex )
    {
        struct stat st;
        if( ::stat( ( dir + "/.git" ).c_str(), &st ) == 0 )
        {
            return true;
        }
        if( dir == "/" )
        {
            break;
        }
        const std::size_t slash = dir.rfind( '/' );
        if( slash == std::string::npos )
        {
            break;
        }
        dir.resize( slash == 0 ? 1 : slash );   // parent dir; "/" is its own parent → loop exit above
    }
    return false;
}

// ── co-change prior boost on the --for lens rank (B3) ───────────────────────────────────────────────
//
// Multi-file localization is the weakest eval stratum, and the literature's fix is history priors: files
// that historically change WITH the files the ranker already believes in are likely part of the same
// change surface even when they share no words with the query. This is the bounded, deterministic wiring
// of that signal: mine the last kCoBoostCommitWindow commits (commit-count window — see
// gitRecentCommitFileSets for why not a date window), take the top kCoBoostSeedCount ranked symbols'
// files as SEEDS, and give a small score boost to the strongest co-change partner files' best symbols.
//
// The hard promises (each one gated in test/cochangeboostcheck.sh):
//   * seeds are UNCHANGEABLE — every boosted score is clamped strictly below the lowest seed score
//     (std::nextafterf), so ranks 1..seedCount are identical boost-on vs boost-off;
//   * inert without history — a depth-1 / no-git tree can never reach the >=3-shared-commits support
//     threshold, so lensRank is untouched and output is BYTE-IDENTICAL to boost-off;
//   * bounded — at most kCoBoostMaxPartnerFiles files × kCoBoostMaxSymbolsPerFile symbols are touched;
//   * deterministic — sets come in git-log order, every reduction is over fileId-indexed arrays, and
//     both selection sorts use total orders ((deg desc, path asc) / (score desc, id asc)).

// Fixed knobs — deliberately NOT flags (one documented behavior, one ablation switch to kill it whole).
inline constexpr std::uint32_t kCoBoostCommitWindow      = 500;    // last-N-commits mining window (matches the eval's --history-depth=500 deepening)
inline constexpr std::size_t   kCoBoostMaxFilesPerCommit = 30;     // same bulk-commit cap as the other co-change miners here
inline constexpr std::uint32_t kCoBoostSeedCount         = 3;      // seeds = the top-3 positively-scored symbols' files
inline constexpr std::uint32_t kCoBoostSupport           = 3;      // a partner must share >= 3 commits with a seed file (cochangePartners' kSupport)
inline constexpr std::size_t   kCoBoostMaxPartnerFiles   = 8;      // strongest partners only, by (deg desc, path asc)
inline constexpr std::size_t   kCoBoostMaxSymbolsPerFile = 3;      // per partner file: its top-3 symbols by (lens score desc, id asc)
inline constexpr float         kCoBoostFrac              = 0.25f;  // boost = frac · deg · seedFloor — scale-free (relative to the rank's own scores)

// what the boost did, for the --for header note (all zero ⇒ nothing was touched)
struct CoBoostInfo
{
    std::uint32_t partnerFileCount   = 0;   // partner files that passed support (before the kCoBoostMaxPartnerFiles cap)
    std::uint32_t boostedFileCount   = 0;   // partner files in which at least one symbol's score actually rose
    std::uint32_t boostedSymbolCount = 0;   // symbols whose score actually rose
};

// Apply the co-change prior to `lensRank` in place. `sets` = per-commit changed-file sets from
// gitRecentCommitFileSets (or empty ⇒ no-op). Returns true iff at least one score changed. Pure function
// of (ing, sets, lensRank): no git, no I/O — callers own the mining (CLI --for / MCP `for` verb).
inline bool applyCoChangeBoost( const IngestResult& ing, const std::vector<std::vector<std::uint32_t>>& sets, std::vector<float>& lensRank, CoBoostInfo* outInfo = nullptr )
{
    VERIFY( lensRank.size() == ing.symbols.size() );
    if( sets.empty() || lensRank.empty() || lensRank.size() != ing.symbols.size() )
    {
        return false;
    }

    // seeds: the top kCoBoostSeedCount symbols under the serializer's own total order (score desc, id asc),
    // positive scores only — a query that matched nothing has no seeds and therefore no boost.
    NodeId seedIds[ kCoBoostSeedCount ];
    std::uint32_t seedSymbolCount = 0;
    {
        for( NodeId id = 0; id < NodeId( lensRank.size() ); ++id )
        {
            if( !( lensRank[id] > 0.0f ) )
            {
                continue;
            }
            // insertion sort into the tiny fixed seed array (score desc, id asc)
            std::uint32_t at = seedSymbolCount < kCoBoostSeedCount ? seedSymbolCount : kCoBoostSeedCount;
            while( at > 0 && ( lensRank[id] > lensRank[seedIds[at - 1]] || ( lensRank[id] == lensRank[seedIds[at - 1]] && id < seedIds[at - 1] ) ) )
            {
                --at;
            }
            if( at >= kCoBoostSeedCount )
            {
                continue;
            }
            for( std::uint32_t k = ( seedSymbolCount < kCoBoostSeedCount ? seedSymbolCount : kCoBoostSeedCount - 1 ); k > at; --k )
            {
                seedIds[k] = seedIds[k - 1];
            }
            seedIds[at] = id;
            if( seedSymbolCount < kCoBoostSeedCount )
            {
                ++seedSymbolCount;
            }
        }
    }
    if( seedSymbolCount == 0 )
    {
        return false;
    }
    const float seedFloor = lensRank[ seedIds[ seedSymbolCount - 1 ] ];   // lowest seed score — the unbreakable ceiling
    VERIFY( seedFloor > 0.0f );

    // seed FILES (deduped, seed-rank order; <= kCoBoostSeedCount of them)
    std::uint32_t seedFiles[ kCoBoostSeedCount ];
    std::uint32_t seedFileCount = 0;
    for( std::uint32_t s = 0; s < seedSymbolCount; ++s )
    {
        const std::uint32_t f = ing.symbols[ seedIds[s] ].fileId;
        bool isKnown = false;
        for( std::uint32_t k = 0; k < seedFileCount; ++k )
        {
            if( seedFiles[k] == f )
            {
                isKnown = true;
                break;
            }
        }
        if( !isKnown )
        {
            seedFiles[seedFileCount++] = f;
        }
    }

    // one pass over the commit sets: per-file commit frequency + per-seed-file shared-commit counts
    const std::size_t fileCount = ing.files.size();
    std::vector<std::uint32_t> freq( fileCount, 0u );
    std::vector<std::uint32_t> together[ kCoBoostSeedCount ];
    for( std::uint32_t k = 0; k < seedFileCount; ++k )
    {
        together[k].assign( fileCount, 0u );
    }
    for( const std::vector<std::uint32_t>& cs : sets )
    {
        for( const std::uint32_t f : cs )
        {
            if( f < fileCount )
            {
                ++freq[f];
            }
        }
        for( std::uint32_t k = 0; k < seedFileCount; ++k )
        {
            if( !std::binary_search( cs.begin(), cs.end(), seedFiles[k] ) )
            {
                continue; // cs is sorted+unique (gitLogFileSets flush)
            }
            for( const std::uint32_t f : cs )
            {
                if( f != seedFiles[k] && f < fileCount )
                {
                    ++together[k][f];
                }
            }
        }
    }

    // partner degree per file: max over seed files of together/freq(seed), gated on the support threshold.
    // Seed files themselves are never partners (their symbols must stay exactly where the ranker put them).
    struct Partner { std::uint32_t fileId; double deg; };
    std::vector<Partner> partners;
    for( std::uint32_t f = 0; f < fileCount; ++f )
    {
        bool isSeedFile = false;
        for( std::uint32_t k = 0; k < seedFileCount; ++k )
        {
            if( seedFiles[k] == f )
            {
                isSeedFile = true;
                break;
            }
        }
        if( isSeedFile )
        {
            continue;
        }
        double deg = 0.0;
        for( std::uint32_t k = 0; k < seedFileCount; ++k )
        {
            if( together[k][f] >= kCoBoostSupport && freq[ seedFiles[k] ] > 0 )
            {
                deg = std::max( deg, double( together[k][f] ) / double( freq[ seedFiles[k] ] ) );
            }
        }
        if( deg > 0.0 )
        {
            partners.push_back( { f, deg } );
        }
    }
    if( partners.empty() )
    {
        return false;
    }
    if( outInfo )
    {
        outInfo->partnerFileCount = std::uint32_t( partners.size() );
    }

    // strongest partners only: (deg desc, path asc) is a total order (paths are unique) → deterministic cap
    std::sort( partners.begin(), partners.end(), [ &ing ]( const Partner& x, const Partner& y )
               { return x.deg != y.deg ? x.deg > y.deg : ing.files[x.fileId] < ing.files[y.fileId]; } );
    if( partners.size() > kCoBoostMaxPartnerFiles )
    {
        partners.resize( kCoBoostMaxPartnerFiles );
    }

    // collect each kept partner file's symbols (id-asc by construction of the single pass)
    HashMap<std::uint32_t, std::uint32_t> partnerIndexByFile;
    partnerIndexByFile.reserve( partners.size() );
    for( std::uint32_t p = 0; p < partners.size(); ++p )
    {
        partnerIndexByFile[partners[p].fileId] = p;
    }
    std::vector<std::vector<NodeId>> partnerSymbols( partners.size() );
    for( const Symbol& sym : ing.symbols )
    {
        const auto it = partnerIndexByFile.find( sym.fileId );
        if( it != partnerIndexByFile.end() )
        {
            partnerSymbols[it->second].push_back( sym.id );
        }
    }

    // boost: each partner file's top kCoBoostMaxSymbolsPerFile symbols (score desc, id asc) gain
    // frac·deg·seedFloor, clamped STRICTLY below the lowest seed score — so a partner symbol can enter the
    // lower bundle (even from score 0, the multi-file miss case) but can never displace a seed, and a
    // symbol already at/above the seed floor is left untouched (the boost never lowers a score).
    const float clampCeil = std::nextafterf( seedFloor, 0.0f );
    std::uint32_t boostedSymbolCount = 0, boostedFileCount = 0;
    for( std::uint32_t p = 0; p < partners.size(); ++p )
    {
        std::vector<NodeId>& ids = partnerSymbols[p];
        if( ids.empty() )
        {
            continue;
        }
        std::sort( ids.begin(), ids.end(), [ &lensRank ]( NodeId a, NodeId b )
                   { return lensRank[a] != lensRank[b] ? lensRank[a] > lensRank[b] : a < b; } );
        const float boostAdd = kCoBoostFrac * float( partners[p].deg ) * seedFloor;
        bool fileRose = false;
        for( std::size_t i = 0; i < ids.size() && i < kCoBoostMaxSymbolsPerFile; ++i )
        {
            const NodeId id = ids[i];
            float boosted = lensRank[id] + boostAdd;
            if( boosted > clampCeil )
            {
                boosted = clampCeil;
            }
            if( boosted > lensRank[id] )
            {
                lensRank[id] = boosted;
                ++boostedSymbolCount;
                fileRose = true;
            }
        }
        if( fileRose )
        {
            ++boostedFileCount;
        }
    }
    if( outInfo )
    {
        outInfo->boostedSymbolCount = boostedSymbolCount;
        outInfo->boostedFileCount   = boostedFileCount;
    }
    return boostedSymbolCount > 0;
}


// Promoted from main.cpp (2026-08-29 main.cpp split): the per-file churn miners are consumed by four verb
// families (--hotspots/--ensemble, --quality-panel, --cochange's change views, --plan-lanes, --html) — the
// cross-family class, so they live here with the git mining they drive rather than in any one family file.
// Per-file commit count over a recent window (`git log -c --since=... --name-only`; the `-c` is
// gitmine.h::kMergeDiffArgs — a merge commit's own content is mined, and merged-branch work is not
// double-counted. Without it this walk was silent about every merge, and a file whose only history is a
// merge commit read churn=0 with nothing disclosing it). Churn is the
// orthogonal-to-complexity axis: hotspot = complexity × churn (CodeScene's key insight — complex code
// that never changes costs nothing; complex code that changes constantly is where bugs live).
// `scope`: nullptr (default) reproduces the pre-flag `--since=<since>` window byte-for-byte; a non-null
// active scope (CLI --since=REV|DATE, see gitmine.h resolveSinceScope) overrides it with the resolved
// window — REV form as a deterministic `REV..` range, date form as `--since=DATE` (wall-clock-relative).
inline bool gitChurnCounts( const std::string& root, const rw::IngestResult& ing, std::vector<std::uint32_t>& out, const char* since, const rw::SinceScope* scope = nullptr,
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
// THE per-file churn mining every churn-consuming verb shares: one window, one multi-root merge rule, one
// definition of "git could not be mined at all" (false ⇒ every caller must report UNAVAILABLE rather than
// treat an all-zero vector as "nothing changed"). Extracted from the --hotspots block when --ensemble became
// its second caller — a second copy of a 20-line per-root merge loop is exactly the clone --quality-delta
// flags, and it is also how the two verbs' windows would silently diverge one round from now.
// `since`/`rootScope`: the single-root path uses the caller's ALREADY-RESOLVED scope (so --hotspots does not
// resolve it twice); the multi-root path resolves per root, because a revision is only meaningful inside the
// repository that contains it. An empty `since` means "the default window", exactly as before.
inline bool mineChurnPerFile( const rw::IngestResult& ing, const std::string& root, bool multiRoot,
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
}   // namespace rw
