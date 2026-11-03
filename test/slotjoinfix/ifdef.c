/* a positional struct literal with a build-dependent entry (slotjoincheck.sh section Z): pf2 is the 2nd entry when WITH_B is
   undefined and the 3rd when it is defined, so its field is not provable; pf0 is the 1st either way. */
struct tri { int ( *tfirst )( int ); int ( *tsecond )( int ); int ( *tthird )( int ); };
int pf0( int a ) { return a; }
int pf1( int a ) { return a + 1; }
int pf2( int a ) { return a + 2; }
struct tri tri_t = {
    pf0,
#ifdef WITH_B
    pf1,
#endif
    pf2,
};
int call_tri_first( struct tri *t ) { return t->tfirst( 1 ); }
int call_tri_second( struct tri *t ) { return t->tsecond( 1 ); }
int call_tri_third( struct tri *t ) { return t->tthird( 1 ); }
