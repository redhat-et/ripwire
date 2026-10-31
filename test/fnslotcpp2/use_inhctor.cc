// E6 (CR 4415276397): a CLASS-MEMBER using-declaration (`using ICtor::ICtor;`, inheriting constructors) names a member, never a
// class reachable by a bare spelling — it must not make the later bare `&ICtor::ic_run` decline as an external class.
struct ICtor { int ic_run(int x); };
int ICtor::ic_run(int x) { return x; }
struct ICDer : ICtor { using ICtor::ICtor; };
typedef int (ICtor::*ICFn)(int);
struct ICEnt { ICFn f; };
static const ICEnt kICEnt[] = { { &ICtor::ic_run } };
struct ICHold { const ICEnt* e; };
int go_ictor(ICtor& s, int k) { ICHold h; h.e = &kICEnt[k]; return (s.*h.e->f)(k); }
