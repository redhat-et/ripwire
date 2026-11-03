/* forcallerhopfix/rankword — UPWARD-2HOP seed fixture: the r=1 narrow funnel names the task's words but holds no message;
   the function that raises the message ("command %d not found") is the next narrow funnel. */
#include <stdio.h>

int command_not_found_hook( int w )
{
    return w + 1;
}

int hook_user( int w )
{
    fputs( "error command\n", stderr );   /* ONE task word plus "error" (never a task word): below the two-word bar */
    return command_not_found_hook( w );
}

int lookup_word( int w )
{
    if( w < 0 )
    {
        fprintf( stderr, "command %d not found\n", w );
        return -1;
    }
    return 0;
}

int run_word( int w )
{
    return lookup_word( w );
}

int main( void )
{
    return hook_user( 1 ) + run_word( 2 );
}
