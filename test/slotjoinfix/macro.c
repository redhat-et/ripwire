#include "mq.h"
typedef void ( *mfp )( int );
struct mitem { TAILQ_ENTRY(mitem) e; mfp f; mfp g; };
void ma( int x ) { (void)x; }
struct mitem M1 = { 0, 0, ma };
void call_mf( struct mitem *o ) { o->f( 1 ); }
void call_mg( struct mitem *o ) { o->g( 2 ); }
