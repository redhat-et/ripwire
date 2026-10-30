/* every caller of release_lockfile is a test: the chain already ends there, so no ranked hop */
int release_lockfile( int fd )
{
    if( fd < 0 )
    {
        return -1; /* lockfile release stale */
    }
    return 0;
}
