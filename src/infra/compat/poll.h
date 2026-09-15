#pragma once
#include "../platform_compat.h"



#ifdef __cplusplus
namespace rw::compat
{
    int rw_poll( struct pollfd* fds, unsigned long nfds, int timeout );
}
#ifndef poll
  #define poll rw::compat::rw_poll
#endif
#endif
