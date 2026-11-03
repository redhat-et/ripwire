int recompute_dirty( int node );
int recompute_edges( int node );
int load_one( void );
int main( void )
{
    return recompute_dirty( 1 ) + recompute_edges( 2 ) + load_one();
}
