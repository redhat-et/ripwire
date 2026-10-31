#include "disk.h"
#include "build.h"
int main() { RealDisk d; Builder b{ &d }; return b.Run( 4 ); }
