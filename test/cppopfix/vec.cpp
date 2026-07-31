// Out-of-line (qualified) operator definitions — declarator is `qualified_identifier name:(operator_name)`.
#include "vec.h"

bool Vec::operator==( const Vec& o ) const { return x == o.x; }

Vec& Vec::operator=( const Vec& o ) { x = o.x; return *this; }
