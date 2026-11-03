/* IX-1 fix round 1: positional shapes whose index -> field mapping is exact, or no row (never a guessed field). */
struct pd
{
    int (*a)( int );
    int (*b)( int );
    int (*c)( int );
    int (*d)( int );
};
static int a3( int x ) { return x; }
static int c3( int x ) { return x + 1; }
static int d3( int x ) { return x + 2; }
static const struct pd pdx = { a3, .c = c3, d3 };
int call_pd_a( struct pd *p ) { return p->a( 1 ); }
int call_pd_c( struct pd *p ) { return p->c( 1 ); }
int call_pd_d( struct pd *p ) { return p->d( 1 ); }
static int b4( int x ) { return x + 3; }
static const struct pd pdy = { .b = b4 };
int call_pd_star( struct pd *p ) { return ( *p->b )( 2 ); }
struct au2
{
    union { int i; long l; };
    int (*x)( int );
    int (*y)( int );
};
static int x5( int v ) { return v; }
static int y5( int v ) { return -v; }
static const struct au2 aux = { { 1 }, x5, y5 };
int call_au_x( struct au2 *p ) { return p->x( 1 ); }
int call_au_y( struct au2 *p ) { return p->y( 1 ); }
struct pair2 { int lo; int hi; };
struct el
{
    struct pair2 r;
    int (*ef_slot)( int );
    int (*eg_slot)( int );
};
static int ef( int v ) { return v; }
static int eg( int v ) { return -v; }
static const struct el elx = { 1, 2, ef, eg };   /* brace elision: ef is .ef_slot, not the third field */
int call_el_f( struct el *p ) { return p->ef_slot( 1 ); }
int call_el_g( struct el *p ) { return p->eg_slot( 1 ); }
struct cf
{
    int (*cp)( int );
#ifdef HAVE_CQ
    int (*cq)( int );
#endif
    int (*cr)( int );
};
static int cf_r( int v ) { return v; }
static const struct cf cfx = { 0, cf_r };   /* its index depends on HAVE_CQ: not provable */
int call_cf_r( struct cf *p ) { return p->cr( 1 ); }
int call_cf_q( struct cf *p ) { return p->cq( 1 ); }
struct pt
{
    int (*ptf)( int );
};
typedef struct pt *pt_p;
static int pt_fn( int v ) { return v; }
static const struct pt ptx = { .ptf = pt_fn };
int call_ptp( pt_p p ) { return p->ptf( 11 ); }
