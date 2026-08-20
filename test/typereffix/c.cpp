// NEGATIVE CONTROL. Here `Widget` is the name of a LOCAL VARIABLE, never a type. It must produce
// read/write use-sites (which it already did before the type role existed) and never a type role —
// the guard that the widened accept set keys on the NODE KIND and not on the spelling.
#include "a.h"

int localNamedLikeTheType()
{
    int Widget = 3;
    Widget     = Widget + 1;
    return Widget;
}
