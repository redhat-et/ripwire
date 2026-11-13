#include "../src/reader.h"
struct FakeReader : FileReader
{
    int ReadFile( int k ) override { return k; }
};
int TestReadFile()
{
    RealReader inTest;
    FakeReader fake;
    return inTest.ReadFile( 2 ) + fake.ReadFile( 3 );
}
