// qualified spellings: an external grpc::Server beside the in-tree mine::Server
#include <grpc/server.h>
#include "scope.h"
typedef int (grpc::Server::*SFn)(int);
struct Ent { const char* k; SFn f; };
static const Ent kEnts[] = { { "start", &grpc::Server::start } };
struct Hold { const Ent* e; };
int go_ext(grpc::Server& s, int k) { Hold h; h.e = &kEnts[k]; return (s.*h.e->f)(k); }
typedef int (mine::Server::*MFn)(int);
struct Ent2 { const char* k; MFn f; };
static const Ent2 kEnts2[] = { { "stop", &mine::Server::stop } };
struct Hold2 { const Ent2* e; };
int go_mine(mine::Server& s, int k) { Hold2 h; h.e = &kEnts2[k]; return (s.*h.e->f)(k); }
