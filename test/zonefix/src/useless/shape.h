#pragma once
// useless/shape.h — a pure abstract interface that depends on pain/util.h but nothing depends on IT
// (deliberately not included by consumer or anyone else in this fixture).
// Intended metrics: Ca=0 Ce=1 -> I=1.00; totalTypes=1 abstractTypes=1 (pure-virtual method, no body)
// -> A=1.00; D=|1+1-1|=1.00 -> zone=useless (A+I=2.0 >= 1.0 -> useless branch).
#include "../pain/util.h"

struct Shape
{
    virtual double area() = 0;   // no body -> abstract method -> Shape counts as an abstract type
};
