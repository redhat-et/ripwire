#pragma once
#include <outside/factory.h>

struct Base
{
    virtual const char* render() { return "base"; }
};

struct Widget
{
    const char* render() { return "widget"; }
};
