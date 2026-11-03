typedef void ( *tfp )( int );
struct priv { tfp run; };
void pa( int x ) { (void)x; }
static struct priv P = { .run = pa };
void call_pa( struct priv *p ) { p->run( 1 ); }
