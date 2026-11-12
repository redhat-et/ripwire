#pragma once
// one-statement fixture: a weighted three-key order. Its twin (ledger.h) shares NOT ONE identifier with it
// beyond the parameter names `a` and `b`, which condition (2) leaves out for this idiom.
namespace geo
{
struct Site { int path; int line; int col; };
inline bool siteBefore( const Site& a, const Site& b )
{
    return ( a.path - b.path ) * 4 + ( a.line - b.line ) * 2 + ( a.col > b.col ? 1 : 0 ) - ( a.col < b.col ? 1 : 0 ) > 0;
}
}
