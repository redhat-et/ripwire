// connascence-of-position fixture: calls with SAFE arg counts (< 5 args).
// None of these should be flagged.

#include <cstdio>
#include <cstdint>

void setPosition( float x, float y, float z ) {}
void printFormat( const char* fmt, int val ) {}
void configure( int a, int b, int c ) {}
void updateState( int x, int y, int z, int w ) {}

void safe_demo()
{
    // GOOD: 2 args
    printf( "value: %d\n", 42 );

    // GOOD: 3 args
    setPosition( 1.0f, 2.0f, 3.0f );

    // GOOD: 3 args
    printFormat( "%d %d", 10, 20 );

    // GOOD: 4 args
    updateState( 1, 2, 3, 4 );

    // GOOD: 1 arg
    printf( "hello\n" );
}
