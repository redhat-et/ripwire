#include "test.h"
int VirtualFS::ReadFile( int p ) { return 0; }
int DumpFs() { VirtualFS v; return v.ReadFile( 3 ); }
