#include "svc.h"
void DiskSource::init( int b ) { base_ = b; }
struct Loader
{
    Source* src_;
    int Load( int k );
};
int Loader::Load( int k )
{
    return src_->Fetch( k ) + 1;
}
void ResetAllSources( DiskSource& d ) { d.init( 0 ); }
int main() { DiskSource d; NetSource n; ResetAllSources( d ); Loader x{ &n }; return x.Load( 1 ); }
