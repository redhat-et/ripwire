typedef void ( *tafp )( int );
struct thandle { tafp f; };
void tbf( int x ) { (void)x; }
struct thandle TB = { .f = tbf };
void call_tb( struct thandle *h ) { h->f( 2 ); }
