#pragma once

#include "infra/sparseCsr.h"

#include <cstdint>
#include <span>

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
// WHY A RETURN AND NOT AN ALERT. The non-convergence branch already fires DEGRADED_PATH_ALERT, and it still
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
};

// Float edge storage stays cache-compact; every iterative vector and reduction is double precision.
// `rank` is caller-owned scratch/output and must not overlap `teleport`.
PageRankRun pageRankDouble( const sparseCsr<float>& inEdges, std::span<const double> weightedOutDegree,
                            std::span<const double> teleport, std::span<double> rank, PageRankConfig config = {} );

} // namespace rw
