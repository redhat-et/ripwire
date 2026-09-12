// test/stdqualfix — file 8: one of TWO `exchange` defs (the other is sub/ledger.h). exchange_user.cpp
// includes only this header, which is exactly what Rule 3 (the include-file narrow) keys on.

#pragma once

class Token
{
public:
    int exchange( int next ) { int was = id; id = next; return was; }
    int id = 0;
};
