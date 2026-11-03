int release_lockfile( int fd );
int test_release_lockfile( void ) { return release_lockfile( 3 ); }
