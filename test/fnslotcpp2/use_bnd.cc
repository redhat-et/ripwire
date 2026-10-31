// E1f: an external grpc::GServer; the in-tree class sits in mygrpc:: ("mygrpc" ends with "grpc" but not on a :: boundary)
#include <grpc/gserver.h>
#include "scope.h"
typedef int (grpc::GServer::*BndSFn)(int);
struct BndEntB { const char* k; BndSFn f; };
static const BndEntB kBndB[] = { { "gstart", &grpc::GServer::gstart } };
struct BndHoldB { const BndEntB* e; };
int go_bnd(grpc::GServer& s, int k) { BndHoldB h; h.e = &kBndB[k]; (s.*h.e->f)(k - 1); return (s.*h.e->f)(k); }
typedef int (mygrpc::GServer::*BndOFn)(int);
struct BndEntC { const char* k; BndOFn f; };
static const BndEntC kBndC[] = { { "gstart", &mygrpc::GServer::gstart } };
struct BndHoldC { const BndEntC* e; };
int go_bok(mygrpc::GServer& s, int k) { if( k < 0 ) { return -1; } BndHoldC h; h.e = &kBndC[k]; int v = (s.*h.e->f)(k); return v * 2; }
