// module_c.cpp -- see module_a.cpp; the third of four satellite clusters bridging into hub.cpp.

int validateCore();   // cross-cluster (hub.cpp)

int cStep1()     { return 3; }
int cStep2()     { return cStep1() + cStep1(); }
int moduleCRun() { return cStep2() + cStep1() + validateCore(); }
