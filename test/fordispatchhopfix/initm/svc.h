#pragma once
struct Source
{
    virtual ~Source() {}
    virtual int Fetch( int k ) = 0;
};
struct DiskSource : Source
{
    int base_ = 0;
    void init( int b );
    int Fetch( int k ) override { return k * 2 + base_; }
};
struct NetSource : Source
{
    int Fetch( int k ) override { return k * 3; }
};
