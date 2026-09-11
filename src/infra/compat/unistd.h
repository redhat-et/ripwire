#pragma once
#include "../platform_compat.h"

#ifndef STDIN_FILENO
  #define STDIN_FILENO 0
#endif
#ifndef STDOUT_FILENO
  #define STDOUT_FILENO 1
#endif
#ifndef STDERR_FILENO
  #define STDERR_FILENO 2
#endif

#ifndef F_OK
  #define F_OK 0
#endif
#ifndef X_OK
  #define X_OK 1
#endif
#ifndef W_OK
  #define W_OK 2
#endif
#ifndef R_OK
  #define R_OK 4
#endif
