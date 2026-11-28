// actedgestwin_unit.cpp — the (T) half of test/actedgescheck.sh: forpages::detail::withoutLane, the lane-off twin pageAnswer pages
// first (an answer whole without the lane is served whole with it). The twin must BE the answer RIPWIRE_ACT_EDGES=0 renders, est_tokens=
// aside: a twin that differs pages differently, and the ON answer is served whole where the OFF answer is paged (measured: a twin that
// kept 3 bytes of range 4 and lost the act element's `"/>` made 11 DEV answers whole, +57 KB).
//   actedgestwin_unit ON_DOC   prints the twin of the answer in ON_DOC to stdout; exit 2 when the answer is not a stream or has no lane

#include "forpages.h"
#include "infra/emit.h"

#include <cstdio>
#include <fstream>
#include <iterator>
#include <optional>
#include <string>

int main( int argc, char** argv )
{
    if( argc != 2 )
    {
        return 2;
    }
    std::ifstream     in( argv[ 1 ], std::ios::binary );
    const std::string doc( ( std::istreambuf_iterator<char>( in ) ), std::istreambuf_iterator<char>() );
    const std::optional<rw::forpages::detail::Stream> st = rw::forpages::detail::readStream( doc );
    if( !st )
    {
        return 2;
    }
    const std::optional<std::string> twin = rw::forpages::detail::withoutLane( *st );
    if( !twin )
    {
        return 2;
    }
    rw::emitRaw( stdout, twin->c_str() );
    return 0;
}
