#pragma once

#include "infra/sparseCsr.h"

#include <cstddef>
#include <cstdint>
#include <span>
#include <utility>

namespace rw
{

struct PageRankConfig
{
    double alpha = 0.85;
    double tolerance = 1e-6;
    std::uint32_t maxIterationCount = 100;
};

// What the power iteration DID, returned rather than logged. `hasConverged == false` means the loop hit
// `maxIterationCount` with the L1 residual still above `tolerance`, so `rank` is a TRUNCATION of the
// computation — a rank vector that stopped short, not the fixed point it claims to approximate.
//
// WHY A RETURN AND NOT AN ALERT. The non-convergence branch already fires DISCLOSE, and it still
// does — but that macro compiles to nothing under NDEBUG, which is every shipped binary. So the only signal
// a release build had for "this ranking is unfinished" was deleted by the preprocessor, and the caller had
// no way to disclose what it could not see. The pair travels with the result instead; src/prconverge.h turns
// it into the pr_iters= / pr_converged= root attributes every ranked document carries.
//
// An empty graph runs no iteration and is `{ 0, true }` — vacuously converged, because there is no residual
// to leave above tolerance. That is deliberately NOT spelled `false`: a false there would put pr_converged="0"
// on every empty-corpus map, which is a defect claim about a run that has nothing to be wrong about.
struct PageRankRun
{
    std::uint32_t iterationCount = 0;
    bool hasConverged = true;
    // The DISCLOSE sink for the truncating exit: it clears hasConverged, which prconverge.h prints as pr_converged="0".
    enum class DisclosureWhy : std::uint8_t
    {
        MaxIterationsReached,
    };
    void disclose( DisclosureWhy ) noexcept
    {
        hasConverged = false;
    }
};

// Float edge storage stays cache-compact; every iterative vector and reduction is double precision.
// `rank` is caller-owned scratch/output and must not overlap `teleport`.
PageRankRun pageRankDouble( const sparseCsr<float>& inEdges, std::span<const double> weightedOutDegree,
                            std::span<const double> teleport, std::span<double> rank, PageRankConfig config = {} );

// ── RANK-SPEED step 2: the Andersen-Chung-Lang push of the PERSONALIZED part ───────────────────────────────
//
// WHY IT LIVES IN THIS TRANSLATION UNIT, which is the whole reason it is declared here and not in a header
// beside its caller. CMakeLists.txt gives src/pagerank.cpp alone `-fno-fast-math` (`/fp:precise` on MSVC),
// because the global profile is `-ffast-math` and PageRank reductions must not reassociate — the comment at
// the top of pagerank.cpp spells out what happens when a summation tree stops being a property of the
// source. This push estimates the SAME fixed point `pageRankDouble` computes, coordinate by coordinate, and
// it is compared against it to decide whether it may ever serve an answer. Holding the two to different
// floating-point licences would turn that comparison into a measurement of the optimizer. So the kernel is
// compiled under the same rules as the kernel it approximates, which means it is compiled HERE.
//
// WHAT IT COMPUTES. `R = (I - alpha*P)^-1` applied to a sparse `seed`, where `P[v][u] = w(u->v)/outDegree[u]`
// — exactly the operator the power iteration gathers, since buildGraph fills the out-edge CSR and `inEdges`
// from one flattened edge vector in one pass (graph.h, "flatten edges + out/in CSR"). It is a LOWER BOUND on
// every coordinate: a push moves residual into the estimate and never overshoots, so
// `estimate[i] <= (R*seed)[i]` always, and the deficit is larger in the tail than at the head. A consumer
// that divides by the maximum does not cancel that, which is why src/pprshadow.h compares the CONSUMER's
// order and not only this vector's.
//
// DETERMINISM. FIFO order, seeds pushed in ascending node id, out-edges walked in CSR order, and a ring
// buffer sized so the loop allocates nothing (a node is queued at most once at a time, so N+1 slots is
// exact). No reduction here depends on anything but the index.
struct PushConfig
{
    double alpha = 0.85;
    double epsilon = 3e-6;          // push u while residual[u] >= epsilon * max(unweighted outdegree(u), 1)
    std::size_t maxEdgeWalks = 0;   // 0 ⇒ the ACL bound, ceil(1/(epsilon*(1-alpha))) + N: a blow-up guard that cannot bind in practice
};

// What the push DID, returned rather than logged — the PageRankRun pattern above, for the same reason.
// `hitWalkBudget == true` means the blow-up guard stopped the walk, so `estimate` is a TRUNCATION: not the
// epsilon-approximation it would otherwise claim to be. It is never silently absorbed — src/pprshadow.h
// prints it, and a caller serving an answer off a truncated push would be serving a wrong answer.
struct PushRun
{
    std::size_t pushCount = 0;
    std::size_t edgeWalkCount = 0;
    // Nodes that received any mass — a FLOOR on the push's support, and never a statement about the graph:
    // a 0 here means no node was reached, not that no node exists.
    std::size_t touchedNodeCount = 0;
    bool hitWalkBudget = false;
    enum class DisclosureWhy : std::uint8_t
    {
        WalkBudgetReached,
    };
    void disclose( DisclosureWhy ) noexcept
    {
        hitWalkBudget = true;
    }
};

// The out-edge CSR the push walks, which is buildGraph's own: `offsets` is g.outOff (N+1), `targets` is
// g.outTargets, `values` is g.outVals, and `degree` is g.wOutDeg — the weighted out-degree, which is the
// exact per-source sum of `values` because buildGraph accumulates it in the loop that fills them.
struct OutEdgeCsr
{
    std::span<const std::uint32_t> offsets;
    std::span<const std::uint32_t> targets;
    std::span<const float>         values;
    std::span<const double>        degree;
};

// `seed` is (node, mass) ascending by node, Sigma = 1. `estimate` is caller-owned output of `degree.size()`
// doubles; the kernel zeroes it. It must not overlap any input.
PushRun pageRankPushPersonalized( const OutEdgeCsr& edges, std::span<const std::pair<std::uint32_t, double>> seed,
                                  std::span<double> estimate, PushConfig config = {} );

} // namespace rw
