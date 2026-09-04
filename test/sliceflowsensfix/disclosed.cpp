// disclosed.cpp — sliceflowsensfix, the DISCLOSED-CONSTRUCT class (C++): shapes the walk does NOT branch
// on, each stated per construct in the legend; the expectation encodes the disclosed behaviour, not the
// language's truth. Expectations: expect.tsv.
int cd01( int a )
{
    int x = 1;
    a > 0 && ( x = 2 );
    return x;
}

int cd02( int a )
{
    int x = 1;
    auto bump = [ & ] { x = 2; };
    bump();
    return x;
}

int cd03( int a )
{
    int x = 1;
    goto done;
    x = 2;
done:
    return x;
}

int cd04( int a )
{
    int x = 1;
    int& alias = x;
    alias = 2;
    return x;
}

int cd05( int a )
{
    int x = 1;
    a > 0 ? ( x = 2 ) : ( x = 3 );
    return x;
}
