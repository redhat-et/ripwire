#include "pagerank.h"

#include "infra/csrverify.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdlib> // std::getenv — the test-only iteration ceiling below (see why it cannot be a fixture)
#include <cstring> // std::strlen — the strict decimal parse of that ceiling
#include <vector>

namespace rw
{

namespace
{

// THE REDUCTION BLOCK SIZE IS A COMPILE-TIME CONSTANT, AND THAT IS THE WHOLE POINT. Every reduction below
// folds fixed-size blocks in canonical index order, so the summation tree is a property of the SOURCE and
// nothing else. Never replace this with a runtime-derived partition — a thread count, a
// `hardware_concurrency()`, a cache-size probe. Floating-point addition is not associative, so a partition
// that varies by machine produces rank vectors that vary by machine, and the tool's determinism contract
// dies silently: every run is self-consistent, every run is reproducible on its own host, and two hosts
// disagree in the low bits, which reorders ties. A graph-database PageRank implementation surveyed in
// 2026-08 partitions its identical fixed-merge-order reduction by `hardware_concurrency()` and inherits
// exactly that; docs/ARCHITECTURE.md records the trap in full.
inline constexpr std::size_t kReductionBlockSize = 1024;

// ── the TEST-ONLY iteration ceiling ───────────────────────────────────────────────────────────────────────
// `RIPWIRE_TEST_PR_MAXITERS=N` LOWERS this run's iteration ceiling to N. It can only lower it (the effective
// ceiling is min(configured, N)), so it cannot make a run iterate longer than the shipped configuration
// allows, and an unset/unparseable/zero value leaves the configuration exactly as it was.
//
// WHY A HOOK AND NOT A FIXTURE — the arithmetic, because "write a graph that does not converge" is the
// obvious answer and it is provably impossible here. The iteration is an alpha-contraction in L1: the map
// r -> alpha*P*r + (alpha*dangling(r) + 1 - alpha)*p is column-stochastic (wOutDeg is the exact sum of each
// source's out-edge weights, and the dangling mass is redistributed through the teleport prior), so
// successive differences shrink by at least alpha every iteration. Two probability vectors differ by at
// most 2 in L1, hence residual_k <= 2 * alpha^k, and the loop stops as soon as residual_k < tolerance:
//     2 * 0.85^k < 1e-6   ->   k > ln(2e6) / ln(1/0.85) = 14.509 / 0.16252 = 89.3
// so NO graph, however pathological, can survive past ~90 iterations against the shipped
// maxIterationCount = 100. The non-convergence branch is unreachable at the defaults BY CONSTRUCTION, not
// by luck (E2 measured 28-52 iterations across four real corpora, well inside that bound). A gate arm that
// asserts the disclosure therefore cannot be armed by any input; it has to be armed by the ceiling.
//
// It is NOT a flag: G5 says every flag is purely additive and appears in the hand-rolled parser and in
// --help, and this must appear in neither — it is a gate's arming mechanism, not a user surface. Unlike
// serialize.h's RIPWIRE_FAULT_CHARGE_BUFFER it is honoured in EVERY build flavour, deliberately: the fact
// the gate exists to prove is that a NDEBUG build discloses non-convergence after DISCLOSE has
// been compiled out of it, and a hook that also vanished under NDEBUG could not ask that question.
// Read once per process, so the answer cannot change mid-run and determinism holds.
//
// Gate: test/prconvergecheck.sh (arm 2, both flavours).
std::uint32_t testIterationCeiling() noexcept
{
    static const std::uint32_t ceiling = []() noexcept -> std::uint32_t
    {
        const char* value = std::getenv( "RIPWIRE_TEST_PR_MAXITERS" );
        if( value == nullptr || *value == '\0' || std::strlen( value ) > 9 )
        {
            return 0; // unset, empty, or absurdly long ⇒ no override
        }
        std::uint32_t parsed = 0;
        for( const char* c = value; *c != '\0'; ++c )
        {
            if( *c < '0' || *c > '9' )
            {
                return 0; // a strict decimal or nothing — never a prefix parse of "12x"
            }
            parsed = parsed * 10 + std::uint32_t( *c - '0' );
        }
        return parsed; // 0 reads as "no override", which is what "=0" should mean anyway
    }();
    return ceiling;
}

double probabilityMass( std::span<const double> values ) noexcept
{
    double total = 0.0;
    for( std::size_t blockBegin = 0; blockBegin < values.size(); blockBegin += kReductionBlockSize )
    {
        const std::size_t blockEnd = std::min( blockBegin + kReductionBlockSize, values.size() );
        double partial = 0.0;
        for( std::size_t valueIndex = blockBegin; valueIndex < blockEnd; ++valueIndex )
        {
            partial += values[valueIndex];
        }
        total += partial;
    }
    return total;
}

}

// The PageRank power iteration itself — the numeric kernel every ranked document's order comes from.
// Each round: gather rank along in-edges (rank / weighted out-degree), spread dangling mass back through
// the teleport vector, damp by alpha, and measure the L1 residual; stop when it drops below tolerance or
// at the iteration ceiling, and return which of the two ended the loop (PageRankRun, pagerank.h).
PageRankRun pageRankDouble( const sparseCsr<float>& inEdges, std::span<const double> weightedOutDegree,
                            std::span<const double> teleport, std::span<double> rank, PageRankConfig config )
{
    const std::size_t nodeCount = inEdges.rows();
    DASSERT( verifyCsr( inEdges, nodeCount ) ); // a corrupt CSR is not impossible; do not let the promise delete the bounds reasoning
    ASSUME( weightedOutDegree.size() == nodeCount );
    ASSUME( teleport.size() == nodeCount );
    ASSUME( rank.size() == nodeCount );
    ASSUME( config.alpha >= 0.0 && config.alpha < 1.0 );
    ASSUME( config.tolerance > 0.0 );
    ASSUME( config.maxIterationCount > 0 );
    // The test-only ceiling can only LOWER the configured one, so the shipped ceiling is still an upper
    // bound on every run and the ASSUME above still describes the loop that runs.
    const std::uint32_t testCeiling = testIterationCeiling();
    const std::uint32_t maxIterationCount = testCeiling > 0 ? std::min( config.maxIterationCount, testCeiling ) : config.maxIterationCount;
    if( nodeCount == 0 )
    {
        return { 0, true }; // no residual to leave above tolerance — vacuously converged, see PageRankRun
    }
    ASSUME( rank.data() != teleport.data() );

    for( std::size_t nodeIndex = 0; nodeIndex < nodeCount; ++nodeIndex )
    {
        ASSUME( std::isfinite( weightedOutDegree[nodeIndex] ) && weightedOutDegree[nodeIndex] >= 0.0 );
        ASSUME( std::isfinite( teleport[nodeIndex] ) && teleport[nodeIndex] >= 0.0 );
    }
    // Checked, never assumed: handing the optimizer a floating-point identity in the translation unit whose
    // whole point is reproducible arithmetic (docs/ARCHITECTURE.md's determinism contract) buys nothing worth
    // the licence it grants.
    DASSERT( std::fabs( probabilityMass( teleport ) - 1.0 ) <= 1e-9 );

    // Allocate all scratch once. The power-iteration loop performs no dynamic allocation.
    std::vector<double> currentRank( teleport.begin(), teleport.end() );
    std::vector<double> nextRank( nodeCount, 0.0 );
    std::vector<double> scaledRank( nodeCount, 0.0 );

    const std::uint32_t* rowOffsets = inEdges.rowOffsets();
    const std::uint32_t* columnIndices = inEdges.colIndices();
    const float* edgeValues = inEdges.values();
    bool hasConverged = false;
    std::uint32_t iterationCount = 0;

    for( ; iterationCount < maxIterationCount; ++iterationCount )
    {
        // Dangling mass uses fixed blocks and canonical fold order.
        double danglingMass = 0.0;
        for( std::size_t blockBegin = 0; blockBegin < nodeCount; blockBegin += kReductionBlockSize )
        {
            const std::size_t blockEnd = std::min( blockBegin + kReductionBlockSize, nodeCount );
            double partial = 0.0;
            for( std::size_t nodeIndex = blockBegin; nodeIndex < blockEnd; ++nodeIndex )
            {
                partial += weightedOutDegree[nodeIndex] > 0.0 ? 0.0 : currentRank[nodeIndex];
            }
            danglingMass += partial;
        }

        for( std::size_t nodeIndex = 0; nodeIndex < nodeCount; ++nodeIndex )
        {
            scaledRank[nodeIndex] = weightedOutDegree[nodeIndex] > 0.0 ? currentRank[nodeIndex] / weightedOutDegree[nodeIndex] : 0.0;
        }

        // In-edge CSR gather. Edges remain float; multiplication and accumulation promote to double.
        const double teleportScale = config.alpha * danglingMass + ( 1.0 - config.alpha );
        for( std::size_t targetNodeId = 0; targetNodeId < nodeCount; ++targetNodeId )
        {
            double incomingRank = 0.0;
            for( std::uint32_t edgeIndex = rowOffsets[targetNodeId]; edgeIndex < rowOffsets[targetNodeId + 1]; ++edgeIndex )
            {
                incomingRank += double( edgeValues[edgeIndex] ) * scaledRank[columnIndices[edgeIndex]];
            }
            nextRank[targetNodeId] = config.alpha * incomingRank + teleportScale * teleport[targetNodeId];
        }

        // L1 residual uses the same fixed-block canonical reduction discipline.
        double residual = 0.0;
        for( std::size_t blockBegin = 0; blockBegin < nodeCount; blockBegin += kReductionBlockSize )
        {
            const std::size_t blockEnd = std::min( blockBegin + kReductionBlockSize, nodeCount );
            double partial = 0.0;
            for( std::size_t nodeIndex = blockBegin; nodeIndex < blockEnd; ++nodeIndex )
            {
                partial += std::fabs( nextRank[nodeIndex] - currentRank[nodeIndex] );
            }
            residual += partial;
        }

        currentRank.swap( nextRank );
        if( residual < config.tolerance )
        {
            ++iterationCount;
            hasConverged = true;
            break;
        }
    }

    // The alert STAYS (non-negotiable #4 — a degrade path never becomes ASSUME( false )), and it is still
    // the only thing that says WHICH site degraded on a dev build. It is no longer the only thing that says
    // the ranking is unfinished: that fact now leaves the function with the ranking it describes, so an
    // NDEBUG build — where this macro is nothing at all — still discloses it in the document it emits.
    PageRankRun run { iterationCount, true };
    if( !hasConverged )
    {
        DISCLOSE( run, PageRankRun::DisclosureWhy::MaxIterationsReached, "PageRank reached max iterations before L1 convergence" );
    }
    std::copy( currentRank.begin(), currentRank.end(), rank.begin() );
    return run;
}

// The Andersen-Chung-Lang push — pagerank.h carries the contract and the reason it is compiled here.
//
// THE INVARIANT THE WHOLE THING RESTS ON: estimate + R*residual == R*seed, maintained exactly by each push
// (a push of mass m at u moves m into estimate[u] and alpha*m*P[.,u] into the residual, retiring
// (1-alpha)*m of the residual's total). R is non-negative, so estimate is a LOWER bound on R*seed
// throughout and the unretired residual bounds the deficit. Stopping while every node's residual is under
// epsilon*max(outdeg,1) is the ACL guarantee; it is NOT a residual on the answer this tool serves, which is
// why nothing here is allowed to claim the push "converged".
//
// TERMINATION is by construction, not by the budget: each push retires at least (1-alpha)*epsilon*max(deg,1)
// of a residual whose total never exceeds 1, so at most 1/((1-alpha)*epsilon) pushes can ever happen. The
// budget below exists because a cap is a blow-up guard, and it is DISCLOSED when it binds rather than
// quietly producing a short walk that reads like a finished one.
PushRun pageRankPushPersonalized( const OutEdgeCsr& edges, std::span<const std::pair<std::uint32_t, double>> seed,
                                  std::span<double> estimate, PushConfig config )
{
    const std::size_t nodeCount = edges.degree.size();
    ASSUME( config.alpha >= 0.0 && config.alpha < 1.0 );
    ASSUME( config.epsilon > 0.0 );
    ASSUME( estimate.size() == nodeCount );
    ASSUME( nodeCount == 0 || edges.offsets.size() == nodeCount + 1 );
    ASSUME( edges.targets.size() == edges.values.size() );
    std::fill( estimate.begin(), estimate.end(), 0.0 );
    if( nodeCount == 0 || seed.empty() )
    {
        return {};   // nothing seeded ⇒ nothing reached. A zero here means "none found", never "none exists".
    }

    // Allocate all scratch once; the push loop below performs no dynamic allocation. The queue is a ring of
    // nodeCount + 1 slots, and that is exact rather than generous: `inQueue` keeps a node from being enqueued
    // twice at a time, so at most nodeCount entries are ever live, and one slot separates full from empty.
    std::vector<double>        residual( nodeCount, 0.0 );
    std::vector<char>          inQueue( nodeCount, 0 );
    std::vector<std::uint32_t> queue( nodeCount + 1, 0u );
    const std::size_t          queueCapacity = queue.size();
    std::size_t                queueHead = 0, queueTail = 0;

    const std::size_t walkBudget = config.maxEdgeWalks > 0
                                       ? config.maxEdgeWalks
                                       : std::size_t( 1.0 / ( config.epsilon * ( 1.0 - config.alpha ) ) ) + 1 + nodeCount;

    // The enqueue rule, named ONCE: a node joins the queue when it is not already on it and its residual has
    // reached the ACL frontier for its own unweighted out-degree. Both the seeding pass and the edge walk go
    // through this, so there is one condition to read and one to be wrong.
    const auto enqueueIfReady = [ & ]( std::uint32_t node ) noexcept
    {
        const std::uint32_t degree    = edges.offsets[node + 1] - edges.offsets[node];
        const double        threshold = config.epsilon * double( degree > 0u ? degree : 1u );
        if( inQueue[node] == 0 && residual[node] >= threshold )
        {
            inQueue[node]    = 1;
            queue[queueTail] = node;
            queueTail        = ( queueTail + 1 ) % queueCapacity;
        }
    };
    // Seeds first, then the queue, both in the caller's ascending node order, so the walk order is a
    // property of the seed set and the CSR and of nothing else.
    for( const auto& [ seedNode, seedMass ] : seed )
    {
        ASSUME( seedNode < nodeCount );
        residual[seedNode] += seedMass;
    }
    for( const auto& [ seedNode, seedMass ] : seed )
    {
        (void)seedMass;
        enqueueIfReady( seedNode );
    }

    PushRun run{};
    while( queueHead != queueTail )
    {
        const std::uint32_t node = queue[queueHead];
        queueHead                = ( queueHead + 1 ) % queueCapacity;
        inQueue[node]            = 0;
        const double mass        = residual[node];
        residual[node]           = 0.0;
        estimate[node] += mass;
        ++run.pushCount;
        const double divisor = edges.degree[node];
        if( !( divisor > 0.0 ) )
        {
            continue;   // dangling: the exact kernel sends that mass back through the teleport, which IS the seed
        }
        const double spread = config.alpha * mass;
        for( std::uint32_t edgeIndex = edges.offsets[node]; edgeIndex < edges.offsets[node + 1]; ++edgeIndex )
        {
            const std::uint32_t target = edges.targets[edgeIndex];
            residual[target] += spread * ( double( edges.values[edgeIndex] ) / divisor );
            ++run.edgeWalkCount;
            enqueueIfReady( target );
        }
        if( run.edgeWalkCount >= walkBudget )
        {
            // The alert STAYS and is still the only thing that names WHICH site degraded on a dev build
            // (non-negotiable #4 — a degrade path never becomes VERIFY( false )); the fact itself leaves in
            // the return value, where NDEBUG cannot delete it.
            DISCLOSE( run, PushRun::DisclosureWhy::WalkBudgetReached,
                      "personalized-rank push reached its edge-walk budget before the epsilon frontier" );
            break;
        }
    }
    // Every node that received mass, pushed or not, in one pass over both vectors — cheaper than a third
    // `seen` array and exactly the same set.
    for( std::size_t nodeIndex = 0; nodeIndex < nodeCount; ++nodeIndex )
    {
        run.touchedNodeCount += ( estimate[nodeIndex] > 0.0 || residual[nodeIndex] > 0.0 ) ? 1u : 0u;
    }
    return run;
}

} // namespace rw
