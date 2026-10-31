#pragma once
struct Source
{
    virtual ~Source() {}
    virtual int Fetch( int k ) = 0;
};
