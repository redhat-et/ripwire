#pragma once

// prconverge.h — the ONE spelling of the PageRank convergence disclosure, shared by every ranked document
// on every surface (the map's XML and JSON dialects, the standalone ranked verb roots, and their MCP twins).
//
// WHY THIS EXISTS. PageRank here is a power iteration with a stopping rule: iterate until the L1 residual
// falls below `tolerance`, or until `maxIterationCount` iterations have run — whichever comes first. Those
// two exits produce documents that look identical and mean different things. The first is the fixed point
// the ranking claims to be. The second is a TRUNCATION of the computation: a rank vector caught mid-descent,
// emitted with the same k= attributes, the same ordering, the same confidence.
//
// Until this header the difference reached nobody. `pageRankDouble` fired DEGRADED_PATH_ALERT on the
// truncating exit and returned its iteration count, and `rankGraphTeleport` discarded the return; the alert
// itself is `#ifndef NDEBUG`, so on every shipped Release binary it is not code at all. A release build
// therefore emitted a non-converged ranking with no alert, no attribute, exit 0 — the whole document
// indistinguishable from a converged one. Constraint #3 (honesty in output) names that class exactly: every
// truncation is disclosed in the header.
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
//                      so by not saying anything, and the legend below is what makes that readable rather
//                      than a thing you have to know.
//
// It is NOT spelled with `_floor` or `_capped`. Those markers (src/graphlegend.h, src/pageview.h) mean "the
// count you are reading is short of the truth" and "a cap stopped the scan"; this one means "the numeric
// method behind the ordering did not reach its own stopping criterion". Three different facts, three names.
//
// CAN IT EVER FIRE? Not at the shipped configuration. The iteration is an alpha-contraction in L1, so
// residual_k <= 2 * alpha^k and 2 * 0.85^k < 1e-6 at k = 90, comfortably inside maxIterationCount = 100 for
// ANY graph (src/pagerank.cpp carries the derivation; E2 measured 28-52 iterations across four real
// corpora). The disclosure is therefore a contract for the configuration, not a live alarm: lower the
// tolerance, raise alpha toward 1, or hand the ranker a graph shape the contraction argument stops covering,
// and the attribute is what tells the reader before the ranking does.
//
// Gate: test/prconvergecheck.sh.

#include <cstdint>
#include <string>

