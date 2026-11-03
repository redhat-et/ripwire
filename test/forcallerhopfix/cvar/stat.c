#include "stat.h"
int probe_limit = 3;
int probe_stat( const char* p ) { return p ? probe_limit : 0; }
