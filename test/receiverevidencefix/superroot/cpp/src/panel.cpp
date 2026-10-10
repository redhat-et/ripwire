#include "shapes.h"

struct Panel : Base
{
    const char* typed()
    {
        Widget base;
        return base.render();
    }

    const char* untyped()
    {
        auto base = outside::make();
        return base.render();
    }
};
