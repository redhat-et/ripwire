#include "lib.h"

int trim( int a, int b )
{
    return a < b ? a : b;
}

int clampLow( int v )
{
    return v < 0 ? 0 : v;
}

int blend( int a, int b, int c )
{
    return trim( a, b ) + clampLow( c );
}
