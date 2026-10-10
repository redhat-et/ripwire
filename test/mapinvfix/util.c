int helper( int x ) { return x + 1; }
int twice( int x ) { return helper( helper( x ) ); }
int thrice( int x ) { return helper( twice( x ) ); }
