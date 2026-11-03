/* near misses: a name-exact question naming a struct or a variable carries no caller hop */
struct ServerConfig
{
    int port;
    int backlog;
};

int g_backlog_limit = 3;
