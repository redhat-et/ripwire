#pragma once
#include "source.h"
struct ScriptedSource : Source
{
    int next_ = 0;
    int Fetch( int k ) override { return k + next_++; }
};
