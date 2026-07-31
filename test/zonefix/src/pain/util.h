#pragma once
// pain/util.h — concrete, no abstract types, no outgoing deps, heavily depended-on (by consumer,
// balanced, and useless -> Ca=3).
// Intended metrics: Ca=3 Ce=0 -> I=0.00; totalTypes=1 abstractTypes=0 -> A=0.00; D=|0+0-1|=1.00 -> zone=pain.

struct Util
{
    int add( int a, int b ) { return a + b; }   // has a body -> NOT abstract
};
