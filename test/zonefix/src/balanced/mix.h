#pragma once
// balanced/mix.h — one abstract + one concrete type, both incoming and outgoing deps, so I and A
// land near the main sequence (A+I ~ 1.0 -> D near 0 -> zone=ok). Depends on pain/util.h (Ce=1) and
// is depended on by consumer/main.cpp (Ca=1) -> I = Ce/(Ca+Ce) = 1/2 = 0.50.
// totalTypes=2 (Mixed abstract, Concrete) abstractTypes=1 -> A = 1/2 = 0.50. D=|0.5+0.5-1|=0.00 -> ok.
#include "../pain/util.h"

struct Mixed
{
    virtual void step() = 0;   // no body -> abstract
};

struct Concrete
{
    int value() { return 0; }   // has a body -> not abstract
};
