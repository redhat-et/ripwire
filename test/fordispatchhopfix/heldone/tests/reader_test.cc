#include "../src/reader.h"
struct FakeReader : FileReader
{
    int ReadFile( int k ) override { return k; }
};
bool ReaderPassesThrough()
{
    RealReader inTest;
    FakeReader fake;
    const int real = inTest.ReadFile( 2 );
    const int stub = fake.ReadFile( 3 );
    return real == 3 && stub == 3;
}
