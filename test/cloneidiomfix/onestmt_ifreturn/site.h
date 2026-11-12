#pragma once
namespace geo
{
struct Site { int path; int line; int col; };
inline bool siteBefore( const Site& a, const Site& b )
{
    if( a.path != b.path ) return a.path < b.path;
    return a.line != b.line ? a.line < b.line : a.col < b.col;
}
}
