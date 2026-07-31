// game/world.cpp — violation 2: another game layer file includes the same infra header.
#include "../infra/allocator.h"

void loadWorld( const char* name )
{
    arenaReset();
    (void)name;
}
