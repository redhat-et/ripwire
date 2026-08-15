// module_d.cpp -- see module_a.cpp; the fourth of four satellite clusters bridging into hub.cpp.

int validateCore();   // cross-cluster (hub.cpp)

int dStep1()     { return 4; }
int dStep2()     { return dStep1() + dStep1(); }
int moduleDRun() { return dStep2() + dStep1() + validateCore(); }
