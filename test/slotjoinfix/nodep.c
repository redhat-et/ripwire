// IX-1 fix round 2 (N-a): a POINTER alias field is a scalar position, never an aggregate a value is brace-elided into.
struct nnode { int v; };
typedef struct nnode *nnode_p;
struct nlink { nnode_p next; void ( *f )( int ); };
void lf( int x ) { (void)x; }
struct nlink L1 = { 0, lf };
void call_nl( struct nlink *l ) { l->f( 1 ); }
