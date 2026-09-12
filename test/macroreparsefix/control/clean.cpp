// test/macroreparsecheck.sh control — a clean C++ file (its first parse has no error), so the member-macro
// re-parse never runs and every output must be byte-identical to the pre-change binary.
#include <vector>

struct Tollbooth
{
    int lanes = 0;

    int openLanes( int closed ) const
    {
        if( closed >= lanes )
        {
            return 0;
        }
        return lanes - closed;
    }
};

int totalToll( const std::vector<int>& fares )
{
    int total = 0;
    for( int fare : fares )
    {
        if( fare > 0 )
        {
            total += fare;
        }
    }
    return total;
}
