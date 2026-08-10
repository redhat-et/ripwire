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

// Float edge storage stays cache-compact; every iterative vector and reduction is double precision.
// `rank` is caller-owned scratch/output and must not overlap `teleport`.
unsigned pageRankDouble( const sparseCsr<float>& inEdges, std::span<const double> weightedOutDegree,
                         std::span<const double> teleport, std::span<double> rank, PageRankConfig config = {} );

} // namespace rw
