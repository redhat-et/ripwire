#pragma once
// one-statement fixture: a three-key comparator. Its twin (ledger.h) shares NOT ONE identifier with it
// beyond the parameter names `a` and `b`, which condition (2) leaves out for this idiom.
namespace geo
{
struct Site { int path; int line; int col; };
inline bool siteBefore( const Site& a, const Site& b )
{
    return a.path != b.path ? a.path < b.path : ( a.line != b.line ? a.line < b.line : a.col + kOrderSlack < b.col );
}
}
