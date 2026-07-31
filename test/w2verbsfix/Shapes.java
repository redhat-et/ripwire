// Shapes.java — Wave-2 cross-verb fixture (w2verbscheck.sh). Hand-counted metrics below.
//
// leaf(x):          1 param, 0 nesting, 0 calls, loc=4
// deepNest(a,b,c):  3 params, 3-deep nesting (if > for > if), calls nothing in-repo, loc=14, ccx=6
// callsBoth(x):     1 param, 0 nesting, calls leaf()+deepNest() -> cbo=2, loc=4
//
// Values below were measured by running `ripwire test/w2verbsfix --metrics` and reading the
// output before being pinned as assertions in w2verbscheck.sh (house style: hand-verify, don't guess).

class Shapes
{
    int leaf( int x )
    {
        return x + 1;
    }

    int deepNest( int a, int b, int c )
    {
        if ( a > 0 )
        {
            for ( int i = 0; i < b; i++ )
            {
                if ( c > 0 )
                {
                    return a + b + c;
                }
            }
        }
        return 0;
    }

    int callsBoth( int x )
    {
        return leaf( x ) + deepNest( x, x, x );
    }
}
