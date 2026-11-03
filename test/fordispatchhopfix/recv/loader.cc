#include "svc.h"
struct Loader
{
    Source* src_;
    Cache*  cache_;
    int Load( int k );
};
int Loader::Load( int k )
{
    int a = src_->Fetch( k );
    int b = cache_->Fetch( k );
    return a + b;
}
int main() { DiskSource d; NetSource n; LruCache l; ArcCache c; Loader x{ &d, &l }; return x.Load( 1 ); }
