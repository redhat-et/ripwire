// adaptive_cut_shape_test.cpp — A4-F4 unit-style gate: adaptiveCut(scanFullDistribution=true) must fire on
// the EXACT shape the audit reproduced with: a real head cliff (35% relative drop) at rank 8, followed by a
// much larger (98%) relative drop out in the tail, beyond hardCeil (40). Before the fix, tracking only the
// single GLOBAL-max relative drop meant the 98% tail drop (which lands beyond hardCeil) always won over the
// 35% in-cap head cliff, so the material in-cap cliff was never chosen — the mode kept 40/40 (inert) on
// exactly the sharp queries it exists for. The fix tracks the best drop WITHIN [1, hardCeil) as its own
// candidate, so the in-cap cliff can win even when a bigger drop exists beyond the cap.
//
// Score vector construction (scanFullDistribution=true, floor=5, ceiling=40):
//   ranks 1..7:  score 100.0 (flat head)
//   rank  8:     score  65.0   <- 35% relative drop from rank 7 (100 -> 65), the real cliff, WITHIN hardCeil
//   ranks 9..60: score  64.0 down to ~63.4 (a long, gently-decaying tail — no other drop anywhere near 20%)
//   PLUS one more point beyond hardCeil: after all 60, the tail is engineered so a single extra drop (rank
//   61: 63.4 -> 1.2, a 98%+ relative drop) sits WELL PAST hardCeil=40. That drop is real and large but
//   cannot be honored as a cut (nothing past position 40 can be returned), so it must not starve the head
//   cliff of being chosen.
//
// Prints "kept=<N> cliffRank=<N> hitCeiling=<0|1> dropPct=<N>" for both the OLD-shaped scan (bounded at
// hardCeil, scanFullDistribution=false — should already find the head cliff, sanity check) and the fixed
// full-distribution scan (should ALSO find the head cliff, not 40/40).

#include "../../src/lexical.h"

#include <cstdio>
#include <vector>

using namespace rw;

int main()
{
    std::vector<float> scores;
    for( int i = 0; i < 7; ++i ) scores.push_back( 100.0f );        // ranks 1..7: flat head
    scores.push_back( 65.0f );                                       // rank 8: 35% drop from 100 -> the real cliff
    for( int i = 0; i < 52; ++i ) scores.push_back( 64.0f - 0.01f * float( i ) );   // ranks 9..60: gentle tail decay
    scores.push_back( 1.2f );                                        // rank 61: a huge (>90%) drop, BEYOND hardCeil=40

    const AdaptiveCut full = adaptiveCut( scores, /*floor=*/5, /*ceiling=*/40, /*scanFullDistribution=*/true );
    std::printf( "full: kept=%zu cliffRank=%zu hitCeiling=%d dropPct=%d\n",
                 full.kept, full.cliffRank, int( full.hitCeiling ), full.dropPct );

    const AdaptiveCut capped = adaptiveCut( scores, /*floor=*/5, /*ceiling=*/40, /*scanFullDistribution=*/false );
    std::printf( "capped: kept=%zu cliffRank=%zu hitCeiling=%d dropPct=%d\n",
                 capped.kept, capped.cliffRank, int( capped.hitCeiling ), capped.dropPct );

    return 0;
}
