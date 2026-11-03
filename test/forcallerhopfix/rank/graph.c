/* forcallerhopfix/rank — UPWARD-2HOP fixture: an error-shaped task ranks a narrow-funnel function (verify_dag, one caller). */
#include <stdio.h>

void report_problem( const char* what )
{
    fprintf( stderr, "%s\n", what );
}

int verify_dag( int node )
{
    if( node < 0 )
    {
        report_problem( "dependency cycle detected" );
        return 0;
    }
    return 1;
}

int recompute_node( int node )
{
    return verify_dag( node );
}

int recompute_dirty( int node )
{
    return recompute_node( node );
}

int recompute_edges( int node )
{
    return recompute_node( node + 1 );
}
