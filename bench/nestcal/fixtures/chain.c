int chain( int v )
{
    if( v == 1 ) { return 10; }
    else if( v == 2 ) { return 20; }
    else if( v == 3 ) { return 30; }
    else if( v == 4 ) { return 40; }
    else { return 0; }
}
int elsefor( int v )
{
    if( v ) { return 1; }
    else
    {
        for( int i = 0; i < v; ++i ) { v += i; }
        return v;
    }
}
