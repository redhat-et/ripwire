// joins.cpp — sliceflowsensfix, the JOIN class (C++): two or more defs of x reach one use because control
// flow merges before it — an if without else, an else-if chain, a switch without default, a loop's
// back-edge, a try body's handler, a build-dependent #ifdef. Expectations: expect.tsv.
void sink( int v );
int  fetch( int a );

int cj01( int a )
{
    int x = 1;
    if( a > 0 )
    {
        x = 2;
    }
    return x;
}

int cj02( int a )
{
    int x = 1;
    if( a > 0 )
    {
        x = 2;
    }
    else
    {
        x = 3;
    }
    sink( x );
    x = 4;
    return x;
}

int cj03( int a )
{
    int x = 1;
    while( a > 0 )
    {
        sink( x );
        x = a;
        a = a - 1;
    }
    return x;
}

int cj04( int a )
{
    int x = 1;
    for( int i = 0; i < a; ++i )
    {
        sink( x );
        x = i;
    }
    return x;
}

int cj05( int a, int b )
{
    int x = 1;
    if( a > 0 )
    {
        if( b > 0 )
        {
            x = 2;
        }
    }
    return x;
}

int cj06( int a )
{
    int x = 1;
    switch( a )
    {
        case 1:
            x = 2;
            break;
    }
    return x;
}

int cj07( int a )
{
    int x = 1;
    try
    {
        x = fetch( a );
        x = 2;
    }
    catch( ... )
    {
        sink( x );
    }
    return x;
}

int cj08( int a )
{
    int x = 1;
#ifdef FLOWSENS_FIXTURE_OPTION
    x = 2;
#endif
    return x;
}

int cj09( int a )
{
    int x = 1;
    while( a > 0 )
    {
        x = a;
        if( x > 3 )
        {
            break;
        }
        x = 0;
        a = a - 1;
    }
    return x;
}

int cj10( int a )
{
    int x = 1;
    if( a > 0 )
    {
        x = 2;
    }
    else if( a < 0 )
    {
        x = 3;
    }
    return x;
}

int cj11( int a )
{
    int x = 1;
    if( a > 0 )
    {
        x = 2;
    }
    int y = x;
    return y;
}
