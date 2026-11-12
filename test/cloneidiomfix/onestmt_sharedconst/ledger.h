#pragma once
namespace ledger
{
struct Entry { int day; int shift; int slot; };
inline bool entryBefore( const Entry& a, const Entry& b )
{
    return a.day != b.day ? a.day < b.day : ( a.shift != b.shift ? a.shift < b.shift : a.slot + kOrderSlack < b.slot );
}
}
