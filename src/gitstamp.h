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
// COST: two git subprocesses per call (`rev-parse` + `status --porcelain`). Every call site is an EXPLICIT
// verb invocation whose own computation already shells out to git for a diff/history/blame/staleness answer
// (or is cheap enough — a doctor/quality-delta health check — that two more subprocess calls are noise next
// to what it already pays). The one path this must NEVER touch is the bare default map (serialize.h's `<r>`
// root with no verb flag): that path reads no git today, costs ~0.02-0.10s warm, and must stay that way —
// `stampAt`/`atAttr` are simply never called from it.

#include "quality.h"   // gitHeadSha / gitOneLine — the SAME git plumbing --abi's own head= already uses

#include <future>   // the stamp prefetch's shared result
#include <memory>   // std::make_shared — the promise the detached prefetch worker fulfils
#include <mutex>    // guards the one prefetch slot
#include <string>
#include <thread>   // the detached prefetch worker

namespace rw { namespace gitstamp
{

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

namespace detail
{
// HEAD's sha and the shallow probe in ONE git child: `rev-parse --is-shallow-repository --verify --quiet HEAD` prints the
// probe's true/false line, then the sha. Accepted only in exactly that shape (exit 0, two lines, the first true or false, a
// sha second); any other answer (unborn HEAD, a failing or odd git, an abandoned read) returns false and the caller asks the
// two questions separately, as it always did, so no shape this does not prove can change a stamp.
inline bool foldedHeadAndShallow( const std::string& root, std::string& sha, bool& shallow )
{
    const GitCommandLines probe = gitCommandLines( gitCmd( " -c core.quotepath=false -C " ) + shSingleQuote( root )
                                                   + " rev-parse --is-shallow-repository --verify --quiet HEAD 2>/dev/null" );
    if( !probe.isStarted || probe.abandoned || probe.status != 0 || probe.lines.size() != 2 || probe.lines[1].empty()
        || ( probe.lines[0] != "true" && probe.lines[0] != "false" ) )
    {
        return false;
    }
    sha     = probe.lines[1];
    shallow = probe.lines[0] == "true";
    return true;
}

// The stamp, computed now: what stampAt returned before the prefetch existed, with HEAD and the shallow probe folded.
inline std::string computeStampAt( const std::string& root )
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
    std::string sha;
    bool        shallow = false;
    if( !foldedHeadAndShallow( root, sha, shallow ) )
    {
        sha = quality::gitHeadSha( root );
        if( sha.empty() )
        {
            return {}; // not a git repo / no HEAD
        }
        shallow = isShallow( root );
    }
    const bool dirty = !quality::gitOneLine( root, "status --porcelain --ignore-submodules=dirty 2>/dev/null" ).empty();
    return sha.substr( 0, 9 ) + ( dirty ? "+dirty" : "" ) + ( shallow ? "+shallow" : "" );
}

// THE ONE PREFETCHED STAMP of a CLI run. --for reads its stamp after the graph build, and its git children (the
// `status --porcelain` above all) then ran serially on the main thread: 13 % of cockroach's --for wall samples. main()
// starts it right after the ingest (so a cache file the ingest wrote inside the tree is seen exactly as before), and the
// children run beside the graph build. Heap-owned and never freed, and the worker is detached: a run that stops before
// reading it (a refusal, a memory-guard stop) never waits on a git child at exit. The MCP server never starts one, so every
// MCP call still stamps the tree as it is at that call.
struct StampPrefetch
{
    std::mutex                      lock;
    std::string                     root;    // the exact root string the prefetch was started for; "" = none
    std::shared_future<std::string> value;
};

inline StampPrefetch& stampPrefetch()
{
    static StampPrefetch* const slot = new StampPrefetch();   // leaked on purpose: see above
    return *slot;
}
}   // namespace detail

// Start computing stampAt( root ) on a worker. One per process: a second call (any root) is a no-op. If no thread can
// start, nothing is recorded and stampAt computes inline, as before.
inline void startStampPrefetch( const std::string& root )
{
    detail::StampPrefetch&            slot = detail::stampPrefetch();
    const std::lock_guard<std::mutex> guard{ slot.lock };
    if( slot.value.valid() || root.empty() )
    {
        return;
    }
    auto                            promise = std::make_shared<std::promise<std::string>>();
    std::shared_future<std::string> value   = promise->get_future().share();
    try
    {
        std::thread( [ promise, root ]()
                     {
                         try
                         {
                             promise->set_value( detail::computeStampAt( root ) );
                         }
                         catch( ... )   // a throw crossing this thread is std::terminate: hand it to the reader instead
                         {
                             promise->set_exception( std::current_exception() );
                         }
                     } ).detach();
    }
    catch( ... )   // std::system_error: no thread — stampAt computes inline
    {
        return;
    }
    slot.root  = root;
    slot.value = std::move( value );
}

inline std::string stampAt( const std::string& root )
{
    std::shared_future<std::string> prefetched;
    {
        detail::StampPrefetch&            slot = detail::stampPrefetch();
        const std::lock_guard<std::mutex> guard{ slot.lock };
        if( slot.value.valid() && slot.root == root )
        {
            prefetched = slot.value;
        }
    }
    if( prefetched.valid() )
    {
        return prefetched.get();   // a worker's throw rethrows here, where the inline computation would have thrown
    }
    return detail::computeStampAt( root );
}

// Formats a ready-to-splice ` at="VALUE"` (leading space included) — or "" when `root` isn't a git repo, so
// a caller can simply concatenate the result into its printf/snprintf attribute list and the attribute is
// OMITTED entirely on a non-repo target. The value is always plain hex + the literal "+dirty" (never user
// content), so it is deliberately NOT run through escapeXml.
inline std::string atAttr( const std::string& root )
{
    const std::string v = stampAt( root );
    return v.empty() ? std::string() : ( " at=\"" + v + "\"" );
}

}}   // namespace rw::gitstamp
