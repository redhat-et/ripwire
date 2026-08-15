// module_b.cpp -- see module_a.cpp; the second of four satellite clusters bridging into hub.cpp.

int validateCore();   // cross-cluster (hub.cpp)

int bStep1()     { return 2; }
int bStep2()     { return bStep1() + bStep1(); }
int moduleBRun() { return bStep2() + bStep1() + validateCore(); }
