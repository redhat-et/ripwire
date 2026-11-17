#pragma once
namespace geo
{
struct Site { int path; int line; int col; };
inline bool siteBefore( const Site& a, const Site& b )
{
    if( a.path != b.path ) { return a.path > b.path; }
    return ( a.line - b.line ) * 2 + ( a.col > b.col ? 1 : 0 ) - ( a.col < b.col ? 1 : 0 ) > 0;
}
}
