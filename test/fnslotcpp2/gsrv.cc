// the in-tree global class GSrv (E4) and a file that reaches the in-tree namespaced class by a using-directive (E5)
struct GSrv { int gs_start(int x); };
int GSrv::gs_start(int x) { return x; }
typedef int (GSrv::*GOFn)(int);
struct GOEnt { GOFn f; };
static const GOEnt kGOEnt[] = { { &GSrv::gs_start } };
struct GOHold { const GOEnt* e; };
int go_gok(GSrv& s, int k) { GOHold h; h.e = &kGOEnt[k]; return (s.*h.e->f)(k); }
