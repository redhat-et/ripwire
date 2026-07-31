// A test-path file: referencing goodHelper here marks it tested=1 (the ROLE signal for "has a safety net").
#include "lib.cpp"
int test_good() { return goodHelper( 41 ) == 42 ? 0 : 1; }
