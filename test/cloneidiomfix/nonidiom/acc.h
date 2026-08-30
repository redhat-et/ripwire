#pragma once
// A real duplicated body that is NOT one of the three recognized idioms: disjoint identifiers, different
// files, different namespaces — every demotion precondition EXCEPT the shape. It must keep gating.
namespace one
{

inline int accumulateWeights( const int* weights, int count )
{
    int total = 0;
    for( int i = 0; i < count; ++i )
    {
        total += weights[i];
        total ^= ( total << 1 );
        total -= i;
    }
    return total;
}

}   // namespace one
