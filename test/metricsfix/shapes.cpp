// metricsfix — a tiny, STABLE corpus with hand-verifiable Q-compute metrics (loc/params/nest/cbo/lcom4).
// Every function here has a known line span, parameter count, nesting depth, and in-repo callee set so
// test/metricscheck.sh can assert the emitted --metrics attributes against the source by hand. Do NOT
// reformat: the line numbers are load-bearing for the loc= assertions.

// leaf(): 3 physical lines (this line..the closing brace), 2 params, nest 0, no in-repo callee → cbo 0.
double leaf( double a, double b )
{
    return a * b + a - b;
}

// nested3(): a triple-nested control body — max nesting depth 3. 1 param. Calls leaf() (1 in-repo callee → cbo 1).
double nested3( int n )
{
    double total = 0.0;
    for( int i = 0; i < n; ++i )
    {
        if( i % 2 == 0 )
        {
            while( total < 100.0 )
            {
                total += leaf( double( i ), double( n ) );   // depth-3 body: for > if > while
            }
        }
    }
    return total;
}

// A class with two methods that SHARE the m_count field AND call each other → LCOM4 = 1 (one component).
class Counter
{
public:
    void bump( int by )
    {
        m_count += by;          // writes the shared field m_count
    }
    int total( int extra )
    {
        bump( extra );          // calls the sibling method bump()
        return m_count;         // reads the shared field m_count
    }
private:
    Counter* m_self;            // a typed-class member (compose edge) so captureFields sees a field
    int      m_count;
};
