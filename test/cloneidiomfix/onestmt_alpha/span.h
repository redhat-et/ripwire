#pragma once
namespace span
{
inline int widthBetween( int lo, int hi, int pad )
{
    return ( lo < hi ? hi - lo : lo - hi ) + ( pad > 0 ? pad * 2 : 0 ) - ( lo > hi ? 1 : 0 ) + ( hi > pad ? hi - pad : pad - hi );
}
}
