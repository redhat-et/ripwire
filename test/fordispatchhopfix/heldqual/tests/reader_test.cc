#include "../src/reader.h"
struct FakeReader : FileReader
{
    int ReadFile( int k ) override { return k; }
};
bool FakePassesThrough()
{
    FakeReader fake;
    return fake.ReadFile( 3 ) == 3;
}
