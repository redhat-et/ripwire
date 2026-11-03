#include "../source.h"
struct FakeA : Source { int Fetch( int k ) override { return k; } };
struct FakeB : Source { int Fetch( int k ) override { return k + 1; } };
int TestLoad() { FakeA a; FakeB b; return a.Fetch( 1 ) + b.Fetch( 2 ); }
