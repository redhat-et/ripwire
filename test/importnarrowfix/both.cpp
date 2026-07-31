// importnarrowfix/both.cpp — NEGATIVE control 2. Includes BOTH a.h and b.h and calls helper().
// Two distinct INCLUDED files each define helper → the include set does NOT disambiguate → Rule 3
// bails (≥2 candidate files) → the call stays HONESTLY AMBIGUOUS (amb=1). Proves Rule 3 fires ONLY
// on an exactly-one-included-file match, never on a both-included tie (a wrong narrow avoided).
#include "a.h"
#include "b.h"

int callBoth()
{
    return helper();   // both a.h and b.h included → ≥2 candidate files → Rule 3 bails → stays AMBIGUOUS
}
