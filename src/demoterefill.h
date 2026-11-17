#pragma once
// demoterefill.h — DEMOTE-ALL-DIALECTS (card B26): the soft target's refill walk, with no dependency beyond the standard library so
// test/demoterefillcheck.sh compiles it alone against a model answer (fordemoteall.h includes it; verbs_for.h and mcpverbs.h call it).
#include <algorithm>
#include <cstddef>
#include <string>

namespace rw
{
// A soft target's rows past the cut get the bytes the rules free: `pointed` is the rules' result on the rendered block (`block()`), and
// while rows were cut (`rowsCut()`) and the rules shrink the block, the rows are rendered again at `baseRowDrop` plus the bytes the
// rules free on the latest render (`renderAt( budget )`: false when that render failed, the block then stays as it was). The freed
// bytes are those of the whole latest render, so the rows that ship after the rules cost about `baseRowDrop`; a render that serves
// no more rows than the one before stops the walk. A refill is ACCEPTED only when its final savings fund the rows it added: the
// block as it would ship (the rules' result, or the block itself when no row moves) fits what the rows were allotted, the larger
// of `baseRowDrop` and the undemoted block the walk started from. A refill whose added rows keep earlier picks whole (K4: a row
// past the cut that is a seed of theirs) frees too little; it is rendered back to the last accepted budget, the rules run again
// there, and the walk stops (CodeRabbit 4543056274). Returns the rules' result on the block as it finally is ("" when none moves).
inline constexpr int kDemoteRefillPasses = 3;
template<class Block, class RowsCut, class RowsShown, class RenderAt, class Point>
inline std::string refillRowsForDemote( std::size_t baseRowDrop, const Block& block, const RowsCut& rowsCut, const RowsShown& rowsShown,
                                        const RenderAt& renderAt, const Point& point )
{
    std::string       pointed    = point();
    const std::size_t allotted   = std::max( baseRowDrop, block().size() );   // the rows' budget, or the undemoted block: no refill ships more
    std::size_t       acceptedAt = baseRowDrop;      // the budget of the render the walk last kept
    for( int pass = 0; pass < kDemoteRefillPasses && !pointed.empty() && rowsCut() && pointed.size() < block().size(); ++pass )
    {
        const std::size_t shownBefore = rowsShown();
        const std::size_t refillAt    = baseRowDrop + ( block().size() - pointed.size() );
        if( !renderAt( refillAt ) )
        {
            break;
        }
        pointed = point();
        const std::size_t ships = pointed.empty() ? block().size() : pointed.size();
        if( ships > allotted )
        {
            if( renderAt( acceptedAt ) )   // the refill's savings do not fund its rows: back to the last kept render
            {
                pointed = point();
            }
            break;
        }
        acceptedAt = refillAt;
        if( rowsShown() <= shownBefore )
        {
            break;
        }
    }
    return pointed;
}
}   // namespace rw
