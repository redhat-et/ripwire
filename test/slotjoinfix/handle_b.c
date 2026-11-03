struct hsb { hfp f; };
typedef struct hsb *handle;
void call_hb( handle h ) { h->f( 3 ); }
