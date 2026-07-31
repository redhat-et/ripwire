// game/player.cpp — violation 1: game layer includes infra layer header.
#include "../infra/allocator.h"

void spawnPlayer()
{
    void* mem = arenaAlloc( 256 );
    (void)mem;
}
