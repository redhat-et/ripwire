// The guard arm that Call must stay UN-narrowed. `Handler( 3 )` is a call whose name is carried by
// BOTH a class and a function; in C++ that spelling is legitimately a constructor call, a functional
// cast, or a free function, so the resolver must keep every candidate rather than pick a namespace.
#include "a.h"

int useHandler()
{
    return Handler( 3 );
}

void useMember()
{
    Handler h;
    h.go();
}
