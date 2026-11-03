int start_server( int port );

int connect_client( int port )
{
    return start_server( port );
}

int run_client( int argc )
{
    int port = argc * 2;
    if( port > 6 )
    {
        return start_server( port );
    }
    return connect_client( port );
}
