/* test/extentcheck.sh fixture — the signature-swallow shape, spelled as LEGAL C so the parse is clean.
 * The struct is defined inside the function's return type, so the struct symbol lies in the function's
 * SIGNATURE span (between the start of its definition and its body). That is the node shape a derailed
 * C++ parse produces when a struct body swallows code and closes on a later function's brace; here it
 * is written on purpose, with no parse error, so the rule is exercised without error recovery. Every
 * function in this file is suspect, which is what --hotspots' unranked_extent_suspect= arm needs. */
struct Point
{
    int x;
    int y;
} makePoint( int x, int y )
{
    struct Point p;
    p.x = x;
    p.y = y;
    if( x < 0 )
    {
        p.x = 0;
    }
    return p;
}
