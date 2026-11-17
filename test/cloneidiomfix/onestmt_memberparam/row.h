#pragma once
// one-statement fixture: both members read a MEMBER `prefix` and take a PARAMETER `prefix`. The member is
// shared vocabulary even though a parameter is spelled the same, so the pair keeps gating.
namespace rows
{
struct Row { int prefix; int count; int depth; };
inline bool rowFits( const Row& r, int prefix )
{
    return r.prefix == prefix ? r.count > 0 && r.count < 9 : ( r.depth > prefix ? r.depth - prefix > 1 : r.depth + prefix < 7 );
}
}
