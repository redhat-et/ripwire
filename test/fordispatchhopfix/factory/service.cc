#include "store.h"
#include "mem_store.h"
struct Service
{
    Store* store_;
    int Lookup( int k );
};
int Service::Lookup( int k )
{
    int v = store_->Get( k );
    return v + 1;
}
int main( int argc, char** )
{
    Service s;
    MemStore mem;
    s.store_ = argc > 1 ? MakePgStore() : &mem;
    return s.Lookup( 1 );
}
