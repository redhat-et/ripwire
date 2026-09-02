// fieldusesfix/shapes.cpp — the member use-sites fieldusescheck.sh asserts. LINE NUMBERS ARE LOAD-BEARING:
// every assertion pins role + exact line, so never insert or remove a line above a use-site without
// re-deriving the gate.
#include "shapes.h"
#include <cstdio>

int count = 0;                    // line 7: a file-scope GLOBAL named like the fields (nonlocal-state precision probe)

void Counter::bump()
{
    count += step;                // line 11: Counter.count WRITE (compound; bare, inside the owner) · Counter.step READ
    this->count++;                // line 12: Counter.count WRITE (this->, update)
}

void Counter::set( int count )
{
    this->count = count;          // line 17: Counter.count WRITE (this->); the bare `count` is the PARAMETER, never the field
}

int Counter::peek() const
{
    return count;                 // line 22: Counter.count READ (bare, inside the owner)
}

void Gauge::fill( double amount )
{
    level = level + amount;       // line 27: Gauge.level WRITE and READ
    count = 0;                    // line 28: Gauge.count WRITE (bare, inside the owner — NOT Counter.count)
}

void Gauge::relay()
{
    inner.count = 3;              // line 33: Counter.count WRITE — receiver `inner` is a Gauge FIELD of type Counter (Rule 2b)
}

void reset( Counter& c, Gauge* g )
{
    c.count = 0;                  // line 38: Counter.count WRITE — `c` is a typed parameter (Counter&)
    g->count = 0;                 // line 39: Gauge.count WRITE — `g` is a typed parameter (Gauge*)
    c.label = nullptr;            // line 40: Counter.label WRITE
    int* alias = &c.count;        // line 41: Counter.count READ (address-of is a READ; the write is NOT claimed)
    *alias = 5;                   // line 42: THE KNOWN MISS — a write through the alias names no field (no alias analysis)
    std::printf( "%d", g->level > 0 ? 1 : 0 );   // line 43: Gauge.level READ
}

int total( const Counter& a, const Gauge& b )
{
    return a.count + b.count;     // line 48: Counter.count READ (via a) · Gauge.count READ (via b)
}

template< class T >
int untyped( T& x )
{
    return x.count;               // line 54: x's type is unknown → BOTH owners are candidates → amb="2"
}

void reset_global()
{
    count = 7;                    // line 59: the GLOBAL `count` WRITE — a free function, no owner → never a field use-site
}
