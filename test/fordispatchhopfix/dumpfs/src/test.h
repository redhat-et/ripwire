#include "disk.h"
struct VirtualFS : Disk { int ReadFile( int p ) override; };
