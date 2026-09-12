template <typename T> int cppDeclined( T& t )
{
    return t.crender();
}

template <typename T> int cppUnique( T& t )
{
    return t.conly();
}

int cppExternal()
{
    return find( 3 );
}

int cppUnresolved()
{
    return cross_only();
}
