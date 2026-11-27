// pprlab — OFFLINE measurement for RANK-SPEED step 2. Not repo code; never shipped, never linked into the
// binary. Built only with -DRIPWIRE_PPRLAB=ON, which is OFF by default (CMakeLists.txt).
//
//   usage: ripwire_pprlab ROOT OUT.tsv
//
// ingest + buildGraph exactly as the binary does, then per seed set: today's exact personalized rank
// (rankGraphTeleport) against an Andersen-Chung-Lang push of the personalized part (+ the stored-global-prior
// term for diffTeleport), swept over epsilon.
//
// ADAPTED FROM THE M2'S KIT (M2_TO_M5_1127_RANKSPEED/pprlab.cpp), with four changes, each for a reason:
//
//  1. IT MEASURES THE SHIPPED KERNEL. The kit carried its own copy of the push in this file. A lab that
//     measures a private copy of the thing under test answers a question about the copy, so this one calls
//     rw::pageRankPushPersonalized from src/pagerank.cpp — the same function the shadow arm calls.
//  2. IT WALKS THE GRAPH'S OWN OUT-EDGE CSR. The kit transposed g.inEdges on every run. buildGraph fills
//     g.outOff/outTargets/outVals and g.wOutDeg from one flattened edge vector in one pass, so the stored
//     out-CSR already IS that transpose. The transpose is kept here anyway, run ONCE, purely to PROVE that
//     claim: the header row reports whether the two agree edge for edge. If they ever disagree, every
//     fidelity number below is measuring the wrong operator and the header says so.
//  3. THE EPSILON SWEEP COVERS THE RECOMMENDED VALUES. The kit swept 1e-3 .. 1e-7. The epsilon rule
//     (largest with zero non-tie top-10 swaps, then / 10) recommends 3e-8 for the working set and 3e-6 for
//     anchors, and 3e-8 is below the kit's floor — so neither the fidelity nor, more to the point, the COST
//     of the push at the epsilon actually recommended had ever been measured. The / 10 is a fidelity margin
//     paid for in pushes: the ACL work bound is O(1/(eps*(1-alpha))), so / 10 on epsilon multiplies the work
//     ceiling by ten.
//  4. THE SWAP COUNT IS TIE-AWARE, by the rule written down in DESIGN_STEP2_RANKPUSH.md §3.2 before
//     anything was measured: a position counts as a swap only when the reference's own gap there exceeds
//     tau = 2 * tolerance / ranked. The kit's top10_same counted any difference, which on a reference that
//     stops at an L1 residual of 1e-6 counts low-bit tie flips as disagreements.
//
// Rows: site trial seeds eps pushes touched edge_walks budget_hit ms_exact ms_push iters top10_same
// top10_set nontie_swaps tied_positions top40_jacc max_abs_err40 min_nontie_gap10 tau first_diff.
//
// The BLEND check (what --for's rows are actually ordered by) is deliberately NOT here: this lab's anchors
// are drawn at random and have no lexical score behind them, so a blend built from them would be a blend of
// a synthetic vector. That check lives in the shadow arm (src/graph.h pprshadowAnchors), on real queries.

#include "graph.h"
#include "infra/emit.h"
#include "ingest.h"
#include "model.h"
#include "pagerank.h"
#include "pprshadow.h"

#include <chrono>
#include <cstdio>
#include <numeric>
#include <vector>

using namespace rw;

