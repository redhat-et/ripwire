#include "pg_store.h"
int PgStore::Get( int k )
{
    int row = k + 1000;
    return row;
}
Store* MakePgStore() { return new PgStore(); }
