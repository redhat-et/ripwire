#pragma once

// gitstamp.h — r26-stamp (Task A): the `at="<sha>[+dirty]"` anchor stamped on every repo-reading verb's root
// element. Motivation: a prior session watched the dogfood repo's HEAD move THREE times mid-session, and
// --abi's own `head=` attribute was the ONLY reason its numbers stayed comparable across those moves. Every
// other verb (--doc-drift, --pr-context, --edit-check, --hotspots, --quality-delta, --doctor, --test-gate,
// --whereis, ...) emits numbers with NO such anchor — a number quoted from one of them into a handoff is an
// unanchored claim, not a checkable fact, until it carries this stamp.
//
// WIDTH matches --abi's own precedent EXACTLY: abicheck.h's root `<abi ...>` element prints `head="%.9s"`,
// a 9-hex-char truncation of the full 40-char sha (crossref.h's `<stray-content>`/`<landing-plan>` roots
// independently converged on the same 9-char width). This module reuses that width rather than inventing a
// second one (notes.h's `shortSha` truncates to 7 for a DIFFERENT, older purpose — an inline note stamp —
// and is left alone; see this header's callers for the "keep both / converge" decision made at each site).
//
// DIRTY matches mergescout.h's own existing precedent (its `dirty` local, computed from a bare
// `git status --porcelain` with no `--uno`): a non-empty porcelain listing marks the tree dirty, and
// porcelain's default already reports UNTRACKED files alongside modified-tracked ones — so "+dirty" here
// means "tracked changes OR untracked files", not "tracked changes only". This converges onto the one dirty
// check already in the tree instead of inventing a second, narrower definition.
//
// NOT A GIT REPO (or no resolvable HEAD): `stampAt` returns "" and the caller OMITS the `at=` attribute
// entirely — never `at="none"`. This matches the codebase's existing convention for an inapplicable
// attribute (serialize.h's `precAttr`/`rootsAttr`/`changedAttr`, abicheck.h's `ref_size` omission comment):
// omit rather than print a value that reads as data.
//
// COST: two git subprocesses per call (`rev-parse` + `status --porcelain`). C1-STAMP: on a one-shot --for the status runs
// early on a worker (DirtyPrefetch above) and the rev-parse / is-shallow answers come from the STAMP record
// (gitstampcache.h) while the files they depend on are unchanged. Every call site is an EXPLICIT
// verb invocation whose own computation already shells out to git for a diff/history/blame/staleness answer
// (or is cheap enough — a doctor/quality-delta health check — that two more subprocess calls are noise next
// to what it already pays). The one path this must NEVER touch is the bare default map (serialize.h's `<r>`
// root with no verb flag): that path reads no git today, costs ~0.02-0.10s warm, and must stay that way —
// `stampAt`/`atAttr` are simply never called from it.

#include "quality.h"   // gitHeadSha / gitOneLine — the SAME git plumbing --abi's own head= already uses

#include <climits>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>
#include <utility>

namespace rw { namespace gitstamp
{

// ── THE DIRTY PROBE, started early (C1-STAMP) ────────────────────────────────────────────────────────────────────────
// `git status --porcelain` is 95-99% of a served --for's git time (A1 warm profile 2026-11-25: 75.6 / 102.8 / 724.9 ms on
// envoy / vscode / llvm-project) and it ran serially on the main thread inside stampAt, after the snapshot load. It reads
// nothing the run produces, so main.cpp starts it on a worker beside the load (DirtyPrefetch, one per one-shot --for) and
// stampAt joins it where the bit is consumed. The bit stays LIVE: the probe is the same command, run once per process for
// that process's own answer — only when it starts moves. A prefetch for another root, a second stampAt in one process, a
// probe that could not start and a worker that failed all take the inline probe below, which is exactly today's.
//
// What must hold for the early start to change nothing: no write of this run may land in the work tree before stampAt,
// or the porcelain would depend on which of the two came first. main.cpp's caller only starts it when every cache this
// run writes (the parse blob, the snapshot, the history record, a --cache file) sits OUTSIDE the repository's top level.
inline std::string dirtyPorcelain( const std::string& root )
{
    return quality::gitOneLine( root, "status --porcelain --ignore-submodules=dirty 2>/dev/null" );
}

namespace stampdetail
{
struct DirtySlot
{
    std::mutex  lock;
    std::string root;
    std::thread worker;          // joinable: a probe is pending for `root`
    std::string porcelain;       // written by the worker, read after its join
    bool        isAnswered = false;
};

inline DirtySlot& dirtySlot()
{
    static DirtySlot slot;
    return slot;
}

// The pending worker for `root`, handed to the caller (it joins); an empty thread when there is none for that root.
inline std::thread takeWorker( const std::string* root )
{
    DirtySlot&                        slot = dirtySlot();
    const std::lock_guard<std::mutex> guard( slot.lock );
    if( !slot.worker.joinable() || ( root != nullptr && *root != slot.root ) )
    {
        return {};
    }
    return std::move( slot.worker );
}
}   // namespace stampdetail

// The porcelain for `root`: the early probe's when one is pending for exactly this root, else a fresh inline probe.
inline std::string dirtyPorcelainJoined( const std::string& root )
{
    std::thread worker = stampdetail::takeWorker( &root );
    if( !worker.joinable() )
    {
        return dirtyPorcelain( root );
    }
    worker.join();
    stampdetail::DirtySlot& slot = stampdetail::dirtySlot();
    if( !slot.isAnswered )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "the early status probe failed, so the same probe runs inline: same command, same bytes" );
        return dirtyPorcelain( root );
    }
    return std::move( slot.porcelain );
}

