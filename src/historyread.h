#pragma once

// historyread.h — the ONE spelling of "the git history behind churn= and amp= could not be read in this run" (K51).
//
// The history walk (`git log` over the 18-month window) feeds two numbers every rich verb prints: churn= (--for, the
// commit count of a file) and amp= (a symbol's callers plus the files that share a commit with it). When git cannot
// finish that walk the stream is EMPTY (git never ran: not on PATH, not executable, no popen) or a newest-first PREFIX
// (git ran and stopped part-way: an unreadable object, a bad ref). Undisclosed, both numbers read as "this file never
// changed" / "no co-change partners", or as the whole window when they are only its newest part. This header is the
// disclosure for it, in the dialect of each host document, so the failure is a field of the answer, not a trace.
//
// THE ATTRIBUTE.  history_unread="1" on the root of a document that prints churn= or amp=; absent when the walk was read
// (including a read that found no commit — an unborn branch, git's own exit 128 with no HEAD: that is a measurement, and
// it stays silent). It means: churn= and the co-change half of amp= count only the commits that WERE read, so both are
// FLOORS — none read when git did not run (churn= absent, amp= callers only), the newest part of the window when it
// stopped part-way. A prefix is kept rather than dropped because a floor is still information (a file with churn="3" from
// a prefix changed at least 3 times); the attribute is what stops it reading as the full count. An absent churn= under
// the attribute is not zero churn. It does NOT mean the repository is damaged beyond that walk, that the other numbers
// in the document are affected, or that a retry will fail: the failed walk is never cached, so the next call walks again.
// A THIRD CAUSE, the budget (gitmine.h THE BUDGET): the walk read fine and was ended on purpose at a commit count or a wall
// time, a prefix like the second cause and FLOORS in the same sense, except that the prefix is cached until HEAD moves.
// The comment names which cause this run hit. A verb that runs no history walk (a plain map, --callers) never carries it.
//
// NOT COVERED (pre-existing, deferred): the other git walks — --cochange and the MCP cochange tool, --rank-by=churn and
// --owners — do not yet tell a failed walk from an empty one (CHANGELOG, the K51 entry). A BUDGET cut of those walks IS told,
// on the CLI, by main()'s one history_cut comment after the answer (gitWalkCutsToDisclose in gitmine.h). Those walks, and
// gitLogNameOnlyRaw, also discard GitLogWalk::epochUnparsed, so a commit whose epoch field would not parse (read as 0)
// lowers a window count or an ownership row without a tell: carried with this deferral, to be disclosed at one place
// when these walks learn to say history_unread (PR #433 review, CodeRabbit on #469).
//
// ONE RENDERER (the prconverge.h rule): the forms differ only in the syntax of their host, never in what they say, so a
// new host adds a DiscloseAs case here, never a sibling function. XmlAttrs and the comment form (LegendComment) go on every
// XML root that prints the numbers; JsonKeys is the JSON twin. The comment is its own definition, so a first screen that
// carries the attribute defines it (legendcoveragecheck), and it holds no "--" digraph and no "<" (it lives in an XML comment).
//
// STATE.  One process-wide report, written once by main.cpp's amp=/churn= block on the main thread, after the walks were
// joined and before any emitter runs; emitters only read it. The MCP server never runs that block, so it never sets it.
// Gate: test/qchurncheck.sh (the K51 block).

#include <cstdint>
#include <string>

#include "prconverge.h"   // DiscloseAs — the shared "which spelling does the host accept" enum

namespace rw
{

// The DISCLOSE sink (CONTRIBUTING §3): the roots whose walk could not be read, by cause.
struct HistoryReadReport
{
    enum class DisclosureWhy : std::uint8_t
    {
        WalkNotRun,    // git did not run (not on PATH, not executable, no popen): the root's stream is empty
        WalkStopped,   // git ran and exited non-zero part-way: the root's stream is a newest-first prefix (possibly empty)
        WalkCut,       // the budget ended the walk (gitmine.h THE BUDGET): the root's stream is a newest-first prefix
    };
    std::uint32_t unreadRoots  = 0;
    std::uint32_t notRunRoots  = 0;
    std::uint32_t stoppedRoots = 0;
    std::uint32_t cutRoots     = 0;
    std::uint64_t cutCommits   = 0;   // commits the cut roots did read
    void          disclose( DisclosureWhy why ) noexcept
    {
        ++unreadRoots;
        ++( why == DisclosureWhy::WalkNotRun ? notRunRoots : why == DisclosureWhy::WalkStopped ? stoppedRoots : cutRoots );
    }
};

inline HistoryReadReport& historyRead() noexcept
{
    static HistoryReadReport report;
    return report;
}

// "" when every walk was read, so a caller that appends unconditionally keeps its exact bytes on the ordinary path.
inline std::string renderHistoryUnread( DiscloseAs as )
{
    if( historyRead().unreadRoots == 0 )
    {
        return {};
    }
    if( as == DiscloseAs::XmlAttrs )
    {
        return " history_unread=\"1\"";
    }
    if( as == DiscloseAs::JsonKeys )
    {
        return ",\"history_unread\":true";
    }
    if( historyRead().cutRoots == historyRead().unreadRoots )
    {
        return "<!--history_unread=1: the git history walk behind churn= and amp= hit its budget after the newest "
             + std::to_string( historyRead().cutCommits ) + " commits, so churn= and amp= count only those: both are floors, and an absent "
             "churn= here is not zero churn. RIPWIRE_GIT_WALK_SECONDS and RIPWIRE_GIT_WALK_COMMITS raise the budget; the cut is cached until HEAD moves.-->";
    }
    std::string comment = "<!--history_unread=1: the git history walk behind churn= and amp= could not be read in full in this run (";
    if( historyRead().stoppedRoots + historyRead().cutRoots == 0 )
    {
        comment += "the walk did not run), so churn= is absent and amp= counts callers only (a floor)";
    }
    else
    {
        const char* const stopped = historyRead().cutRoots == 0 ? "stopped part-way" : historyRead().stoppedRoots == 0 ? "hit its budget" : "stopped part-way or hit its budget";
        comment += historyRead().notRunRoots == 0 ? std::string( "the walk " ) + stopped : std::string( "the walk did not run for one root and " ) + stopped + " for another";
        comment += "), so churn= and amp= count only the commits that were read: both are floors";
    }
    comment += "; an absent churn= here is not zero churn. The failed walk is not cached, so the next call walks again.-->";
    return comment;
}

} // namespace rw
