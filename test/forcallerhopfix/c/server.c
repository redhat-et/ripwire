/* the sink of the change-propagation fixture: start_server is the function a name-exact question names */
int listen_socket( int port )
{
    return port + 1;
}

int start_server( int port )
{
    int fd = listen_socket( port );
    return fd;
}
