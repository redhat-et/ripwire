// Twin of elide.c with every field type defined in THIS file: a braced first value keeps the index exact.
typedef struct { int a; int b; } iinner_t;
typedef void ( *ifp_t )( int );
struct iouter { iinner_t in; ifp_t f; ifp_t g; };
void ia( int x ) { (void)x; } void ib( int x ) { (void)x; }
struct iouter itab[] = { { { 1, 2 }, ia, ib } };
void call_if( struct iouter *o ) { o->f( 1 ); }
void call_ig( struct iouter *o ) { o->g( 2 ); }
// The floor: a function-pointer typedef from a header is a type this file cannot see, so the value after it has no row.
struct hdrfp { efp_t f; efp_t g; };
void ha( int x ) { (void)x; } void hb( int x ) { (void)x; }
struct hdrfp htab = { ha, hb };
void call_hf( struct hdrfp *o ) { o->f( 1 ); }
void call_hg( struct hdrfp *o ) { o->g( 2 ); }
