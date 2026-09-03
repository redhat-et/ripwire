#include "lib.h"

int runOne( int a )
{
    return scale( a, 2 ) + trim( a, a ) + clampLow( a );
}

int runTwo( int a )
{
    Box b;
    return b.width( a ) + b.height();
}
