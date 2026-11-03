/* r=4: three socket timeout types rank above the one narrow function, so the ranked hop (r=1..3 only) carries none */
struct socket_timeout_state { int socket_timeout; };
struct socket_timeout_limits { int socket_timeout_max; };
struct socket_timeout_stats { int socket_timeout_count; };

int poll_socket_once( int fd )
{
    return fd > 0 ? 0 : -1; /* socket timeout */
}

int poll_loop( int fd )
{
    return poll_socket_once( fd );
}
