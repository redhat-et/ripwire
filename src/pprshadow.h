#pragma once

// pprshadow.h — RANK-SPEED step 2's SHADOW ARM: run the exact personalized rank and the Andersen-Chung-Lang
// push side by side, serve the EXACT one, and print what the two disagreed about.
//
// WHY A SHADOW ARM AND NOT A SWITCH. This is an approximation inside the ranking that decides what an agent
// is shown, and the house rule is that an approximation which changes the answer is a WRONG ANSWER. So the
// default path is untouched, and the mode that measures the push cannot reach the document: under `shadow`
// the function returns the exact vector and stdout is byte-identical to a run with the hook unset
// (test/pprpushcheck.sh arm (C) is that assertion). An approximation that cannot reach the answer cannot
// ship a wrong one by accident; that property, not care, is what makes building this safe.
//
// WHY AN ENVIRONMENT HOOK AND NOT A FLAG. The house precedent is pagerank.cpp's RIPWIRE_TEST_PR_MAXITERS:
// G5 says every flag is purely additive, lives in the hand-rolled parser and appears in --help, and this is
// a gate's arming and measurement mechanism, not a user surface, so it must appear in none of those
// (arm (A) asserts the --help absence). Read ONCE per process, so the answer cannot change mid-run and
// determinism holds.
//
//   RIPWIRE_PPR_PUSH=off      (default, and the value of every unset/unparseable environment) — today's code
//   RIPWIRE_PPR_PUSH=shadow   compute both, SERVE THE EXACT ONE, print one row per call to stderr
//   RIPWIRE_PPR_PUSH=on       serve the push. Never a default. See kPushOnIsSiteScoped below.
//
// THE ROWS GO TO STDERR, deliberately: stdout is the minified XML document and G4 forbids a newline outside
// CDATA, so a row on stdout would break well-formedness and the token-density contract at once. stderr is
// also what makes arm (C) a byte comparison rather than a diff with exclusions.

// Deliberately NOT graph.h: anchoredLexicalRank lives there and includes this, so the dependency runs one
// way only. Everything here takes spans and vectors, never a Graph.
#include "infra/emit.h"
#include "pagerank.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <numeric>
#include <span>
#include <utility>
#include <vector>

