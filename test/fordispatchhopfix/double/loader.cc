#include "source.h"
struct Loader
{
    Source* src_;
    int Load( int k );
};
int Loader::Load( int k )
{
    int v = src_->Fetch( k );
    return v + 1;
}
int DiskSource::Fetch( int k )
{
    int doubled = k * 2;
    return doubled;
}
