// kills.cpp — sliceflowsensfix, the KILL class (C++): between an earlier def of x and the use stands a later
// def of x on every path, an exit that never reaches the use, or a sibling branch. The expected reaching
// definitions of every use row live in expect.tsv, written before the flow-sensitive walk existed.
void sink( int v );
int  fetch( int a );

int ck01( int a )
{
    int x = a;
    x = 5;
    return x;
}

int ck02( int a )
{
    int x = 1;
    if( a > 0 )
    {
        x = 2;
        return x;
    }
    return x;
}

int ck03( int a )
{
    int x = 1;
    if( a > 0 )
    {
        x = 2;
    }
    else
    {
        sink( x );
    }
    return x;
}

int ck04( int a )
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
    return x;
}

int ck05( int a )
{
    int x = 1;
    while( a > 0 )
    {
        x = a;
        sink( x );
        a = a - 1;
    }
    return x;
}

int ck06( int a )
{
    int x = 1;
    for( int i = 0; i < a; ++i )
    {
        sink( x );
        x = i;
        x = i + 1;
    }
    return x;
}

int ck07( int a )
{
    int x = 1;
    switch( a )
    {
        case 1:
            x = 2;
            break;
        case 2:
            x = 3;
            break;
        default:
            x = 4;
            break;
    }
    return x;
}

int ck08( int a )
{
    int x = 1;
    if( a < 0 )
    {
        x = 2;
        throw a;
    }
    return x;
}

int ck09( int a )
{
    int x = 1;
    do
    {
        x = a;
        a = a - 1;
    } while( a > 0 );
    return x;
}

int ck10( int a )
{
    int x = 1;
    if( a > 0 )
    {
        x = 2;
    }
    x = 3;
    return x;
}
