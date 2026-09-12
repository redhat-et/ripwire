// test/stdqualfix — file 10: the RULE-3 arm. `exchange` has two defs; this file includes the one header that
// holds a candidate, so Rule 3 narrows `std::exchange` to Token::exchange and marks the site narrowed — a
// pinned, amb-free edge. Including a header is not evidence about namespace std, so the guard must still
// apply to a narrowed site: the fixed binary refuses it as external.

#include "token.h"

#include <utility>

int rotate( int a, int b )
{
    return std::exchange( a, b );
}
