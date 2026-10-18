// Minimal model of pageview.h callHierarchyRowCap (lane edf251f7) + pageWindow, release ENSURES = [[assume]].
#include <algorithm>
#include <cstddef>
#include <cstdio>
#ifdef NO_ASSUME
#define ENS( e ) ((void)0)
#else
#define ENS( e ) [[assume( static_cast<bool>( e ) )]]
#endif
constexpr int kCap = 40, kBand = kCap + kCap / 4;
constexpr std::size_t kBytes = 16000;
inline int eff( int l, int h ) noexcept { return l > 0 ? l : h; }
inline int rowCapLane( int pageLimit, std::size_t rowTotal, std::size_t rb = 0 ) noexcept
{
    const bool inRow  = rowTotal <= std::size_t( kBand );
    const bool inByte = rb > 0 && rb <= kBytes;
    const int  cap    = ( pageLimit <= 0 && rowTotal > std::size_t( kCap ) && ( inRow || inByte ) ) ? int( rowTotal ) : eff( pageLimit, kCap );
    ENS( cap > 0 );
    return cap;
}
inline int rowCapBase( int pageLimit, std::size_t rowTotal ) noexcept
{
    const int cap = ( pageLimit <= 0 && rowTotal > std::size_t( kCap ) && rowTotal <= std::size_t( kBand ) ) ? int( rowTotal ) : eff( pageLimit, kCap );
    ENS( cap > 0 );
    return cap;
}
struct PW { std::size_t b, e; };
inline PW pw( std::size_t total, int limit, int offset ) noexcept
{
    const std::size_t off = offset > 0 ? std::min<std::size_t>( std::size_t( offset ), total ) : 0;
    if( limit <= 0 ) { return { off, total }; }
    return { off, std::min<std::size_t>( off + std::size_t( limit ), total ) };
}
__attribute__((noinline)) PW laneBand( std::size_t total, int limit, int offset, std::size_t rb ) { return pw( total, rowCapLane( limit, total, rb ), offset ); }
__attribute__((noinline)) PW laneRow( std::size_t total, int limit, int offset ) { return pw( total, rowCapLane( limit, total ), offset ); }
__attribute__((noinline)) PW base( std::size_t total, int limit, int offset ) { return pw( total, rowCapBase( limit, total ), offset ); }
int main()
{
    volatile std::size_t t = 3, rb = 0;
    volatile int lim = 0, off = 0;
    const PW a = laneBand( t, lim, off, rb ), b = laneRow( t, lim, off ), c = base( t, lim, off );
    std::printf( "total=3 limit=0: laneBand end=%zu laneRow end=%zu base end=%zu (want 3 3 3)\n", a.e, b.e, c.e );
    return ( a.e == 3 && b.e == 3 && c.e == 3 ) ? 0 : 1;
}
