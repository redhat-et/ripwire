#pragma once
struct Source
{
    virtual ~Source() {}
    virtual int Fetch( int k ) = 0;
};
struct DiskSource : Source
{
    int Fetch( int k ) override { return k * 2; }
};
struct CachedSource : Source
{
    Source* inner_;
    int Fetch( int k ) override;
};
