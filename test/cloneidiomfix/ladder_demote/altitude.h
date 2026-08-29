#pragma once
// A scalar threshold ladder — the field shape that prompted the idiom class, reproduced so the gate for the
// idiom-class clone demotion does not depend on an external tree.
namespace flight
{

enum class AltitudeBand : unsigned char { Low, Mid, High, Danger };

inline AltitudeBand altitudeBandOf( float y )
{
    if( y <  6.0f ) return AltitudeBand::Low;
    if( y < 12.0f ) return AltitudeBand::Mid;
    if( y < 16.0f ) return AltitudeBand::High;
    return AltitudeBand::Danger;
}

}   // namespace flight
