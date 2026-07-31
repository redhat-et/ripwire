#pragma once

// Tiny stable C++ corpus for ctxpack regression golden. Has a real call edge (perimeter -> distance)
// so PageRank has something to rank.

struct Point
{
    double x;
    double y;
};

double distance( Point a, Point b );
double perimeter( const Point* pts, int n );
