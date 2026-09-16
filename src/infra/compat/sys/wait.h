#pragma once
#include "../../platform_compat.h"

#ifndef WIFEXITED
  #define WIFEXITED(status)   (((status) & 0x7f) == 0)
#endif
#ifndef WEXITSTATUS
  #define WEXITSTATUS(status) (((status) >> 8) & 0xff)
#endif
#ifndef WIFSIGNALED
  #define WIFSIGNALED(status) (((status) & 0x7f) != 0)
#endif
#ifndef WTERMSIG
  #define WTERMSIG(status)    ((status) & 0x7f)
#endif
#ifndef WNOHANG
  #define WNOHANG 1
#endif
