#pragma once
struct FileReader
{
    virtual ~FileReader() {}
    virtual int ReadFile( int k ) = 0;
};
namespace a
{
struct Reader : FileReader
{
    Reader();
    int ReadFile( int k ) override;
};
}   // namespace a
namespace b
{
struct Reader
{
    int fd = 0;
};
}   // namespace b