// May the status probe start early? Only when every cache this run can write — the per-user cache directory (parse blob,
// snapshot, history record, STAMP record) and an explicit --cache file — resolves OUTSIDE the work tree, so nothing the run
// writes can be in the porcelain whichever finishes first. Anything that does not resolve says no: stampAt then probes
// inline, as before.
inline bool writesStayOutsideWorkTree( const std::string& root, std::string_view cacheFile )
{
    const std::string top = rw::enclosingGitWorkTree( root );
    if( top.empty() )
    {
        return false;
    }
    const auto isOutside = [ &top ]( const std::string& dir )
    {
        char resolved[ PATH_MAX ];
        if( os::realpath( dir.c_str(), resolved ) == nullptr )
        {
            return false;
        }
        const std::string_view real( resolved );
        return top != "/" && real != top && !( real.starts_with( top ) && real.size() > top.size() && real[ top.size() ] == '/' );
    };
    if( !isOutside( quality::cacheDirLadder() ) )
    {
        return false;
    }
    if( cacheFile.empty() )
    {
        return true;
    }
    const std::size_t slash = cacheFile.rfind( '/' );
    return isOutside( slash == std::string_view::npos ? std::string( "." ) : slash == 0 ? std::string( "/" ) : std::string( cacheFile.substr( 0, slash ) ) );
}

// RAII owner of the early probe: starts it (when `isWanted`), and joins it if nothing consumed it, so no worker outlives
// the run that started it.
class DirtyPrefetch
{
public:
    DirtyPrefetch( const std::string& root, bool isWanted )
    {
        if( !isWanted )
        {
            return;
        }
        stampdetail::DirtySlot&           slot = stampdetail::dirtySlot();
        const std::lock_guard<std::mutex> guard( slot.lock );
        if( slot.worker.joinable() )
        {
            return;   // one probe per process
        }
        slot.root       = root;
        slot.isAnswered = false;
        try
        {
            slot.worker = std::thread( [ &slot, probeRoot = root ]()
            {
                try
                {
                    slot.porcelain  = dirtyPorcelain( probeRoot );
                    slot.isAnswered = true;
                }
                catch( ... )   // a throw crossing this thread boundary would be std::terminate
                {
                    slot.isAnswered = false;
                }
            } );
        }
        catch( ... )   // no thread: stampAt probes inline, exactly as before
        {
            DISCLOSE( Diagnostics::answerUnchanged, "the early status probe could not start a thread, so stampAt probes inline: same bytes" );
        }
    }
    DirtyPrefetch( const DirtyPrefetch& )            = delete;
    DirtyPrefetch& operator=( const DirtyPrefetch& ) = delete;
    ~DirtyPrefetch()
    {
        std::thread worker = stampdetail::takeWorker( nullptr );
        if( worker.joinable() )
        {
            worker.join();
        }
    }
};

// The stamp value itself: "<9-hex-char sha>[+dirty]", or "" when `root` is not a git repo with a resolvable
// HEAD (the caller's job is to omit the attribute on empty, never to print a placeholder).
// 2026-09-06 stranger audit: a `--depth=1` clone (actions/checkout's default, and how many people clone a
// repo they only want to read) has ONE commit of history. Every churn= was 1, --hotspots ranked on
// complexity alone under a "12mo@HEAD" window label, --doctor said history="1", and the --html page said
// CHURN_OK = 1 — nothing anywhere said the history was truncated, so a reader took a shallow clone's
// churn for the repository's churn. The stamp is the one anchor every repo-reading verb already carries,
// so the disclosure rides it: at="<sha>[+dirty][+shallow]". One extra `git rev-parse` per stamped verb.
inline bool isShallow( const std::string& root )
{
    return quality::gitIsShallow( root );   // the ONE probe (quality.h, shallow-history honesty)
}

