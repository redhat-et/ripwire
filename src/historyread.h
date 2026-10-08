#pragma once

// historyread.h — the ONE spelling of "the git history behind churn= and amp= could not be read in this run" (K51).
//
// The history walk (`git log` over the 18-month window) feeds two numbers every rich verb prints: churn= (--for, the
// commit count of a file) and amp= (a symbol's callers plus the files that share a commit with it). When git cannot
// finish that walk — an unreadable object, a bad ref, git failing to start — the stream is EMPTY OR A PREFIX, and both
// numbers read as "this file never changed" and "no co-change partners": a zero that measured nothing. This header is
// the disclosure for it, in the dialect of each host document, so the failure is a field of the answer, not a trace.
//
// THE ATTRIBUTE.  history_unread="1" on the root of a document that prints churn= or amp=; absent when the walk was read
// (including a read that found no commit: that is a measurement, and it stays silent). It means: churn= is not
// available and amp= counts callers only — a FLOOR. It does NOT mean the repository is damaged beyond that walk, that the
// other numbers in the document are affected, or that a retry will fail: the failed walk is never cached, so the next call
// walks again. A verb that runs no history walk (a plain map, --callers) never carries it.
//
// ONE RENDERER (the prconverge.h rule): the forms differ only in the syntax of their host, never in what they say, so a
// new host adds a DiscloseAs case here, never a sibling function. XmlAttrs and the comment form (LegendComment) go on every
// XML root that prints the numbers; JsonKeys is the JSON twin. The comment is its own definition, so a first screen that
// carries the attribute defines it (legendcoveragecheck), and it holds no "--" digraph and no "<" (it lives in an XML comment).
//
// STATE.  One process-wide report, written once by main.cpp's amp=/churn= block on the main thread, after the walks were
// joined and before any emitter runs; emitters only read it. The MCP server never runs that block, so it never sets it.
// Gate: test/historyreadcheck.sh.

#include <cstdint>
#include <string>

#include "prconverge.h"   // DiscloseAs — the shared "which spelling does the host accept" enum

namespace rw
{

// The DISCLOSE sink (CONTRIBUTING §3): `unreadRoots` counts the roots whose walk could not be read.
struct HistoryReadReport
{
    enum class DisclosureWhy : std::uint8_t
    {
        WalkUnread,   // git log did not start or did not finish: the root's stream is empty or a prefix
    };
    std::uint32_t unreadRoots = 0;
    void          disclose( DisclosureWhy ) noexcept { ++unreadRoots; }
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
    return "<!--history_unread=1: the git history walk behind churn= and amp= could not be read in this run, so churn= is absent and amp= counts "
           "callers only (a floor); an absent churn= here is not zero churn. The failed walk is not cached, so the next call walks again.-->";
}

} // namespace rw
