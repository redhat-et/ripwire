// A.java — Java ingest fixture for javarubycheck.sh.
// One class with two methods where addTwo() calls addOne() → one intra-file call edge
// addTwo -> addOne.

class A
{
    int addOne( int x )
    {
        return x + 1;
    }

    int addTwo( int x )
    {
        return addOne( addOne( x ) );
    }
}
