typedef void ( *tafp )( int );
struct tsa { tafp f; };
typedef struct tsa *thandle;
void taf( int x ) { (void)x; }
struct tsa TA = { .f = taf };
void call_ta( thandle h ) { h->f( 1 ); }