namespace rw
{

// What a ranked document discloses about the power iteration that ordered it. `isPageRank == false` is the
// honest default: a document whose order came from somewhere else discloses nothing here rather than
// borrowing a PageRank run's numbers, which is how one attribute comes to describe two rankings.
struct RankDisclosure
{
    std::uint32_t iterationCount = 0;
    bool          hasConverged   = true;
    bool          isPageRank     = false;
};

// ── THE TWO LEGEND CLAUSES, and why the split is not a cost dodge ────────────────────────────────────────
// test/legendcoveragecheck.sh's arm (A) fails ANY root attribute a first screen does not define, so
// `pr_iters=` cannot be emitted without a definition where the reader meets it — the always-on clause below
// is obligatory, not optional. What IS a choice is its LENGTH. This attribute rides the DEFAULT map, the
// single most-emitted document the tool has, and G4 is maximum token density; a 700-byte paragraph about a
// condition that provably cannot fire at the shipped configuration (see the header comment) would be paid on
// every invocation forever. So the always-on clause is written in the map legend's own compact
// `name=value(qualifier)` dialect — the same shape as `est_tokens=hdr-copy(none-if-stable)` beside it — and
// it is fully DEFINITIONAL for both names, which is arm (B)'s stricter predicate, at ~130 bytes.
//
// The prose lands where it is load-bearing: kPrConvergeLegendTruncated is appended ONLY on the map whose
// iteration actually stopped short, i.e. exactly when a reader needs to be told what to do about it. This is
// the same rule kChurnRankLegend / kMaxTokensFitLegend already follow — a clause is charged to the document
// that carries the fact, never to the document that does not.
//
// G4: NO "--" digraph anywhere in either string (both are spliced into an XML comment, where "--" is a
// well-formedness error), which is why verbs are named bare rather than with their flags, and no "<" either.
inline constexpr const char* kPrConvergeLegendDense =
    "pr_iters=pagerank-power-iterations(stop:L1-residual-below-tol,else-ceiling) "
    "pr_converged=0-only-when-ceiling-hit-first(absent=converged;no-such-attr=not-pagerank-ordered) ";

// The truncating exit, in prose, on the document that took it.
inline constexpr const char* kPrConvergeLegendTruncated =
    "pr_converged=\"0\" on this map means the ranking below is a rank vector that STOPPED SHORT of tolerance "
    "rather than the fixed point it approximates: the power iteration hit its iteration ceiling with the L1 "
    "residual between successive vectors still above the convergence threshold. The k= scores, and therefore "
    "the order, are a snapshot of an unfinished computation. Treat the ordering as indicative and the scores "
    "as not comparable with any converged map. ";

// The clause a caller splices into its legend, composed from the disclosure so no emitter has to restate the
// rule about which half goes where. Empty for a document that ran no power iteration ⇒ zero bytes, and the
// legend it would have joined stays byte-identical.
inline std::string prConvergeLegend( const RankDisclosure& d )
{
    if( !d.isPageRank )
    {
        return {};
    }
    std::string s = kPrConvergeLegendDense;
    if( !d.hasConverged )
    {
        s += kPrConvergeLegendTruncated;
    }
    return s;
}

// The root-element attributes, one spelling per dialect. Appended in the same slot on every surface. A
// disclosure with `isPageRank == false` renders as the empty string, so a caller that has no power iteration
// to describe pays zero bytes and its document stays byte-identical to the pre-feature one.
inline std::string prConvergeAttrXml( const RankDisclosure& d )
{
    if( !d.isPageRank )
    {
        return {};
    }
    std::string a = " pr_iters=\"";
    a += std::to_string( d.iterationCount );
    a += '"';
    if( !d.hasConverged )
    {
        a += " pr_converged=\"0\"";
    }
    return a;
}

// The JSON twin. The two dialects' headers must carry the SAME KEYSET for the same run (§B1.2 / §B2.1: a
// keyset that differs by dialect is how one number comes to mean two things), so this mirrors the XML rule
// exactly — pr_iters always, pr_converged only on the truncating exit, and `false` rather than 0 because
// JSON has a boolean and the XML "0" is only there because XML does not.
inline std::string prConvergeAttrJson( const RankDisclosure& d )
{
    if( !d.isPageRank )
    {
        return {};
    }
    std::string a = ",\"pr_iters\":";
    a += std::to_string( d.iterationCount );
    if( !d.hasConverged )
    {
        a += ",\"pr_converged\":false";
    }
    return a;
}

// The map's legend is a CHAIN OF SELF-CONTAINED COMMENT BLOCKS (kChurnRankLegend and friends each open and
// close their own `<!-- -->`), while every other ranked verb splices its clauses INSIDE one comment it opens
// itself. Both spellings therefore exist, and the difference is not cosmetic: getting it wrong emits the
// clause as document TEXT outside any comment, which is a G4 breach at exit 0. This is the wrapped form; use
// it wherever the caller appends to a completed comment, and prConvergeLegend() wherever it appends inside
// an open one.
inline std::string prConvergeLegendComment( const RankDisclosure& d )
{
    if( !d.isPageRank )
    {
        return {};
    }
    return "<!-- " + prConvergeLegend( d ) + "-->";
}

// ── the surfaces with NO attribute grammar ───────────────────────────────────────────────────────────────
// Two ranked outputs are not XML and not JSON: the markdown architecture report, and the mermaid rendering of
// the nested module hierarchy. Neither has a root element to hang pr_iters= on, and neither should carry a
// paragraph on every run — a markdown report gains nothing from a line saying a number converged, which is
// the state it is always in at the shipped configuration.
//
// What they must NOT do is go quiet on the case that matters. "The clause landed at 3 of its 5 echo sites"
// is this repo's own named failure family, and a disclosure that exists only where the syntax was convenient
// is that failure with a rationale attached. So these two emit NOTHING on the converged path (zero bytes,
// byte-identical output) and a single plain line on the truncating one — the disclosure is structural where
// a structure exists and textual where none does, and it is never absent where it is load-bearing.
// `linePrefix` is the host language's own comment/callout marker, because a note that breaks the document
// it warns about is worse than the silence — "> " is a markdown blockquote, and "%% " is a mermaid comment,
// which is what keeps the diagram pasteable into a renderer with the note still attached to it.
inline std::string prConvergeTextWarning( const RankDisclosure& d, const char* linePrefix = "> " )
{
    if( !d.isPageRank || d.hasConverged )
    {
        return {};
    }
    std::string s = linePrefix;
    s += "NOTE: this ranking did NOT converge. The PageRank power iteration ran its full ceiling of ";
    s += std::to_string( d.iterationCount );
    s += " iterations with the L1 residual still above tolerance, so the order below is a snapshot of an "
         "unfinished computation rather than the fixed point it approximates.\n\n";
    return s;
}

} // namespace rw
