// svc_main.cpp — the service's own caller of its API (an in-root edge in both solo and merged runs).
#include "../include/svc_api.h"

int svc_run( int request )
{
    return svc_handle( request );
}
