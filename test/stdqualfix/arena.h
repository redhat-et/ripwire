// test/stdqualfix — file 6: the same-directory DECOY for polyfill.h's std::__1::launder.

#pragma once

class Arena
{
public:
    void* launder( void* p ) { return p; }
};
