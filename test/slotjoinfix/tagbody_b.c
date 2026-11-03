typedef void ( *tfp )( int );
struct priv { int n; tfp run; };
void pb( int x ) { (void)x; }
static struct priv Q = { .run = pb };
void call_pb( struct priv *p ) { p->run( 2 ); }
