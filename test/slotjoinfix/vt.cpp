// C++ twin: a function-pointer field this file declares; a member function of the same name is no slot.
struct Vt
{
    int (*op)( int );
};
static int opa( int x ) { return x; }
static Vt vt = { opa };
int use( Vt *v ) { return v->op( 1 ); }
class Runner
{
public:
    int op( int x ) { return x; }
};
int run( Runner *r ) { return r->op( 3 ); }
