#pragma once
namespace order
{
struct Site { int path; int line; int col; };
struct Entry { int day; int shift; int slot; };
inline bool siteBefore( const Site& a, const Site& b )
{
    return ( a.path - b.path ) * 4 + ( a.line - b.line ) * 2 + ( a.col > b.col ? 1 : 0 ) - ( a.col < b.col ? 1 : 0 ) > 0;
}
inline bool entryBefore( const Entry& a, const Entry& b )
{
    return ( a.day - b.day ) * 4 + ( a.shift - b.shift ) * 2 + ( a.slot > b.slot ? 1 : 0 ) - ( a.slot < b.slot ? 1 : 0 ) > 0;
}
}
