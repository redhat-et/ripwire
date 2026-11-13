#pragma once
namespace cells
{
struct Cell { int prefix; int width; int height; };
inline bool cellFits( const Cell& q, int prefix )
{
    return q.prefix == prefix ? q.width > 0 && q.width < 9 : ( q.height > prefix ? q.height - prefix > 1 : q.height + prefix < 7 );
}
}
