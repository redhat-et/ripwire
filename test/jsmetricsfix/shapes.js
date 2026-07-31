// shapes.js — hand-verified metrics fixture for jsmetricscheck.sh (JavaScript side).
// Every function's loc/params/nest/cbo below is counted BY HAND from the source text; the gate
// asserts these exact numbers against --metrics output, so a silent JS-metrics regression (e.g.
// nest/params staying 0 because the JS grammar's node shapes are not recognized) is caught loudly.

// leaf: 1 param, 0 nesting, 0 calls, loc = 4 (signature line through closing brace)
function leaf( a )
{
    return a + 1;
}

// deepNest: 3 params, 3 levels of control nesting (if > for > if), calls nothing in-repo (cbo=0)
function deepNest( a, b, c )
{
    if ( a > 0 )
    {
        for ( let i = 0; i < b; i++ )
        {
            if ( i > c )
            {
                return i;
            }
        }
    }
    return 0;
}

// callsLeafAndDeep: 1 param, 0 nesting, calls leaf() and deepNest() -> cbo=2
function callsLeafAndDeep( x )
{
    leaf( x );
    return deepNest( x, 1, 2 );
}

// arrowWithParams: arrow-fn bound to const, 2 params, 1 level of nesting (if)
const arrowWithParams = ( p, q ) =>
{
    if ( p > q )
    {
        return p;
    }
    return q;
};

module.exports = { leaf, deepNest, callsLeafAndDeep, arrowWithParams };
