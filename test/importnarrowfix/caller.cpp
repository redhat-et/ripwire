// importnarrowfix/caller.cpp — POSITIVE case. #includes ONLY a.h and calls bare helper().
// helper is ambiguous (a.h::helper AND b.h::helper) under the bare §2a ladder, but this file
// includes exactly ONE of the two defining files (a.h) → Rule 3 narrows the call to a.h::helper
// ONLY (amb=0 for this call). A free function has no enclosing scope, so Rule 1 cannot fire —
// the resolution is Rule 3's alone.
#include "a.h"

int callIncludedOnly()
{
    return helper();   // Rule 3: caller includes ONLY a.h → resolves to a.h::helper, drops b.h::helper
}
