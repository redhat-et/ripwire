#pragma once

// A C++ struct: a call spelled with its name constructs it.
struct Point {
    int x;
    explicit Point( int v ) : x( v ) {}
};
