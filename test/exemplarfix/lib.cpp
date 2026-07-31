// exemplarfix — a tiny, STABLE corpus for test/exemplarcheck.sh. Two same-kind (free function)
// siblings, one clearly BEST-IN-CLASS by ROLE: high fan-in (called by many), low cognitive
// complexity, and referenced from a test file (tested=1). The other is a worse sibling: no
// callers, deeply nested (high ccx), untested. --exemplar=fn must pick `goodHelper`, never `messyHelper`.
// Do NOT reformat: line spans are load-bearing for the loc/ccx used in the tie-break.

// goodHelper: clean, no nesting → low ccx. Called by four callers below → high fan-in.
int goodHelper( int x )
{
    return x + 1;
}

// messyHelper: deeply nested control flow → high cognitive complexity. No caller → fan-in 0.
int messyHelper( int x )
{
    int acc = 0;
    for( int i = 0; i < x; ++i )
    {
        if( i % 2 == 0 )
        {
            while( acc < i )
            {
                if( acc > 3 )
                {
                    acc += i;
                }
                acc += 1;
            }
        }
    }
    return acc;
}

// four callers of goodHelper → fan-in 4 (>> messyHelper's 0)
int callerA( int n ) { return goodHelper( n ); }
int callerB( int n ) { return goodHelper( n ) + goodHelper( n ); }
int callerC( int n ) { return goodHelper( n * 2 ); }
int callerD( int n ) { return goodHelper( n - 1 ); }
