#include "elide.h"
// The first field's type is a struct typedef from ANOTHER file: `1, 2` fill it by brace elision, so no later index is provable.
struct eouter { einner_t in; efp_t f; efp_t g; };
void ea( int x ) { (void)x; } void eb( int x ) { (void)x; } void ec( int x ) { (void)x; }
struct eouter otab[] = { { 1, 2, ea, eb } };
struct eouter o2 = { 3, 4, ec };
void call_ef( struct eouter *o ) { o->f( 1 ); }
void call_eg( struct eouter *o ) { o->g( 2 ); }
