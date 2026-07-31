// infra/allocator.h — a low-level infra header.
// Lives in the infra layer; game-layer files must not include this.
#pragma once

void* arenaAlloc( unsigned size );
void  arenaReset();
