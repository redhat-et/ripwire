#include "stat.h"
int scan_one( void ) { struct probe_stat s; s.n = 0; return probe_stat( "x" ) + s.n; }
