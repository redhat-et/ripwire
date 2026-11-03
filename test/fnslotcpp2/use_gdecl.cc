// E4: the in-tree class is GLOBAL (GSrv); a using-declaration of an external ext::GSrv makes the bare `&GSrv::start` that one
#include <ext/gsrv.h>
using ext::GSrv;
typedef int (GSrv::*GSFn)(int);
struct GSEnt { GSFn f; };
static const GSEnt kGSEnt[] = { { &GSrv::gs_start } };
struct GSHold { const GSEnt* e; };
int go_gdecl(GSrv& s, int k) { GSHold h; h.e = &kGSEnt[k]; return (s.*h.e->f)(k); }
