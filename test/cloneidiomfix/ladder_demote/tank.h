#pragma once
// The SAME bucketing-ladder idiom in a different domain, a different file and a different namespace, and
// sharing not one non-keyword identifier with flight::altitudeBandOf. This pair is the demotion case.
namespace supply
{

enum class TankState : unsigned char { Empty, Reserve, Cruise, Brimming };

inline TankState tankStateFor( float litres )
{
    if( litres <  20.0f ) return TankState::Empty;
    if( litres <  90.0f ) return TankState::Reserve;
    if( litres < 140.0f ) return TankState::Cruise;
    return TankState::Brimming;
}

}   // namespace supply
