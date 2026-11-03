// a using-DIRECTIVE of an external namespace: a bare `Server` outside mine is not proven to be mine::Server
#include <grpc/server.h>
#include "scope.h"
using namespace grpc;
typedef int (Server::*DFn)(int);
struct DEnt { const char* k; DFn f; };
static const DEnt kDEnts[] = { { "start", &Server::start } };
struct DHold { const DEnt* e; };
int go_dir(Server& s, int k) { DHold h; h.e = &kDEnts[k]; return (s.*h.e->f)(k); }
