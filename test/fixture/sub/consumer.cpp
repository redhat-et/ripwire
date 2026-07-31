#include "../geometry.h"

// Cross-dir caller: `distance` is DECLARED in ../geometry.h and DEFINED in ../geometry.cpp, and this file
// is in a different directory from both. Before the decl/def-collapse fix this call resolved to TWO
// candidates (decl + def) with no same-file/dir winner → tier-3 dropped it (edge vanished). It must now
// resolve to the geometry.cpp definition. This is the regression guard for adversarial-review fix #1.

double diagonal( Point a, Point b )
{
    return distance( a, b );
}
