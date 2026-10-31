#pragma once
#include "store.h"
struct PgStore : Store
{
    int Get( int k ) override;
};
