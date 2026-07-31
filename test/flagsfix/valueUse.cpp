// valueUse.cpp — the `if constexpr` sites the VALUE-STYLE gates govern. One branch per child gate, each
// calling a helper defined elsewhere so the flip's downstream (what the newly-live code starts executing)
// is a real call edge and not an empty set.
#include "valueGates.h"

int waveHelper();
int turnHelper();

int valueEntry()
{
    int n = 0;
    if constexpr ( fixval::kWave )  { n += waveHelper(); }
    if constexpr ( fixval::kTurns ) { n += turnHelper(); }
    return n;
}
