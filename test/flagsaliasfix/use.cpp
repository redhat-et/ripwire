#include "aliases.h"

#if ALIASFIX_WALLS
int wallsFeature()
{
    return 1;
}
#endif

#if ALIASFIX_TURNS
int turnsFeature()
{
    return 2;
}
#endif