namespace
{
using Clock = std::chrono::steady_clock;
// Elapsed milliseconds comes from rw::pprshadow::elapsedMs — the same body the shadow arm times with, so the
// lab's milliseconds and the product's are the same measurement and not two spellings of one.

struct Lcg
{
    std::uint64_t s;
    std::uint64_t next() { s = s * 6364136223846793005ull + 1442695040888963407ull; return s >> 17; }
};

// The kit's transpose of inEdges, kept ONLY as the cross-check described in change 2 above.
struct OutCsr
{
    std::vector< std::uint32_t > off, to;
    std::vector< float >         val;
};
OutCsr transposeIn( const Graph& g )
{
    const std::size_t N  = g.wOutDeg.size();
    const auto*       ro = g.inEdges.rowOffsets();
    const auto*       ci = g.inEdges.colIndices();
    const auto*       va = g.inEdges.values();
    OutCsr            o;
    o.off.assign( N + 1, 0 );
    for( std::size_t v = 0; v < N; ++v )
    {
        for( auto e = ro[v]; e < ro[v + 1]; ++e ) { ++o.off[ ci[e] + 1 ]; }
    }
    for( std::size_t u = 0; u < N; ++u ) { o.off[u + 1] += o.off[u]; }
    o.to.resize( g.inEdges.nnz() );
    o.val.resize( g.inEdges.nnz() );
    std::vector< std::uint32_t > fill( o.off.begin(), o.off.end() - 1 );
    for( std::size_t v = 0; v < N; ++v )
    {
        for( auto e = ro[v]; e < ro[v + 1]; ++e )
        {
            const auto u   = ci[e];
            const auto pos = fill[u]++;
            o.to[pos]      = std::uint32_t( v );
            o.val[pos]     = va[e];
        }
    }
    return o;
}
// Edge for edge, including order within a source. A `false` here invalidates every fidelity row below.
bool sameCsr( const OutCsr& a, const Graph& g )
{
    if( a.off.size() != g.outOff.size() || a.to.size() != g.outTargets.size() || a.val.size() != g.outVals.size() )
    {
        return false;
    }
    for( std::size_t i = 0; i < a.off.size(); ++i ) { if( a.off[i] != g.outOff[i] ) { return false; } }
    for( std::size_t i = 0; i < a.to.size(); ++i )  { if( a.to[i] != g.outTargets[i] || a.val[i] != g.outVals[i] ) { return false; } }
    return true;
}
}   // namespace

