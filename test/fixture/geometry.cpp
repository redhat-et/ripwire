#include "geometry.h"
#include <cmath>

double distance( Point a, Point b )
{
    const double dx = a.x - b.x;
    const double dy = a.y - b.y;
    return std::sqrt( dx * dx + dy * dy );
}

double perimeter( const Point* pts, int n )
{
    double total = 0.0;
    for( int i = 0; i < n; ++i )
    {
        total += distance( pts[i], pts[ ( i + 1 ) % n ] );   // edge: perimeter -> distance
    }
    return total;
}
