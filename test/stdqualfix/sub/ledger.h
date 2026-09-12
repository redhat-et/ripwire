// test/stdqualfix — file 9: the second `exchange` def, in another directory, never included by
// exchange_user.cpp. Its only job is to make the name K=2 so Rule 3 is eligible to fire.

#pragma once

class Ledger
{
public:
    int exchange( int next ) { int was = total; total = next; return was; }
    int total = 0;
};
