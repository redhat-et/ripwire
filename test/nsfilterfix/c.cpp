// The base-clause arm: `Handler` here can ONLY be the class. A candidate filter keyed on the
// reference's namespace must never offer the free function here.
#include "a.h"

class Derived : public Handler
{
public:
    void step();
};

void Derived::step()
{
}
