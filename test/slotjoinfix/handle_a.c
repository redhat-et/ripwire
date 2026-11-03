// IX-1 fix round 2 (MF-B): the alias name `handle` names struct hsa here and struct hsb in handle_b.c.
typedef void ( *hfp )( int );
struct hsa { hfp f; };
struct hsb { hfp f; };
typedef struct hsa *handle;
void af( int x ) { (void)x; } void bf( int x ) { (void)x; }
struct hsa HA = { .f = af };
struct hsb HB = { .f = bf };
void call_h( handle h ) { h->f( 2 ); }
