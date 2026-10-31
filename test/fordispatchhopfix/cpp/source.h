#pragma once
struct Source
{
    virtual ~Source() {}
    virtual int Fetch( int k ) = 0;
};
struct DiskSource : Source
{
    int Fetch( int k ) override;
};
struct NetSource : Source
{
    int Fetch( int k ) override;
};
