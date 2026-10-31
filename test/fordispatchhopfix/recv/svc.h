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
struct NetSource : Source
{
    int Fetch( int k ) override { return k * 3; }
};
struct Cache
{
    virtual ~Cache() {}
    virtual int Fetch( int k ) = 0;
};
struct LruCache : Cache
{
    int Fetch( int k ) override { return k - 1; }
};
struct ArcCache : Cache
{
    int Fetch( int k ) override { return k - 2; }
};
