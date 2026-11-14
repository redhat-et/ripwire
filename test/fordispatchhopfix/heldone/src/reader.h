#pragma once
struct FileReader
{
    virtual ~FileReader() {}
    virtual int ReadFile( int k ) = 0;
};
struct RealReader : FileReader
{
    RealReader();
    int ReadFile( int k ) override;
};
