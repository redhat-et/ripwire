// demote_refill_test.cpp — test/demoterefillcheck.sh's driver for rw::refillRowsForDemote (src/demoterefill.h, DEMOTE-ALL-DIALECTS):
// a model answer of ranked rows, each 100 bytes, rendered as the rows that fit a byte budget; the rules turn a row into a 10-byte
// pointer. Prints one line per scenario: `<name>: rows=<shown> ships=<bytes> allotted=<bytes> renders=<n>`.
//   refill  rows 11..14 are always demotable: the freed bytes buy rows, and the walk keeps them (the block ships within budget).
//   k4      rows 11..12 are demotable only while row 13 is NOT shown (row 13 is a task-named seed whose proven edges from 11..12 keep
//           them whole, K4): the refill that admits row 13 frees nothing. CodeRabbit 4543056274: that refill must not ship.
#include "demoterefill.h"

#include <cstddef>
#include <cstdio>
#include <string>

namespace
{
struct Model
{
    std::size_t rowBytes = 100, ptrBytes = 10, total = 40;
    bool        k4       = false;
    std::size_t shown = 0, renders = 0;
    std::string blockText;

    bool demotable( std::size_t r ) const   // r is 1-based
    {
        if( r < 11 || r > 14 )
        {
            return false;
        }
        return !( k4 && r <= 12 && shown >= 13 ) && !( k4 && r > 12 );
    }
    bool renderAt( std::size_t budget )
    {
        ++renders;
        shown     = std::min( total, budget / rowBytes );
        blockText = std::string( shown * rowBytes, 'r' );
        return true;
    }
    std::string point() const
    {
        std::size_t bytes = 0, moved = 0;
        for( std::size_t r = 1; r <= shown; ++r )
        {
            const bool d = demotable( r );
            moved += d ? 1 : 0;
            bytes += d ? ptrBytes : rowBytes;
        }
        return moved == 0 ? std::string() : std::string( bytes, 'p' );
    }
};

void scenario( const char* name, bool k4 )
{
    Model             m;
    m.k4 = k4;
    const std::size_t base = 1250;   // 12 rows fit: rows past 12 are cut
    m.renderAt( base );
    const std::size_t allotted = std::max( base, m.blockText.size() );
    const std::string pointed  = rw::refillRowsForDemote(
        base, [ & ]() -> const std::string& { return m.blockText; }, [ & ] { return m.shown < m.total; }, [ & ] { return m.shown; },
        [ & ]( std::size_t b ) { return m.renderAt( b ); }, [ & ] { return m.point(); } );
    const std::size_t ships = pointed.empty() ? m.blockText.size() : pointed.size();
    std::printf( "%s: rows=%zu ships=%zu allotted=%zu renders=%zu\n", name, m.shown, ships, allotted, m.renders );
}
}   // namespace

int main()
{
    scenario( "refill", false );
    scenario( "k4", true );
    return 0;
}
