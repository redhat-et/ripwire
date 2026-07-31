// deadfix/deadfix.h — gate fixture for S5-A --dead-code detection.
//
// exportedApi() is defined HERE (in a header). Even though nothing in THIS tree calls it,
// it MUST NOT appear in --dead-code because it is header-defined (= potentially exported to
// callers outside the indexed tree). This is the key export-exclusion heuristic.

#pragma once

// Header-defined symbol: exported, must never be flagged dead regardless of local call count.
inline int exportedApi( int x )
{
    return x * 3;
}
