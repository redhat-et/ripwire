#pragma once

struct Point
{
    double x;
    double y;
};

double area_of_triangle( double base, double height );
double perimeter( const Point* pts, int n );
Point  scale_point( Point p, double k );
double distance( Point a, Point b );
