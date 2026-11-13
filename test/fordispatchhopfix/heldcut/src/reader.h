#pragma once
struct FileReader
{
    virtual ~FileReader() {}
    virtual int ReadFile( int k ) = 0;
};
struct LongReader : FileReader
{
    LongReader();
    int ReadFile( int k ) override;
};
