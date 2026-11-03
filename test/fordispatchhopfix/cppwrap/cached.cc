#include "source.h"
int CachedSource::Fetch( int k )
{
    return inner_->Fetch( k ) + 1;
}
int RunAll() { DiskSource d; CachedSource c; c.inner_ = &d; return c.Fetch( 1 ); }
