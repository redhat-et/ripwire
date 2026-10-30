// an out-of-line member definition at the global scope: its declarator `mine::Server::both` puts the body inside mine::Server,
// so the bare `&Server::start` names it
#include "scope.h"
typedef int (mine::Server::*OFn)(int);
struct OEnt { OFn f; };
int mine::Server::both(int k) {
  OEnt e;
  e.f = &Server::start;
  mine::Server& self = *this;
  return (self.*e.f)(k);
}
