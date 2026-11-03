// IX-1 fix round 1, C++: a static data member and a base class are no initializer position; typedef / using receivers.
struct Sm
{
    static int n;
    int (*sa)( int );
    int (*sb)( int );
};
static int fa( int v ) { return v; }
static int fb( int v ) { return -v; }
static Sm smx = { fa, fb };
int call_sa( Sm *p ) { return p->sa( 1 ); }
int call_sb( Sm *p ) { return p->sb( 1 ); }
struct Base0
{
};
struct Dd : Base0
{
    int (*dc)( int );
    int (*dd)( int );
};
static int fc( int v ) { return v; }
static int fd( int v ) { return -v; }
static Dd ddx = { {}, fc, fd };
int call_dc( Dd *p ) { return p->dc( 1 ); }
int call_dd( Dd *p ) { return p->dd( 1 ); }
struct Sg
{
    int (*gq)( int );
};
static int gfn( int v ) { return v; }
static Sg sgx = { .gq = gfn };
typedef Sg STd;
using SAu = Sg;
int c_tdef( STd *p ) { return p->gq( 5 ); }
int c_using( SAu *p ) { return p->gq( 6 ); }
