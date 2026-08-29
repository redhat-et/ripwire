#pragma once
// An enum -> string switch name table. Every arm is a label plus a literal return; no other statement.
namespace paint
{

enum class Hue : unsigned char { Red, Green, Blue, Amber, Slate };

inline const char* hueName( Hue h )
{
    switch( h )
    {
        case Hue::Red:   return "red";
        case Hue::Green: return "green";
        case Hue::Blue:  return "blue";
        case Hue::Amber: return "amber";
        case Hue::Slate: return "slate";
    }
    return "unknown";
}

}   // namespace paint