namespace rw::pprshadow
{

enum class Mode : std::uint8_t
{
    Off,
    Shadow,
    On,
};

// The epsilon per SITE, pre-registered in DESIGN_STEP2_RANKPUSH.md §3 and relayed from the M2's covering
// note: the largest epsilon with zero non-tie top-10 swaps on every dev call, divided by ten. The anchors
// site is two orders of magnitude looser than the working-set site because its teleport is supported on
// kAnchorCount = 20 nodes rather than on every symbol in the corpus.
//
// RE-DERIVED, NOT INHERITED. test/pprlab.cpp sweeps epsilon and the gate asserts the fidelity criterion AT
// THIS VALUE, so the constant and the evidence for it move together. The M2's own sweep stopped at 1e-7,
// which is above the working-set value and below nothing — so the recommended epsilons were outside the
// measured range and the lab's sweep is extended to cover them.
inline constexpr double kEpsilonAnchors = 3e-6;
inline constexpr double kEpsilonWorkingSet = 3e-8;

// The teleport this shadow arm can push from must be SPARSE: the push's whole advantage is that it touches a
// neighbourhood instead of the corpus, and a teleport with mass on every symbol (diffTeleport's uniform
// floor) has no neighbourhood. The working-set site is therefore measured OFFLINE only
// (test/pprlab.cpp, where the plain rank is in hand and R*w can supply the global term), and a dense
// teleport here records a row with no comparison rather than a comparison of something else.
inline constexpr std::size_t kMaxSeedSupport = 4096;

// `on` IS SITE-SCOPED, and this is not caution, it is an honesty constraint with a specific source.
// anchoredLexicalRank already discloses no pr_iters= — its own comment says what leaves it is a BLEND, so no
// document ordered by it was ordered by a power iteration, and stamping pr_iters= there would name a run
// that shaped only part of the order. So serving a push THERE claims nothing it cannot support. The
// working-set sites (mcpindex.h getIndex, main.cpp runDefaultMap) DO print pr_iters=, and a push produces no
// iteration count at all, so `on` there would stamp a document with the iteration count of a run that did
// not happen. That needs a new disclosure attribute in the answer serializer, which is not this lane's file.
inline constexpr bool kPushOnIsSiteScoped = true;

// The reference's own error, which is what makes a swap count. The power iteration stops on an L1 residual
// below `tolerance`, so one coordinate's remaining error is bounded by that residual; a GAP between two
// coordinates can be closed by error in both, hence the 2; and dividing by the ranked-node count puts it on
// the scale of a rank coordinate, since a uniform rank is 1/ranked. A gap at or below tau is a TIE, and a
// tie flipping is not a swap -- exact ties flip on any low-bit change, so counting them would make the
// criterion measure the optimizer. Stated as a bound before anything was measured, so it cannot be fitted.
inline constexpr double kReferenceTolerance = 1e-6;
inline double referenceGapError( std::size_t rankedNodeCount ) noexcept
{
    return rankedNodeCount > 0 ? 2.0 * kReferenceTolerance / double( rankedNodeCount ) : 2.0 * kReferenceTolerance;
}

// Read once per process. An unset, empty or unrecognized value is `Off`, which is also the value of every
// shipped run: the hook cannot be turned on by accident and cannot change a binary's default behaviour.
inline Mode mode() noexcept
{
    static const Mode cached = []() noexcept -> Mode
    {
        const char* value = std::getenv( "RIPWIRE_PPR_PUSH" );
        if( value == nullptr )
        {
            return Mode::Off;
        }
        if( std::strcmp( value, "shadow" ) == 0 )
        {
            return Mode::Shadow;
        }
        if( std::strcmp( value, "on" ) == 0 )
        {
            return Mode::On;
        }
        return Mode::Off;   // "off", "", "1", "yes", a typo — all of them mean today's code path
    }();
    return cached;
}

// The top-k node ids of a score vector, in the answer's own order: score descending, id ascending. The id
// tie-break is what makes every comparison below a comparison of ORDERS and not of float noise.
//
// THE ONE COPY OF THIS RULE. test/verify_pagerank.cpp's `topOrder` was a second body of it over doubles;
// it now calls this, so the ordering the gate asserts and the ordering the shadow arm measures cannot drift
// apart. k == score.size() gives the full order: the comparator is a total order over distinct ids, so
// partial_sort over the whole range is the complete sort and the result is unique.
// Templated on the CONTAINER, not the element, so a std::vector<float>, a std::vector<double> and a
// std::span<const double> all deduce: a span parameter would deduce from none of them.
template< class Scores >
inline std::vector< std::uint32_t > topByScore( const Scores& score, std::size_t k )
{
    std::vector< std::uint32_t > order( score.size() );
    std::iota( order.begin(), order.end(), 0u );
    k = std::min( k, order.size() );
    std::partial_sort( order.begin(), order.begin() + std::ptrdiff_t( k ), order.end(),
                       [ & ]( std::uint32_t a, std::uint32_t b ) { return score[a] != score[b] ? score[a] > score[b] : a < b; } );
    order.resize( k );
    return order;
}

// Milliseconds since a steady_clock reading, named once. DELIBERATELY steady_clock and not the tree's
// wallClockNs (src/ingest_crawl.h), which reads system_clock: a system clock can be stepped by NTP or by
// hand mid-run, and a timing a decision rests on must not be able to go backwards.
inline double elapsedMs( std::chrono::steady_clock::time_point since )
{
    return std::chrono::duration< double, std::milli >( std::chrono::steady_clock::now() - since ).count();
}

// The BINDING criterion, tie-aware. A position k is a non-tie swap iff the reference's own gap at k exceeds
// tau AND the candidate names a different node there. Positions whose gap is within tau are ties and are
// excluded, which is the rule exactly as relayed: a swap counts only when the reference gap exceeds the
// reference's own error.
struct SwapCount
{
    std::size_t nonTieSwaps = 0;
    std::size_t tiedPositions = 0;
    double minNonTieGap = 0.0;   // 0.0 when every compared position was a tie — a floor, not "no gap exists"
    int firstDiffRank = -1;      // -1 = no position differed at all, tie or not
};
inline SwapCount countNonTieSwaps( std::span<const float> reference, const std::vector<std::uint32_t>& referenceOrder,
                                   const std::vector<std::uint32_t>& candidateOrder, std::size_t depth, double tau )
{
    SwapCount out;
    bool      sawNonTieGap = false;
    const std::size_t last = std::min( depth, std::min( referenceOrder.size(), candidateOrder.size() ) );
    for( std::size_t k = 0; k < last; ++k )
    {
        // The gap BELOW position k: the margin that decides whether k's occupant is really ahead of the next one.
        const double gap = k + 1 < referenceOrder.size() ? double( reference[referenceOrder[k]] ) - double( reference[referenceOrder[k + 1]] ) : tau + 1.0;
        const bool   differs = referenceOrder[k] != candidateOrder[k];
        if( differs && out.firstDiffRank < 0 )
        {
            out.firstDiffRank = int( k );
        }
        if( gap > tau )
        {
            if( !sawNonTieGap || gap < out.minNonTieGap )
            {
                out.minNonTieGap = gap;
                sawNonTieGap     = true;
            }
            if( differs )
            {
                ++out.nonTieSwaps;
            }
        }
        else
        {
            ++out.tiedPositions;
        }
    }
    return out;
}

// What one call of the shadow arm found. Every field is printed; nothing is folded into a verdict here, so a
// reader of the rows can apply a different criterion to the same measurement.
struct Row
{
    const char* site = "anchors";
    std::size_t nodeCount = 0;
    std::size_t edgeCount = 0;
    std::size_t seedCount = 0;
    double      epsilon = 0.0;
    std::size_t pushes = 0;
    std::size_t touched = 0;
    std::size_t edgeWalks = 0;
    bool        budgetHit = false;
    double      msExact = 0.0;
    double      msPush = 0.0;
    std::uint32_t iterations = 0;
    int         top10Same = -1;        // 1 / 0; -1 = not compared (a dense teleport), never silently a 0
    int         top10SetSame = -1;
    std::size_t nonTieSwaps = 0;
    std::size_t tiedPositions = 0;
    double      top40Jaccard = 0.0;    // REPORTED ONLY — not in the pass condition
    double      maxAbsErrTop40 = 0.0;  // REPORTED ONLY — not in the pass condition
    double      minNonTieGap10 = 0.0;
    double      tau = 0.0;
    int         firstDiffRank = -1;
    int         blend10Same = -1;      // the CONSUMER's order: blendMaxNorm's top 10. -1 = not compared
};

// One row per call, tab-separated, to stderr, led by a literal tag so a gate can select rows without
// matching prose. Values are printed with enough precision to re-derive the verdict; the timings are the
// only columns that move between two identical runs, which is what lets the determinism arm compare the rest.
inline void emitRow( const Row& r )
{
    rw::emitTo( stderr,
                "pprshadow\tsite={}\tN={}\tnnz={}\tseeds={}\teps={:.3e}\tpushes={}\ttouched={}\tedge_walks={}\tbudget_hit={}"
                "\tms_exact={:.3f}\tms_push={:.3f}\titers={}\ttop10_same={}\ttop10_set_same={}\tnontie_swaps={}\ttied_positions={}"
                "\ttop40_jacc={:.4f}\tmax_abs_err40={:.6e}\tmin_nontie_gap10={:.6e}\ttau={:.6e}\tfirst_diff={}\tblend10_same={}\n",
                r.site, r.nodeCount, r.edgeCount, r.seedCount, r.epsilon, r.pushes, r.touched, r.edgeWalks, r.budgetHit ? 1 : 0,
                r.msExact, r.msPush, r.iterations, r.top10Same, r.top10SetSame, r.nonTieSwaps, r.tiedPositions, r.top40Jaccard,
                r.maxAbsErrTop40, r.minNonTieGap10, r.tau, r.firstDiffRank, r.blend10Same );
}

// The sparse seed the push walks: the EXACT teleport the power iteration is handed, which is biasPrior's
// output renormalized to Sigma = 1 the same way rankGraphTeleport renormalizes it. Returned empty when the
// support is wider than kMaxSeedSupport, which is the dense-teleport refusal, not a failure.
//
// This header is compiled under the global -ffast-math, unlike the kernel it feeds, so the mass sum below may
// reassociate. It is named, not hidden: scaling the seed by a constant scales the push's estimate by the same
// constant and the estimate is renormalized before it is read, so the only thing a last-bit difference in this
// sum can move is whether a residual sits exactly on the epsilon threshold. The arithmetic that is COMPARED
// against the power iteration is all inside pagerank.cpp, where reassociation is off.
inline std::vector<std::pair<std::uint32_t, double>> sparseSeedOf( const std::vector<float>& biasedPrior )
{
    std::vector<std::pair<std::uint32_t, double>> seed;
    double mass = 0.0;
    for( std::size_t i = 0; i < biasedPrior.size(); ++i )
    {
        if( biasedPrior[i] > 0.f )
        {
            if( seed.size() >= kMaxSeedSupport )
            {
                return {};
            }
            seed.push_back( { std::uint32_t( i ), double( biasedPrior[i] ) } );
            mass += double( biasedPrior[i] );
        }
    }
    if( !( mass > 0.0 ) )
    {
        return {};
    }
    for( auto& [ node, value ] : seed )
    {
        (void)node;
        value /= mass;
    }
    return seed;   // already ascending by node: built by one forward pass
}

} // namespace rw::pprshadow
