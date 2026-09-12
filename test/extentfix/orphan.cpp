// test/extentcheck.sh fixture — the dissolved-container shape. Tally's body is never closed, so
// tree-sitter-cpp folds the whole file into one ERROR region: the struct itself is not extracted, and
// every function after it comes out as a `method` row with NO scope — a member of a class that does
// not exist. Nothing in the extents contradicts itself here; only the recovery says the kind is a guess.
struct Tally
{
    int count = 0;
    void add( int n )
    {
        count += n;
    }

int standalone( int v )
{
    if( v > 0 )
    {
        return v;
    }
    return -v;
}

void another( int &x )
{
    if( x < 0 )
    {
        x = 0;
    }
}
