// test/extentcheck.sh fixture — a clean file beside the suspect ones: nothing here may be flagged, and
// --hotspots must rank it on its full complexity.
int scoreWindow( int lo, int hi, int value )
{
    if( value < lo )
    {
        return -1;
    }
    if( value > hi )
    {
        return 1;
    }
    return 0;
}

struct Meter
{
    int reading = 0;

    void bump( int by )
    {
        if( by > 0 )
        {
            reading += by;
        }
    }
};
