// I7: a template whose dependent base is a template PARAMETER named like an in-tree class (`template <class DBase> struct Mixin : DBase`)
struct DBase { int dfoo(int x); };
int DBase::dfoo(int x) { return x; }
template <class DBase> struct Mixin : DBase { int own(int x) { return x; } };
struct DReal { int dfoo(int x) { return 9; } };
typedef int (Mixin<DReal>::*DMFn)(int);
struct DpEnt { const char* n; DMFn fn; };
static const DpEnt kDpEnts[] = { { "dfoo", &Mixin<DReal>::dfoo } };
struct DpHolder { const DpEnt* e; };
int dispatch_dep(Mixin<DReal>& r, int k) { if( k < 0 ) { return -1; } DpHolder h; h.e = &kDpEnts[k]; int v = (r.*h.e->fn)(k); return v + 1; }
typedef int (DBase::*DBFn)(int);
struct DBEnt { const char* n; DBFn fn; };
static const DBEnt kDBEnts[] = { { "dfoo", &DBase::dfoo } };
struct DBHolder { const DBEnt* e; };
int go_dbok(DBase& r, int k) { DBHolder h; h.e = &kDBEnts[k]; return (r.*h.e->fn)(k) + (r.*h.e->fn)(k + 1); }
