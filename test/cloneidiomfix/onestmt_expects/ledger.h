#pragma once
namespace ledger
{
struct Entry { int day; int shift; int slot; };
inline bool entryBefore( const Entry& a, const Entry& b )
{
    return ( a.day - b.day ) * 4 + ( a.shift - b.shift ) * 2 + ( a.slot > b.slot ? 1 : 0 ) - ( a.slot < b.slot ? 1 : 0 ) > 0;
}
}
