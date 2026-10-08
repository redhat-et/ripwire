#pragma once
#include <ostream>

// Plain inherits flush() from an OUTSIDE class.
class Plain : public std::ostream {
public:
    void finish();
};
