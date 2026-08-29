#pragma once
// The same name-table idiom, different domain, no shared non-keyword identifier with paint::hueName.
namespace show
{

enum class Phase : unsigned char { Intro, Rise, Peak, Coda, Bows };

inline const char* phaseName( Phase p )
{
    switch( p )
    {
        case Phase::Intro: return "intro";
        case Phase::Rise:  return "rise";
        case Phase::Peak:  return "peak";
        case Phase::Coda:  return "coda";
        case Phase::Bows:  return "bows";
    }
    return "unlisted";
}

}   // namespace show
