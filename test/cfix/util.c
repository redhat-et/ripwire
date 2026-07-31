#include "util.h"

struct Point
{
    int x;
    int y;
};

typedef struct Point PointT;

enum Color { RED, GREEN, BLUE };

#define SQUARE( n ) ( (n) * (n) )

int add_one( int x )
{
    return x + 1;
}

int add_two( int x )
{
    return add_one( x ) + 1;
}
