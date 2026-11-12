#pragma once
namespace order
{
struct Site { int path; int line; int col; };
struct Entry { int day; int shift; int slot; };
inline bool siteBefore( const Site& a, const Site& b )
{
    return a.path != b.path ? a.path < b.path : ( a.line != b.line ? a.line < b.line : a.col < b.col );
}
inline bool entryBefore( const Entry& a, const Entry& b )
{
    return a.day != b.day ? a.day < b.day : ( a.shift != b.shift ? a.shift < b.shift : a.slot < b.slot );
}
}
