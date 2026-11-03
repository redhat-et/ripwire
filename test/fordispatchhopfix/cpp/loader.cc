#include "source.h"
int Clamp( int v ) { return v > 100 ? 100 : v; }
struct Loader
{
    Source* src_;
    explicit Loader( Source* s ) : src_( s ) {}
    int Load( int k );
};
int Loader::Load( int k )
{
    int v = src_->Fetch( k );
    return Clamp( v + 1 );
}
int DiskSource::Fetch( int k ) { return k * 2; }
int NetSource::Fetch( int k ) { return k * 3; }
