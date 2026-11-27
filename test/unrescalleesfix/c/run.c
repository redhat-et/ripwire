#include <string.h>

int local_c( void ) { return 1; }

int run( const char* s )
{
    int n = local_c();
    n += py_only( s );
    n += (int) strlen( s );
    n += shared( n );
    n += shared( n + 1 );
    return n;
}
