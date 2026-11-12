#pragma once
namespace geo
{
struct Site { int path; int line; int col; };
inline bool siteBefore( const Site& a, const Site& b )
{
    EXPECTS( a.path >= 0 );
    return a.path != b.path ? a.path < b.path : ( a.line != b.line ? a.line < b.line : a.col < b.col );
}
}
