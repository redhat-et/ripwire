#pragma once

// prconverge.h — the ONE spelling of the PageRank convergence disclosure, shared by every ranked document
// on every surface (the map's XML and JSON dialects, the standalone ranked verb roots, and their MCP twins).
//
// Why the disclosure exists (the truncating exit was invisible on Release builds): the full story is
// docs/ARCHITECTURE.md, "The convergence disclosure contract". This header is only the spelling.
//
// THE ATTRIBUTES.
//   pr_iters="N"       how many power iterations produced this document's ordering. Present on EVERY
//                      PageRank-ordered root; absent means the ordering did not come from a power iteration
//                      at all (a lexical query rank, a HITS hub/authority vector), not that the number is
//                      unknown.
//   pr_converged="0"   present ONLY when that iteration stopped at the ceiling with the residual still above
//                      tolerance. ABSENCE MEANS IT CONVERGED — the same absence-means-fine shape
//                      `skipped_oversize=`, `changed=` and `over_ceiling="1"` already use in the map header,
//                      and for the same reason: the converged path is the overwhelming majority and must
//                      cost zero bytes. There is deliberately no pr_converged="1"; a run that converged says
//                      so by not saying anything, and the legend is what makes that readable rather than a
//                      thing you have to know.
//
// It is NOT spelled with `_floor` or `_capped`. Those markers (src/graphlegend.h, src/pageview.h) mean "the
// count you are reading is short of the truth" and "a cap stopped the scan"; this one means "the numeric
// method behind the ordering did not reach its own stopping criterion". Three different facts, three names.
//
// At the shipped configuration the truncating exit is provably unreachable — src/pagerank.cpp carries the
// contraction derivation. The disclosure is a contract for the configuration, not a live alarm.
//
// ONE RENDERER, NOT SIX ENTRY POINTS, and the second reason is measured. The first reason is design: the
// forms below differ only in the syntax their host document accepts, never in what they say, so five public
// names for one fact is exactly the drift this file exists to prevent — the header's own title is "the ONE
// spelling". The second is that a cluster of tiny keyword-dense symbols is a RETRIEVAL hazard in this repo,
// not a neutral style choice: at six symbols this header took four of the top seven hits for the query
// "power iteration rank convergence damping factor" and five of the top eight for "pagerank power iteration",
// pushing `pageRankDouble` — the numeric kernel, and the labelled answer to both — from rank 1 to 6 and from
// 2 to 9 (bench/recalleval, ranking lane). BM25 length-normalization prefers a short symbol whose whole text
// is the query's vocabulary, and a spelling header is nothing but the vocabulary. Consolidating restored it.
// Keep this file at one renderer; if a form is added, add a `DiscloseAs` case, never a sibling function.
//
// Gate: test/prconvergecheck.sh.

#include <cstdint>
#include <string>

