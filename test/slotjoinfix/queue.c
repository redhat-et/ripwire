#include "ops.h"
int fire_command( const struct cmd_ent *entry, int a )
{
    return entry->exec( (struct cmd_ent *)entry, a );
}
int fire_other( struct other *o )
{
    return o->exec( 1 );
}
int fire_cast( void *p )
{
    return ( (struct other *)p )->exec( 2 );
}
int fire_scalar( long w )
{
    return (int)w;
}
