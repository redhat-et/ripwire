#include "source.h"
int RunAll() { DiskSource disk; return disk.Fetch( 1 ); }
int main() { return RunAll(); }
