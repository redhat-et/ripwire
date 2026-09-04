// straight.cpp — sliceflowsensfix, the STRAIGHT-LINE control class (C++): no branch, no loop, no exit —
// the flow-sensitive answer must equal the source-order one. Expectations: expect.tsv.
void sink( int v );

int cs01( int a )
{
    return a;
}

int cs02( int a )
{
    int x = a + 1;
    sink( x );
    return x;
}

int cs03( int a )
{
    int x = 1;
    x += a;
    x += 2;
    return x;
}

int cs04( int a )
{
    int x;
    x = a;
    int y = x * 2;
    return y + x;
}

int cs05( int a )
{
    int x = a;
    sink( x
          + 1 );
    return x;
}
