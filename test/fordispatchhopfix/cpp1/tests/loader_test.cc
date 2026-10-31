#include "../source.h"
struct FakeSource : Source
{
    int Fetch( int k ) override { return k; }
};
int TestLoad() { FakeSource f; return f.Fetch( 3 ); }
