/* >16 stores into ONE slot (test/slotjoincheck.sh section L): the <vs> window cuts at 16 and its next= must find every store,
   however the initializer is spaced (aligned, unspaced) or written (a field assignment). */
struct bigent { int ( *bigcb )( int ); };
int bg00( int a ) { return a + 0; }
int bg01( int a ) { return a + 1; }
int bg02( int a ) { return a + 2; }
int bg03( int a ) { return a + 3; }
int bg04( int a ) { return a + 4; }
int bg05( int a ) { return a + 5; }
int bg06( int a ) { return a + 6; }
int bg07( int a ) { return a + 7; }
int bg08( int a ) { return a + 8; }
int bg09( int a ) { return a + 9; }
int bg10( int a ) { return a + 10; }
int bg11( int a ) { return a + 11; }
int bg12( int a ) { return a + 12; }
int bg13( int a ) { return a + 13; }
int bg14( int a ) { return a + 14; }
int bg15( int a ) { return a + 15; }
int bg16( int a ) { return a + 16; }
int bg17( int a ) { return a + 17; }
struct bigent bigtab[] = {
    { .bigcb = bg00 },
    { .bigcb    = bg01 },
    { .bigcb=bg02 },
    { .bigcb = bg03 },
    { .bigcb    = bg04 },
    { .bigcb=bg05 },
    { .bigcb = bg06 },
    { .bigcb    = bg07 },
    { .bigcb=bg08 },
    { .bigcb = bg09 },
    { .bigcb    = bg10 },
    { .bigcb=bg11 },
    { .bigcb = bg12 },
    { .bigcb    = bg13 },
    { .bigcb=bg14 },
    { .bigcb = bg15 },
    { .bigcb    = bg16 },
    { .bigcb=bg17 },
};
int big_fire( struct bigent *e ) { return e->bigcb( 1 ); }
