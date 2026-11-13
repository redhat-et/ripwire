#pragma once
namespace gap
{
inline int gapOf( int x, int y = 0, int margin = 0 )
{
    return ( x < y ? y - x : x - y ) + ( margin > 0 ? margin * 2 : 0 ) - ( x > y ? 1 : 0 ) + ( y > margin ? y - margin : margin - y );
}
}
