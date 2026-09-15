#pragma once
#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include_next <arpa/inet.h>
#endif
