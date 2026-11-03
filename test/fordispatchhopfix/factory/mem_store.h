#pragma once
#include "store.h"
struct MemStore : Store
{
    int Get( int k ) override
    {
        int cached = k * 7;
        return cached;
    }
};
