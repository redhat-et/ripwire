/* the wide funnel: parse_manifest has four callers, so a task about its error carries no ranked hop */
int parse_manifest( const char* text )
{
    if( text == 0 )
    {
        return -1; /* manifest syntax malformed */
    }
    return 0;
}

int load_one( void ) { return parse_manifest( "a" ); }
int load_two( void ) { return parse_manifest( "b" ); }
int load_three( void ) { return parse_manifest( "c" ); }
int load_four( void ) { return parse_manifest( "d" ); }
