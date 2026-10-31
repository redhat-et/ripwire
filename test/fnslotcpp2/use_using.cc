// a using-declaration of the external class: the bare spelling names grpc::Server, not the in-tree mine::Server
#include <grpc/server.h>
#include "scope.h"
using grpc::Server;
typedef int (Server::*UFn)(int);
struct UEnt { const char* k; UFn f; };
static const UEnt kUEnts[] = { { "start", &Server::start } };
struct UHold { const UEnt* e; };
int go_using(Server& s, int k) { UHold h; h.e = &kUEnts[k]; return (s.*h.e->f)(k); }
