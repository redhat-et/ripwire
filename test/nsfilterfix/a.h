// A CLASS named Handler, and (in b.cpp) a free FUNCTION of exactly the same name. The pair is what a
// namespace-compatible candidate filter is supposed to separate: a base-class position can only ever
// mean the class, while a call position `Handler(x)` legitimately means either.
#pragma once

class Handler
{
public:
    void go();
};
