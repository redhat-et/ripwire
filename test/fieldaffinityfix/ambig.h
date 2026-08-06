// The AMBIGUITY case. `slot` is declared by TWO aggregates, so a bare `q->slot` names a field this
// module cannot attribute to either one without a points-to analysis it deliberately does not have
// (Chilimbi PLDI 1999 approximates a structure instance as a <function, struct type> pair and concedes
// the approximation; ripwire refuses the guess instead and counts the refusal). Every such access must
// be SKIPPED and tallied into amb_skipped= — an under-count, never a mis-attribution.
#pragma once

#include <cstdint>

struct LeftBox
{
    std::uint64_t slot;
    std::uint64_t leftOnly;
};

struct RightBox
{
    std::uint64_t slot;
    std::uint64_t rightOnly;
};