namespace rw
{

// What a ranked document discloses about the power iteration that ordered it. `isPageRank == false` is the
// honest default: a document whose order came from somewhere else discloses nothing here rather than
// borrowing another run's numbers, which is how one attribute comes to describe two rankings.
struct RankDisclosure
{
    std::uint32_t iterationCount = 0;
    bool          hasConverged   = true;
    bool          isPageRank     = false;
};

// Which spelling the caller's host document accepts. Picking the wrong one is picking the wrong DOCUMENT,
// which is a decision worth naming at the call site rather than hiding in a function name.
enum class DiscloseAs
{
    XmlAttrs,       // ` pr_iters="N"` [+ ` pr_converged="0"`] — appended to a root element's attributes
    JsonKeys,       // `,"pr_iters":N` [+ `,"pr_converged":false`] — appended to a JSON header's keys
    LegendClause,   // the definition, spliced INSIDE an XML comment the caller has already opened
    LegendComment,  // the same definition as its own `<!-- -->` block
    MarkdownNote,   // truncating exit only: one line, for a document with no attribute grammar at all
    MermaidNote,    // truncating exit only: the same line as a diagram comment
};

// Render one form of the disclosure. Empty string whenever there is nothing to say — no power iteration
// ordered this document, or (for the two note forms) it converged — so a caller that appends unconditionally
// keeps its exact pre-feature bytes and pays nothing on the overwhelmingly common path.
inline std::string renderDisclosure( const RankDisclosure& d, DiscloseAs as )
{
    if( !d.isPageRank )
    {
        return {};
    }
    const std::string iterations = std::to_string( d.iterationCount );

    // ── the two attribute dialects ───────────────────────────────────────────────────────────────────────
    // §B1.2 / §B2.1: the dialects must carry the SAME KEYSET for the same run — a keyset that differs by
    // dialect is how one number comes to mean two things — so the two arms differ only in punctuation, and
    // JSON says `false` rather than 0 because it has a boolean and XML does not.
    if( as == DiscloseAs::XmlAttrs )
    {
        return " pr_iters=\"" + iterations + "\"" + ( d.hasConverged ? "" : " pr_converged=\"0\"" );
    }
    if( as == DiscloseAs::JsonKeys )
    {
        return ",\"pr_iters\":" + iterations + ( d.hasConverged ? "" : ",\"pr_converged\":false" );
    }

    // ── the two note forms: documents with no attribute grammar ──────────────────────────────────────────
    // The markdown architecture report and the mermaid module diagram have no root element to hang an
    // attribute on. What they must NOT do is go quiet on the case that matters — "the clause landed at 3 of
    // its 5 echo sites" is this repo's own named failure family, and a disclosure present only where the
    // syntax was convenient is that failure with a rationale attached. So: nothing at all on the converged
    // path (zero bytes, byte-identical output), one line on the truncating one, carrying the host language's
    // own comment marker, because a note that breaks the document it warns about is worse than silence.
    if( as == DiscloseAs::MarkdownNote || as == DiscloseAs::MermaidNote )
    {
        if( d.hasConverged )
        {
            return {};
        }
        return std::string( as == DiscloseAs::MermaidNote ? "%% " : "> " )
             + "NOTE: this ranking did NOT converge. The PageRank power iteration ran its full ceiling of "
             + iterations
             + " iterations with the L1 residual still above tolerance, so the order below is a snapshot of an "
               "unfinished computation rather than the fixed point it approximates.\n\n";
    }

    // ── the legend ───────────────────────────────────────────────────────────────────────────────────────
    // test/legendcoveragecheck.sh arm (A) fails ANY root attribute a first screen does not define, so the
    // always-on clause is obligatory, not optional. Its LENGTH is the choice: this attribute rides the
    // DEFAULT map, the most-emitted document the tool has, and G4 is maximum token density — a paragraph
    // about a condition that provably cannot fire would be paid on every invocation forever. So it is
    // written in the map legend's own compact `name=value(qualifier)` dialect (the same shape as
    // `est_tokens=hdr-copy(none-if-stable)` beside it), fully DEFINITIONAL for both names, at ~130 bytes.
    //
    // The prose is charged only to the document that took the truncating exit, i.e. exactly where a reader
    // needs telling what to do about it — the rule kChurnRankLegend / kMaxTokensFitLegend already follow.
    //
    // G4: no "--" digraph and no "<" anywhere in either string; both are spliced into an XML comment where
    // "--" is a well-formedness error, which is why verbs are named bare rather than with their flags.
    std::string clause =
        "pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) "
        "pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) ";
    if( !d.hasConverged )
    {
        clause +=
            "pr_converged=\"0\" on this map means the ranking below is a rank vector that STOPPED SHORT of tolerance "
            "rather than the fixed point it approximates: the power iteration hit its iteration ceiling with the L1 "
            "residual between successive vectors still above the convergence threshold. The k= scores, and therefore "
            "the order, are a snapshot of an unfinished computation. Treat the ordering as indicative and the scores "
            "as not comparable with any converged map. ";
    }
    // The map's legend is a CHAIN of self-contained comment blocks (kChurnRankLegend and friends each open
    // and close their own), while every other ranked verb splices clauses inside one comment it opened
    // itself. Getting this wrong emits the clause as document TEXT outside any comment — a G4 breach at
    // exit 0 — which is why the distinction is a named form and not a bool the caller has to remember.
    return ( as == DiscloseAs::LegendComment ) ? "<!-- " + clause + "-->" : clause;
}

} // namespace rw
