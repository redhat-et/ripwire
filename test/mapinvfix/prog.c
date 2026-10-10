int helper( int x );
int run( int n ) { return helper( n ) + helper( n + 1 ); }
int main( void ) { return run( 2 ); }
