// A C library with extern "C" exports, reachable from Python via ctypes.
// ctxpack A4-R5 should link user.py's `lib.clib_scale(...)` to clib_scale here.

static double clib_helper( double x )
{
    return x * 0.5;
}

extern "C"
{
    double clib_scale( double x )
    {
        return clib_helper( x ) * 10.0;
    }

    int clib_reset( void )
    {
        return 0;
    }
}
