#include "../core/math.h"
#include "../iface/shape.h"
struct Circle : Shape { double area() const override { return add( 3, 0 ) * 3.14; } };
