#include "../cch.h"
struct Arc : Cch { int F( int k ) override { return k * 4; } };
void TestArc() { Arc a; a.F( 1 ); }
