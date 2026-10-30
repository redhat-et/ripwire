// E5: `using namespace mine;` makes the bare `&Server::both` mine::Server's, outside the namespace: stays typed
#include "scope.h"
using namespace mine;
typedef int (Server::*IFn)(int);
struct IEnt { IFn f; };
static const IEnt kIEnt[] = { { &Server::both } };
struct IHold { const IEnt* e; };
int go_dirin(Server& s, int k) { IHold h; h.e = &kIEnt[k]; return (s.*h.e->f)(k); }
