#pragma once
struct Store
{
    virtual ~Store() {}
    virtual int Get( int k ) = 0;
};
Store* MakePgStore();
