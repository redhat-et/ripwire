#include "geometry.h"

#include <cmath>

double area_of_triangle( double base, double height )
{
    return 0.5 * base * height;
}

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
        total += distance( pts[i], pts[( i + 1 ) % n] );
    }
    return total;
}

Point scale_point( Point p, double k )
{
    return Point{ p.x * k, p.y * k };
}
