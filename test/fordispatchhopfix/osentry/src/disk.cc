#include "disk.h"
#include "build.h"
int RealDisk::ReadFile( int p ) { return p * 7 + 1; }
int ENTRY() { RealDisk d; Builder b{ &d }; return b.Run( 4 ); }