// The history verbs' root attribute (0.6.6): ` shallow="1"` when the clone is depth-limited, else "" — the
// SAME name and reading --doctor's git row already carries. Rides the root of every verb whose numbers are
// history-derived (owners, hotspots, cochange), so the qualification sits on the answer itself rather than
// only in at='s +shallow suffix. Absent on a full clone: those answers stay byte-identical.
// Both take the probe's answer rather than the root, so a verb that prints the attribute AND its legend pays
// for ONE `git rev-parse` (call isShallow once, pass it to both).
inline const char* shallowAttr( bool shallow )
{
    return shallow ? " shallow=\"1\"" : "";
}

// The full-legend clause that defines it, as its OWN comment (the graph_unindexed= / notes_degraded= precedent:
// compactlegend.h lists the `<!-- shallow=` opener as prose and its completeness table carries the compact
// reading). Emitted exactly when the attribute is — defined where it is met. No literal double dash: it rides
// inside an XML comment (G4), so the git flags are spelled by name.
inline constexpr const char* kShallowLegendComment =
    "<!-- shallow=\"1\" on the root: a depth-limited (shallow) clone. Every history-derived number here (churn, ownership bf= "
    "and share=, co-change) counts only the commits fetched, not the repository's history; git fetch with deepen=N or "
    "unshallow restores it -->";

inline const char* shallowLegend( bool shallow )
{
    return shallow ? kShallowLegendComment : "";
}

// The history verbs' empty-history refusal (--hotspots, --cochange, --owners and their MCP twins). It said "git
// unavailable / no history (need a git repo)" whenever mining came back empty, which on a shallow clone is false
// twice: git is there and so is a repo — only the fetched history is too short, or its one squashed commit is
// skipped as bulk. A shallow clone with history now hears exactly that; every other case keeps its bytes.
// "" means "not that case": the caller then prints its own pre-existing sentence, byte for byte.
inline std::string shallowHistoryCause( const std::string& root )
{
    if( quality::gitRepoHasHistory( root ) && isShallow( root ) )
    {
        return "shallow clone: the fetched history holds no commit this verb can mine (a depth-limited clone keeps only its "
               "newest commits, and one touching many files is skipped as bulk); "
             + std::string( quality::kShallowDeepenHint );
    }
    return {};
}

// The unknown-ref refusal's shallow hint (--pr-context base ref, --merge-scout refs). "unknown ref 'HEAD~1'" is
// true on a depth-1 clone, and says nothing of the likeliest cause; this suffix names it. "" on a full clone
// (byte-identical refusal), so a real typo there reads exactly as before.
inline std::string shallowRefHint( const std::string& root )
{
    if( !isShallow( root ) )
    {
        return {};
    }
    return " — this is a shallow clone, so the ref may lie beyond the fetched history; " + std::string( quality::kShallowDeepenHint );
}

inline std::string stampAt( const std::string& root )
{
    // NO SUBPROCESS ON A NON-GIT ROOT (M10 follow-up, lane L9, capture-audit-2026-09-04). The COST note above
    // reasons about call sites that already shell out to git — but M10 spliced this stamp onto --for, whose
    // retrieval path is contractually git-free on a git-less corpus (test/nongitqmetricscheck.sh: "rich
    // retrieval on a non-git root must not spawn git merely to degrade"), and stampAt then paid TWO popens to
    // learn there was no repo. hasEnclosingGitRepo is the same filesystem probe (stat for .git, walking up)
    // that quality::gitRawCommitStreamCached already gates its own walk on: it costs no subprocess, changes
    // no answer — on a non-git root the result was always "" — and makes the property hold for EVERY stamped
    // verb rather than for whichever one a gate happened to be watching.
    if( !rw::hasEnclosingGitRepo( root ) )
    {
        return {};
    }
    const std::string sha = quality::gitHeadSha( root );
    if( sha.empty() )
    {
        return {}; // not a git repo / no HEAD
    }
    const bool dirty = !dirtyPorcelainJoined( root ).empty();   // C1-STAMP: the early probe's answer when one is pending (above)
    return sha.substr( 0, 9 ) + ( dirty ? "+dirty" : "" ) + ( isShallow( root ) ? "+shallow" : "" );
}

// Formats a ready-to-splice ` at="VALUE"` (leading space included) — or "" when `root` isn't a git repo, so
// a caller can simply concatenate the result into its printf/snprintf attribute list and the attribute is
// OMITTED entirely on a non-repo target. The value is always plain hex + the literal "+dirty" (never user
// content), so it is deliberately NOT run through escapeXml.
inline std::string atAttrOf( const std::string& stamp )
{
    return stamp.empty() ? std::string() : ( " at=\"" + stamp + "\"" );
}
inline std::string atAttr( const std::string& root )
{
    return atAttrOf( stampAt( root ) );
}

}}   // namespace rw::gitstamp
