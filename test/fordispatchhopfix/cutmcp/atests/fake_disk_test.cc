#include "../src/disk.h"
struct FakeDisk : Disk { int ReadFile( int p ) override; };
int FakeDisk::ReadFile( int p ) { return p; }