int main( int argc, char** argv )
{
    if( argc < 3 ) { rw::emitTo( stderr, "usage: pprlab ROOT OUT.tsv\n" ); return 1; }
    const auto   t0       = Clock::now();
    IngestResult ing      = ingest( argv[1] );
    const double msIngest = pprshadow::elapsedMs( t0 );
    const auto   t1       = Clock::now();
    Graph        g        = buildGraph( ing );
    const double msGraph  = pprshadow::elapsedMs( t1 );

    const std::size_t N     = g.wOutDeg.size();
    const double      alpha = 0.85;
    FILE*             out   = std::fopen( argv[2], "w" );
    if( out == nullptr ) { rw::emitTo( stderr, "pprlab: cannot write {}\n", argv[2] ); return 1; }

    // plain rank (today's rankGraph) and the global term R*w derived from it: with the plain teleport,
    // biasPrior gives pw proportional to w, so the plain fixed point is c*R*(w/Sigma w).
    const auto        t2      = Clock::now();
    const RankedGraph plain   = rankGraph( g );
    const double      msPlain = pprshadow::elapsedMs( t2 );
    std::vector< double > w( N );
    for( std::size_t i = 0; i < N; ++i ) { w[i] = g.priorWeight.size() == N ? double( g.priorWeight[i] ) : 1.0; }
    double sumW = 0, dang = 0;
    for( std::size_t i = 0; i < N; ++i ) { sumW += w[i]; }
    for( std::size_t i = 0; i < N; ++i ) { if( !( g.wOutDeg[i] > 0 ) ) { dang += plain.rank[i]; } }
    const double          cg = alpha * dang + ( 1 - alpha );
    std::vector< double > Rw( N );
    for( std::size_t i = 0; i < N; ++i ) { Rw[i] = sumW / cg * double( plain.rank[i] ); }

    const OutCsr   transposed = transposeIn( g );
    const bool     csrAgrees  = sameCsr( transposed, g );
    std::size_t    dangling   = 0;
    for( std::size_t i = 0; i < N; ++i ) { dangling += !( g.wOutDeg[i] > 0 ); }
    const std::size_t ranked = N - std::min< std::size_t >( N, g.unrankedNodeCount );
    const double      tau    = pprshadow::referenceGapError( ranked );
    rw::emitTo( out,
                "#root\t{}\tN={}\tE_in={}\tE_out={}\tout_csr_is_transpose_of_in={}\tdangling={}\tunranked={}\tranked={}"
                "\ttau={:.6e}\tplain_iters={}\tms_ingest={:.0f}\tms_graph={:.0f}\tms_plain={:.1f}\n",
                argv[1], N, std::size_t( g.inEdges.nnz() ), g.outTargets.size(), csrAgrees ? 1 : 0, dangling,
                std::size_t( g.unrankedNodeCount ), ranked, tau, plain.iterationCount, msIngest, msGraph, msPlain );
    rw::emitRaw( out, "site\ttrial\tseeds\teps\tpushes\ttouched\tedge_walks\tbudget_hit\tms_exact\tms_push\titers"
                      "\ttop10_same\ttop10_set\tnontie_swaps\ttied_positions\ttop40_jacc\tmax_abs_err40\tmin_nontie_gap10\ttau\tfirst_diff\n" );

    // files that hold ranked symbols
    std::vector< std::vector< std::uint32_t > > symsOf( ing.files.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( s.id < N && w[s.id] > 0 ) { symsOf[s.fileId].push_back( s.id ); }
    }
    std::vector< std::uint32_t > files;
    for( std::uint32_t f = 0; f < symsOf.size(); ++f ) { if( !symsOf[f].empty() ) { files.push_back( f ); } }
    std::vector< std::uint32_t > rankedSyms;
    for( std::uint32_t i = 0; i < N; ++i ) { if( w[i] > 0 ) { rankedSyms.push_back( i ); } }
    if( files.empty() || rankedSyms.empty() )
    {
        rw::emitRaw( out, "#PPRLABDONE\tno ranked symbol in this corpus -- zero rows is a refusal, not agreement\n" );
        (void)std::fclose( out );   // the rows are fflush'd per row; a close failure cannot un-write them
        return 0;
    }

    // The recommended epsilons (3e-6 anchors, 3e-8 working set) and the two decades around them. Change 3.
    const double eps[] = { 1e-3, 3e-4, 1e-4, 3e-5, 1e-5, 3e-6, 1e-6, 3e-7, 1e-7, 3e-8, 1e-8 };
    Lcg          rng{ 0x5eedULL };
    struct Site { const char* name; int files; int anchors; };
    const Site sites[] = { { "ws1", 1, 0 }, { "ws5", 5, 0 }, { "ws20", 20, 0 }, { "anchor20", 0, 20 } };
    for( const Site& site : sites )
    {
        for( int trial = 0; trial < 10; ++trial )
        {
            std::vector< float >                            p( N, 0.f );
            std::vector< std::pair< std::uint32_t, double > > seed;   // the personalized part, mass 1
            double      coefGlobal = 0, coefLocal = 0;                // unnormalized u = coefGlobal*Rw + coefLocal*R(seed)
            std::size_t nSeeds = 0;
            if( site.files )
            {
                std::vector< char > changed( ing.files.size(), 0 );
                for( int k = 0; k < site.files; ++k ) { changed[ files[ rng.next() % files.size() ] ] = 1; }
                p = diffTeleport( ing, changed );
                // p*w = b*w + (a-b)*(1_C*w); a and b are read back off p rather than recomputed from beta.
                double a = 0, b = 0, mC = 0;
                for( const Symbol& s : ing.symbols )
                {
                    if( s.id >= N ) { continue; }
                    if( changed[s.fileId] ) { a = p[s.id]; } else { b = p[s.id]; }
                }
                // "in the changed set AND ranked" is the seed's membership rule; it is named ONCE, and the
                // masses are divided through afterwards rather than in a second pass that repeats the test.
                for( const Symbol& s : ing.symbols )
                {
                    // s.id < N is part of the membership rule, not a belt: ing.symbols can outrun the graph's
                    // node count, and w is sized to the graph.
                    if( s.id < N && changed[s.fileId] && w[s.id] > 0 ) { seed.push_back( { s.id, w[s.id] } ); mC += w[s.id]; }
                }
                if( !( mC > 0 ) ) { continue; }
                for( auto& [ seedId, seedMass ] : seed ) { (void)seedId; seedMass /= mC; }
                std::sort( seed.begin(), seed.end() );
                coefGlobal = b;
                coefLocal  = ( a - b ) * mC;
                nSeeds     = seed.size();
            }
            else
            {
                std::vector< std::pair< std::uint32_t, double > > an;
                for( int k = 0; k < site.anchors; ++k )
                {
                    an.push_back( { rankedSyms[ rng.next() % rankedSyms.size() ], 0.5 + double( rng.next() % 1000 ) / 2000.0 } );
                }
                std::sort( an.begin(), an.end() );
                an.erase( std::unique( an.begin(), an.end(), []( auto& x, auto& y ) { return x.first == y.first; } ), an.end() );
                double conf = 0;
                for( auto& [ id, c ] : an ) { (void)id; conf += c; }
                for( auto& [ id, c ] : an ) { p[id] = float( c / conf ); }
                double m = 0;
                for( auto& [ id, c ] : an ) { (void)c; m += double( p[id] ) * w[id]; }
                if( !( m > 0 ) ) { continue; }
                for( auto& [ id, c ] : an ) { (void)c; seed.push_back( { id, double( p[id] ) * w[id] / m } ); }
                coefGlobal = 0;
                coefLocal  = 1;
                nSeeds     = seed.size();
            }
            if( seed.empty() ) { continue; }

            const auto        te      = Clock::now();
            const RankedGraph ex      = rankGraphTeleport( g, p );
            const double      msExact = pprshadow::elapsedMs( te );
            const auto        ex40    = pprshadow::topByScore( ex.rank, 40 );
            for( const double e : eps )
            {
                std::vector< double > estimate( N, 0.0 );
                const auto            tp = Clock::now();
                const PushRun         pr = pageRankPushPersonalized( OutEdgeCsr{ g.outOff, g.outTargets, g.outVals, g.wOutDeg }, seed,
                                                                     estimate, PushConfig{ .alpha = alpha, .epsilon = e } );
                double sum = 0;
                std::vector< double > u( N );
                for( std::size_t i = 0; i < N; ++i ) { u[i] = coefGlobal * Rw[i] + coefLocal * estimate[i]; sum += u[i]; }
                std::vector< float > uf( N, 0.f );
                if( sum > 0 ) { for( std::size_t i = 0; i < N; ++i ) { uf[i] = float( u[i] / sum ); } }   // the consumer reads a float rank
                const double msPush = pprshadow::elapsedMs( tp );

                const auto ap40  = pprshadow::topByScore( uf, 40 );
                const auto swaps = pprshadow::countNonTieSwaps( ex.rank, ex40, ap40, 10, tau );
                std::vector< std::uint32_t > a10( ex40.begin(), ex40.begin() + std::min< std::size_t >( 10, ex40.size() ) );
                std::vector< std::uint32_t > b10( ap40.begin(), ap40.begin() + std::min< std::size_t >( 10, ap40.size() ) );
                std::sort( a10.begin(), a10.end() );
                std::sort( b10.begin(), b10.end() );
                std::vector< std::uint32_t > a40( ex40 ), b40( ap40 ), both, either;
                std::sort( a40.begin(), a40.end() );
                std::sort( b40.begin(), b40.end() );
                std::set_intersection( a40.begin(), a40.end(), b40.begin(), b40.end(), std::back_inserter( both ) );
                std::set_union( a40.begin(), a40.end(), b40.begin(), b40.end(), std::back_inserter( either ) );
                double maxErr = 0;
                for( const auto id : ex40 ) { maxErr = std::max( maxErr, std::fabs( double( uf[id] ) - double( ex.rank[id] ) ) ); }

                rw::emitTo( out, "{}\t{}\t{}\t{:.0e}\t{}\t{}\t{}\t{}\t{:.1f}\t{:.1f}\t{}\t{}\t{}\t{}\t{}\t{:.3f}\t{:.3e}\t{:.3e}\t{:.3e}\t{}\n",
                            site.name, trial, nSeeds, e, pr.pushCount, pr.touchedNodeCount, pr.edgeWalkCount, pr.hitWalkBudget ? 1 : 0,
                            msExact, msPush, ex.iterationCount, swaps.nonTieSwaps == 0 ? 1 : 0, a10 == b10 ? 1 : 0,
                            swaps.nonTieSwaps, swaps.tiedPositions, either.empty() ? 1.0 : double( both.size() ) / double( either.size() ),
                            maxErr, swaps.minNonTieGap, tau, swaps.firstDiffRank );
                (void)std::fflush( out );   // best-effort per-row flush so a killed long run keeps the rows it wrote
            }
        }
    }
    rw::emitRaw( out, "#PPRLABDONE\n" );
    (void)std::fclose( out );   // every row was fflush'd as it was written; nothing is buffered to lose here
    return 0;
}
