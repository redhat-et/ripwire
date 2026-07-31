// usesfix/store.h — ABS-3 use-site index gate fixture (declarations + a base class for `extends`).
//
// Base is the EXTENDS target: Widget derives from it (store.cpp). compute() is the CALL target.
// counter is a free function that is CALLED, and tally is the int that is both READ and WRITTEN.

struct Base
{
    int kind = 0;
};

int compute( int x );

int counter();
