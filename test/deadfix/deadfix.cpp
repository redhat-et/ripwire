// deadfix/deadfix.cpp — gate fixture for S5-A --dead-code detection.
//
// Three cases to distinguish:
//   (a) orphan()  — defined here, NEVER called by anything in this tree
//                   → must appear in --dead-code (in-degree == 0, defined in a .cpp)
//   (b) worker()  — defined here, CALLED by driver() below
//                   → must NOT appear in --dead-code (has a caller)
//   (c) exported symbols are defined in deadfix.h (see deadfix.h)
//                   → must NOT appear in --dead-code (header-defined = exported)

// A clearly unreachable function — no one calls this in the indexed tree.
// It is not defined in a header, so it has no exported excuse.
static int orphan( int x )
{
    return x * 2 + 1;
}

// A function that IS called (by driver below) — must not be flagged.
static int worker( int a, int b )
{
    return a + b;
}

// A function that calls worker — establishes the in-edge so worker has in-degree > 0.
int driver( int x )
{
    return worker( x, x + 1 );
}
