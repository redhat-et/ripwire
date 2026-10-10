#include <stddef.h>

struct ops
{
    size_t ( *size )( struct ops* );
};

size_t size( struct ops* o ) { return 0; }

size_t viaPointer( struct ops* o ) { return o->size( o ); }
