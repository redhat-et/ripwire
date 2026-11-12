#pragma once
namespace geo
{
struct Site { int path; int line; int col; };
inline bool siteBefore( const Site& a, const Site& b )
{
    return ( a.path - b.path ) * 4 + ( a.line - b.line ) * kOrderSlack + ( a.col > b.col ? 1 : 0 ) - ( a.col < b.col ? 1 : 0 ) > 0;
}
}
