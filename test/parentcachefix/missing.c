int h( int a, int b );
int k( int c );
void g( void )
{
    h( 1, 2 )
    k( h( 3, 4 ) );
}
